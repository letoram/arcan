#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <inttypes.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <pwd.h>
#include <ctype.h>
#include <signal.h>
#include <pthread.h>
#include <poll.h>
#include <unistd.h>
#include "tsm/libtsm.h"
#include "tsm/libtsm_int.h"
#include "tsm/shl-pty.h"

static struct {
	struct tui_context* screen;
	struct tsm_vte* vte;
	struct shl_pty* pty;
	pthread_mutex_t synch;

	pid_t child;

	volatile bool alive;
	bool die_on_term;
	long last_input;
	int dirtyfd;

} term = {
	.die_on_term = true,
	.synch = PTHREAD_MUTEX_INITIALIZER
};

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

extern int arcan_tuiint_dirty(struct tui_context* tui);

void* pump_pty()
{
	int fd = shl_pty_get_fd(term.pty);

	while (term.alive){
		char buf[4096];
		ssize_t nr = read(fd, buf, 4096);
		if (-1 == nr){
			if (errno == EAGAIN || errno == EINTR)
				continue;
			term.alive = false;
			arcan_tui_set_flags(term.screen, TUI_HIDE_CURSOR);
			break;
		}

/* shl_pty_write calls are mutex- protected,
 * so vte_input -> write- callback -> mutex
 */
		pthread_mutex_lock(&term.synch);
		tsm_vte_input(term.vte, buf, nr);
		tsm_vte_update_debug(term.vte);
		pthread_mutex_unlock(&term.synch);

/* wake the other thread */
		if (arcan_tuiint_dirty(term.screen)){
			write(term.dirtyfd, &(char){'1'}, 1);
		}
	}
	return NULL;
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
		"ARCAN_TERMINAL_EXEC : run value through /bin/sh -c instead of shell\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"    key      \t   value   \t   description\n"
		"-------------\t-----------\t-----------------\n"
		" env         \t key=val   \t override default environment (repeatable)\n"
		" chdir       \t dir       \t change working dir before spawning shell\n"
		" bgalpha     \t rv(0..255)\t background opacity (default: 255, opaque)\n"
		" bgc         \t r,g,b     \t background color \n"
		" fgc         \t r,g,b     \t foreground color \n"
		" ci          \t ind,r,g,b \t override palette at index\n"
		" cc          \t r,g,b     \t cursor color\n"
		" cl          \t r,g,b     \t cursor alternate (locked) state color\n"
		" cursor      \t name      \t set cursor (block, frame, halfblock,\n"
		"             \t           \t vline, uline)\n"
		" blink       \t ticks     \t set blink period, 0 to disable (default: 12)\n"
		" login       \t [user]    \t login (optional: user, only works for root)\n"
#ifndef FSRV_TERMINAL_NOEXEC
		" exec        \t cmd       \t allows arcan scripts to run shell commands\n"
#endif
		" keep_alive  \t           \t don't exit if the terminal or shell terminates\n"
		" palette     \t name      \t use built-in palette (below)\n"
		"Built-in palettes:\n"
		"default, solarized, solarized-black, solarized-white, srcery\n"
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

static bool on_subwindow(struct tui_context* c,
	arcan_tui_conn* newconn, uint32_t id, uint8_t type, void* tag)
{
	struct tui_cbcfg cbcfg = {};

/* only bind the debug type and bind it to the terminal emulator state machine */
	if (type == TUI_WND_DEBUG){
		return tsm_vte_debug(term.vte, newconn, c);
	}
	return false;
}

static void on_mouse_motion(struct tui_context* c,
	bool relative, int x, int y, int modifiers, void* t)
{
	trace("mouse motion(%d:%d, mods:%d, rel: %d",
		x, y, modifiers, (int) relative);

	if (!relative){
		tsm_vte_mouse_motion(term.vte, x, y, modifiers);
	}
}

static void on_mouse_button(struct tui_context* c,
	int last_x, int last_y, int button, bool active, int modifiers, void* t)
{
	trace("mouse button(%d:%d - @%d,%d (mods: %d)\n",
		button, (int)active, last_x, last_y, modifiers);
	tsm_vte_mouse_button(term.vte, button, active, modifiers);
}

static void on_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	trace("on_key(%"PRIu32",%"PRIu8",%"PRIu16")", keysym, scancode, subid);
	tsm_vte_handle_keyboard(term.vte,
		keysym, isascii(keysym) ? keysym : 0, mods, subid);
}

