/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * This is still a rather crude terminal emulator, owing most of its actual
 * heavy lifting to David Hermanns libtsm - which sadly isn't actively
 * maintained anymore.
 *
 * There are quite a few interesting paths to explore here when
 * sandboxing etc. are in place, in particular.
 *
 *   - virtualized /dev/ tree with implementations for /dev/dsp,
 *     /dev/mixer etc. and other device nodes we might want plugged
 *     or unplugged.
 *
 *   - "honey-pot" style proc, sysfs etc.
 *
 *   - mapping / remapping existing file-descriptors in situ
 *
 *  period hint and rescale in between pulses), drag-n-drop
 *  style font switching, dynamic pipe redirection, env clone/restore,
 *  time-keeping manipulation
 *
 * Still there are basic stuff that isn't working so hot at the moment:
 *  - non-freetype supported font rendering
 *  - advanced color
 *  - palette switching
 *  - alternate escape sequences (for titlebar upd. link propagation etc.)
 *  - doubleclick on word
 *  - scrollback- status / control
 *  - cursor / refresh behavior:
 *    - serious flickering in top/mc during drag resize (cps limit?)
 *    - cursor bleed in vim etc.
 *    - cursor style selection, blinking support
 *    - forward mouse cursor input to shell
 *  - integrate tsm in codebase / buildsystem as it isn't work maintaining
 *    as separate dependency anymore
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
#include <pwd.h>
#include <signal.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/signal.h>
#include <sys/wait.h>

#include "tsm/libtsm.h"
#include "tsm/shl-pty.h"

#include <arcan_shmif.h>
#include "frameserver.h"

#include "util/font_8x8.h"

#define DEFINE_XKB
#include "util/xsymconv.h"

#ifdef TTF_SUPPORT
#include "arcan_ttf.h"
static TTF_Font* font;
#endif

static struct {
	struct tsm_screen* screen;
	struct tsm_vte* vte;
	struct shl_pty* pty;

	bool dirty, mute;

	pid_t child;
	int child_fd;

	int rows;
	int cols;
	int mag;
	int cell_w, cell_h;
	int cursor_x, cursor_y;

/* mouse selection management */
	int mouse_x, mouse_y;
	int lm_x, lm_y;
	int bsel_x, bsel_y;
	bool in_select;

/* tracking when to reset scrollback */
	int sbofs;

	uint8_t fgc[3];
	uint8_t bgc[3];
	uint8_t alpha;

	tsm_age_t age;

	struct arcan_shmif_cont acon;

	struct arcan_shmif_cont clip_in;
	struct arcan_shmif_cont clip_out;
} term = {
	.cell_w = 8,
	.cell_h = 8,
	.rows = 25,
	.cols = 80,
	.mag = 1,
	.alpha = 0xff,
	.bgc = {0x00, 0x00, 0x00},
	.fgc = {0xff, 0xff, 0xff},
};

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
}

struct unpack_col {
	union{
		struct {
			uint8_t r;
			uint8_t g;
			uint8_t b;
			uint8_t a;
		};

		uint32_t rgba;
	};
};

/* support different cursor types here; blinking, underline,
 * vert-line, block, square. */

static void cursor_at(int x, int y, shmif_pixel ccol)
{
	size_t w = term.acon.addr->w;
	shmif_pixel* dst = term.acon.vidp;
	x *= term.cell_w;
	y *= term.cell_h;

/* just outline border if we are on top of an existing cell */
	for (int col = x; col < x + term.cell_w; col++){
		dst[y * term.acon.pitch + col] = ccol;
		dst[(y + term.cell_h-1 )* term.acon.pitch + col] = ccol;
	}

	for (int row = y+1; row < y + term.cell_h-1; row++){
		dst[row * term.acon.pitch + x] = ccol;
		dst[row * term.acon.pitch + x + term.cell_w - 1] = ccol;
	}
}

