/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * This is still a crude terminal emulator, with most of the heavy lifting
 * due to David Herrmanns libtsm. Most of the common features are in place,
 * with the following rough list on the 'todo':
 *
 * - Compatibilty Work
 * - More / Better cursor and offscreen buffer support
 * - X Mouse protocols and similar extensions (set titlebar text etc.)
 *
 * Known Bugs:
 *  - Some fullscreen rendering (vim) and scrolling issues
 *
 * Experiments:
 *  - State transfers (of env, etc. to allow restore)
 *  - Paste complex data streams into shell namespace (to move files)
 *  - Injecting / redirecting descriptors (senseye integration)
 *  - Drag and Drop- file copy
 *  - Time-keeping manipulation
 *
 * Another decent project is to take a lot of this interface and move into
 * some re-usable utility- code for tile-text like interfaces for
 * applications like senseye translators and similar to re-use with working
 * cut-and-pace/behavior respecting displayhints, fonthints etc.
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
#include <math.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/types.h>
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
#else
typedef struct {
    uint8_t r, g, b;
} TTF_Color;
#endif

enum cursors {
	CURSOR_BLOCK = 0,
	CURSOR_HALFBLOCK,
	CURSOR_FRAME,
	CURSOR_VLINE,
	CURSOR_ULINE,
	CURSOR_END
};

enum dirty_state {
	DIRTY_NONE = 0,
	DIRTY_UPDATED = 1,
	DIRTY_PENDING = 2,
	DIRTY_PENDING_FULL = 4
};

struct {
/* terminal / state control */
	struct tsm_screen* screen;
	struct tsm_vte* vte;
	struct shl_pty* pty;
	pid_t child;
	int child_fd;
	unsigned flags;
	bool focus, inactive;
	int inact_timer;

/* font rendering / tracking - we support one main that defines cell size
 * and one secondary that can be used for alternative glyphs */
#ifdef TTF_SUPPORT
	TTF_Font* font[2];
	int font_fd[2];
	int hint;
/* size in font pt */
	size_t font_sz;
#endif
	float ppcm;
	enum dirty_state dirty;
	int64_t last;

/* if we receive a label set in mouse events, we switch to a different
 * interpreteation where drag, click, dblclick, wheelup, wheeldown work */
	bool gesture_support;

/* mouse selection management */
	int mouse_x, mouse_y;
	int lm_x, lm_y;
	int bsel_x, bsel_y;
	bool in_select;
	int scrollback;
	bool mouse_forward;
	bool scroll_lock;

/* tracking when to reset scrollback */
	int sbofs;

/* color, cursor and other drawing states */
	int cursor_x, cursor_y;
	int last_dbl_x,last_dbl_y;
	int rows;
	int cols;
	int last_shmask;
	int cell_w, cell_h, pad_w, pad_h;

	uint8_t fgc[3];
	uint8_t bgc[3];
	shmif_pixel ccol, clcol;

/* store a copy of the state where the cursor is */
	struct tsm_screen_attr cattr;
	uint32_t cvalue;
	bool cursor_off;
	enum cursors cursor;

	uint8_t alpha;

/* track last time counter we did update on to avoid overdraw */
	tsm_age_t age;

/* upstream connection */
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont clip_in;
	struct arcan_shmif_cont clip_out;
} term = {
	.cell_w = 8,
	.cell_h = 8,
	.focus = true,
	.rows = 25,
	.cols = 80,
	.alpha = 0xff,
	.bgc = {0x00, 0x00, 0x00},
	.fgc = {0xff, 0xff, 0xff},
	.ccol = SHMIF_RGBA(0x00, 0xaa, 0x00, 0xff),
	.clcol = SHMIF_RGBA(0xaa, 0xaa, 0x00, 0xff),
#ifdef TTF_SUPPORT
	.font_fd = {BADFD, BADFD},
	.ppcm = ARCAN_SHMPAGE_DEFAULT_PPCM,
	.hint = TTF_HINTING_NONE
#endif
};

/* to be able to update the cursor cell with other information */
static int draw_cbt(struct tsm_screen* screen, uint32_t ch,
	unsigned x, unsigned y, const struct tsm_screen_attr* attr,
	tsm_age_t age, bool cstate, bool empty);

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
}

const char* curslbl[] = {
	"block",
	"halfblock",
	"frame",
	"vline",
	"uline",
	NULL
};

static void cursor_at(int x, int y, shmif_pixel ccol, bool active)
{
	shmif_pixel* dst = term.acon.vidp;
	x *= term.cell_w;
	y *= term.cell_h;

/* first draw "original character" if it's not occluded */
	if (term.cursor_off || term.cursor != CURSOR_BLOCK){
		draw_cbt(term.screen, term.cvalue, term.cursor_x, term.cursor_y,
			&term.cattr, 0, false, false);
	}
	if (term.cursor_off)
		return;

	switch (term.cursor){
	case CURSOR_BLOCK:
		draw_box(&term.acon, x, y, term.cell_w, term.cell_h, ccol);
	break;
	case CURSOR_HALFBLOCK:
	draw_box(&term.acon, x, y, term.cell_w >> 1, term.cell_h, ccol);
	break;
	case CURSOR_FRAME:
		for (int col = x; col < x + term.cell_w; col++){
			dst[y * term.acon.pitch + col] = ccol;
			dst[(y + term.cell_h-1 ) * term.acon.pitch + col] = ccol;
		}

		for (int row = y+1; row < y + term.cell_h-1; row++){
			dst[row * term.acon.pitch + x] = ccol;
			dst[row * term.acon.pitch + x + term.cell_w - 1] = ccol;
		}
	break;
	case CURSOR_VLINE:
		draw_box(&term.acon, x + 1, y, 1, term.cell_h, ccol);
	break;
	case CURSOR_ULINE:
		draw_box(&term.acon, x, y+term.cell_h-1, term.cell_w, 1, ccol);
	break;
	case CURSOR_END:
	default:
	break;
	}
}

