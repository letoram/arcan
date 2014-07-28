/*
 * Arcan Terminal
 * A mix of Suckless-Terminal and libtsm- examples
 * wrapped in the arcan shared memory interface.
 */
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <locale.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <libtsm.h>
#include <pwd.h>
#include <signal.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/signal.h>
#include <sys/wait.h>

#include "shl/shl-pty.h"

#include <arcan_shmif.h>
#include "frameserver.h"

#ifndef ARCAN_TTF_SUPPORT
	#include "graphing/net_graph.h"
#endif

static struct {
	struct tsm_screen* screen;
	struct tsm_vte* vte;
	struct shl_pty* pty;

	pid_t child;
	int child_fd;

	int rows;
	int cols;
	int cell_w, cell_h;
	int screen_w, screen_h;
#ifndef ARCAN_TTF_SUPPORT
	struct graph_context* graphing;
#endif

	int last_fd;
	struct arcan_shmif_cont arc_conn;
} term = {
	.cell_w = 8,
	.cell_h = 8,
	.rows = 80,
	.cols = 25
};

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
}

static void screen_size(int screenw, int screenh, int fontw, int fonth)
{
	int px_w = screenw * fontw;
	int px_h = screenh * fonth;

	if (!arcan_shmif_resize(&term.arc_conn, px_w, px_h)){
		LOG("arcan_shmif_resize(), couldn't set"
			"	requested dimensions (%d, %d)\n", px_w, px_h);
		exit(EXIT_FAILURE);
	}

/*
 * tsm_screen_resize if not first,
 * shl_pty_resize to propagate
 */

#ifndef ARCAN_TTF_SUPPORT
	if (term.graphing){
		graphing_destroy(term.graphing);
	}

	term.graphing = graphing_new(px_w, px_h, (uint32_t*) term.arc_conn.vidp);
#endif

	term.screen_w = screenw;
	term.screen_h = screenh;
	term.cell_w = fontw;
	term.cell_h = fonth;
}

#ifndef ARCAN_TTF_SUPPORT
static int draw_cb(struct tsm_screen* screen, uint32_t id,
	const uint32_t* ch, size_t len, unsigned width, unsigned x, unsigned y,
	const struct tsm_screen_attr* attr, tsm_age_t age, void* data)
{
		uint8_t fgc[3], bgc[3];
		uint8_t* dfg = fgc, (* dbg) = bgc;

		if (attr->inverse){
			dfg = bgc;
			dbg = fgc;
		}

		dfg[0] = attr->fr;
		dfg[1] = attr->fg;
		dfg[2] = attr->fb;
		dbg[0] = attr->br;
		dbg[1] = attr->bg;
		dbg[2] = attr->bb;

		draw_box(term.graphing, x * term.cell_w, y * term.cell_h,
			term.cell_w, term.cell_h, RGBA(bgc[0], bgc[1], bgc[2], 0xff));

		uint8_t u8_ch[tsm_ucs4_get_width(*ch) + 1];
		size_t nch = tsm_ucs4_to_utf8(*ch, (char*) u8_ch);
		if (nch == 0)
			return 0;

/* without proper ttf support, we just go with '?' for unknowns */
		u8_ch[0] = u8_ch[0] <= 128 ? u8_ch[0] : '?';
		u8_ch[1] = '\0';

		draw_text(term.graphing, (const char*) u8_ch,
			x * term.cell_w, y * term.cell_h,
			RGBA(fgc[0], fgc[1], fgc[2], 0xff)
		);

		return 0;
}
#else
/* use arcan_ttf or possible a UCS- font lib
 * include renderfon,
 * generate format string,
 */
#endif

static void read_callback(struct shl_pty* pty,
	void* data, char* u8, size_t len)
{
	tsm_vte_input(term.vte, u8, len);
}

static void write_callback(struct tsm_vte* vte,
	const char* u8, size_t len, void* data)
{
	shl_pty_write(term.pty, u8, len);
}

static void setup_shell()
{
	char* shell = getenv("SHELL");
	const struct passwd* pass = getpwuid( getuid() );
	if (pass){
		setenv("LOGNAME", pass->pw_name, 1);
		setenv("USER", pass->pw_name, 1);
		setenv("SHELL", pass->pw_shell, 0);
		setenv("HOME", pass->pw_dir, 0);
	}

	unsetenv("COLUMNS");
	unsetenv("LINES");
	unsetenv("TERMCAP");

	int sigs[] = {
		SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM
	};

	setenv("TERM", "xterm-256color", 1);
	for (int i = 0; i < sizeof(sigs); i++)
		signal(sigs[i], SIG_DFL);

	char* args[] = {shell, "-i", NULL};

	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

static void ioev_ctxtbl(arcan_ioevent* ioev, const char* label)
{
/* map mouse motion + button to select, etc. */
	if (label){
	}

/* keyboard input */
	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		bool pressed = ioev->input.translated.active;
		if (!pressed)
			return;

		tsm_vte_handle_keyboard(term.vte,
			ioev->input.translated.keysym,
			ioev->input.translated.keysym,
			ioev->input.translated.modifiers,
			ioev->input.translated.subid
		);
	}
	else if (ioev->datatype == EVENT_IDATATYPE_DIGITAL){
	}
	else if (ioev->datatype == EVENT_IDATATYPE_ANALOG){
	}
}