static int draw_cb(struct tsm_screen* screen, uint32_t id,
	const uint32_t* ch, size_t len, unsigned width, unsigned x, unsigned y,
	const struct tsm_screen_attr* attr, tsm_age_t age, void* data)
{
	uint8_t fgc[3], bgc[3];
	uint8_t* dfg = fgc, (* dbg) = bgc;
	int base_y = y * term.cell_h;
	int base_x = x * term.cell_w;

	if (term.mute || (age && term.age && age <= term.age))
		return 0;

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

	term.dirty = true;

	if (x == term.cursor_x && y == term.cursor_y){
/* blend or draw differently */
		cursor_at(x, y, RGBA(0x00, 0xff, 0x00, 0xff));
		return 0;
	}
	else{
		draw_box(&term.acon, base_x, base_y, term.cell_w,
			term.cell_h, SHMIF_RGBA(bgc[0], bgc[1], bgc[2], term.alpha));
	}

	if (len == 0)
		return 0;

	size_t u8_sz = tsm_ucs4_get_width(*ch) + 1;
	uint8_t u8_ch[u8_sz];
	size_t nch = tsm_ucs4_to_utf8(*ch, (char*) u8_ch);

#ifdef TTF_SUPPORT
	if (font == NULL){
#endif
		u8_ch[1] = '\0';
		draw_text(&term.acon, (const char*) u8_ch, base_x, base_y,
			SHMIF_RGBA(fgc[0], fgc[1], fgc[2], 0xff)
		);
		return 0;
#ifdef TTF_SUPPORT
	}
#endif

#ifdef TTF_SUPPORT
	u8_ch[u8_sz-1] = '\0';
	TTF_Color fg = {.r = fgc[0], .g = fgc[1], .b = fgc[2]};

/* unfortunately, this lil' function do not do in-place rendering,
 * should be fixed to cut down on w * h malloc/free pairs */
	TTF_Surface* surf = TTF_RenderUTF8(font, (char*) u8_ch, fg);
	if (!surf)
		return 0;

	size_t w = term.acon.addr->w;
	shmif_pixel* dst = term.acon.vidp;

	for (int row = 0; row < surf->height; row++)
		for (int col = 0; col < surf->width; col++){
			uint8_t* bgra = (uint8_t*) &surf->data[ row * surf->stride + (col * 4) ];
			off_t ofs = (row + base_y) * term.acon.pitch + col + base_x;
			if (bgra[3] == 0)
				dst[ofs] = SHMIF_RGBA(bgc[0], bgc[1], bgc[2], 0xff);
/* blend 1 - src alpha */
			else{
				shmif_pixel inp = dst[ofs];
				uint32_t r, g, b;
/* classic "avoid div hack" */
				r = bgra[3] * fgc[0] + bgc[0] * (255 - bgra[3]);
				r += 0x80;
				r = (r + (r >> 8)) >> 8;
				g = bgra[3] * fgc[1] + bgc[1] * (255 - bgra[3]);
				g += 0x80;
				g = (g + (g >> 8)) >> 8;
				b = bgra[3] * fgc[2] + bgc[2] * (255 - bgra[3]);
				b += 0x80;
				b = (b + (b >> 8)) >> 8;
				dst[ofs] = SHMIF_RGBA(r, g, b, (bgc[0] == term.bgc[0] &&
					bgc[1] == term.bgc[1] && term.bgc[2] == term.bgc[2]) ?
					term.alpha : 0xff);
			}
		}

	free(surf);
	return 0;
#endif
}

static void update_screen()
{
	term.cursor_x = tsm_screen_get_cursor_x(term.screen);
	term.cursor_y = tsm_screen_get_cursor_y(term.screen);
	term.age = tsm_screen_draw(term.screen, draw_cb, NULL /* draw_cb_data */);
}

static void update_screensize(bool cont)
{
	int cols = term.acon.w / term.cell_w;
	int rows = term.acon.h / term.cell_h;

	shmif_pixel px = SHMIF_RGBA(0x00, 0x00, 0x00, term.alpha);
	for (size_t i=0; i < term.acon.pitch * term.acon.h; i++)
		term.acon.vidp[i] = px;

	term.cols = cols;
	term.rows = rows;

	shl_pty_resize(term.pty, cols, rows);
	tsm_screen_resize(term.screen, cols, rows);

	term.age = 0;
	update_screen();
}

static void read_callback(struct shl_pty* pty,
	void* data, char* u8, size_t len)
{
	tsm_vte_input(term.vte, u8, len);
	term.cursor_x = tsm_screen_get_cursor_x(term.screen);
	term.cursor_y = tsm_screen_get_cursor_y(term.screen);
	update_screen();
}