static void draw_ch_u8(uint8_t u8_ch[5],
	int base_x, int base_y, uint8_t fg[4], uint8_t bg[4],
	bool bold, bool underline, bool italic)
{
	u8_ch[1] = '\0';
	draw_text_bg(&term.acon, (const char*) u8_ch, base_x, base_y,
		SHMIF_RGBA(fg[0], fg[1], fg[2], fg[3]),
		SHMIF_RGBA(bg[0], bg[1], bg[2], bg[3])
	);
}

#ifdef TTF_SUPPORT
static void draw_ch(uint32_t ch,
	int base_x, int base_y, uint8_t fg[4], uint8_t bg[4],
	bool bold, bool underline, bool italic)
{
	draw_box(&term.acon, base_x, base_y, term.cell_w, term.cell_h,
		SHMIF_RGBA(bg[0], bg[1], bg[2], bg[3]));

	int prem = TTF_STYLE_NORMAL | (TTF_STYLE_UNDERLINE * underline);
	prem |= TTF_STYLE_ITALIC * italic;
	prem |= (bold ? TTF_STYLE_BOLD : TTF_STYLE_NORMAL);

	unsigned xs = 0, ind = 0;
	int adv = 0;

	TTF_RenderUNICODEglyph(
		&term.acon.vidp[base_y * term.acon.pitch + base_x],
		term.cell_w, term.cell_h, term.acon.pitch,
		term.font, term.font[1] ? 2 : 1,
		ch, &xs, fg, bg, true, false, prem, &adv, &ind
	);
}
#endif

static void send_cell_sz()
{
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE),
	};

	sprintf((char*)ev.ext.message.data, "cell_w:%d:cell_h:%d",
		term.cell_w, term.cell_h);
	arcan_shmif_enqueue(&term.acon, &ev);
}

static int draw_cb(struct tsm_screen* screen, uint32_t id,
	const uint32_t* ch, size_t len, unsigned width, unsigned x, unsigned y,
	const struct tsm_screen_attr* attr, tsm_age_t age, void* data)
{
	return
	draw_cbt(screen,*ch, x, y, attr, age,
		!(term.flags & TSM_SCREEN_HIDE_CURSOR), len == 0);
}

static int draw_cbt(struct tsm_screen* screen, uint32_t ch,
	unsigned x, unsigned y, const struct tsm_screen_attr* attr,
	tsm_age_t age, bool cstate, bool empty)
{
	uint8_t fgc[4] = {attr->fr, attr->fg, attr->fb, 255};
	uint8_t bgc[4] = {attr->br, attr->bg, attr->bb, term.alpha};
	uint8_t* dfg = fgc, (* dbg) = bgc;
	int y1 = y * term.cell_h;
	int x1 = x * term.cell_w;

	if (x >= term.cols || y >= term.rows)
		return 0;

	if (age && term.age && age <= term.age)
		return 0;

	if (attr->inverse){
		dfg = bgc;
		dbg = fgc;
		dbg[3] = term.alpha;
		dfg[3] = 0xff;
	}

	int x2 = x1 + term.cell_w;
	int y2 = y1 + term.cell_h;

/* update dirty rectangle for synchronization */
	if (x1 < term.acon.dirty.x1)
		term.acon.dirty.x1 = x1;
	if (x2 > term.acon.dirty.x2)
		term.acon.dirty.x2 = x2;
	if (y1 < term.acon.dirty.y1)
		term.acon.dirty.y1 = y1;
	if (y2 > term.acon.dirty.y2)
		term.acon.dirty.y2 = y2;

	bool match_cursor = false;
	if (x == term.cursor_x && y == term.cursor_y){
		if (!(tsm_screen_get_flags(term.screen) & TSM_SCREEN_HIDE_CURSOR))
			match_cursor = cstate;
	}

	term.dirty |= DIRTY_UPDATED;

	draw_box(&term.acon, x1, y1, term.cell_w, term.cell_h,
		SHMIF_RGBA(bgc[0], bgc[1], bgc[2], term.alpha));

/* quick erase if nothing more is needed */
	if (empty){
		if (attr->inverse)
	draw_box(&term.acon, x1, y1, term.cell_w, term.cell_h,
		SHMIF_RGBA(fgc[0], fgc[1], fgc[2], term.alpha));

	if (!match_cursor)
			return 0;
		else
			ch = 0x00000008;
	}

	if (match_cursor){
		term.cattr = *attr;
		term.cvalue = ch;
		cursor_at(x, y, term.scroll_lock ? term.clcol : term.ccol, true);
		return 0;
	}

#ifdef TTF_SUPPORT
	if (!term.font[0]){
#endif
	size_t u8_sz = tsm_ucs4_get_width(ch) + 1;
	uint8_t u8_ch[u8_sz];
	size_t nch = tsm_ucs4_to_utf8(ch, (char*) u8_ch);
	u8_ch[u8_sz-1] = '\0';
		draw_ch_u8(u8_ch, x1, y1, dfg, dbg,
			attr->bold, attr->underline, attr->italic);
#ifdef TTF_SUPPORT
	}
	else
		draw_ch(ch, x1, y1, dfg, dbg, attr->bold, attr->underline, attr->italic);
#endif

	return 0;
}

