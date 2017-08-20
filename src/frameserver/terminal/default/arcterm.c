#include <arcan_shmif.h>
#include <arcan_tui.h>
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
	pid_t child;

/* timestamp of last provided user input, reset each visible frame.
 * useful for heuristics about the source of update, i.e. if we have a
 * running command that keeps feeding the state machine, or we happen
 * to have:
 * user-input -> client_action -> state machine update
 * as that is a strong synch indicator to have low input latency. */
	bool uinput;

/* graceful shutdown */
	bool alive;
} term;

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

/*
 * process one round of PTY input, this is non-blocking
 */
static int pump_pty()
{
	int rv = shl_pty_dispatch(term.pty);
	if (rv == -ENODEV){
		term.alive = false;
	}
	else if (rv == -EAGAIN)
		return 0;

	return rv;
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
		" blink       \t ticks     \t set blink period, 0 to disable (default: 12)\n"
		" login       \t [user]    \t login (optional: user, only works for root)\n"
		" min_upd     \t ms        \t wait at least [ms] between refreshes (default: 30)\n"
		" scroll      \t steps     \t (experimental) smooth scrolling, (default:0=off) steps px/upd\n"
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

	if (!relative){
		tsm_vte_mouse_motion(term.vte, x, y, modifiers);
		term.uinput = true;
	}
}

static void on_mouse_button(struct tui_context* c,
	int last_x, int last_y, int button, bool active, int modifiers, void* t)
{
	trace("mouse button(%d:%d - @%d,%d (mods: %d)\n",
		button, (int)active, last_x, last_y, modifiers);
	tsm_vte_mouse_button(term.vte, button, active, modifiers);
	term.uinput = true;
}

static void on_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	trace("on_key(%"PRIu32",%"PRIu8",%"PRIu16")", keysym, scancode, subid);
	tsm_vte_handle_keyboard(term.vte,
		keysym, isascii(keysym) ? keysym : 0, mods, subid);
	term.uinput = true;
}

static bool on_u8(struct tui_context* c, const char* u8, size_t len, void* t)
{
	uint8_t buf[5] = {0};
	trace("utf8-input: %s", u8);
	memcpy(buf, u8, len >= 5 ? 4 : len);
	if (shl_pty_write(term.pty, (char*) buf, len) < 0)
		term.alive = false;
	term.uinput = true;
	return true;
}

static void on_utf8_paste(struct tui_context* c,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	trace("utf8-paste(%s):%d", str, (int) cont);
	tsm_vte_paste(term.vte, (char*)str, len);
	term.uinput = true;
}

static void on_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	trace("resize(%zu(%zu),%zu(%zu))", neww, col, newh, row);
	if (term.pty)
		shl_pty_resize(term.pty, col, row);
}