static void write_callback(struct tsm_vte* vte,
	const char* u8, size_t len, void* data)
{
	shl_pty_write(term.pty, u8, len);
}

static void setup_shell(struct arg_arr* argarr)
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

/* might get overridden with putenv below */
	setenv("TERM", "xterm-256color", 1);

	while (arg_lookup(argarr, "env", ind++, &val))
		putenv(strdup(val));

	int sigs[] = {
		SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM
	};

	for (int i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
		signal(sigs[i], SIG_DFL);

	char* args[] = {shell, "-i", NULL};

	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

static void mute_toggle()
{
	term.mute = !term.mute;
	update_screen();
}

static void send_sigint()
{
	shl_pty_signal(term.pty, SIGINT);
}

static void scroll_up()
{
	tsm_screen_sb_up(term.screen, 1);
	term.sbofs += 1;
	update_screen();
}

static void scroll_down()
{
	tsm_screen_sb_down(term.screen, 1);
	term.sbofs -= 1;
	term.sbofs = term.sbofs < 0 ? 0 : term.sbofs;
	update_screen();
}

static void move_up()
{
	if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Up, 0, 0, 0))
		update_screen();
}

static void move_down()
{
	if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Down, 0, 0, 0))
		update_screen();
}

/* in TSM< typically mapped to ctrl+ arrow but we allow external rebind */
static void move_left()
{
	if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Left, 0, 0, 0))
		update_screen();
}

static void move_right()
{
	if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Right, 0, 0, 0))
		update_screen();
}

static void select_begin()
{
	tsm_screen_selection_start(term.screen,
		tsm_screen_get_cursor_x(term.screen),
		tsm_screen_get_cursor_y(term.screen)
	);
}

#include "util/utf8.c"

static void select_copy()
{
	char* sel = NULL;
/*
 * there are more advanced clipboard options to be used when
 * we have the option of exposing other devices using a fuse- vfs
 * in: /vdev/istream, /vdev/vin, /vdev/istate
 * out: /vdev/ostream, /dev/vout, /vdev/vstate, /vdev/dsp
 */
	if (!term.clip_out.vidp)
		return;

/* the selection routine here seems very wonky, assume the complexity comes
 * from char.conv and having to consider scrollback -- but the current behavior
 * looks like it cuts of on whitespace */
	tsm_screen_selection_copy(term.screen, &sel);
	if (!sel)
		return;

	arcan_event msgev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	uint32_t state = 0, codepoint = 0, len = strlen(sel);
	char* outs = sel;
	size_t maxlen = sizeof(msgev.ext.message) - 1;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i < maxlen; i++){
		if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(sel[i])))
			lastok = i;

			if (i != lastok){
				i = lastok;
				if (0 == i)
					return;
			}
		}

		memcpy(msgev.ext.message.data, outs, i);
		msgev.ext.message.data[i] = '\0';
		len -= i;
		outs += i;
		if (len)
			msgev.ext.message.multipart = 1;
		else
			msgev.ext.message.multipart = 0;

		arcan_shmif_enqueue(&term.clip_out, &msgev);
	}

/* flush remaining */
	if (len){
		snprintf((char*)msgev.ext.message.data, maxlen, "%s", outs);
		msgev.ext.message.multipart = 0;
		arcan_shmif_enqueue(&term.clip_out, &msgev);
	}

	free(sel);
}

static void select_cancel()
{
	tsm_screen_selection_reset(term.screen);
}

static void page_up()
{
	tsm_screen_sb_up(term.screen, term.rows);
	term.sbofs += term.rows;
	update_screen();
}

static void page_down()
{
	tsm_screen_sb_down(term.screen, term.rows);
	term.sbofs -= term.rows;
	term.sbofs = term.sbofs < 0 ? 0 : term.sbofs;
	update_screen();
}

/* map to the quite dangerous SIGUSR1 when we don't have INFO? */
static void send_siginfo()
{
	shl_pty_signal(term.pty, SIGUSR1);
}

struct lent {
	const char* lbl;
	void(*ptr)(void);
};