static void update_screen()
{
/* don't redraw while we have an update pending or when we
 * are in an invisible state */
	if (term.inactive)
		return;

/* "always" erase previous cursor, except when terminal screen state explicitly
 * say that cursor drawing should be turned off */
	draw_cbt(term.screen, term.cvalue, term.cursor_x, term.cursor_y,
		&term.cattr, 0, false, false);

	term.cursor_x = tsm_screen_get_cursor_x(term.screen);
	term.cursor_y = tsm_screen_get_cursor_y(term.screen);

	if (term.dirty & DIRTY_PENDING_FULL){
		term.acon.dirty.x1 = 0;
		term.acon.dirty.x2 = term.acon.w;
		term.acon.dirty.y1 = 0;
		term.acon.dirty.y2 = term.acon.h;
		tsm_screen_selection_reset(term.screen);

		shmif_pixel col = SHMIF_RGBA(
			term.bgc[0],term.bgc[1],term.bgc[2],term.alpha);

		if (term.pad_w)
			draw_box(&term.acon,
				term.acon.w-term.pad_w-1, 0, term.pad_w+1, term.acon.h, col);
		if (term.pad_h)
			draw_box(&term.acon,
				0, term.acon.h-term.pad_h-1, term.acon.w, term.pad_h+1, col);
	}

	term.flags = tsm_screen_get_flags(term.screen);
	term.age = tsm_screen_draw(term.screen, draw_cb, NULL /* draw_cb_data */);

	draw_cbt(term.screen, term.cvalue, term.cursor_x, term.cursor_y,
		&term.cattr, 0, !term.cursor_off, false);
}

/*
 * Note that this can currently lead to tearing problems (draw calls
 * while pending and no queue mechanism for resize step) but considering
 * all the other funky steps that happen here..
 */
static void update_screensize(bool clear)
{
	int cols = term.acon.w / term.cell_w;
	int rows = term.acon.h / term.cell_h;
	LOG("update screensize (%d * %d), (%d * %d)\n",
		cols, rows, (int)term.acon.w, (int)term.acon.h);

	term.pad_w = term.acon.w - (cols * term.cell_w);
	term.pad_h = term.acon.h - (rows * term.cell_h);

	if (cols != term.cols || rows != term.rows){
		if (cols > term.cols)
			term.pad_w += (cols - term.cols) * term.cell_w;

		if (rows > term.rows)
			term.pad_h += (rows - term.rows) * term.cell_h;

		int dr = term.rows - rows;
		term.cols = cols;
		term.rows = rows;

/*
 * actual resize, we can assume that we are not in signal
 * state as shmif_ will block on that
 */
		shl_pty_resize(term.pty, cols, rows);
		tsm_screen_resize(term.screen, cols, rows);
	}

	while (atomic_load(&term.acon.addr->vready))
		;

	shmif_pixel col = SHMIF_RGBA(
		term.bgc[0],term.bgc[1],term.bgc[2],term.alpha);

	if (clear)
		draw_box(&term.acon, 0, 0, term.acon.w, term.acon.h, col);

/* will enforce full redraw, and full redraw will also update padding */
	term.dirty |= DIRTY_PENDING_FULL;
	update_screen();
}

static void read_callback(struct shl_pty* pty,
	void* data, char* u8, size_t len)
{
	tsm_vte_input(term.vte, u8, len);
	term.cursor_x = tsm_screen_get_cursor_x(term.screen);
	term.cursor_y = tsm_screen_get_cursor_y(term.screen);
	term.dirty |= DIRTY_PENDING;
}

