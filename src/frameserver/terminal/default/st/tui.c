#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <time.h>
#include <errno.h>
#include "st.h"
#include "win.h"
#include "../cli.h"

/* attributes
 * mouse;
 *  motion - IS_SET(MODE_MOUSE) && !IS_SET(MODE_MOUSEMANY) ret
 *           IS_SET(MODE_MOUSEMOTION) && (!buttons) ret
 *           build button bitmap (1 << btn-1)
 *           code = 32
 *
 *  button - code = 0
 *           MODE_MOUSEX10 (don't report release)
 *           scroll-buttons (never release)
 *
 * same code for encode button into code
 * then for snprintf
 *
	if ((!IS_SET(MODE_MOUSESGR) && e->type == ButtonRelease) || btn == 12)
		code += 3;
	else if (btn >= 8)
		code += 128 + btn - 8;
	else if (btn >= 4)
		code += 64 + btn - 4;
	else
		code += btn - 1;

	if (!IS_SET(MODE_MOUSEX10)) {
		code += ((state & ShiftMask  ) ?  4 : 0)
		      + ((state & Mod1Mask   ) ?  8 : 0)
		      + ((state & ControlMask) ? 16 : 0);
	}

	if (IS_SET(MODE_MOUSESGR)) {
		len = snprintf(buf, sizeof(buf), "\033[<%d;%d;%d%c",
				code, x+1, y+1,
				e->type == ButtonRelease ? 'm' : 'M');
	} else if (x < 223 && y < 223) {
		len = snprintf(buf, sizeof(buf), "\033[M%c%c%c",
				32+code, 32+x+1, 32+y+1);
	} else {
		return;
	}
	ttywrite(buf, len, 0);
*/

typedef struct {
	uint16_t k;
	uint16_t mask;
	char *s;
	signed char appkey;
	signed char appcursor;

} Key;

static
struct {
	int fd;
	int mode;
	struct tui_context *T;
	bool dead;
	bool mouse_sel;
} term;

static struct tui_context *tcon;

#include "config.tui.h"

#define TRUERED(x)		(((x) & 0xff0000) >> 16)
#define TRUEGREEN(x)		(((x) & 0xff00) >> 8)
#define TRUEBLUE(x)		(((x) & 0xff))

static struct tui_cell glyph_to_cell(Glyph g)
{
	uint8_t buf[4];
	memcpy(buf, &g.u, 4);
	uint32_t dst = 0;

	struct tui_cell ret = {.ch = g.u};

	int flags =
		(!!(g.mode & ATTR_BOLD) * TUI_ATTR_BOLD) |
		(!!(g.mode & ATTR_UNDERLINE) * TUI_ATTR_UNDERLINE) |
		(!!(g.mode & ATTR_ITALIC) * TUI_ATTR_ITALIC) |
		(!!(g.mode & ATTR_BLINK) * TUI_ATTR_BLINK) |
		(!!(g.mode & ATTR_REVERSE) * TUI_ATTR_INVERSE);

/* the annoyance is when fg is indexed and bg is not and vice versa,
 * then resolve and expect state machine to do the recoloring */
	if (IS_TRUECOL(g.fg) ^ IS_TRUECOL(g.fg)){
	}
	else if (IS_TRUECOL(g.fg)){
		ret.attr.fr = TRUERED(g.fg);
		ret.attr.fg = TRUEGREEN(g.fg);
		ret.attr.fb = TRUEBLUE(g.fg);
		ret.attr.br = TRUERED(g.bg);
		ret.attr.bg = TRUEGREEN(g.bg);
		ret.attr.bb = TRUEBLUE(g.bg);
	}
	else {
		flags |= TUI_ATTR_COLOR_INDEXED;
		if (g.fg < 16){
			ret.attr.fc[0] = TUI_COL_TBASE + g.fg;
		}
		if (g.bg < 16){
			ret.attr.bc[0] = TUI_COL_TBASE + g.bg;
		}

		if (g.fg == 258)
			ret.attr.fc[0] = TUI_COL_TEXT;

		if (g.bg == 259)
			ret.attr.bc[0] = TUI_COL_TEXT;
		else
			printf("uknown bg index: %d\n", g.bg);
	}