static const struct lent labels[] = {
	{"MUTE", mute_toggle},
	{"SIGINT", send_sigint},
	{"SIGINFO", send_siginfo},
	{"SCROLL_UP", scroll_up},
	{"SCROLL_DOWN", scroll_down},
	{"PAGE_UP", page_up},
	{"PAGE_DOWN", page_down},
	{"UP", move_up},
	{"DOWN", move_down},
	{"LEFT", move_left},
	{"RIGHT", move_right},
	{NULL, NULL}
};

static void expose_labels()
{
	const struct lent* cur = labels;

	while(cur->lbl){
		arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(LABELHINT),
			.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
		};
		snprintf(ev.ext.labelhint.label,
			sizeof(ev.ext.labelhint.label)/sizeof(ev.ext.labelhint.label[0]),
			"%s", cur->lbl
		);
		cur++;
		arcan_shmif_enqueue(&term.acon, &ev);
	}
}

static bool consume_label(arcan_ioevent* ioev, const char* label)
{
	const struct lent* cur = labels;
	while(cur->lbl){
		if (strcmp(label, cur->lbl) == 0){
			cur->ptr();
			update_screen();
			return true;
		}
		cur++;
	}

	return false;
}

static void ioev_ctxtbl(arcan_ioevent* ioev, const char* label)
{
/* keyboard input */
	int shmask = 0;
	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		bool pressed = ioev->input.translated.active;
		if (!pressed)
			return;

		if (label[0] && consume_label(ioev, label))
			return;

		if (term.sbofs != 0){
			term.sbofs = 0;
			tsm_screen_sb_reset(term.screen);
			update_screen();
		}

/* ignore the meta keys as we already treat them in modifiers */
		int sym = ioev->input.translated.keysym;
		if (sym >= 300 && sym <= 314)
			return;

/* if utf8- values have been supplied, use them! */
		if (ioev->input.translated.utf8[0]){
			size_t len = 0;
			while (len < 5 && ioev->input.translated.utf8[len]) len++;
			shl_pty_write(term.pty, (char*)ioev->input.translated.utf8, len);
			return;
		}

/* otherwise try to hack something together */
		shmask |= ((ioev->input.translated.modifiers &
			(ARKMOD_RSHIFT | ARKMOD_LSHIFT)) > 0) * TSM_SHIFT_MASK;
		shmask |= ((ioev->input.translated.modifiers &
			(ARKMOD_LCTRL | ARKMOD_RCTRL)) > 0) * TSM_CONTROL_MASK;
		shmask |= ((ioev->input.translated.modifiers &
			(ARKMOD_LALT | ARKMOD_RALT)) > 0) * TSM_ALT_MASK;
		shmask |= ((ioev->input.translated.modifiers &
			(ARKMOD_LMETA | ARKMOD_RMETA)) > 0) * TSM_LOGO_MASK;
		shmask |= ((ioev->input.translated.modifiers & ARKMOD_NUM) > 0) * TSM_LOCK_MASK;

		if (sym && sym < sizeof(symtbl_out) / sizeof(symtbl_out[0]))
			sym = symtbl_out[ioev->input.translated.keysym];

		if (tsm_vte_handle_keyboard(term.vte,
			sym, /* should be 'keysym' */
			sym, // ioev->input.translated.keysym, /* should be ascii */
			shmask,
			ioev->subid /* should be unicode */
		)){}
	}
	else if (ioev->devkind == EVENT_IDEVKIND_MOUSE){
		if (ioev->datatype == EVENT_IDATATYPE_ANALOG){
			if (ioev->subid == 0)
				term.mouse_x = ioev->input.analog.axisval[0] / term.cell_w;
			else if (ioev->subid == 1){
				term.mouse_y = ioev->input.analog.axisval[0] / term.cell_h;
				if (!term.in_select)
					return;

				bool upd = false;
				if (term.mouse_x != term.lm_x){
					term.lm_x = term.mouse_x;
					upd = true;
				}
				if (term.mouse_y != term.lm_y){
					term.lm_y = term.mouse_y;
					upd = true;
				}

				if (upd){
					tsm_screen_selection_target(term.screen, term.lm_x, term.lm_y);
					update_screen();
				}
/* in select? check if motion tile is different than old, if so,
 * tsm_selection_target */
			}
		}
/* press? press-point tsm_screen_selection_start,
 * release and press-tile ~= release_tile? copy */
		else if (ioev->subid == 1){
			if (ioev->input.digital.active){
				tsm_screen_selection_start(term.screen, term.mouse_x, term.mouse_y);
				term.bsel_x = term.mouse_x;
				term.bsel_y = term.mouse_y;
				term.lm_x = term.mouse_x;
				term.lm_y = term.mouse_y;
				term.in_select = true;
			}
			else{
				if (term.mouse_x != term.bsel_x || term.mouse_y != term.bsel_y)
					select_copy();
				tsm_screen_selection_reset(term.screen);
				term.in_select = false;
				update_screen();
			}
		}
	}
}