static void read_callback(struct shl_pty* pty,
	void* data, char* u8, size_t len)
{
	tsm_vte_input(term.vte, u8, len);
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
	return sscanf(inv, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
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

	const char* val;
	if (arg_lookup(args, "help", 0, &val)){
		dump_help();
		return EXIT_SUCCESS;
	}

	int limit_flush = 60;
	int cap_refresh = 16;

	if (arg_lookup(args, "min_upd", 0, &val))
		cap_refresh = strtol(val, NULL, 10);

	struct tui_cbcfg cbcfg = {
		.input_mouse_motion = on_mouse_motion,
		.input_mouse_button = on_mouse_button,
		.input_utf8 = on_u8,
		.input_key = on_key,
		.utf8 = on_utf8_paste,
		.resized = on_resize
	};

	struct tui_settings cfg = arcan_tui_defaults(con, NULL);
	cfg.mouse_fwd = false;
	term.screen = arcan_tui_setup(con, &cfg, &cbcfg, sizeof(cbcfg));

	if (!term.screen){
		fprintf(stderr, "failed to setup TUI connection\n");
		return EXIT_FAILURE;
	}
	arcan_tui_refresh(term.screen);

/*
 * now we have the display server connection and the abstract screen,
 * configure the terminal state machine
 */
	if (tsm_vte_new(&term.vte, term.screen, write_callback,
		NULL /* write_cb_data */, tsm_log, NULL /* tsm_log_data */) < 0){
		LOG("failed to setup terminal emulator, giving up\n");
		return EXIT_FAILURE;
	}

/*
 * forward the colors defined in tui (where we only really track
 * forground and background, though tui should have a defined palette
 * for the normal groups when the other bits are in place
 */
	tsm_vte_set_color(term.vte, VTE_COLOR_BACKGROUND, cfg.bgc);
	tsm_vte_set_color(term.vte, VTE_COLOR_FOREGROUND, cfg.fgc);

	bool recolor = false;
	if (arg_lookup(args, "palette", 0, &val)){
		tsm_vte_set_palette(term.vte, val);
		recolor = true;
	}

	int ind = 0;
	uint8_t ccol[4];
	while(arg_lookup(args, "ci", ind++, &val)){
		recolor = true;
		if (4 == parse_color(val, ccol))
			tsm_vte_set_color(term.vte, ccol[0], &ccol[1]);
	}
	tsm_set_strhandler(term.vte, str_callback, 256, NULL);

	signal(SIGHUP, sighuph);

	if (recolor){
		uint8_t fgc[3], bgc[3];
		tsm_vte_get_color(term.vte, VTE_COLOR_BACKGROUND, bgc);
		tsm_vte_get_color(term.vte, VTE_COLOR_FOREGROUND, fgc);
		arcan_tui_set_color(term.screen, TUI_COL_BG, bgc);
		arcan_tui_set_color(term.screen, TUI_COL_TEXT, fgc);
	}

/*
 * and lastly, spawn the pseudo-terminal
 */
	size_t rows = 0, cols = 0;
	arcan_tui_dimensions(term.screen, &rows, &cols);
	term.child = shl_pty_open(&term.pty, read_callback, NULL, cols, rows);
	if (term.child < 0){
		LOG("couldn't spawn child terminal.\n");
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

	term.alive = true;
	int inf = shl_pty_get_fd(term.pty);

/* first frame */
	while(pump_pty()){};
	arcan_tui_refresh(term.screen);

/*
 * timekeeping:
 *  attempt refresh @60Hz, tick callback will drive _process forward - 30Hz if
 *  we're being swamped with data (find /)
 */
	int delay = -1;
	unsigned long long last_frame = arcan_timemillis();

	while (term.alive){
		struct tui_process_res res = arcan_tui_process(&term.screen,1,&inf,1,delay);
		if (res.errc < TUI_ERRC_OK || res.bad)
				break;

/* if the terminal is being swamped (find / for instance), try to keep at
 * least a 30Hz refresh timer if we have no user input */
		int nr;
		while ((nr = pump_pty()) > 0){
			if (arcan_timemillis() - last_frame <
				(term.uinput ? limit_flush : 2 * limit_flush)){
				delay = cap_refresh - (arcan_timemillis() - last_frame);
				if (delay < 0)
					delay = 0;
			}
			break;
		}

/* in legacy terminal management, if we update too often, chances are that
 * we'll get cursors jumping around in vim etc so artificially constrain */
		if (arcan_timemillis() - last_frame < cap_refresh){
			delay = cap_refresh - (arcan_timemillis() - last_frame);
			continue;
		}

/* and on an actually successful update, reset the user-input flag and timing */
		int rc = arcan_tui_refresh(term.screen);
		if (rc >= 0){
			term.uinput = false;
			last_frame = arcan_timemillis();
			delay = -1;
		}
		else if (rc == -1){
			if (errno == EAGAIN)
				delay = 0;
			else if (errno == EINVAL)
				break;
		}
	}

/* might have been destroyed already, just in case */
	if (term.pty)
		term.pty = (shl_pty_close(term.pty), NULL);
	arcan_tui_destroy(term.screen, NULL);

	return EXIT_SUCCESS;
}
