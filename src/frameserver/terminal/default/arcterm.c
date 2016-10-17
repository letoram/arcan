#include <arcan_shmif.h>
#include <arcan_shmif_tui.h>
#include <inttypes.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <pwd.h>
#include <ctype.h>
#include <signal.h>
#include "tsm/libtsm.h"
#include "tsm/shl-pty.h"

static struct {
	struct tui_context* screen;
	struct tsm_vte* vte;
	struct shl_pty* pty;
	size_t cursor_x, cursor_y;
	pid_t child;

/* toggle whenever something has happened that should mandate a disp-synch */
	int inp_dirty;
} term;

/*
 * unless there's been explicit keyboard input, defer display updates until
 * at least this amount of miliseconds have elapsed. This is used to balance
 * the latency-v-power-consumption-v-data-propagation problems.
 */
#define REFRESH_TIMEOUT 10

/*#define TRACE_ENABLE*/
static inline void trace(const char* msg, ...)
{
#ifdef TRACE_ENABLE
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
	fprintf(stderr, "\n");
#endif
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"    key      \t   value   \t   description\n"
		"-------------\t-----------\t-----------------\n"
		" bgalpha     \t rv(0..255)\t background opacity (default: 255, opaque)\n"
		" bgc         \t r,g,b     \t background color \n"
		" fgc         \t r,g,b     \t foreground color \n"
		" ci          \t ind,r,g,b \t override palette at index\n"
		" cc          \t r,g,b     \t cursor color\n"
		" cl          \t r,g,b     \t cursor alternate (locked) state color\n"
		" cursor      \t name      \t set cursor (block, frame, halfblock,\n"
		"             \t           \t underline, vertical)\n"
		" login       \t [user]    \t login (optional: user, only works for root)\n"
		" palette     \t name      \t use built-in palette (below)\n"
		"Built-in palettes:\n"
		"default, solarized, solarized-black, solarized-white\n"
		"---------\t-----------\t----------------\n"
	);
}

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
}

static void sighuph(int num)
{
	if (term.pty)
		term.pty = (shl_pty_close(term.pty), NULL);
}

static void on_mouse_motion(struct tui_context* c,
	bool relative, int x, int y, int modifiers, void* t)
{
	trace("mouse motion(%d:%d, mods:%d, rel: %d",
		x, y, modifiers, (int) relative);

}

static void on_mouse_button(struct tui_context* c,
	int last_x, int last_y, int button, bool active, int modifiers, void* t)
{
	trace("mouse button(%d:%d - @%d,%d (mods: %d)\n",
		button, (int)active, last_x, last_y, modifiers);
}

static void on_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	trace("on_key(%"PRIu32",%"PRIu8",%"PRIu16")", keysym, scancode, subid);
	tsm_vte_handle_keyboard(term.vte,
		keysym, isascii(keysym) ? keysym : 0, mods, subid);
	term.inp_dirty = 1;
}

static bool on_u8(struct tui_context* c, const char* u8, size_t len, void* t)
{
	uint8_t buf[5] = {0};
	trace("utf8-input: %s", u8);
	memcpy(buf, u8, len >= 5 ? 4 : len);
	shl_pty_write(term.pty, (char*) buf, len);
	shl_pty_dispatch(term.pty);
	term.inp_dirty = 1;
	return true;
}

static void on_utf8_paste(struct tui_context* c,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	trace("utf8-paste(%s):%d", str, (int) cont);
	tsm_vte_paste(term.vte, (char*)str, len);
	term.inp_dirty = 1;
}

static void on_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	trace("resize(%zu(%zu),%zu(%zu))", neww, col, newh, row);
	if (term.pty)
		shl_pty_resize(term.pty, col, row);
	term.inp_dirty = 1;
}

static void read_callback(struct shl_pty* pty,
	void* data, char* u8, size_t len)
{
	tsm_vte_input(term.vte, u8, len);
	arcan_tui_cursorpos(term.screen, &term.cursor_x, &term.cursor_y);
}

static void write_callback(struct tsm_vte* vte,
	const char* u8, size_t len, void* data)
{
	shl_pty_write(term.pty, u8, len);
	shl_pty_dispatch(term.pty);
}

/* for future integration with more specific shmif- features when it
 * comes to streaming images back and forth, sending additional meta-
 * information about security state and context, highlighing datatypes
 * and so on */
static void str_callback(struct tsm_vte* vte, enum tsm_vte_group group,
	const char* msg, size_t len, bool crop, void* data)
{
/* parse and see if we should set title */
	if (!msg || len < 3 || crop)
		return;

	if ((msg[0] == '0' || msg[0] == '1' || msg[0] == '2') && msg[1] == ';')
		arcan_tui_ident(term.screen, &msg[2]);
	else
		LOG("ignoring unknown OSC sequence (%s)\n", msg);
}

static char* get_shellenv()
{
	char* shell = getenv("SHELL");

	const struct passwd* pass = getpwuid( getuid() );
	if (pass){
		setenv("LOGNAME", pass->pw_name, 1);
		setenv("USER", pass->pw_name, 1);
		setenv("SHELL", pass->pw_shell, 0);
		setenv("HOME", pass->pw_dir, 0);
		shell = pass->pw_shell;
	}

/* will be exec:ed so don't worry to much about leak or mgmt */
	return shell;
}