static bool on_u8(struct tui_context* c, const char* u8, size_t len, void* t)
{
	uint8_t buf[5] = {0};
	trace("utf8-input: %s", u8);
	memcpy(buf, u8, len >= 5 ? 4 : len);

//	int rv = shl_pty_write(term.pty, (char*) buf, len);
	int fd = shl_pty_get_fd(term.pty);
	int rv = write(fd, u8, len);

	if (rv < 0){
		term.alive = false;
		arcan_tui_set_flags(c, TUI_HIDE_CURSOR);
	}

	return true;
}

static void on_utf8_paste(struct tui_context* c,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	trace("utf8-paste(%s):%d", str, (int) cont);
	tsm_vte_paste(term.vte, (char*)str, len);
}

static unsigned long long last_frame;

static void on_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	trace("resize(%zu(%zu),%zu(%zu))", neww, col, newh, row);
	if (term.pty)
		shl_pty_resize(term.pty, col, row);

	last_frame = 0;
}

static void read_callback(struct shl_pty* pty,
	void* data, char* u8, size_t len)
{
	tsm_vte_input(term.vte, u8, len);
}

static void write_callback(struct tsm_vte* vte,
	const char* u8, size_t len, void* data)
{
	int fd = shl_pty_get_fd(term.pty);
	write(fd, u8, len);
	//shl_pty_write(term.pty, u8, len);
}