static void targetev(arcan_tgtevent* ev)
{
	switch (ev->kind){
/* switch palette? */
	case TARGET_COMMAND_GRAPHMODE:
	break;

/* sigsuspend to group */
	case TARGET_COMMAND_PAUSE:
	break;

/* sigresume to session */
	case TARGET_COMMAND_UNPAUSE:
	break;

	case TARGET_COMMAND_RESET:
		tsm_vte_hard_reset(term.vte);
	break;

	case TARGET_COMMAND_BCHUNK_IN:
	case TARGET_COMMAND_BCHUNK_OUT:
/* map ioev[0].iv to some reachable known path in
 * the terminal namespace, don't forget to dupe as it
 * will be on next event */
	break;

	case TARGET_COMMAND_DISPLAYHINT:{
		arcan_shmif_resize(&term.acon, ev->ioevs[0].iv, ev->ioevs[1].iv);
		update_screensize(ev->ioevs[2].iv != 0);
	}
	break;

/*
 * map the two clipboards needed for both cut and for paste operations
 */
	case TARGET_COMMAND_NEWSEGMENT:
		if (ev->ioevs[1].iv == 1){
			if (!term.clip_in.vidp){
				term.clip_in = arcan_shmif_acquire(&term.acon,
					NULL, SEGID_CLIPBOARD_PASTE, 0);
			}
			else
				LOG("multiple paste- clipboards received, likely appl. error\n");
		}
		else if (ev->ioevs[1].iv == 0){
			if (!term.clip_out.vidp){
				term.clip_out = arcan_shmif_acquire(&term.acon,
					NULL, SEGID_CLIPBOARD, 0);
			}
			else
				LOG("multiple clipboards received, likely appl. error\n");
		}
	break;

	case TARGET_COMMAND_STEPFRAME:
	break;

/* problem:
 *  1. how to grab and pack shell environment?
 *  2. kill shell, spawn new using unpacked environment */
	case TARGET_COMMAND_STORE:
	case TARGET_COMMAND_RESTORE:
	break;

	case TARGET_COMMAND_EXIT:
		exit(EXIT_SUCCESS);
	break;

	default:
	break;
	}
}

static void event_dispatch(arcan_event* ev)
{
	switch (ev->category){
	case EVENT_IO:
		ioev_ctxtbl(&(ev->io), ev->io.label);
	break;

	case EVENT_TARGET:
		targetev(&ev->tgt);
	break;
/* map up: set_palette,
 * move_line_end, move_line_home,
 * tab_right, tab_left, insert_lines, delete_lines,
 */

	default:
	break;
	}
}

static void check_pasteboard()
{
	arcan_event ev;

	while (arcan_shmif_poll(&term.clip_in, &ev) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		arcan_tgtevent* tev = &ev.tgt;
		switch(tev->kind){
		case TARGET_COMMAND_MESSAGE:
			shl_pty_write(term.pty, tev->message, strlen(tev->message));
		break;
		case TARGET_COMMAND_EXIT:
			arcan_shmif_drop(&term.clip_in);
			return;
		break;
		default:
		break;
		}
	}
}

#ifdef TTF_SUPPORT
static void probe_font(const char* msg, size_t* dw, size_t* dh)
{
	TTF_Color fg = {.r = 0xff, .g = 0xff, .b = 0xff};
	int w = *dw, h = *dh;
	TTF_SizeText(font, msg, &w, &h);

	if (w > *dw)
		*dw = w;

	if (h > *dh)
		*dh = h;
}
#endif