static void targetev(arcan_event* tgtev)
{
/*	arcan_tgtevent* ev = &tgtev->data.target; */

	switch (tgtev->kind){
	case TARGET_COMMAND_FDTRANSFER:
		term.last_fd = frameserver_readhandle(tgtev);
	break;

/* switch palette? */
	case TARGET_COMMAND_GRAPHMODE:
	break;

/* sigsuspend */
	case TARGET_COMMAND_PAUSE:
	break;

/* sigresume */
	case TARGET_COMMAND_UNPAUSE:
	break;

	case TARGET_COMMAND_RESET:
		tsm_vte_reset(term.vte);
	break;

/* dump raw to child out, just read/iterate until EOF
 * and map through tsm_vte_input */
	case TARGET_COMMAND_STORE:
	break;

/* redirect raw to parent */
	case TARGET_COMMAND_RESTORE:
	break;

	case TARGET_COMMAND_EXIT:
	break;

	default:
	break;
	}
}

static void main_loop()
{
	while(true){
		arcan_event ev;

		int rc = shl_pty_dispatch(term.pty);
		if (0 < rc){
			printf("pty dispatch fail\n");
		}

		while (arcan_event_poll(&term.arc_conn.inev, &ev) == 1){
			switch (ev.category){
			case EVENT_IO:
				ioev_ctxtbl(&(ev.data.io), ev.label);
			break;

			case EVENT_TARGET:
			break;

			default:
			break;
			}

/* map up: set_palette, reset, hard_reset, input, handle_keyboard,
 * move_to, move_up, move_down, move_left, move_right, move_line_end,
 * move_line_home, tab_right, tab_left, insert_lines, delete_lines,
 * erase_cursor, erase_chars, ... selection reset, selection start,
 * selection copy, ... */
		}

		tsm_screen_draw(term.screen, draw_cb, NULL /* draw_cb_data */);
		arcan_shmif_signal(&term.arc_conn, SHMIF_SIGVID);
	}
}

void arcan_frameserver_terminal_run(const char* resource, const char* keyfile)
{
	struct arg_arr* args = arg_unpack(resource);
	const char* val;

	if (arg_lookup(args, "rows", 0, &val))
		term.rows = strtoul(val, NULL, 10);

	if (arg_lookup(args, "cols", 0, &val))
		term.cols = strtoul(val, NULL, 10);

	if (arg_lookup(args, "cell_w", 0, &val))
		term.cell_w = strtoul(val, NULL, 10);

	if (arg_lookup(args, "cell_h", 0, &val))
		term.cell_h = strtoul(val, NULL, 10);

	if (tsm_screen_new(&term.screen, tsm_log, 0) < 0){
		LOG("fatal, couldn't setup tsm screen\n");
		return;
	}

	if (tsm_vte_new(&term.vte, term.screen, write_callback,
		NULL /* write_cb_data */, tsm_log, NULL /* tsm_log_data */) < 0){
		LOG("fatal, couldn't setup vte\n");
		return;
	}

	term.arc_conn = arcan_shmif_acquire(keyfile, SHMIF_INPUT, true, false);
	if (!term.arc_conn.addr){
		LOG("fatal, couldn't map shared memory from (%s)\n", keyfile);
	}

	tsm_screen_set_max_sb(term.screen, 1000);

	setlocale(LC_CTYPE, "");

/* possible need to track this and run shl_pty_close */
	signal(SIGHUP, SIG_IGN);

	screen_size(term.rows, term.cols, 8, 8);

	if ( (term.child = shl_pty_open(&term.pty,
		read_callback, NULL /* term data */, 80, 25)) == 0){
		setup_shell();
		exit(EXIT_FAILURE);
	}

	if (term.child < 0){
		LOG("couldn't spawn child terminal.\n");
		return;
	}

	arcan_event outev = {
		.kind = EVENT_EXTERNAL_REGISTER,
		.category = EVENT_EXTERNAL,
		.data.external.registr.title = "ArcTerm",
		.data.external.registr.kind = SEGID_SHELL
	};

	arcan_event_enqueue(&term.arc_conn.outev, &outev);
	main_loop();
}