static void write_callback(struct tsm_vte* vte,
	const char* u8, size_t len, void* data)
{
	shl_pty_write(term.pty, u8, len);
	shl_pty_dispatch(term.pty);
	term.dirty |= DIRTY_PENDING;
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

	if ((msg[0] == '0' || msg[0] == '1' || msg[0] == '2') && msg[1] == ';'){
		arcan_event outev = {
			.ext.kind = ARCAN_EVENT(IDENT),
			.category = EVENT_EXTERNAL
		};
		size_t lim=sizeof(outev.ext.message.data)/sizeof(outev.ext.message.data[1]);
		snprintf((char*)outev.ext.message.data, lim, "%s", &msg[2]);
		arcan_shmif_enqueue(&term.acon, &outev);
	}
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

static void send_sigint()
{
	shl_pty_signal(term.pty, SIGINT);
}

static void page_up()
{
	tsm_screen_sb_up(term.screen, term.rows);
	term.sbofs += term.rows;
	term.dirty |= DIRTY_PENDING;
}

static void page_down()
{
	tsm_screen_sb_down(term.screen, term.rows);
	term.sbofs -= term.rows;
	term.sbofs = term.sbofs < 0 ? 0 : term.sbofs;
	term.dirty |= DIRTY_PENDING;
}

static void scroll_up()
{
	tsm_screen_sb_up(term.screen, 1);
	term.sbofs += 1;
	term.dirty |= DIRTY_PENDING;
}

static void scroll_down()
{
	tsm_screen_sb_down(term.screen, 1);
	term.sbofs -= 1;
	term.sbofs = term.sbofs < 0 ? 0 : term.sbofs;
	term.dirty |= DIRTY_PENDING;
}

static void move_up()
{
	if (term.scroll_lock)
		page_up();
	else if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Up, 0, 0, 0))
		term.dirty |= DIRTY_PENDING;
}

static void move_down()
{
	if (term.scroll_lock)
		page_down();
	if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Down, 0, 0, 0))
		term.dirty |= DIRTY_PENDING;
}

/* in TSM< typically mapped to ctrl+ arrow but we allow external rebind */
static void move_left()
{
	if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Left, 0, 0, 0))
		term.dirty |= DIRTY_PENDING;
}

static void move_right()
{
	if (tsm_vte_handle_keyboard(term.vte, XKB_KEY_Right, 0, 0, 0))
		term.dirty |= DIRTY_PENDING;
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
 * from char.conv and having to consider scrollback */
	ssize_t len = tsm_screen_selection_copy(term.screen, &sel);
	if (!sel || len <= 1)
		return;

	len--;
	arcan_event msgev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

/* empty cells gets marked as null, but that would cut the copy short */
	for (size_t i = 0; i < len; i++){
		if (sel[i] == '\0')
			sel[i] = ' ';
	}

	uint32_t state = 0, codepoint = 0;
	char* outs = sel;
	size_t maxlen = sizeof(msgev.ext.message.data) - 1;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
		if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(sel[i])))
			lastok = i;

			if (i != lastok){
				if (0 == i)
					return;
			}
		}

		memcpy(msgev.ext.message.data, outs, lastok);
		msgev.ext.message.data[lastok] = '\0';
		len -= lastok;
		outs += lastok;
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

/* map to the quite dangerous SIGUSR1 when we don't have INFO? */
static void send_siginfo()
{
#ifdef SIGINFO
	shl_pty_signal(term.pty, SIGINFO);
#else
	shl_pty_signal(term.pty, SIGUSR1);
#endif
}

static void select_at()
{
	tsm_screen_selection_reset(term.screen);
	unsigned sx, sy, ex, ey;
	int rv = tsm_screen_get_word(term.screen,
		term.mouse_x, term.mouse_y, &sx, &sy, &ex, &ey);

	if (0 == rv){
		tsm_screen_selection_reset(term.screen);
		tsm_screen_selection_start(term.screen, sx, sy);
		tsm_screen_selection_target(term.screen, ex, ey);
		select_copy();
		term.dirty |= DIRTY_PENDING;
	}

	term.in_select = false;
}

static void select_row()
{
	tsm_screen_selection_reset(term.screen);
	tsm_screen_selection_start(term.screen, 0, term.cursor_y);
	tsm_screen_selection_target(term.screen, term.cols-1, term.cursor_y);
	select_copy();
	term.dirty |= DIRTY_PENDING;
	term.in_select = false;
}

struct lent {
	const char* lbl;
	void(*ptr)(void);
};

#ifdef TTF_SUPPORT
static bool setup_font(int fd, size_t font_sz, int mode);
void inc_fontsz()
{
	term.font_sz += 2;
	setup_font(BADFD, term.font_sz, 0);
}

void dec_fontsz()
{
	if (term.font_sz > 8)
		term.font_sz -= 2;
	setup_font(BADFD, term.font_sz, 0);
}
#endif

static void scroll_lock()
{
	term.scroll_lock = !term.scroll_lock;
	if (!term.scroll_lock){
		term.sbofs = 0;
		tsm_screen_sb_reset(term.screen);
		term.dirty |= DIRTY_PENDING;
	}
}

static void mouse_forward()
{
	term.mouse_forward = !term.mouse_forward;
}