static void main_loop()
{
	arcan_event ev;

	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
	int ptyfd = shl_pty_get_fd(term.pty);

	while(term.acon.addr->dms){
		int pc = 2;
		struct pollfd fds[3] = {
			{ .fd = ptyfd, .events = pollev},
			{ .fd = term.acon.epipe, .events = pollev},
			{ .fd  = -1, .events = pollev}
		};

/* if we've received a clipboard for paste- operations */
		if (term.clip_in.vidp){
			fds[2].fd = term.clip_in.epipe;
			pc = 3;
		}

		int sv = poll(fds, pc, 32);
		if (fds[0].revents & POLLIN){
			int rc = shl_pty_dispatch(term.pty);
		}
		else if (fds[0].revents)
			break;

		if (fds[1].revents & POLLIN){
			while (arcan_shmif_poll(&term.acon, &ev) > 0)
				event_dispatch(&ev);
			int rc = shl_pty_dispatch(term.pty);
		}
		else if (fds[1].revents)
			break;
		else if (pc == 3 && (fds[2].revents & POLLIN))
			check_pasteboard();
/* audible beep or not? */
		if (term.dirty && !term.mute){
			arcan_shmif_signal(&term.acon, SHMIF_SIGVID);
			term.dirty = false;
		}
	}
	arcan_shmif_drop(&term.acon);
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"    key      \t   value   \t   description\n"
		"-------------\t-----------\t-----------------\n"
		" rows        \t n_rows    \t specify initial number of terminal rows\n"
	  " cols        \t n_cols    \t specify initial number of terminal columns\n"
		" cell_w      \t px_w      \t specify individual cell width in pixels\n"
		" cell_h      \t px_h      \t specify individual cell height in pixels\n"
		" bgr         \t rv(0..255)\t background red channel\n"
		" bgg         \t rv(0..255)\t background green channel\n"
		" bgb         \t rv(0..255)\t background blue channel\n"
		" bgalpha     \t rv(0..255)\t background opacity (default: 255, opaque)\n"
		" fgr         \t rv(0..255)\t foreground red channel\n"
		" fgg         \t rv(0..255)\t foreground green channel\n"
		" fgb         \t rv(0..255)\t foreground blue channel\n"
		" palette     \t name      \t use built-in palette (below)\n"
#ifdef TTF_SUPPORT
		" font        \t ttf-file  \t render using font specified by ttf-file\n"
		" font_sz     \t px        \t set font rendering size (may alter cellsz))\n"
		" font_hint   \t hintval   \t hint to font renderer (light, mono, none)\n"
#endif
		"Built-in palettes:\n"
		"default, solarized, solarized-black, solarized-white\n"
		"---------\t-----------\t----------------\n"
	);
}