static void setup_shell(struct arg_arr* argarr, char* const args[])
{
	static const char* unset[] = {
		"COLUMNS", "LINES", "TERMCAP",
		"ARCAN_ARG", "ARCAN_APPLPATH", "ARCAN_APPLTEMPPATH",
		"ARCAN_FRAMESERVER_LOGDIR", "ARCAN_RESOURCEPATH",
		"ARCAN_SHMKEY", "ARCAN_SOCKIN_FD", "ARCAN_STATEPATH"
	};

	int ind = 0;
	const char* val;

	for (int i=0; i < sizeof(unset)/sizeof(unset[0]); i++)
		unsetenv(unset[i]);

/* set some of the common UTF-8 default envs, shell overrides if needed */
	setenv("LANG", "en_GB.UTF-8", 0);
	setenv("LC_CTYPE", "en_GB.UTF-8", 0);

/* FIXME: check what we should do with PWD, SHELL, TMPDIR, TERM, TZ,
 * DATEMSK, LINES, LOGNAME(portable set), MSGVERB, PATH */

/* might get overridden with putenv below, or if we are exec:ing /bin/login */
	setenv("TERM", "xterm-256color", 1);

	while (arg_lookup(argarr, "env", ind++, &val))
		putenv(strdup(val));

/* signal default handlers persist across exec, reset */
	int sigs[] = {
		SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM
	};

	for (int i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
		signal(sigs[i], SIG_DFL);

	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

static int parse_color(const char* inv, uint8_t outv[4])
{
	return scanf(inv, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
		&outv[0], &outv[1], &outv[2], &outv[3]);
}

int afsrv_terminal(struct arcan_shmif_cont* con, struct arg_arr* args)
{
/*
 * this table act as both callback- entry points and a list of features that we
 * actually use. So binary chunk transfers, video/audio paste, geohint etc.
 * are all ignored and disabled
 */
	if (!con)
		return EXIT_FAILURE;

	struct tui_cbcfg cbcfg = {
		.input_mouse_motion = on_mouse_motion,
		.input_mouse_button = on_mouse_button,
		.input_utf8 = on_u8,
		.input_key = on_key,
		.utf8 = on_utf8_paste,
		.resized = on_resize
	};

	struct tui_settings cfg = arcan_tui_defaults();
	arcan_tui_apply_arg(&cfg, args, NULL);
	term.screen = arcan_tui_setup(con, &cfg, &cbcfg, sizeof(cbcfg));

	if (!term.screen){
		fprintf(stderr, "failed to setup TUI connection\n");
		return EXIT_FAILURE;
	}

/*
 * now we have the display server connection and the abstract screen,
 * configure the terinal state machine
 */
	if (tsm_vte_new(&term.vte, term.screen, write_callback,
		NULL /* write_cb_data */, tsm_log, NULL /* tsm_log_data */) < 0){
		LOG("failed to setup terminal emulator, giving up\n");
		return EXIT_FAILURE;
	}

	const char* val;
	if (arg_lookup(args, "palette", 0, &val))
		tsm_vte_set_palette(term.vte, val);

	int ind = 0;
	uint8_t ccol[4];
	while(arg_lookup(args, "ci", ind++, &val)){
		if (4 == parse_color(val, ccol))
			tsm_vte_set_color(term.vte, ccol[0], &ccol[1]);
	}
	tsm_set_strhandler(term.vte, str_callback, 256, NULL);

	signal(SIGHUP, sighuph);

	tsm_vte_set_color(term.vte, VTE_COLOR_BACKGROUND, cfg.bgc);
	tsm_vte_set_color(term.vte, VTE_COLOR_FOREGROUND, cfg.fgc);
	LOG("set fgc: %d, %d, %d\n", cfg.fgc[0], cfg.fgc[1], cfg.fgc[2]);

/*
 * and lastly, spawn the pseudo-terminal
 */

	size_t rows = 0, cols = 0;
	arcan_tui_dimensions(term.screen, &rows, &cols);
	term.child = shl_pty_open(&term.pty, read_callback, NULL, cols, rows);
	if (term.child < 0){
		LOG("couldn't spawn child termainl.\n");
		return EXIT_FAILURE;
	}

/* we're inside child */
	if (term.child == 0){
		char* argv[] = {get_shellenv(), "-i", NULL};

/* special case handling for "login", this requires root */
		if (arg_lookup(args, "login", 0, &val)){
			struct stat buf;
			argv[1] = "-p";
			if (stat("/bin/login", &buf) == 0 && S_ISREG(buf.st_mode))
				argv[0] = "/bin/login";
			else if (stat("/usr/bin/login", &buf) == 0 && S_ISREG(buf.st_mode))
				argv[0] = "/usr/bin/login";
			else{
				LOG("login prompt requested but none was found\n");
				return EXIT_FAILURE;
			}
		}

		setup_shell(args, argv);
		return EXIT_FAILURE;
	}

	int inf = shl_pty_get_fd(term.pty);
	shl_pty_dispatch(term.pty);
	arcan_tui_refresh(&term.screen, 1);
	int ts = arcan_timemillis();

	while (1){
		struct tui_process_res res = arcan_tui_process(&term.screen, 1, &inf, 1, -1);
		if (res.errc < TUI_ERRC_OK || res.bad)
				break;

		shl_pty_dispatch(term.pty);

		if (arcan_timemillis() - ts > REFRESH_TIMEOUT){
			if (arcan_tui_refresh(&term.screen, 1))
				ts = arcan_timemillis();
		}
	}

/* might have been destroyed already, just in case */
	if (term.pty)
		term.pty = (shl_pty_close(term.pty), NULL);
	arcan_tui_destroy(term.screen);

	return EXIT_SUCCESS;
}