static const struct lent labels[] = {
	{"SIGINT", send_sigint},
	{"SIGINFO", send_siginfo},
	{"LINE_UP", scroll_up},
	{"LINE_DOWN", scroll_down},
	{"PAGE_UP", page_up},
	{"PAGE_DOWN", page_down},
	{"UP", move_up},
	{"DOWN", move_down},
	{"LEFT", move_left},
	{"RIGHT", move_right},
	{"MOUSE_FORWARD", mouse_forward},
	{"SELECT_AT", select_at},
	{"SELECT_ROW", select_row},
	{"SCROLL_LOCK", scroll_lock},
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
	term.last = 0;

	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		bool pressed = ioev->input.translated.active;
		if (!pressed)
			return;

		if (term.in_select){
			term.in_select = false;
			tsm_screen_selection_reset(term.screen);
		}
		term.inact_timer = -4;
		if (label[0] && consume_label(ioev, label))
			return;

		if (term.sbofs != 0){
			term.sbofs = 0;
			tsm_screen_sb_reset(term.screen);
			term.dirty |= DIRTY_PENDING;
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
			shl_pty_dispatch(term.pty);
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
		term.last_shmask = shmask;

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
				int yv = ioev->input.analog.axisval[0];
				term.mouse_y = yv / term.cell_h;

				if (term.mouse_forward){
					tsm_vte_mouse_motion(term.vte,
						term.mouse_x, term.mouse_y, term.last_shmask);
					return;
				}

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
/* we use the upper / lower regions as triggers for scrollback + selection,
 * with a magnitude based on how far "off" we are */
				if (yv < 0.3 * term.cell_h)
					term.scrollback = -1 * (1 + yv / term.cell_h);
				else if (yv > term.rows * term.cell_h + 0.3 * term.cell_h)
					term.scrollback = 1 + (yv - term.rows * term.cell_h) / term.cell_h;
				else
					term.scrollback = 0;

/* in select and drag negative in window or half-size - then use ticker
 * to scroll and an accelerated scrollback */
				if (upd){
					tsm_screen_selection_target(term.screen, term.lm_x, term.lm_y);
					term.dirty |= DIRTY_PENDING;
				}
/* in select? check if motion tile is different than old, if so,
 * tsm_selection_target */
			}
		}
/* press? press-point tsm_screen_selection_start,
 * release and press-tile ~= release_tile? copy */
		else if (ioev->datatype == EVENT_IDATATYPE_DIGITAL){
			if (term.mouse_forward){
				tsm_vte_mouse_button(term.vte,
					ioev->subid,ioev->input.digital.active,term.last_shmask);
				return;
			}

			if (ioev->flags & ARCAN_IOFL_GESTURE){
				if (strcmp(ioev->label, "dblclick") == 0){
/* select row if double doubleclick */
					if (term.last_dbl_x == term.mouse_x &&
						term.last_dbl_y == term.mouse_y){
						tsm_screen_selection_reset(term.screen);
						tsm_screen_selection_start(term.screen, 0, term.mouse_y);
						tsm_screen_selection_target(
							term.screen, term.cols-1, term.mouse_y);
						select_copy();
						term.dirty |= DIRTY_PENDING;
						term.in_select = false;
					}
/* select word */
					else{
						unsigned sx, sy, ex, ey;
						sx = sy = ex = ey = 0;
						int rv = tsm_screen_get_word(term.screen,
							term.mouse_x, term.mouse_y, &sx, &sy, &ex, &ey);
						if (0 == rv){
							tsm_screen_selection_reset(term.screen);
							tsm_screen_selection_start(term.screen, sx, sy);
							tsm_screen_selection_target(term.screen, ex, ey);
							select_copy();
							term.dirty |= DIRTY_PENDING;
							term.in_select = false;
						}
					}

					term.last_dbl_x = term.mouse_x;
					term.last_dbl_y = term.mouse_y;
				}
				else if (strcmp(ioev->label, "click") == 0){
/* forward to terminal? */
				}
				return;
			}
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
				term.dirty |= DIRTY_PENDING;
			}
		}
	}
}