	ret.attr.aflags = flags;
	return ret;
}

void xsetmode(int set, unsigned int flags)
{
	int mode = term.mode;
	MODBIT(term.mode, set, flags);
	if ((term.mode & MODE_REVERSE) != (mode & MODE_REVERSE))
		redraw();
}

int
xsetcursor(int cursor)
{
	return 0;
}

int
xstartdraw(void)
{
	return 1;
}

void xbell(void)
{

}

void xclipcopy(void)
{

}

void xsettitle(char *p)
{
	arcan_tui_ident(term.T, p);
}

void xdrawcursor(int cx, int cy, Glyph ch, int ocx, int ocy, Glyph och)
{
	arcan_tui_move_to(term.T, cx, cy);
}

void xsetpointermotion(int set)
{
}

void xloadcols(void)
{
/* also used for RIS - reset to initial state */
}

int xsetcolorname(int x, const char *name)
{
	return 0;
}

int xgetcolor(int x, unsigned char *r, unsigned char *g, unsigned char *b)
{
	return 0;
}

void xseticontitle(char *p)
{
}

void xsetsel(char *str)
{
	arcan_tui_copy(term.T, str);
}

void xdrawline(Line line, int x1, int y1, int x2)
{
	arcan_tui_move_to(term.T, x1, y1);
	for (int x = x1; x < x2; x++){
		struct tui_cell cell = glyph_to_cell(line[x]);
		if (term.mouse_sel && selected(x, y1))
			cell.attr.aflags |= TUI_ATTR_INVERSE;
		arcan_tui_write(term.T, cell.ch, &cell.attr);
	}
}

void xfinishdraw(void)
{
	if (arcan_tui_refresh(term.T) < 0 && errno == EINVAL){
		term.dead = true;
	}
}

void xximspot(int x, int y)
{
}

/* input is never relative here, this is a legacy part of tui that woul;d
 * take a context attribute to change */
static void on_mouse(struct tui_context* c,
	bool relative, int x, int y, int modifiers, void* t)
{
	if (relative)
		return;

	if (term.mouse_sel){
		selextend(x, y, SEL_REGULAR, 0);
	}
}

static void on_mouse_button(
	struct tui_context* c, int x, int y, int btn, bool act, int mod, void *T)
{
	if (btn == TUIBTN_LEFT){
		if (act){
			if (!term.mouse_sel){
				term.mouse_sel = true;
				selstart(x, y, SEL_REGULAR);
			}
		}
		else if (term.mouse_sel){
			selextend(x, y, SEL_REGULAR, 1);
			term.mouse_sel = false;
			char* sel = getsel();
			if (sel){
				arcan_tui_copy(term.T, sel);
			}
			selclear();
		}
	}
	if (!tisaltscreen()){
		if (btn == TUIBTN_WHEEL_UP){
			if (mod & TUIM_SHIFT)
				kscrollup(&(Arg){.i = -1});
			else
			kscrollup(&(Arg){.i = 1});
		}
		else if (btn == TUIBTN_WHEEL_DOWN){
			if (mod & TUIM_SHIFT)
				kscrolldown(&(Arg){.i = -1});
			else
				kscrolldown(&(Arg){.i = 1});
		}
	}
}