static void str_callback(struct tsm_vte* vte, enum tsm_vte_group group,
	const char* msg, size_t len, bool crop, void* data)
{
/* parse and see if we should set title */
	if (!msg || len < 3 || crop){
		debug_log(vte,
			"bad OSC sequence, len = %zu (%s)\n", len, msg ? msg : "");
		return;
	}

/* 0, 1, 2 : set title */
	if ((msg[0] == '0' || msg[0] == '1' || msg[0] == '2') && msg[1] == ';'){
		arcan_tui_ident(term.screen, &msg[2]);
		return;
	}

	debug_log(vte,
		"%d:unhandled OSC command (PS: %d), len: %zu\n",
		vte->log_ctr++, (int)msg[0], len
	);

/* 4 : change color */
/* 5 : special color */
/* 52 : clipboard contents */
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
#ifdef __OpenBSD__
	setenv("TERM", "wsvt25", 1);
#else
	setenv("TERM", "xterm-256color", 1);
#endif

	while (arg_lookup(argarr, "env", ind++, &val))
		putenv(strdup(val));

	if (arg_lookup(argarr, "chdir", 0, &val)){
		chdir(val);
	}

#ifndef NSIG
#define NSIG 32
#endif

	char* exec_arg = getenv("ARCAN_TERMINAL_EXEC");
#ifdef FSRV_TERMINAL_NOEXEC
	if (arg_lookup(argarr, "exec", 0, &val)){
		LOG("permission denied, noexec compiled in");
	}
#else
	if (arg_lookup(argarr, "exec", 0, &val)){
		exec_arg = strdup(val);
	}
#endif

	sigset_t sigset;
	sigemptyset(&sigset);
	pthread_sigmask(SIG_SETMASK, &sigset, NULL);

	for (size_t i = 1; i < NSIG; i++)
		signal(i, SIG_DFL);

/* special case, ARCAN_TERMINAL_EXEC and ARCAN_TERMINAL_ARGV skips the normal
 * shell setup and switches to a custom binary + arg instead */
	if (exec_arg){
		char* args[] = {"/bin/sh", "-c" , exec_arg, NULL};
		unsetenv("ARCAN_TERMINAL_EXEC");
		execv(args[0], args);
		exit(EXIT_FAILURE);
	}

	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

static bool on_subst(struct tui_context* tui,
	struct tui_cell* cells, size_t n_cells, size_t row, void* t)
{
	bool res = false;
	for (size_t i = 0; i < n_cells-1; i++){
/* far from an optimal shaping rule, but check for special forms of continuity,
 * 3+ of (+_-) like shapes horizontal or vertical, n- runs of whitespace or
 * vertical similarities in terms of whitespace+character
 */
		if ( (isspace(cells[i].ch) && isspace(cells[i+1].ch)) ){
			cells[i].attr.shape_break = 1;
			res = true;
		}
	}

	return res;
}

static void on_exec_state(struct tui_context* tui, int state, void* tag)
{
	if (state == 0)
		shl_pty_signal(term.pty, SIGCONT);
	else if (state == 1)
		shl_pty_signal(term.pty, SIGSTOP);
	else if (state == 2)
		shl_pty_signal(term.pty, SIGHUP);
}

static int parse_color(const char* inv, uint8_t outv[4])
{
	return sscanf(inv, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
		&outv[0], &outv[1], &outv[2], &outv[3]);
}

extern void arcan_tuiint_set_vsynch(struct tui_context* tui, pthread_mutex_t* mut);

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

	struct tui_cbcfg cbcfg = {
		.input_mouse_motion = on_mouse_motion,
		.input_mouse_button = on_mouse_button,
		.input_utf8 = on_u8,
		.input_key = on_key,
		.utf8 = on_utf8_paste,
		.resized = on_resize,
		.subwindow = on_subwindow,
		.exec_state = on_exec_state,
/*
 * for advanced rendering, but not that interesting
 * .substitute = on_subst
 */
	};

	term.screen = arcan_tui_setup(con, NULL, &cbcfg, sizeof(cbcfg));

	if (!term.screen){
		fprintf(stderr, "failed to setup TUI connection\n");
		return EXIT_FAILURE;
	}
	arcan_tui_reset_flags(term.screen, TUI_ALTERNATE);
	arcan_tui_refresh(term.screen);

/*
 * now we have the display server connection and the abstract screen,
 * configure the terminal state machine
 */
	if (tsm_vte_new(&term.vte, term.screen, write_callback, NULL) < 0){
		arcan_tui_destroy(term.screen, "Couldn't setup terminal emulator");
		return EXIT_FAILURE;
	}

/*
 * allow the window state to survive, terminal won't be updated but
 * other tui behaviors are still valid
 */
	if (arg_lookup(args, "keep_alive", 0, NULL)){
		term.die_on_term = false;
	}

/*
 * forward the colors defined in tui (where we only really track
 * forground and background, though tui should have a defined palette
 * for the normal groups when the other bits are in place
 */
	if (arg_lookup(args, "palette", 0, &val)){
		tsm_vte_set_palette(term.vte, val);
	}

	int ind = 0;
	uint8_t ccol[4];
	while(arg_lookup(args, "ci", ind++, &val)){
		if (4 == parse_color(val, ccol))
			tsm_vte_set_color(term.vte, ccol[0], &ccol[1]);
	}
	tsm_set_strhandler(term.vte, str_callback, 256, NULL);

	signal(SIGHUP, sighuph);

	uint8_t fgc[3], bgc[3];
	tsm_vte_get_color(term.vte, VTE_COLOR_BACKGROUND, bgc);
	tsm_vte_get_color(term.vte, VTE_COLOR_FOREGROUND, fgc);
	arcan_tui_set_color(term.screen, TUI_COL_BG, bgc);
	arcan_tui_set_color(term.screen, TUI_COL_TEXT, fgc);

/*
 * and lastly, spawn the pseudo-terminal
 */
	size_t rows = 0, cols = 0;
	arcan_tui_dimensions(term.screen, &rows, &cols);
	term.child = shl_pty_open(&term.pty, read_callback, NULL, cols, rows);
	if (term.child < 0){
		arcan_tui_destroy(term.screen, "Shell process died unexpectedly");
		return EXIT_FAILURE;
	}

/* we're inside child */
	if (term.child == 0){
		char* argv[] = {get_shellenv(), "-i", NULL, NULL};

		if (arg_lookup(args, "cmd", 0, &val) && val){
			argv[2] = strdup(val);
		}

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

#ifdef __OpenBSD__
	pledge(SHMIF_PLEDGE_PREFIX " tty", NULL);
#endif

	term.alive = true;

/* spawn a thread that deals with feeding the tsm specifically, then we run
 * our normal event look constantly in the normal process / refresh style. */
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	arcan_tuiint_set_vsynch(term.screen, &term.synch);

/* pipe pair used to signal between the threads */
	int pair[2];
	if (-1 == pipe(pair))
		return EXIT_FAILURE;

	term.dirtyfd = pair[1];

	if (-1 == pthread_create(&pth, &pthattr, pump_pty, NULL))
		term.alive = false;

	while(term.alive || !term.die_on_term){
		struct tui_process_res res =
			arcan_tui_process(&term.screen, 1, &pair[0], 1, -1);

		if (res.errc < TUI_ERRC_OK)
			break;

	/* flush out the signal pipe, don't care about contents */
		if (res.ok){
			char buf[256];
			read(pair[0], buf, 256);
		}

		int rc = arcan_tui_refresh(term.screen);
	}

	arcan_tui_destroy(term.screen, NULL);

	return EXIT_SUCCESS;
}