static void targetev(arcan_tgtevent* ev)
{
	switch (ev->kind){
/* control alpha, palette, cursor mode, ... */
	case TARGET_COMMAND_GRAPHMODE:
		if (ev->ioevs[0].iv == 1){
			term.alpha = ev->ioevs[1].fv;
			term.dirty = DIRTY_PENDING_FULL;
		}
	break;

/* sigsuspend to group */
	case TARGET_COMMAND_PAUSE:
	break;

/* sigresume to session */
	case TARGET_COMMAND_UNPAUSE:
	break;

	case TARGET_COMMAND_RESET:
		term.last_shmask = 0;
		tsm_vte_hard_reset(term.vte);
	break;

	case TARGET_COMMAND_BCHUNK_IN:
	case TARGET_COMMAND_BCHUNK_OUT:
/* map ioev[0].iv to some reachable known path in
 * the terminal namespace, don't forget to dupe as it
 * will be on next event */
	break;

	case TARGET_COMMAND_FONTHINT:{
#ifdef TTF_SUPPORT
		int fd = BADFD;
		if (ev->ioevs[1].iv == 1)
			fd = ev->ioevs[0].iv; //dup(ev->ioevs[0].iv);

		switch(ev->ioevs[3].iv){
		case -1: break;
/* happen to match TTF_HINTING values, though LED layout could be
 * modified through DISPLAYHINT but in practice, not so much. */
		default:
			term.hint = ev->ioevs[3].iv;
		break;
		}

/* unit conversion again, we get the size in cm, truetype wrapper takes pt,
 * (at 0.03527778 cm/pt), then update_font will take ppcm into account */
		float npx = setup_font(fd, ev->ioevs[2].fv > 0 ?
			ev->ioevs[2].fv / 0.0352778 : 0, ev->ioevs[4].iv);

		update_screensize(false);
#endif
	}
	break;

	case TARGET_COMMAND_DISPLAYHINT:{
/* be conservative in responding to resize,
 * parent should be running crop shader anyhow */
		bool dev =
			(ev->ioevs[0].iv && ev->ioevs[1].iv) &&
			(abs(ev->ioevs[0].iv - term.acon.addr->w) > 0 ||
			 abs(ev->ioevs[1].iv - term.acon.addr->h) > 0);

/* visibility change */
		bool update = false;
		if (!(ev->ioevs[2].iv & 128)){
			if (ev->ioevs[2].iv & 2){
				term.last_shmask = 0;
				term.inactive = true;
			}
			else if (term.inactive){
				term.inactive = false;
				update = true;
			}

	/* selection change */
			if (ev->ioevs[2].iv & 4){
				term.focus = false;
				if (!term.cursor_off){
					term.last_shmask = 0;
					term.cursor_off = true;
					term.dirty |= DIRTY_PENDING;
				}
			}
			else{
				term.focus = true;
				term.inact_timer = 0;
				if (term.cursor_off){
					term.cursor_off = false;
					term.dirty |= DIRTY_PENDING;
				}
			}
		}

/* switch cursor kind on changes to 4 in ioevs[2] */
		if (dev){
			arcan_shmif_resize(&term.acon, ev->ioevs[0].iv, ev->ioevs[1].iv);
			update_screensize(true);
		}

/* currently ignoring field [3], RGB layout as freetype with
 * subpixel hinting builds isn't default / tested properly here */

#ifdef TTF_SUPPORT
		if (ev->ioevs[4].fv > 0 && fabs(ev->ioevs[4].fv - term.ppcm) > 0.01){
			float sf = term.ppcm / ev->ioevs[4].fv;
			term.ppcm = ev->ioevs[4].fv;
			setup_font(BADFD, 0, 0);
			update = true;
		}
#endif

		if (update)
			term.dirty = DIRTY_PENDING_FULL;
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

/* we use draw_cbt so that dirty region will be updated accordingly */
	case TARGET_COMMAND_STEPFRAME:
		if (ev->ioevs[1].iv == 1 && term.focus){
			term.inact_timer++;
			term.cursor_off = term.inact_timer > 1 ? !term.cursor_off : false;
			term.dirty |= DIRTY_PENDING;
		}
		else{
			if (!term.cursor_off && term.focus){
				term.cursor_off = true;
				term.dirty |= DIRTY_PENDING;
			}
		}
		if (term.in_select && term.scrollback != 0){
			if (term.scrollback < 0)
				tsm_screen_sb_up(term.screen, abs(term.scrollback));
			else
				tsm_screen_sb_down(term.screen, term.scrollback);
			term.dirty |= DIRTY_PENDING;
		}
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

	default:
	break;
	}
}

static bool check_pasteboard()
{
	arcan_event ev;
	bool rv = false;

	while (arcan_shmif_poll(&term.clip_in, &ev) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		arcan_tgtevent* tev = &ev.tgt;
		switch(tev->kind){
		case TARGET_COMMAND_MESSAGE:
			shl_pty_write(term.pty, tev->message, strlen(tev->message));
			rv = true;
		break;
		case TARGET_COMMAND_EXIT:
			arcan_shmif_drop(&term.clip_in);
			return false;
		break;
		default:
		break;
		}
	}

	return rv;
}

#ifdef TTF_SUPPORT
static void probe_font(TTF_Font* font,
	const char* msg, size_t* dw, size_t* dh)
{
	TTF_Color fg = {.r = 0xff, .g = 0xff, .b = 0xff};
	int w = *dw, h = *dh;
	TTF_SizeUTF8(font, msg, &w, &h, TTF_STYLE_BOLD | TTF_STYLE_UNDERLINE);

/* SizeUTF8 does not give the right dimensions for all hinting */
	if (term.hint == TTF_HINTING_RGB)
		w++;

	if (w > *dw)
		*dw = w;

	if (h > *dh)
		*dh = h;
}

/*
 * modes supported now is 0 (default), 1 (append)
 */
static bool setup_font(int fd, size_t font_sz, int mode)
{
	TTF_Font* font;

	if (font_sz <= 0)
		font_sz = term.font_sz;

	int modeind = mode >= 1 ? 1 : 0;

/* re-use last descriptor and change size or grab new */
	if (BADFD == fd)
		fd = term.font_fd[modeind];

	float font_sf = font_sz;
	size_t sf_sz = font_sf + ((font_sf * term.ppcm / 28.346566f) - font_sf);

	font = TTF_OpenFontFD(fd, sf_sz);
	if (!font)
		return false;

	TTF_SetFontHinting(font, term.hint);

	size_t w = 0, h = 0;
	static const char* set[] = {
		"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
		"m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "x", "y",
		"z", "!", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
		"M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "X", "Y",
		"Z", "|", "_"
	};

	if (mode == 0){
		term.font_sz = font_sz;
		for (size_t i = 0; i < sizeof(set)/sizeof(set[0]); i++)
			probe_font(font, set[i], &w, &h);

		if (w && h){
			term.cell_w = w;
			term.cell_h = h;
		}

		send_cell_sz();
	}

	TTF_SetFontStyle(font, TTF_STYLE_NORMAL);
	TTF_Font* old_font = term.font[modeind];

	term.font[modeind] = font;

/* internally, TTF_Open dup:s the descriptor, we only keep it here
 * to allow size changes without specifying a new font */
	if (term.font_fd[modeind] != fd)
		close(term.font_fd[modeind]);
	term.font_fd[modeind] = fd;

	if (old_font){
		TTF_CloseFont(old_font);
		update_screensize(false);
	}

	return true;
}
#endif

static void main_loop()
{
	arcan_event ev;

	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
	int ptyfd = shl_pty_get_fd(term.pty);
	int timeout = -1;
	int flushc = 0, last_estate = 0;

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

/* try to balance latency and responsiveness in the case of saturation */
		int sv, tv;
		if (last_estate == -EAGAIN)
			tv = 0;
		else if (atomic_load(&term.acon.addr->vready) && term.dirty)
			tv = 4;
		else
			tv = -1;
		sv = poll(fds, pc, tv);
		bool dispatch = last_estate == -EAGAIN;

		if (sv != 0){
			if (fds[1].revents & POLLIN){
				while (arcan_shmif_poll(&term.acon, &ev) > 0){
					event_dispatch(&ev);
				}
				dispatch = true;
			}
/* fail on upstream event */
			else if (fds[1].revents)
				break;
			else if (pc == 3 && (fds[2].revents & POLLIN))
				dispatch |= check_pasteboard();

/* fail on the terminal descriptor */
			if (fds[0].revents & POLLIN)
				dispatch = true;
			else if (fds[0].revents)
				break;
		}

/* need some limiter here so we won't completely stall if the terminal
 * gets spammed (running find / or cat on huge file are good testcases) */
		while ( (last_estate = shl_pty_dispatch(term.pty)) == -EAGAIN &&
			(atomic_load(&term.acon.addr->vready) || flushc++ < 10))
		;

		flushc = 0;
		if (atomic_load(&term.acon.addr->vready))
			continue;

		update_screen();

/* we don't synch explicitly, hence the vready check above */
		if (term.dirty & DIRTY_UPDATED){
			term.dirty = DIRTY_NONE;
			arcan_shmif_signal(&term.acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
			term.last = arcan_timemillis();
/* set invalid synch region until redraw changes that */
			term.acon.dirty.x1 = term.acon.w;
			term.acon.dirty.x2 = 0;
			term.acon.dirty.y1 = term.acon.h;
			term.acon.dirty.y2 = 0;
		}
	}

/* don't want to fight with signal handler */
	if (term.pty)
		term.pty = (shl_pty_close(term.pty), NULL);
	arcan_shmif_drop(&term.acon);
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"    key      \t   value   \t   description\n"
		"-------------\t-----------\t-----------------\n"
		" rows        \t n_rows    \t specify initial surface width\n"
	  " cols        \t n_cols    \t specify initial surface height\n"
		" ppcm        \t density   \t specify output display pixel density\n"
		" bgr         \t rv(0..255)\t background red channel\n"
		" bgg         \t rv(0..255)\t background green channel\n"
		" bgb         \t rv(0..255)\t background blue channel\n"
		" bgalpha     \t rv(0..255)\t background opacity (default: 255, opaque)\n"
		" fgr         \t rv(0..255)\t foreground red channel\n"
		" fgg         \t rv(0..255)\t foreground green channel\n"
		" fgb         \t rv(0..255)\t foreground blue channel\n"
		" ccr,ccg,ccb \t rv(0..255)\t cursor color\n"
		" clr,clg,clb \t rv(0..255)\t cursor alternate (locked) state color\n"
		" cursor      \t name      \t set cursor (block, frame, halfblock,\n"
		"             \t           \t underline, vertical)\n"
		" login       \t [user]    \t login (optional: user, only works for root)\n"
		" palette     \t name      \t use built-in palette (below)\n"
#ifdef TTF_SUPPORT
		" font        \t ttf-file  \t render using font specified by ttf-file\n"
		" font_fb     \t ttf-file  \t use other font for missing glyphs\n"
		" font_sz     \t px        \t set font rendering size (may alter cellsz))\n"
		" font_hint   \t hintval   \t hint to font renderer (light, mono, subpixel, none)\n"
#endif
		"Built-in palettes:\n"
		"default, solarized, solarized-black, solarized-white\n"
		"---------\t-----------\t----------------\n"
	);
}