static void on_key(struct tui_context* c, uint32_t symest,
	uint8_t scancode, uint16_t mods, uint16_t subid, void* t)
{
	char *str = NULL;
	if (mods & TUIM_SHIFT){
		if (symest == TUIK_UP){
			kscrollup(&(Arg){.i = -1});
			return;
		}
		else if (symest == TUIK_DOWN){
			kscrolldown(&(Arg){.i = -1});
			return;
		}
	}

	for (size_t i = 0; i < LEN(key); i++){
		if (key[i].k == symest){
			int mask = key[i].mask;
			if (mask == TUIK_ANY_MOD ||
				(mask == TUIK_NO_MOD && !mods) ||
				(mask & mods)){

				if (key[i].appcursor){
					if ((term.mode & MODE_APPCURSOR)){
						if (key[i].appcursor < 0)
							continue;
					}
					else {
						if (key[i].appcursor > 0)
							continue;
					}
				}

				if (key[i].appkey){
					if ((term.mode & MODE_APPKEYPAD)){
						if (key[i].appkey < 0)
							continue;
					}
					else {
						if (key[i].appkey > 0)
							continue;
					}
				}

				str = key[i].s;
				break;
			}
		}
	}

	if (!str)
		return;

	ttywrite(str, strlen(str), 0);
}

static void on_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	tresize(col, row);
	ttyresize(col, row);
}

static void on_utf8_paste(struct tui_context* c,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	ttywrite((const char*) str, len, 0);
}

static void on_visibility(
	struct tui_context *c, bool visible, bool focus, void *T)
{

}

static void on_exec_state(struct tui_context *c, int state, void *T)
{
	if (state == 2){
		ttyhangup();
		term.dead = true;
	}
}

/*
 * for focus: ttywrite(\033[I")
 * and [0 to for focus out
 */

/*
 * for key input with mask,
 * lookup through kmap and write onwards
 */

static bool on_u8(struct tui_context* c, const char* u8, size_t len, void* t)
{
	ttywrite(u8, len, 0);
	return true;
}

int st_tui_main(arcan_tui_conn* conn, struct arg_arr* args)
{
/* regular tui process loop and handler table */
	const char *opt_line = NULL;
	const char *opt_io = NULL;
	char **opt_cmd = NULL;

	struct tui_cbcfg cbcfg =
	{
		.resized = on_resize,
		.utf8 = on_utf8_paste,
		.input_key = on_key,
		.input_utf8 = on_u8,
		.input_mouse_motion = on_mouse,
		.input_mouse_button = on_mouse_button,
		.visibility = on_visibility,
		.exec_state = on_exec_state
	};

	static const char* unset[] = {
		"COLUMNS", "LINES", "TERMCAP",
		"ARCAN_ARG", "ARCAN_APPLPATH", "ARCAN_APPLTEMPPATH",
		"ARCAN_FRAMESERVER_LOGDIR", "ARCAN_RESOURCEPATH",
		"ARCAN_SHMKEY", "ARCAN_SOCKIN_FD"
	};

	int ind = 0;
	const char* val;

	for (int i=0; i < sizeof(unset)/sizeof(unset[0]); i++)
		unsetenv(unset[i]);

	while (arg_lookup(args, "env", ind++, &val) && val)
		putenv(strdup(val));

	tnew(80, 25);
	term.fd = ttynew(opt_line, shell, opt_io, opt_cmd);
	term.T = arcan_tui_setup(conn, NULL, &cbcfg, sizeof(cbcfg));
	arcan_tui_cursor_style(term.T, cursor_style_arg(args), NULL);

	struct timespec now, last;
	clock_gettime(CLOCK_MONOTONIC, &now);
	last = now;

	int64_t timeout = -1;

	while (!term.dead){
		struct tui_process_res res =
			arcan_tui_process(&term.T, 1, &term.fd, 1, timeout);

		if (res.ok){
			ttyread();
		}

		clock_gettime(CLOCK_MONOTONIC, &now);
		timeout = (maxlatency - TIMEDIFF(now, last)) / maxlatency * minlatency;
		if (timeout > 0)
			continue;
		timeout = -1;

		draw();
		clock_gettime(CLOCK_MONOTONIC, &last);
		now = last;
	}

	arcan_tui_destroy(term.T, NULL);
	return EXIT_SUCCESS;
}