int afsrv_terminal(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	const char* val;
#ifdef TTF_SUPPORT
	TTF_Init();
#endif

	if (!con || arg_lookup(args, "help", 0, &val)){
		dump_help();
		return EXIT_FAILURE;
	}

	bool custom_w = false;
	if (arg_lookup(args, "rows", 0, &val))
		term.rows = strtoul(val, NULL, 10);

	if (arg_lookup(args, "cols", 0, &val))
		term.cols = strtoul(val, NULL, 10);

	if (arg_lookup(args, "cell_w", 0, &val)){
		custom_w = true;
		term.cell_w = strtoul(val, NULL, 10);
	}

	if (arg_lookup(args, "fgr", 0, &val))
		term.fgc[0] = strtoul(val, NULL, 10);
	if (arg_lookup(args, "fgg", 0, &val))
		term.fgc[1] = strtoul(val, NULL, 10);
	if (arg_lookup(args, "fgb", 0, &val))
		term.fgc[2] = strtoul(val, NULL, 10);

	if (arg_lookup(args, "bgr", 0, &val))
		term.bgc[0] = strtoul(val, NULL, 10);
	if (arg_lookup(args, "bgg", 0, &val))
		term.bgc[1] = strtoul(val, NULL, 10);
	if (arg_lookup(args, "bgb", 0, &val))
		term.bgc[2] = strtoul(val, NULL, 10);

	if (arg_lookup(args, "bgalpha", 0, &val))
		term.alpha = strtoul(val, NULL, 10);

	if (arg_lookup(args, "cell_h", 0, &val)){
		custom_w = true;
		term.cell_h = strtoul(val, NULL, 10);
	}
#ifdef TTF_SUPPORT
	size_t sz = term.cell_h;
	if (arg_lookup(args, "font_sz", 0, &val))
		sz = strtoul(val, NULL, 10);
	if (arg_lookup(args, "font", 0, &val)){
		font = TTF_OpenFont(val, sz);
		if (!font)
			LOG("font %s could not be opened, forcing built-in fallback\n", val);
		else {
			LOG("font %s opened, ", val);
			if (arg_lookup(args, "font_hint", 0, &val)){
			if (strcmp(val, "light") == 0)
				TTF_SetFontHinting(font, TTF_HINTING_LIGHT);
			else if (strcmp(val, "mono") == 0)
				TTF_SetFontHinting(font, TTF_HINTING_MONO);
			else if (strcmp(val, "none") == 0)
				TTF_SetFontHinting(font, TTF_HINTING_NONE);
			else{
				LOG("unknown hinting %s, falling back to none\n", val);
				TTF_SetFontHinting(font, TTF_HINTING_NONE);
			}
		}
		else{
			LOG("no hinting specified, using none.\n");
			TTF_SetFontHinting(font, TTF_HINTING_NONE);
		}

/* Just run through a practice set to determine the actual width when hinting
 * is taken into account. We still suffer the problem of more advanced glyphs
 * though */
		if (!custom_w){
			TTF_SetFontStyle(font, TTF_STYLE_BOLD);
			size_t w = 0, h = 0;
			static const char* set[] = {
				"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
				"m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "x", "y",
				"z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
				"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
				"M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "X", "Y",
				"Z"
			};
			for (size_t i = 0; i < sizeof(set)/sizeof(set[0]); i++)
				probe_font(set[i], &w, &h);
			if (w && h){
				term.cell_w = w;
				term.cell_h = h;
			}
			TTF_SetFontStyle(font, TTF_STYLE_NORMAL);
		}
	}
	}
	else
		LOG("no font specified, using built-in fallback.");
#endif

	if (tsm_screen_new(&term.screen, tsm_log, 0) < 0){
		LOG("fatal, couldn't setup tsm screen\n");
		return EXIT_FAILURE;
	}

	if (tsm_vte_new(&term.vte, term.screen, write_callback,
		NULL /* write_cb_data */, tsm_log, NULL /* tsm_log_data */) < 0){
		LOG("fatal, couldn't setup vte\n");
		return EXIT_FAILURE;
	}

	if (arg_lookup(args, "palette", 0, &val))
		tsm_vte_set_palette(term.vte, val);

	gen_symtbl();
	term.acon = *con;

	arcan_shmif_resize(&term.acon,
		term.cell_w * term.cols, term.cell_h * term.rows);
	update_screensize(false);
	expose_labels();
	tsm_screen_set_max_sb(term.screen, 1000);

	struct tsm_screen_attr attr = {
		.fccode = -1,
		.bccode = -1,
		.fr = term.fgc[0],
		.fg = term.fgc[1],
		.fb = term.fgc[2],
		.br = term.bgc[0],
		.bg = term.bgc[1],
		.bb = term.bgc[2]
	};
	tsm_screen_set_def_attr(term.screen, &attr);

	setlocale(LC_CTYPE, "C");
	signal(SIGHUP, SIG_IGN);

	if ( (term.child = shl_pty_open(&term.pty,
		read_callback, NULL, term.rows, term.cols)) == 0){
		setup_shell(args);
		exit(EXIT_FAILURE);
	}

	if (term.child < 0){
		LOG("couldn't spawn child terminal.\n");
		return EXIT_FAILURE;
	}

/* immediately request a clipboard for cut operations (none received ==
 * running appl doesn't care about cut'n'paste/drag'n'drop support). */
	arcan_event segreq = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.width = 1,
		.ext.segreq.height = 1,
		.ext.segreq.kind = SEGID_CLIPBOARD,
		.ext.segreq.id = 0xfeedface
	};
	arcan_shmif_enqueue(&term.acon, &segreq);

	main_loop();
	return EXIT_SUCCESS;
}