static void sighuph(int num)
{
	if (term.pty)
		term.pty = (shl_pty_close(term.pty), NULL);
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
	uint8_t ccol[3] = {0, 255, 0};
	int initw = term.cell_w * term.rows;
	int inith = term.cell_h * term.cols;

	if (arg_lookup(args, "width", 0, &val))
		initw = strtoul(val, NULL, 10);
	if (arg_lookup(args, "height", 0, &val))
		inith = strtoul(val, NULL, 10);
	if (arg_lookup(args, "ppcm", 0, &val)){
		term.ppcm = strtof(val, NULL);
		if (isnan(term.ppcm) || isinf(term.ppcm) || !(term.ppcm > 0))
			term.ppcm = ARCAN_SHMPAGE_DEFAULT_PPCM;
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

	bool ccol_upd = false;
	if (arg_lookup(args, "ccr", 0, &val)){
		ccol[0] = strtoul(val, NULL, 10);
		ccol_upd = true;
	}
	if (arg_lookup(args, "ccg", 0, &val)){
		ccol[1] = strtoul(val, NULL, 10);
		ccol_upd = true;
	}
	if (arg_lookup(args, "ccb", 0, &val)){
		ccol[2] = strtoul(val, NULL, 10);
		ccol_upd = true;
	}

	if (ccol_upd)
		term.ccol = SHMIF_RGBA(ccol[0], ccol[1], ccol[2], 0xff);
	ccol_upd = false;

	if (arg_lookup(args, "clr", 0, &val)){
		ccol[0] = strtoul(val, NULL, 10);
		ccol_upd = true;
	}
	if (arg_lookup(args, "clg", 0, &val)){
		ccol[1] = strtoul(val, NULL, 10);
		ccol_upd = true;
	}
	if (arg_lookup(args, "clb", 0, &val)){
		ccol[2] = strtoul(val, NULL, 10);
		ccol_upd = true;
	}

	if (ccol_upd)
		term.clcol = SHMIF_RGBA(ccol[0], ccol[1], ccol[2], 0xff);

	if (arg_lookup(args, "cursor", 0, &val)){
		const char** cur = curslbl;
	while(*cur){
		if (strcmp(*cur, val) == 0){
			term.cursor = (cur - curslbl);
			break;
		}
		cur++;
	 }
	}

	if (arg_lookup(args, "bgalpha", 0, &val))
		term.alpha = strtoul(val, NULL, 10);
#ifdef TTF_SUPPORT
	size_t sz = term.cell_h;

	if (arg_lookup(args, "font_hint", 0, &val)){
		if (strcmp(val, "light") == 0)
			term.hint = TTF_HINTING_LIGHT;
		else if (strcmp(val, "mono") == 0)
			term.hint = TTF_HINTING_MONO;
		else if (strcmp(val, "normal") == 0)
			term.hint = TTF_HINTING_NORMAL;
		else if (strcmp(val, "subpixel") == 0)
			term.hint = TTF_HINTING_RGB;
	}

	if (arg_lookup(args, "font_sz", 0, &val))
		sz = strtoul(val, NULL, 10);
	if (arg_lookup(args, "font", 0, &val)){
		int fd = open(val, O_RDONLY);
		setup_font(fd, sz, 0);
/* fallback font for missing glyphs */
		if (fd != -1 && arg_lookup(args,"font_fb", 0, &val)){
			fd = open(val, O_RDONLY);
			setup_font(fd, sz, 1);
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
	term.acon.hints = SHMIF_RHINT_SUBREGION;

	arcan_shmif_resize(&term.acon, initw, inith);
	shmif_pixel bgc = SHMIF_RGBA(term.bgc[0], term.bgc[1], term.bgc[2], term.alpha);
	for (size_t i = 0; i < initw*inith; i++)
		term.acon.vidp[i] = bgc;
	arcan_shmif_signal(&term.acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
	expose_labels();
	tsm_screen_set_max_sb(term.screen, 1000);

/* register to get raw OSC (Operating System Command) strings, used for
 * purposes like setting window title, changing palette, and for hackish
 * integration with shell */
	tsm_set_strhandler(term.vte, str_callback, 256, NULL);

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

/* find /bin/login or /usr/bin/login, keep env. as some may want
 * to forward an ARCAN_CONNPATH in order to draw / control */
	signal(SIGHUP, sighuph);
	if ( (term.child = shl_pty_open(&term.pty,
		read_callback, NULL, 1, 1)) == 0){
		if (arg_lookup(args, "login", 0, &val)){
			struct stat buf;
			char* argv[] = {NULL, "-p", NULL};
			if (stat("/bin/login", &buf) == 0 && S_ISREG(buf.st_mode))
				argv[0] = "/bin/login";
			else if (stat("/usr/bin/login", &buf) == 0 && S_ISREG(buf.st_mode))
				argv[0] = "/usr/bin/login";
			else{
				LOG("login prompt requested but none was found\n");
				exit(EXIT_FAILURE);
			}
			setup_shell(args, argv);
			exit(EXIT_FAILURE);
		}

		char* const argv[] = {get_shellenv(), "-i", NULL};
		setup_shell(args, argv);
		exit(EXIT_FAILURE);
	}

	if (term.child < 0){
		LOG("couldn't spawn child terminal.\n");
		return EXIT_FAILURE;
	}

	update_screensize(false);

/* immediately request a clipboard for cut operations (none received ==
 * running appl doesn't care about cut'n'paste/drag'n'drop support). */
/* and send a timer that will be used for cursor blinking when active */
	arcan_shmif_enqueue(&term.acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.width = 1,
		.ext.segreq.height = 1,
		.ext.segreq.kind = SEGID_CLIPBOARD,
		.ext.segreq.id = 0xfeedface
	});

/* and a 1s. timer for blinking cursor */
	arcan_shmif_enqueue(&term.acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = 12,
		.ext.clock.id = 0xabcdef00,
	});

/* show the current cell dimensions to help limit resize requests */
	send_cell_sz();

	main_loop();
	return EXIT_SUCCESS;
}
