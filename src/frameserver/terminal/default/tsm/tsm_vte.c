/*
 * libtsm - VT Emulator
 *
 * Copyright (c) 2011-2013 David Herrmann <dh.herrmann@gmail.com>
 * Copyright (c) 2015-2018 Bjorn Stahl <contact@arcan-fe.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/*
 * Virtual Terminal Emulator
 * This is the VT implementation. It is written from scratch. It uses the
 * screen state-machine as output and is tightly bound to it. It supports
 * functionality from vt100 up to vt500 series. It doesn't implement an
 * explicitly selected terminal but tries to support the most important commands
 * to be compatible with existing implementations. However, full vt102
 * compatibility is the least that is provided.
 *
 * The main parser in this file controls the parser-state and dispatches the
 * actions to the related handlers. The parser is based on the state-diagram
 * from Paul Williams: http://vt100.net/emu/
 * It is written from scratch, though.
 * This parser is fully compatible up to the vt500 series. It requires UTF-8 and
 * does not support any other input encoding. The G0 and G1 sets are therefore
 * defined as subsets of UTF-8. You may still map G0-G3 into GL, though.
 *
 * However, the CSI/DCS/etc handlers are not designed after a specific VT
 * series. We try to support all vt102 commands but implement several other
 * often used sequences, too. Feel free to add further.
 */

#include <errno.h>
#include <stdarg.h>
#include <inttypes.h>
#include "libtsm_int.h"

/* Input parser states */
enum parser_state {
	STATE_NONE,		/* placeholder */
	STATE_GROUND,		/* initial state and ground */
	STATE_ESC,		/* ESC sequence was started */
	STATE_ESC_INT,		/* intermediate escape characters */
	STATE_CSI_ENTRY,	/* starting CSI sequence */
	STATE_CSI_PARAM,	/* CSI parameters */
	STATE_CSI_INT,		/* intermediate CSI characters */
	STATE_CSI_IGNORE,	/* CSI error; ignore this CSI sequence */
	STATE_DCS_ENTRY,	/* starting DCS sequence */
	STATE_DCS_PARAM,	/* DCS parameters */
	STATE_DCS_INT,		/* intermediate DCS characters */
	STATE_DCS_PASS,		/* DCS data passthrough */
	STATE_DCS_IGNORE,	/* DCS error; ignore this DCS sequence */
	STATE_OSC_STRING,	/* parsing OCS sequence */
	STATE_ST_IGNORE,	/* unimplemented seq; ignore until ST */
	STATE_NUM
};

/* Input parser actions */
enum parser_action {
	ACTION_NONE = 0, /* placeholder */
	ACTION_IGNORE,		/* ignore the character entirely */
	ACTION_PRINT,		/* print the character on the console */
	ACTION_EXECUTE,		/* execute single control character (C0/C1) */
	ACTION_CLEAR,		/* clear current parameter state */
	ACTION_COLLECT,		/* collect intermediate character */
	ACTION_PARAM,		/* collect parameter character */
	ACTION_ESC_DISPATCH,	/* dispatch escape sequence */
	ACTION_CSI_DISPATCH,	/* dispatch csi sequence */
	ACTION_DCS_START,	/* start of DCS data */
	ACTION_DCS_COLLECT,	/* collect DCS data */
	ACTION_DCS_END,		/* end of DCS data */
	ACTION_OSC_START,	/* start of OSC data */
	ACTION_OSC_COLLECT,	/* collect OSC data */
	ACTION_OSC_END,		/* end of OSC data */
};

static const char* action_lut[] = {
	"none",
	"ignore",
	"print",
	"execute",
	"clear",
	"collect",
	"param",
	"esc",
	"csi",
	"dcs_s",
	"dcs_c",
	"dcs_e",
	"osc_s",
	"osc_c",
	"osc_e",
};

const static int MOUSE_PROTO = MOUSE_SGR | MOUSE_X10 | MOUSE_RXVT;

/* CSI flags */
#define CSI_BANG	0x0001		/* CSI: ! */
#define CSI_CASH	0x0002		/* CSI: $ */
#define CSI_WHAT	0x0004		/* CSI: ? */
#define CSI_GT		0x0008		/* CSI: > */
#define CSI_SPACE	0x0010		/* CSI:   */
#define CSI_SQUOTE	0x0020		/* CSI: ' */
#define CSI_DQUOTE	0x0040		/* CSI: " */
#define CSI_MULT	0x0080		/* CSI: * */
#define CSI_PLUS	0x0100		/* CSI: + */
#define CSI_POPEN	0x0200		/* CSI: ( */
#define CSI_PCLOSE	0x0400		/* CSI: ) */

/* terminal flags */
#define FLAG_CURSOR_KEY_MODE			0x00000001 /* DEC cursor key mode */
#define FLAG_KEYPAD_APPLICATION_MODE		0x00000002 /* DEC keypad application mode; TODO: toggle on numlock? */
#define FLAG_LINE_FEED_NEW_LINE_MODE		0x00000004 /* DEC line-feed/new-line mode */
#define FLAG_8BIT_MODE				0x00000008 /* Disable UTF-8 mode and enable 8bit compatible mode */
#define FLAG_7BIT_MODE				0x00000010 /* Disable 8bit mode and use 7bit compatible mode */
#define FLAG_USE_C1				0x00000020 /* Explicitly use 8bit C1 codes; TODO: implement */
#define FLAG_KEYBOARD_ACTION_MODE		0x00000040 /* Disable keyboard; TODO: implement? */
#define FLAG_INSERT_REPLACE_MODE		0x00000080 /* Enable insert mode */
#define FLAG_SEND_RECEIVE_MODE			0x00000100 /* Disable local echo */
#define FLAG_TEXT_CURSOR_MODE			0x00000200 /* Show cursor */
#define FLAG_INVERSE_SCREEN_MODE		0x00000400 /* Inverse colors */
#define FLAG_ORIGIN_MODE			0x00000800 /* Relative origin for cursor */
#define FLAG_AUTO_WRAP_MODE			0x00001000 /* Auto line wrap mode */
#define FLAG_AUTO_REPEAT_MODE			0x00002000 /* Auto repeat key press; TODO: implement */
#define FLAG_NATIONAL_CHARSET_MODE		0x00004000 /* Send keys from nation charsets; TODO: implement */
#define FLAG_BACKGROUND_COLOR_ERASE_MODE	0x00008000 /* Set background color on erase (bce) */
#define FLAG_PREPEND_ESCAPE			0x00010000 /* Prepend escape character to next output */
#define FLAG_TITE_INHIBIT_MODE			0x00020000 /* Prevent switching to alternate screen buffer */
#define FLAG_PASTE_BRACKET 0x00040000 /* Bracketed Paste mode */

static uint8_t color_palette[VTE_COLOR_NUM][3] = {
	[VTE_COLOR_BLACK]         = {   0,   0,   0 }, /* black */
	[VTE_COLOR_RED]           = { 205,   0,   0 }, /* red */
	[VTE_COLOR_GREEN]         = {   0, 205,   0 }, /* green */
	[VTE_COLOR_YELLOW]        = { 205, 205,   0 }, /* yellow */
	[VTE_COLOR_BLUE]          = {   0,   0, 238 }, /* blue */
	[VTE_COLOR_MAGENTA]       = { 205,   0, 205 }, /* magenta */
	[VTE_COLOR_CYAN]          = {   0, 205, 205 }, /* cyan */
	[VTE_COLOR_LIGHT_GREY]    = { 229, 229, 229 }, /* light grey */
	[VTE_COLOR_DARK_GREY]     = { 127, 127, 127 }, /* dark grey */
	[VTE_COLOR_LIGHT_RED]     = { 255,   0,   0 }, /* light red */
	[VTE_COLOR_LIGHT_GREEN]   = {   0, 255,   0 }, /* light green */
	[VTE_COLOR_LIGHT_YELLOW]  = { 255, 255,   0 }, /* light yellow */
	[VTE_COLOR_LIGHT_BLUE]    = {  92,  92, 255 }, /* light blue */
	[VTE_COLOR_LIGHT_MAGENTA] = { 255,   0, 255 }, /* light magenta */
	[VTE_COLOR_LIGHT_CYAN]    = {   0, 255, 255 }, /* light cyan */
	[VTE_COLOR_WHITE]         = { 255, 255, 255 }, /* white */

	[VTE_COLOR_FOREGROUND]    = { 229, 229, 229 }, /* light grey */
	[VTE_COLOR_BACKGROUND]    = {   0,   0,   0 }, /* black */
};

static uint8_t color_palette_solarized[VTE_COLOR_NUM][3] = {
	[VTE_COLOR_BLACK]         = {   7,  54,  66 }, /* black */
	[VTE_COLOR_RED]           = { 220,  50,  47 }, /* red */
	[VTE_COLOR_GREEN]         = { 133, 153,   0 }, /* green */
	[VTE_COLOR_YELLOW]        = { 181, 137,   0 }, /* yellow */
	[VTE_COLOR_BLUE]          = {  38, 139, 210 }, /* blue */
	[VTE_COLOR_MAGENTA]       = { 211,  54, 130 }, /* magenta */
	[VTE_COLOR_CYAN]          = {  42, 161, 152 }, /* cyan */
	[VTE_COLOR_LIGHT_GREY]    = { 238, 232, 213 }, /* light grey */
	[VTE_COLOR_DARK_GREY]     = {   0,  43,  54 }, /* dark grey */
	[VTE_COLOR_LIGHT_RED]     = { 203,  75,  22 }, /* light red */
	[VTE_COLOR_LIGHT_GREEN]   = {  88, 110, 117 }, /* light green */
	[VTE_COLOR_LIGHT_YELLOW]  = { 101, 123, 131 }, /* light yellow */
	[VTE_COLOR_LIGHT_BLUE]    = { 131, 148, 150 }, /* light blue */
	[VTE_COLOR_LIGHT_MAGENTA] = { 108, 113, 196 }, /* light magenta */
	[VTE_COLOR_LIGHT_CYAN]    = { 147, 161, 161 }, /* light cyan */
	[VTE_COLOR_WHITE]         = { 253, 246, 227 }, /* white */

	[VTE_COLOR_FOREGROUND]    = { 238, 232, 213 }, /* light grey */
	[VTE_COLOR_BACKGROUND]    = {   7,  54,  66 }, /* black */
};

static uint8_t color_palette_solarized_black[VTE_COLOR_NUM][3] = {
	[VTE_COLOR_BLACK]         = {   0,   0,   0 }, /* black */
	[VTE_COLOR_RED]           = { 220,  50,  47 }, /* red */
	[VTE_COLOR_GREEN]         = { 133, 153,   0 }, /* green */
	[VTE_COLOR_YELLOW]        = { 181, 137,   0 }, /* yellow */
	[VTE_COLOR_BLUE]          = {  38, 139, 210 }, /* blue */
	[VTE_COLOR_MAGENTA]       = { 211,  54, 130 }, /* magenta */
	[VTE_COLOR_CYAN]          = {  42, 161, 152 }, /* cyan */
	[VTE_COLOR_LIGHT_GREY]    = { 238, 232, 213 }, /* light grey */
	[VTE_COLOR_DARK_GREY]     = {   0,  43,  54 }, /* dark grey */
	[VTE_COLOR_LIGHT_RED]     = { 203,  75,  22 }, /* light red */
	[VTE_COLOR_LIGHT_GREEN]   = {  88, 110, 117 }, /* light green */
	[VTE_COLOR_LIGHT_YELLOW]  = { 101, 123, 131 }, /* light yellow */
	[VTE_COLOR_LIGHT_BLUE]    = { 131, 148, 150 }, /* light blue */
	[VTE_COLOR_LIGHT_MAGENTA] = { 108, 113, 196 }, /* light magenta */
	[VTE_COLOR_LIGHT_CYAN]    = { 147, 161, 161 }, /* light cyan */
	[VTE_COLOR_WHITE]         = { 253, 246, 227 }, /* white */

	[VTE_COLOR_FOREGROUND]    = { 238, 232, 213 }, /* light grey */
	[VTE_COLOR_BACKGROUND]    = {   0,   0,   0 }, /* black */
};

static uint8_t color_palette_solarized_white[VTE_COLOR_NUM][3] = {
	[VTE_COLOR_BLACK]         = {   7,  54,  66 }, /* black */
	[VTE_COLOR_RED]           = { 220,  50,  47 }, /* red */
	[VTE_COLOR_GREEN]         = { 133, 153,   0 }, /* green */
	[VTE_COLOR_YELLOW]        = { 181, 137,   0 }, /* yellow */
	[VTE_COLOR_BLUE]          = {  38, 139, 210 }, /* blue */
	[VTE_COLOR_MAGENTA]       = { 211,  54, 130 }, /* magenta */
	[VTE_COLOR_CYAN]          = {  42, 161, 152 }, /* cyan */
	[VTE_COLOR_LIGHT_GREY]    = { 238, 232, 213 }, /* light grey */
	[VTE_COLOR_DARK_GREY]     = {   0,  43,  54 }, /* dark grey */
	[VTE_COLOR_LIGHT_RED]     = { 203,  75,  22 }, /* light red */
	[VTE_COLOR_LIGHT_GREEN]   = {  88, 110, 117 }, /* light green */
	[VTE_COLOR_LIGHT_YELLOW]  = { 101, 123, 131 }, /* light yellow */
	[VTE_COLOR_LIGHT_BLUE]    = { 131, 148, 150 }, /* light blue */
	[VTE_COLOR_LIGHT_MAGENTA] = { 108, 113, 196 }, /* light magenta */
	[VTE_COLOR_LIGHT_CYAN]    = { 147, 161, 161 }, /* light cyan */
	[VTE_COLOR_WHITE]         = { 253, 246, 227 }, /* white */

	[VTE_COLOR_FOREGROUND]    = {   7,  54,  66 }, /* black */
	[VTE_COLOR_BACKGROUND]    = { 238, 232, 213 }, /* light grey */
};

static uint8_t (*get_palette(struct tsm_vte *vte))[3]
{
	if (!vte->palette_name)
		return color_palette;

	if (!strcmp(vte->palette_name, "solarized"))
		return color_palette_solarized;
	if (!strcmp(vte->palette_name, "solarized-black"))
		return color_palette_solarized_black;
	if (!strcmp(vte->palette_name, "solarized-white"))
		return color_palette_solarized_white;

	return color_palette;
}

void debug_log(struct tsm_vte* vte, const char* msg, ...)
{
	if (!vte || !vte->debug)
		return;

	vte->debug_ofs = 0;

	char* out;
	ssize_t len;

	va_list args;
	va_start(args, msg);
		if ( (len = vasprintf(&out, msg, args)) == -1)
			out = NULL;
	va_end(args);

	if (!out)
		return;

	if (vte->debug_lines[vte->debug_pos] != NULL){
		free(vte->debug_lines[vte->debug_pos]);
	}

	vte->debug_lines[vte->debug_pos] = out;
	vte->debug_pos = (vte->debug_pos + 1) % DEBUG_HISTORY;
	tsm_vte_update_debug(vte);
}

#define DEBUG_LOG(X, Y, ...) debug_log(X, "%d:" Y, (X)->log_ctr++, ##__VA_ARGS__)

#define STEP_ROW() { \
	crow++; \
	if (crow < rows)\
		 arcan_tui_move_to(vte->debug, 0, crow);\
	else\
		goto out;\
	}

static size_t wrap_write(struct tsm_vte* vte, size_t crow, const char* msg)
{
	if (!msg || strlen(msg) == 0)
		return crow;

	size_t rows = 0, cols = 0;
	arcan_tui_dimensions(vte->debug, &rows, &cols);

	size_t xpos = 0;
	const char* cur = msg;
	while (*cur){
		size_t next = 0;

		while (cur[next] && (cur[next] != ' ' || (next == 0 || cur[next-1] == ':')))
			next++;

		if (next >= cols && cols > 1){
			next = cols-1;
		}

		if (xpos + next >= cols){
			xpos = 0;
			STEP_ROW();
		}

		arcan_tui_writeu8(vte->debug, (uint8_t*) cur, next, NULL);
		xpos += next;
		cur += next;
	}

	STEP_ROW();
out:
	return crow;
}

void tsm_vte_update_debug(struct tsm_vte* vte)
{
	char* msg = NULL;

	if (!vte || !vte->debug)
		return;

	struct tui_process_res res = arcan_tui_process(&vte->debug, 1, NULL, 0, 0);
	if (res.errc < TUI_ERRC_OK || res.bad){
		arcan_tui_destroy(vte->debug, NULL);
		vte->debug = NULL;
		return;
	}

	arcan_tui_erase_screen(vte->debug, false);
	size_t rows = 0, cols = 0, crow = 0;
	arcan_tui_dimensions(vte->debug, &rows, &cols);
	arcan_tui_move_to(vte->debug, 0, 0);

	char linebuf[256];
	unsigned fl = vte->csi_flags;
	snprintf(linebuf, sizeof(linebuf), "CSI: %s%s%s%s%s%s%s%s%s%s%s debug: %s",
		(fl & CSI_BANG) ? "!" : "",
		(fl & CSI_CASH) ? "$" : "",
		(fl & CSI_WHAT) ? "?" : "",
		(fl & CSI_GT) ? ">" : "",
		(fl & CSI_SPACE) ? "'spce'" : "",
		(fl & CSI_SQUOTE) ? "'" : "",
		(fl & CSI_DQUOTE) ? "\"" : "",
		(fl & CSI_MULT) ? "*" : "",
		(fl & CSI_PLUS) ? "+" : "",
		(fl & CSI_PLUS) ? "(" : "",
		(fl & CSI_PLUS) ? ")" : "",
		(vte->debug_verbose) ? "verbose" : "normal"
	);
	arcan_tui_writeu8(vte->debug, (uint8_t*) linebuf, strlen(linebuf), NULL);
	STEP_ROW();

	const char* state = "none";
	switch (vte->state){
		case STATE_NONE: state = "none"; break;
		case STATE_GROUND: state = "ground"; break;
		case STATE_ESC: state = "esc"; break;
		case STATE_ESC_INT: state = "int"; break;
		case STATE_CSI_ENTRY: state = "entry"; break;
		case STATE_CSI_PARAM: state = "param"; break;
		case STATE_CSI_INT: state = "int"; break;
		case STATE_CSI_IGNORE: state = "csi-ignore"; break;
		case STATE_DCS_ENTRY: state = "entry"; break;
		case STATE_DCS_PARAM: state = "param"; break;
		case STATE_DCS_INT: state = "int"; break;
		case STATE_DCS_PASS: state = "pass"; break;
		case STATE_DCS_IGNORE: state = "dcs-ignore"; break;
		case STATE_OSC_STRING: state = "string"; break;
		case STATE_ST_IGNORE:	state = "st-ignore"; break;
	}
	fl = vte->flags;

	snprintf(linebuf, sizeof(linebuf), "State: %s Flags:"
		" %s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s", state,
		(fl & FLAG_CURSOR_KEY_MODE) ? "ckey " : "",
		(fl & FLAG_KEYPAD_APPLICATION_MODE) ? "kp_app " : "",
		(fl & FLAG_LINE_FEED_NEW_LINE_MODE) ? "lf_nl " : "",
		(fl & FLAG_8BIT_MODE) ? "8b " : "",
		(fl & FLAG_7BIT_MODE) ? "7b " : "",
		(fl & FLAG_USE_C1) ? "c1 " : "",
		(fl & FLAG_KEYBOARD_ACTION_MODE) ? "kbd_am " : "",
		(fl & FLAG_INSERT_REPLACE_MODE) ? "irep " : "",
		(fl & FLAG_SEND_RECEIVE_MODE) ? "snd_rcv " : "",
		(fl & FLAG_TEXT_CURSOR_MODE) ? "txt_cursor " : "",
		(fl & FLAG_INVERSE_SCREEN_MODE) ? "inv_scr " : "",
		(fl & FLAG_ORIGIN_MODE) ? "origin " : "",
		(fl & FLAG_AUTO_WRAP_MODE) ? "awrap " : "",
		(fl & FLAG_AUTO_REPEAT_MODE) ? "arep " : "",
		(fl & FLAG_NATIONAL_CHARSET_MODE) ? "nch " : "",
		(fl & FLAG_BACKGROUND_COLOR_ERASE_MODE) ? "bgcl_er " : "",
		(fl & FLAG_PREPEND_ESCAPE) ? "esc_prep " : "",
		(fl & FLAG_TITE_INHIBIT_MODE) ? "alt_inhibit " : "",
		(fl & FLAG_PASTE_BRACKET) ? "bpaste " : ""
	);
	crow = wrap_write(vte, crow, linebuf);

	fl = vte->mstate;
	snprintf(linebuf, sizeof(linebuf), "Mouse @(x,y): %zu, %zu Btn: %d State: "
		"%s%s%s%s%s%s",
		vte->saved_state.mouse_x, vte->saved_state.mouse_y, vte->mbutton,
		(fl & MOUSE_BUTTON) ? "button " : "",
		(fl & MOUSE_DRAG) ? "drag " : "",
		(fl & MOUSE_MOTION) ? "motion " : "",
		(fl & MOUSE_SGR) ? "sgr " : "",
		(fl & MOUSE_X10) ? "x10 " : "",
		(fl & MOUSE_RXVT) ? "rxvt " : ""
	);
	crow = wrap_write(vte, crow, linebuf);

/* since this can be arbitrarily long, split on space unless preceeded by a
 * colon, unless the window is so small that the word doesn't fit, since it's
 * debugging data, just ignore utf8 - normal TUI applications would use either
 * autowrap or apply their own wrapping rules */
	msg = arcan_tui_statedescr(vte->con);
	crow = wrap_write(vte, crow, msg);

/* fill out with history logent */
	size_t pos = vte->debug_pos > 0 ? vte->debug_pos - 1 : DEBUG_HISTORY - 1;
	char* ent;

	size_t row_lim = rows - crow;
	crow = rows - 1;

	for (size_t i = 0; i < vte->debug_ofs; i++)
		pos = pos > 0 ? pos - 1 : DEBUG_HISTORY - 1;

/* should reverse this direction */
	while ( row_lim-- && (ent = vte->debug_lines[pos]) && pos != vte->debug_pos){
		arcan_tui_move_to(vte->debug, 0, crow);
		arcan_tui_writeu8(vte->debug, (uint8_t*)ent, strlen(ent), NULL);
		crow--;
		pos = pos > 0 ? pos - 1 : DEBUG_HISTORY - 1;
	}

#undef STEP_ROW
out:
	arcan_tui_refresh(vte->debug);
	if (msg)
		free(msg);

/* last n warnings depending on how many rows we have
 * inputs before last synch
 * outputs before last synch
 * main tui settings (w, h, mode)
 * current foreground
 * current background
 * mouse state
 * wrap mode
 * origin mode
 * decode flags
 */
}

/* Several effects may occur when non-RGB colors are used. For instance, if bold
 * is enabled, then a dark color code is always converted to a light color to
 * simulate bold (even though bold may actually be supported!). To support this,
 * we need to differentiate between a set color-code and a set rgb-color.
 * This function actually converts a set color-code into an RGB color. This must
 * be called before passing the attribute to the console layer so the console
 * layer can always work with RGB values and does not have to care for color
 * codes. */
static void to_rgb(struct tsm_vte *vte, bool defattr)
{
	struct tui_screen_attr* attr = defattr ? &vte->def_attr : &vte->cattr;
	int fgc = defattr ? vte->d_fgcode : vte->c_fgcode;
	int bgc = defattr ? vte->d_bgcode : vte->c_bgcode;

	if (fgc >= 0) {
		/* bold causes light colors */
		if (attr->bold && fgc < 8)
			fgc += 8;
		if (fgc >= VTE_COLOR_NUM)
			fgc = VTE_COLOR_FOREGROUND;

		attr->fr = vte->palette[fgc][0];
		attr->fg = vte->palette[fgc][1];
		attr->fb = vte->palette[fgc][2];

		if (vte->faint){
			attr->fr = attr->fr >> 1;
			attr->fg = attr->fg >> 1;
			attr->fb = attr->fb >> 1;
		}
	}

	if (bgc >= 0) {
		if (bgc >= VTE_COLOR_NUM)
			bgc = VTE_COLOR_BACKGROUND;

		attr->br = vte->palette[bgc][0];
		attr->bg = vte->palette[bgc][1];
		attr->bb = vte->palette[bgc][2];
	}
}

/*
 * update fg or bg attribute field with the palette- lookup based on code
 */
static void set_rgb(struct tsm_vte* vte,
	struct tui_screen_attr* attr, bool fg, int code)
{
	if (code >= VTE_COLOR_NUM)
		code = VTE_COLOR_FOREGROUND;

	if (attr == &vte->def_attr){
		if (fg)
			vte->d_fgcode = code;
		else
			vte->d_bgcode = code;
	}
	else {
		if (fg)
			vte->c_fgcode = code;
		else
			vte->c_bgcode = code;
	}

	if (code < 0)
		return;

	if (fg){
		attr->fr = vte->palette[code][0];
		attr->fg = vte->palette[code][1];
		attr->fb = vte->palette[code][2];
	}
	else{
		attr->br = vte->palette[code][0];
		attr->bg = vte->palette[code][1];
		attr->bb = vte->palette[code][2];
	}
}

SHL_EXPORT
int tsm_vte_new(struct tsm_vte **out, struct tui_context *con,
		tsm_vte_write_cb write_cb, void *data)
{
	struct tsm_vte *vte;
	int ret;

	if (!out || !con || !write_cb)
		return -EINVAL;

	vte = malloc(sizeof(*vte));
	if (!vte)
		return -ENOMEM;

	memset(vte, 0, sizeof(*vte));
	vte->ref = 1;
	vte->con = con;
	vte->write_cb = write_cb;
	vte->data = data;
	uint8_t* palette = (uint8_t*) get_palette(vte);
	memcpy(vte->palette, palette, 3 * VTE_COLOR_NUM);
	set_rgb(vte, &vte->def_attr, true, VTE_COLOR_FOREGROUND);
	set_rgb(vte, &vte->def_attr, false, VTE_COLOR_BACKGROUND);
	memcpy(&vte->cattr, &vte->def_attr, sizeof(struct tui_screen_attr));

	ret = tsm_utf8_mach_new(&vte->mach);
	if (ret)
		goto err_free;

	tsm_vte_reset(vte);
	arcan_tui_erase_screen(vte->con, false);

	DEBUG_LOG(vte, "new vte object");
	arcan_tui_refinc(vte->con);
	*out = vte;
	return 0;

err_free:
	free(vte);
	return ret;
}

SHL_EXPORT
void tsm_vte_ref(struct tsm_vte *vte)
{
	if (!vte)
		return;

	vte->ref++;
}

SHL_EXPORT
void tsm_vte_unref(struct tsm_vte *vte)
{
	if (!vte || !vte->ref)
		return;

	if (--vte->ref)
		return;

	arcan_tui_refdec(vte->con);
	tsm_utf8_mach_free(vte->mach);

	for (size_t i = 0; i < DEBUG_HISTORY; i++){
		if (vte->debug_lines[i])
			free(vte->debug_lines[i]);
	}

	if (vte->debug)
		arcan_tui_destroy(vte->debug, NULL);

	free(vte);
}

SHL_EXPORT
void tsm_vte_set_color(struct tsm_vte *vte,
	enum vte_color ind, const uint8_t rgb[3])
{

	if (ind >= VTE_COLOR_NUM || (int)ind < 0)
		return;

	vte->palette[ind][0] = rgb[0];
	vte->palette[ind][1] = rgb[1];
	vte->palette[ind][2] = rgb[2];

/*
 * NOTE: this does not update the actual color on cattr/def_attr
 */
}

SHL_EXPORT
void tsm_vte_get_color(struct tsm_vte *vte,
	enum vte_color ind, uint8_t *rgb)
{
	if (ind >= VTE_COLOR_NUM || ind < 0)
		return;

	rgb[0] = vte->palette[ind][0];
	rgb[1] = vte->palette[ind][1];
	rgb[2] = vte->palette[ind][2];
}

SHL_EXPORT
int tsm_vte_set_palette(struct tsm_vte *vte, const char *pstr)
{
	char *tmp = NULL;

	if (!vte)
		return -EINVAL;

	if (pstr) {
		tmp = strdup(pstr);
		if (!tmp)
			return -ENOMEM;
	}

	free(vte->palette_name);
	vte->palette_name = tmp;
	uint8_t* palette = (uint8_t*) get_palette(vte);
	memcpy(vte->palette, palette, 3 * VTE_COLOR_NUM);
	set_rgb(vte, &vte->def_attr, true, VTE_COLOR_FOREGROUND);
	set_rgb(vte, &vte->def_attr, false, VTE_COLOR_BACKGROUND);
	to_rgb(vte, true);
	memcpy(&vte->cattr, &vte->def_attr, sizeof(vte->cattr));

	arcan_tui_defattr(vte->con, &vte->def_attr);
	arcan_tui_erase_screen(vte->con, false);

	return 0;
}

/*
 * Write raw byte-stream to pty.
 * When writing data to the client we must make sure that we send the correct
 * encoding. For backwards-compatibility reasons we should always send 7bit
 * characters exclusively. However, when FLAG_7BIT_MODE is not set, then we can
 * also send raw 8bit characters. For instance, in FLAG_8BIT_MODE we can use the
 * GR characters as keyboard input and send them directly or even use the C1
 * escape characters. In unicode mode (default) we can send multi-byte utf-8
 * characters which are also 8bit. When sending these characters, set the \raw
 * flag to true so this function does not perform debug checks on data we send.
 * If debugging is disabled, these checks are also disabled and won't affect
 * performance.
 * For better debugging, we also use the __LINE__ and __FILE__ macros. Use the
 * vte_write() and vte_write_raw() macros below for more convenient use.
 *
 * As a rule of thumb do never send 8bit characters in escape sequences and also
 * avoid all 8bit escape codes including the C1 codes. This will guarantee that
 * all kind of clients are always compatible to us.
 *
 * If SEND_RECEIVE_MODE is off (that is, local echo is on) we have to send all
 * data directly to ourself again. However, we must avoid recursion when
 * tsm_vte_input() itself calls vte_write*(), therefore, we increase the
 * PARSER counter when entering tsm_vte_input() and reset it when leaving it
 * so we never echo data that origins from tsm_vte_input().
 * But note that SEND_RECEIVE_MODE is inherently broken for escape sequences
 * that request answers. That is, if we send a request to the client that awaits
 * a response and parse that request via local echo ourself, then we will also
 * send a response to the client even though he didn't request one. This
 * recursion fix does not avoid this but only prevents us from endless loops
 * here. Anyway, only few applications rely on local echo so we can safely
 * ignore this.
 */
static void vte_write_debug(struct tsm_vte *vte, const char *u8, size_t len,
			    bool raw, const char *file, int line)
{
#ifdef BUILD_ENABLE_DEBUG
	/* in debug mode we check that escape sequences are always <0x7f so they
	 * are correctly parsed by non-unicode and non-8bit-mode clients. */
	size_t i;

	if (!raw) {
		for (i = 0; i < len; ++i) {
			if (u8[i] & 0x80)
				DEBUG_LOG(vte,
					"sending 8bit character inline to client in %s:%d", file, line);
		}
	}
#endif

	/* in local echo mode, directly parse the data again */
	if (!vte->parse_cnt && !(vte->flags & FLAG_SEND_RECEIVE_MODE)) {
		if (vte->flags & FLAG_PREPEND_ESCAPE)
			tsm_vte_input(vte, "\e", 1);
		tsm_vte_input(vte, u8, len);
	}

	if (vte->flags & FLAG_PREPEND_ESCAPE)
		vte->write_cb(vte, "\e", 1, vte->data);
	vte->write_cb(vte, u8, len, vte->data);

	vte->flags &= ~FLAG_PREPEND_ESCAPE;
}

#define vte_write(_vte, _u8, _len) \
	vte_write_debug((_vte), (_u8), (_len), false, __FILE__, __LINE__)
#define vte_write_raw(_vte, _u8, _len) \
	vte_write_debug((_vte), (_u8), (_len), true, __FILE__, __LINE__)

/* write to console */
static void write_console(struct tsm_vte *vte, tsm_symbol_t sym)
{
	to_rgb(vte, false);
	arcan_tui_write(vte->con, sym, &vte->cattr);
}

static void reset_state(struct tsm_vte *vte)
{
	vte->saved_state.cursor_x = 0;
	vte->saved_state.cursor_y = 0;
	vte->saved_state.mouse_x = 0;
	vte->saved_state.mouse_y = 0;
	vte->saved_state.mouse_state = 0;
	vte->mbutton = 0;
	vte->saved_state.origin_mode = false;
	vte->saved_state.wrap_mode = true;
	vte->saved_state.gl = &vte->g0;
	vte->saved_state.gr = &vte->g1;

	vte->saved_state.c_fgcode = vte->d_fgcode;
	vte->saved_state.cattr.fr = vte->def_attr.fr;
	vte->saved_state.cattr.fg = vte->def_attr.fg;
	vte->saved_state.cattr.fb = vte->def_attr.fb;
	vte->saved_state.c_bgcode = vte->d_bgcode;
	vte->saved_state.cattr.br = vte->def_attr.br;
	vte->saved_state.cattr.bg = vte->def_attr.bg;
	vte->saved_state.cattr.bb = vte->def_attr.bb;
	vte->saved_state.cattr.bold = 0;
	vte->saved_state.cattr.italic = 0;
	vte->saved_state.cattr.underline = 0;
	vte->saved_state.cattr.inverse = 0;
	vte->saved_state.cattr.protect = 0;
	vte->saved_state.cattr.blink = 0;
	vte->saved_state.cattr.strikethrough = 0;
	vte->saved_state.cattr.custom_id = 0;
}

static void save_state(struct tsm_vte *vte)
{
	arcan_tui_cursorpos(vte->con,
		&vte->saved_state.cursor_x, &vte->saved_state.cursor_y);
	vte->saved_state.cattr = vte->cattr;
	vte->saved_state.faint = vte->faint;
	vte->saved_state.gl = vte->gl;
	vte->saved_state.gr = vte->gr;
	vte->saved_state.mouse_state = vte->mstate;
	vte->saved_state.wrap_mode = vte->flags & FLAG_AUTO_WRAP_MODE;
	vte->saved_state.origin_mode = vte->flags & FLAG_ORIGIN_MODE;
}

static void restore_state(struct tsm_vte *vte)
{
	arcan_tui_move_to(vte->con, vte->saved_state.cursor_x,
			       vte->saved_state.cursor_y);
	vte->cattr = vte->saved_state.cattr;
	to_rgb(vte, false);
	if (vte->flags & FLAG_BACKGROUND_COLOR_ERASE_MODE)
		arcan_tui_defattr(vte->con, &vte->cattr);
	vte->gl = vte->saved_state.gl;
	vte->gr = vte->saved_state.gr;
	vte->faint = vte->saved_state.faint;
	vte->mstate = vte->saved_state.mouse_state;

	if (vte->saved_state.wrap_mode) {
		vte->flags |= FLAG_AUTO_WRAP_MODE;
		arcan_tui_set_flags(vte->con, TUI_AUTO_WRAP);
	} else {
		vte->flags &= ~FLAG_AUTO_WRAP_MODE;
		arcan_tui_reset_flags(vte->con, TUI_AUTO_WRAP);
	}

	if (vte->saved_state.origin_mode) {
		vte->flags |= FLAG_ORIGIN_MODE;
		arcan_tui_set_flags(vte->con, TUI_REL_ORIGIN);
	} else {
		vte->flags &= ~FLAG_ORIGIN_MODE;
		arcan_tui_reset_flags(vte->con, TUI_REL_ORIGIN);
	}
}

/*
 * Reset VTE state
 * This performs a soft reset of the VTE. That is, everything is reset to the
 * same state as when the VTE was created. This does not affect the console,
 * though.
 */
SHL_EXPORT
void tsm_vte_reset(struct tsm_vte *vte)
{
	if (!vte)
		return;

	vte->flags = 0;
	vte->flags |= FLAG_TEXT_CURSOR_MODE;
	vte->flags |= FLAG_AUTO_REPEAT_MODE;
	vte->flags |= FLAG_SEND_RECEIVE_MODE;
	vte->flags |= FLAG_AUTO_WRAP_MODE;
	vte->flags |= FLAG_BACKGROUND_COLOR_ERASE_MODE;
	arcan_tui_reset(vte->con);
	arcan_tui_set_flags(vte->con, TUI_AUTO_WRAP);

	tsm_utf8_mach_reset(vte->mach);
	vte->state = STATE_GROUND;
	vte->gl = &vte->g0;
	vte->gr = &vte->g1;
	vte->glt = NULL;
	vte->grt = NULL;
	vte->g0 = &tsm_vte_unicode_lower;
	vte->g1 = &tsm_vte_unicode_upper;
	vte->g2 = &tsm_vte_unicode_lower;
	vte->g3 = &tsm_vte_unicode_upper;

	memcpy(&vte->cattr, &vte->def_attr, sizeof(vte->cattr));
	vte->c_fgcode = vte->d_fgcode;
	vte->c_bgcode = vte->d_bgcode;
	to_rgb(vte, false);
	arcan_tui_defattr(vte->con, &vte->def_attr);

	reset_state(vte);
}

SHL_EXPORT
void tsm_vte_hard_reset(struct tsm_vte *vte)
{
	tsm_vte_reset(vte);
	arcan_tui_erase_screen(vte->con, false);
	arcan_tui_erase_sb(vte->con);
	arcan_tui_move_to(vte->con, 0, 0);
}

static void mouse_wr(struct tsm_vte *vte,
	int btni, int press, int mods, int row, int col)
{
	size_t nw = 0;
	char buf[32];

	if (vte->mstate & MOUSE_SGR){
		nw = snprintf(buf, 32, "\e[%d;%d;%d%c", btni | mods, col, row, press ? 'M' : 'm');
	}
	else if (vte->mstate & MOUSE_X10){
		if (col > 222)
			col -= 32;
		if (row > 222)
			row -= 32;
		nw = snprintf(buf, 32, "\e[<M%c%c%c", (btni | mods) + 32, col+32, row+32);
	}
	else if (vte->mstate & MOUSE_RXVT){
		if (!press)
			btni = 3;

		nw = snprintf(buf, 32, "\e[<%d;%d;%dM", btni | mods, col, row);
	}

	if (nw && nw < 32)
		vte_write(vte, buf, nw);
}

SHL_EXPORT
void tsm_vte_paste(struct tsm_vte *vte, const char *u8, size_t len)
{
	if (vte->flags & FLAG_PASTE_BRACKET){
		vte_write(vte, "\e[200~", 6);
	}

	vte_write(vte, u8, len);

	if (vte->flags & FLAG_PASTE_BRACKET){
		vte_write(vte, "\e[201~", 6);
	}
}

SHL_EXPORT
void tsm_vte_mouse_motion(struct tsm_vte *vte, int x, int y, int mods)
{
	if (x == vte->saved_state.mouse_x &&
		y == vte->saved_state.mouse_y)
			return;

/* convert mouse state mask to match protocol */
	int mc = 0;
	mc |= (mods & TSM_SHIFT_MASK)   ? 1 : 0;
	mc |= (mods & TSM_ALT_MASK)     ? 2 : 0;
	mc |= (mods & TSM_CONTROL_MASK) ? 4 : 0;

	vte->saved_state.mouse_x = x;
	vte->saved_state.mouse_y = y;

	if ( ((vte->mstate & MOUSE_DRAG) && vte->mbutton) ||
		((vte->mstate & MOUSE_MOTION)) ){
		int btnind =
			vte->mbutton & 0x01 ? 1 :
			vte->mbutton & 0x02 ? 2 :
			vte->mbutton & 0x04 ? 3 : 4;
		mouse_wr(vte, btnind-1+32, 1, mc, y+1, x+1);
	}
}

SHL_EXPORT
void tsm_vte_mouse_button(struct tsm_vte *vte, int index, bool press, int mods)
{
	int old = vte->mbutton;

/* out of buttons? */
	if (index < 0 || index > 5)
		return;

/* modify held- mask */
	else if (index <= 3){
		if (press)
			vte->mbutton |= (1 << (index - 1));
		else
			vte->mbutton &= ~(1 << (index - 1));
	}

/* only report on change (but not for wheel) */
	if (old == vte->mbutton && index < 4)
		return;

	int mc = 0;
	mc |= (mods & TSM_SHIFT_MASK)   ? 1 : 0;
	mc |= (mods & TSM_ALT_MASK)     ? 2 : 0;
	mc |= (mods & TSM_CONTROL_MASK) ? 4 : 0;

	mouse_wr(vte, index < 4 ? index-1 : index-4+64, press, mods,
		vte->saved_state.mouse_y+1, vte->saved_state.mouse_x+1);
}

static void send_primary_da(struct tsm_vte *vte)
{
	vte_write(vte, "\e[?60;1;6;9;15c", 15);
}

/* execute control character (C0 or C1) */
static void do_execute(struct tsm_vte *vte, uint32_t ctrl)
{
	switch (ctrl) {
	case 0x00: /* NUL */
		/* Ignore on input */
		break;
	case 0x05: /* ENQ */
		/* Transmit answerback message */
		/* TODO: is there a better answer than ACK?  */
		vte_write(vte, "\x06", 1);
		break;
	case 0x07: /* BEL */
		/* Sound bell tone */
		/* TODO: I always considered this annying, however, we
		 * should at least provide some way to enable it if the
		 * user *really* wants it.
		 */
		break;
	case 0x08: /* BS */
		/* Move cursor one position left */
		arcan_tui_move_left(vte->con, 1);
		break;
	case 0x09: /* HT */
		/* Move to next tab stop or end of line */
		arcan_tui_tab_right(vte->con, 1);
		break;
	case 0x0a: /* LF */
	case 0x0b: /* VT */
	case 0x0c: /* FF */
		/* Line feed or newline (CR/NL mode) */
		if (vte->flags & FLAG_LINE_FEED_NEW_LINE_MODE)
			arcan_tui_newline(vte->con);
		else
			arcan_tui_move_down(vte->con, 1, true);
		break;
	case 0x0d: /* CR */
		/* Move cursor to left margin */
		arcan_tui_move_line_home(vte->con);
		break;
	case 0x0e: /* SO */
		/* Map G1 character set into GL */
		vte->gl = &vte->g1;
		break;
	case 0x0f: /* SI */
		/* Map G0 character set into GL */
		vte->gl = &vte->g0;
		break;
	case 0x11: /* XON */
		/* Resume transmission */
		/* TODO */
		break;
	case 0x13: /* XOFF */
		/* Stop transmission */
		/* TODO */
		break;
	case 0x18: /* CAN */
		/* Cancel escape sequence */
		/* nothing to do here */
		break;
	case 0x1a: /* SUB */
		/* Discard current escape sequence and show err-sym */
		write_console(vte, 0xbf);
		break;
	case 0x1b: /* ESC */
		/* Invokes an escape sequence */
		/* nothing to do here */
		break;
	case 0x1f: /* DEL */
		/* Ignored */
		break;
	case 0x84: /* IND */
		/* Move down one row, perform scroll-up if needed */
		arcan_tui_move_down(vte->con, 1, true);
		break;
	case 0x85: /* NEL */
		/* CR/NL with scroll-up if needed */
		arcan_tui_newline(vte->con);
		break;
	case 0x88: /* HTS */
		/* Set tab stop at current position */
		arcan_tui_set_tabstop(vte->con);
		break;
	case 0x8d: /* RI */
		/* Move up one row, perform scroll-down if needed */
		arcan_tui_move_up(vte->con, 1, true);
		break;
	case 0x8e: /* SS2 */
		/* Temporarily map G2 into GL for next char only */
		vte->glt = &vte->g2;
		break;
	case 0x8f: /* SS3 */
		/* Temporarily map G3 into GL for next char only */
		vte->glt = &vte->g3;
		break;
	case 0x9a: /* DECID */
		/* Send device attributes response like ANSI DA */
		send_primary_da(vte);
		break;
	case 0x9c: /* ST */
		/* End control string */
		/* nothing to do here */
		break;
	default:
		DEBUG_LOG(vte, "unhandled control char %u", ctrl);
	}
}

static void do_clear(struct tsm_vte *vte)
{
	int i;

	vte->csi_argc = 0;
	for (i = 0; i < CSI_ARG_MAX; ++i)
		vte->csi_argv[i] = -1;
	vte->csi_flags = 0;
}

static void do_collect(struct tsm_vte *vte, uint32_t data)
{
	switch (data) {
	case '!':
		vte->csi_flags |= CSI_BANG;
		break;
	case '$':
		vte->csi_flags |= CSI_CASH;
		break;
	case '?':
		vte->csi_flags |= CSI_WHAT;
		break;
	case '>':
		vte->csi_flags |= CSI_GT;
		break;
	case ' ':
		vte->csi_flags |= CSI_SPACE;
		break;
	case '\'':
		vte->csi_flags |= CSI_SQUOTE;
		break;
	case '"':
		vte->csi_flags |= CSI_DQUOTE;
		break;
	case '*':
		vte->csi_flags |= CSI_MULT;
		break;
	case '+':
		vte->csi_flags |= CSI_PLUS;
		break;
	case '(':
		vte->csi_flags |= CSI_POPEN;
		break;
	case ')':
		vte->csi_flags |= CSI_PCLOSE;
		break;
	}
}

static void do_param(struct tsm_vte *vte, uint32_t data)
{
	int new;

	if (data == ';') {
		if (vte->csi_argc < CSI_ARG_MAX)
			vte->csi_argc++;
		return;
	}

	if (vte->csi_argc >= CSI_ARG_MAX)
		return;

	/* avoid integer overflows; max allowed value is 16384 anyway */
	if (vte->csi_argv[vte->csi_argc] > 0xffff)
		return;

	if (data >= '0' && data <= '9') {
		new = vte->csi_argv[vte->csi_argc];
		if (new <= 0)
			new = data - '0';
		else
			new = new * 10 + data - '0';
		vte->csi_argv[vte->csi_argc] = new;
	}
}

static bool set_charset(struct tsm_vte *vte, tsm_vte_charset *set)
{
	if (vte->csi_flags & CSI_POPEN)
		vte->g0 = set;
	else if (vte->csi_flags & CSI_PCLOSE)
		vte->g1 = set;
	else if (vte->csi_flags & CSI_MULT)
		vte->g2 = set;
	else if (vte->csi_flags & CSI_PLUS)
		vte->g3 = set;
	else
		return false;

	return true;
}

static void do_esc(struct tsm_vte *vte, uint32_t data)
{
	switch (data) {
	case 'B': /* map ASCII into G0-G3 */
		if (set_charset(vte, &tsm_vte_unicode_lower))
			return;
		break;
	case '<': /* map DEC supplemental into G0-G3 */
		if (set_charset(vte, &tsm_vte_dec_supplemental_graphics))
			return;
		break;
	case '0': /* map DEC special into G0-G3 */
		if (set_charset(vte, &tsm_vte_dec_special_graphics))
			return;
		break;
	case 'A': /* map British into G0-G3 */
		/* TODO: create British charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case '4': /* map Dutch into G0-G3 */
		/* TODO: create Dutch charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'C':
	case '5': /* map Finnish into G0-G3 */
		/* TODO: create Finnish charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'R': /* map French into G0-G3 */
		/* TODO: create French charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'Q': /* map French-Canadian into G0-G3 */
		/* TODO: create French-Canadian charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'K': /* map German into G0-G3 */
		/* TODO: create German charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'Y': /* map Italian into G0-G3 */
		/* TODO: create Italian charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'E':
	case '6': /* map Norwegian/Danish into G0-G3 */
		/* TODO: create Norwegian/Danish charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'Z': /* map Spanish into G0-G3 */
		/* TODO: create Spanish charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'H':
	case '7': /* map Swedish into G0-G3 */
		/* TODO: create Swedish charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case '=': /* map Swiss into G0-G3 */
		/* TODO: create Swiss charset from DEC */
		if (set_charset(vte, &tsm_vte_unicode_upper))
			return;
		break;
	case 'F':
		if (vte->csi_flags & CSI_SPACE) {
			/* S7C1T */
			/* Disable 8bit C1 mode */
			vte->flags &= ~FLAG_USE_C1;
			return;
		}
		break;
	case 'G':
		if (vte->csi_flags & CSI_SPACE) {
			/* S8C1T */
			/* Enable 8bit C1 mode */
			vte->flags |= FLAG_USE_C1;
			return;
		}
		break;
	}

	/* everything below is only valid without CSI flags */
	if (vte->csi_flags) {
		DEBUG_LOG(vte, "unhandled escape seq %u", data);
		return;
	}

	switch (data) {
	case 'D': /* IND */
		/* Move down one row, perform scroll-up if needed */
		arcan_tui_move_down(vte->con, 1, true);
		break;
	case 'E': /* NEL */
		/* CR/NL with scroll-up if needed */
		arcan_tui_newline(vte->con);
		break;
	case 'H': /* HTS */
		/* Set tab stop at current position */
		arcan_tui_set_tabstop(vte->con);
		break;
	case 'M': /* RI */
		/* Move up one row, perform scroll-down if needed */
		arcan_tui_move_up(vte->con, 1, true);
		break;
	case 'N': /* SS2 */
		/* Temporarily map G2 into GL for next char only */
		vte->glt = &vte->g2;
		break;
	case 'O': /* SS3 */
		/* Temporarily map G3 into GL for next char only */
		vte->glt = &vte->g3;
		break;
	case 'Z': /* DECID */
		/* Send device attributes response like ANSI DA */
		send_primary_da(vte);
		break;
	case '\\': /* ST */
		/* End control string */
		/* nothing to do here */
		break;
	case '~': /* LS1R */
		/* Invoke G1 into GR */
		vte->gr = &vte->g1;
		break;
	case 'n': /* LS2 */
		/* Invoke G2 into GL */
		vte->gl = &vte->g2;
		break;
	case '}': /* LS2R */
		/* Invoke G2 into GR */
		vte->gr = &vte->g2;
		break;
	case 'o': /* LS3 */
		/* Invoke G3 into GL */
		vte->gl = &vte->g3;
		break;
	case '|': /* LS3R */
		/* Invoke G3 into GR */
		vte->gr = &vte->g3;
		break;
	case '=': /* DECKPAM */
		/* Set application keypad mode */
		vte->flags |= FLAG_KEYPAD_APPLICATION_MODE;
		break;
	case '>': /* DECKPNM */
		/* Set numeric keypad mode */
		vte->flags &= ~FLAG_KEYPAD_APPLICATION_MODE;
		break;
	case 'c': /* RIS */
		/* hard reset */
		tsm_vte_hard_reset(vte);
		break;
	case '7': /* DECSC */
		/* save console state */
		save_state(vte);
		break;
	case '8': /* DECRC */
		/* restore console state */
		restore_state(vte);
		break;
	default:
		DEBUG_LOG(vte, "unhandled escape seq %u", data);
	}
}

static void csi_attribute(struct tsm_vte *vte)
{
	static const uint8_t bval[6] = { 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };
	unsigned int i, val;
	int code;
	uint8_t cr = 0, cg = 0, cb = 0;

	if (vte->csi_argc <= 1 && vte->csi_argv[0] == -1) {
		vte->csi_argc = 1;
		vte->csi_argv[0] = 0;
	}

	for (i = 0; i < vte->csi_argc; ++i) {
		switch (vte->csi_argv[i]) {
		case -1:
			break;
		case 0:
			vte->c_fgcode = vte->d_fgcode;
			vte->cattr.fr = vte->def_attr.fr;
			vte->cattr.fg = vte->def_attr.fg;
			vte->cattr.fb = vte->def_attr.fb;
			vte->c_bgcode = vte->d_bgcode;
			vte->cattr.br = vte->def_attr.br;
			vte->cattr.bg = vte->def_attr.bg;
			vte->cattr.bb = vte->def_attr.bb;
			vte->cattr.bold = 0;
			vte->cattr.underline = 0;
			vte->cattr.inverse = 0;
			vte->cattr.blink = 0;
			vte->faint = false;
			vte->cattr.italic = 0;
			vte->cattr.strikethrough = 0;
			break;
		case 1:
			vte->cattr.bold = 1;
		break;
		case 2:
			vte->faint = true;
		break;
		case 3:
			vte->cattr.italic = 1;
		break;
		case 4:
			vte->cattr.underline = 1;
			break;
		case 5:
			vte->cattr.blink = 1;
			break;
		case 7:
			vte->cattr.inverse = 1;
			break;
		case 22:
			vte->cattr.bold = 0;
			vte->faint = false;
			break;
		case 23:
			vte->cattr.italic = 0;
			break;
		case 24:
			vte->cattr.underline = 0;
			break;
		case 25:
			vte->cattr.blink = 0;
			break;
		case 27:
			vte->cattr.inverse = 0;
			break;
		case 29:
/* 'not crossed out' */
		break;
		case 30:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_BLACK);
			break;
		case 31:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_RED);
			break;
		case 32:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_GREEN);
			break;
		case 33:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_YELLOW);
			break;
		case 34:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_BLUE);
			break;
		case 35:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_MAGENTA);
			break;
		case 36:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_CYAN);
			break;
		case 37:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_LIGHT_GREY);
			break;
		case 39:
			vte->c_fgcode = vte->d_fgcode;
			vte->cattr.fr = vte->def_attr.fr;
			vte->cattr.fg = vte->def_attr.fg;
			vte->cattr.fb = vte->def_attr.fb;
			break;
		case 40:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_BLACK);
			break;
		case 41:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_RED);
			break;
		case 42:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_GREEN);
			break;
		case 43:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_YELLOW);
			break;
		case 44:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_BLUE);
			break;
		case 45:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_MAGENTA);
			break;
		case 46:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_CYAN);
			break;
		case 47:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_LIGHT_GREY);
			break;
		case 49:
			vte->c_bgcode = vte->d_bgcode;
			vte->cattr.br = vte->def_attr.br;
			vte->cattr.bg = vte->def_attr.bg;
			vte->cattr.bb = vte->def_attr.bb;
			break;
		case 90:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_DARK_GREY);
			break;
		case 91:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_LIGHT_RED);
			break;
		case 92:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_LIGHT_GREEN);
			break;
		case 93:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_LIGHT_YELLOW);
			break;
		case 94:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_LIGHT_BLUE);
			break;
		case 95:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_LIGHT_MAGENTA);
			break;
		case 96:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_LIGHT_CYAN);
			break;
		case 97:
			set_rgb(vte, &vte->cattr, true, VTE_COLOR_WHITE);
			break;
		case 100:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_DARK_GREY);
			break;
		case 101:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_LIGHT_RED);
			break;
		case 102:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_LIGHT_GREEN);
			break;
		case 103:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_LIGHT_YELLOW);
			break;
		case 104:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_LIGHT_BLUE);
			break;
		case 105:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_LIGHT_MAGENTA);
			break;
		case 106:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_LIGHT_CYAN);
			break;
		case 107:
			set_rgb(vte, &vte->cattr, false, VTE_COLOR_WHITE);
			break;
		case 38:
			/* fallthrough */
		case 48:
			val = vte->csi_argv[i];
			if (vte->csi_argv[i + 1] == 5) { // 256color mode
				if (i + 2 >= vte->csi_argc ||
					vte->csi_argv[i + 2] < 0) {
					DEBUG_LOG(vte, "invalid 256color SGR");
					break;
				}
				code = vte->csi_argv[i + 2];
				if (code < 16) {
					//nochange
				} else if (code < 232) {
					code -= 16;
					cb = bval[code % 6];
					code /= 6;
					cg = bval[code % 6];
					code /= 6;
					cr = bval[code % 6];
					code = -1;
				} else {
					code = (code - 232) * 10 + 8;
					cr = code;
					cg = code;
					cb = code;
					code = -1;
				}
				i += 2;
			} else if (vte->csi_argv[i + 1] == 2) {  // true color mode
				if (i + 4 >= vte->csi_argc ||
					vte->csi_argv[i + 2] < 0 ||
					vte->csi_argv[i + 3] < 0 ||
					vte->csi_argv[i + 4] < 0) {
						DEBUG_LOG(vte, "invalid true color SGR");
						break;
					}
				cr = vte->csi_argv[i + 2];
				cg = vte->csi_argv[i + 3];
				cb = vte->csi_argv[i + 4];
				code = -1;
				i += 4;
			} else {
				DEBUG_LOG(vte, "invalid SGR");
				break;
			}
			if (val == 38) {
				vte->c_fgcode = code;
				if (code >= 0){
					set_rgb(vte, &vte->cattr, true, code);
				}
				else{
					vte->cattr.fr = cr;
					vte->cattr.fg = cg;
					vte->cattr.fb = cb;
				}
			} else {
				vte->c_bgcode = code;
				if (code >= 0){
					set_rgb(vte, &vte->cattr, false, code);
				}
				else {
					vte->cattr.br = cr;
					vte->cattr.bg = cg;
					vte->cattr.bb = cb;
				}
			}
			break;
		default:
			DEBUG_LOG(vte, "unhandled SGR attr %i",
				   vte->csi_argv[i]);
		}
	}

	to_rgb(vte, false);
	if (vte->flags & FLAG_BACKGROUND_COLOR_ERASE_MODE)
		arcan_tui_defattr(vte->con, &vte->cattr);
}

static void csi_soft_reset(struct tsm_vte *vte)
{
	tsm_vte_reset(vte);
}

static void csi_compat_mode(struct tsm_vte *vte)
{
	/* always perform soft reset */
	csi_soft_reset(vte);

	if (vte->csi_argv[0] == 61) {
		/* Switching to VT100 compatibility mode. We do
		 * not support this mode, so ignore it. In fact,
		 * we are almost compatible to it, anyway, so
		 * there is no need to explicitly select it.
		 * However, we enable 7bit mode to avoid
		 * character-table problems */
		vte->flags |= FLAG_7BIT_MODE;
		vte->g0 = &tsm_vte_unicode_lower;
		vte->g1 = &tsm_vte_dec_supplemental_graphics;
	} else if (vte->csi_argv[0] == 62 ||
		   vte->csi_argv[0] == 63 ||
		   vte->csi_argv[0] == 64) {
		/* Switching to VT2/3/4 compatibility mode. We
		 * are always compatible with this so ignore it.
		 * We always send 7bit controls so we also do
		 * not care for the parameter value here that
		 * select the control-mode.
		 * VT220 defines argument 2 as 7bit mode but
		 * VT3xx up to VT5xx use it as 8bit mode. We
		 * choose to conform with the latter here.
		 * We also enable 8bit mode when VT220
		 * compatibility is requested explicitly. */
		if (vte->csi_argv[1] == 1 ||
		    vte->csi_argv[1] == 2)
			vte->flags |= FLAG_USE_C1;

		vte->flags |= FLAG_8BIT_MODE;
		vte->g0 = &tsm_vte_unicode_lower;
		vte->g1 = &tsm_vte_dec_supplemental_graphics;
	} else {
		DEBUG_LOG(vte, "unhandled DECSCL 'p' CSI %i, switching to utf-8 mode again",
			   vte->csi_argv[0]);
	}
}

static inline void set_reset_flag(struct tsm_vte *vte, bool set,
				  unsigned int flag)
{
	if (set)
		vte->flags |= flag;
	else
		vte->flags &= ~flag;
}

static void csi_mode(struct tsm_vte *vte, bool set)
{
	unsigned int i;

	for (i = 0; i < vte->csi_argc; ++i) {
		if (!(vte->csi_flags & CSI_WHAT)) {
			switch (vte->csi_argv[i]) {
			case -1:
				continue;
			case 2: /* KAM */
				set_reset_flag(vte, set,
					       FLAG_KEYBOARD_ACTION_MODE);
				continue;
			case 4: /* IRM */
				set_reset_flag(vte, set,
					       FLAG_INSERT_REPLACE_MODE);
				if (set)
					arcan_tui_set_flags(vte->con,
						TUI_INSERT_MODE);
				else
					arcan_tui_reset_flags(vte->con,
						TUI_INSERT_MODE);
				continue;
			case 12: /* SRM */
				set_reset_flag(vte, set,
					       FLAG_SEND_RECEIVE_MODE);
				continue;
			case 20: /* LNM */
				set_reset_flag(vte, set,
					       FLAG_LINE_FEED_NEW_LINE_MODE);
				continue;
			default:
				DEBUG_LOG(vte, "unknown non-DEC (Re)Set-Mode %d",
					   vte->csi_argv[i]);
				continue;
			}
		}

		switch (vte->csi_argv[i]) {
		case -1:
			continue;
		case 1: /* DECCKM */
			set_reset_flag(vte, set, FLAG_CURSOR_KEY_MODE);
			continue;
		case 2: /* DECANM */
			/* Select VT52 mode */
			/* We do not support VT52 mode. Is there any reason why
			 * we should support it? We ignore it here and do not
			 * mark it as to-do item unless someone has strong
			 * arguments to support it. */
			continue;
		case 3: /* DECCOLM */
			/* If set, select 132 column mode, otherwise use 80
			 * column mode. If neither is selected explicitly, we
			 * use dynamic mode, that is, we send SIGWCH when the
			 * size changes and we allow arbitrary buffer
			 * dimensions. On soft-reset, we automatically fall back
			 * to the default, that is, dynamic mode.
			 * Dynamic-mode can be forced to a static mode in the
			 * config. That is, every time dynamic-mode becomes
			 * active, the terminal will be set to the dimensions
			 * that were selected in the config. This allows setting
			 * a fixed size for the terminal regardless of the
			 * display size.
			 * TODO: Implement this */
			continue;
		case 4: /* DECSCLM */
			/* Select smooth scrolling. We do not support the
			 * classic smooth scrolling because we have a scrollback
			 * buffer. There is no need to implement smooth
			 * scrolling so ignore this here. */
			continue;
		case 5: /* DECSCNM */
			set_reset_flag(vte, set, FLAG_INVERSE_SCREEN_MODE);
			if (set)
				arcan_tui_set_flags(vte->con,
						TUI_INVERSE);
			else
				arcan_tui_reset_flags(vte->con,
						TUI_INVERSE);
			continue;
		case 6: /* DECOM */
			set_reset_flag(vte, set, FLAG_ORIGIN_MODE);
			if (set)
				arcan_tui_set_flags(vte->con,
						TUI_REL_ORIGIN);
			else
				arcan_tui_reset_flags(vte->con,
						TUI_REL_ORIGIN);
			continue;
		case 7: /* DECAWN */
			set_reset_flag(vte, set, FLAG_AUTO_WRAP_MODE);
			if (set)
				arcan_tui_set_flags(vte->con,
						TUI_AUTO_WRAP);
			else
				arcan_tui_reset_flags(vte->con,
						TUI_AUTO_WRAP);
			continue;
		case 8: /* DECARM */
			set_reset_flag(vte, set, FLAG_AUTO_REPEAT_MODE);
			continue;
		case 9: /* X10 mouse compatibility mode */
			// set_reset_flag(vte, set, FLAG_ */
			continue;
		case 12: /* blinking cursor */
			/* TODO: implement */
			continue;
		case 18: /* DECPFF */
			/* If set, a form feed (FF) is sent to the printer after
			 * every screen that is printed. We don't have printers
			 * these days directly attached to terminals so we
			 * ignore this here. */
			continue;
		case 19: /* DECPEX */
			/* If set, the full screen is printed instead of
			 * scrolling region only. We have no printer so ignore
			 * this mode. */
			continue;

/* 20: CRLF mode */

		case 25: /* DECTCEM */
			set_reset_flag(vte, set, FLAG_TEXT_CURSOR_MODE);
			if (set)
				arcan_tui_reset_flags(vte->con,
						TUI_HIDE_CURSOR);
			else
				arcan_tui_set_flags(vte->con,
						TUI_HIDE_CURSOR);
			continue;

/* 40: 80 -> 132 mode */

		case 42: /* DECNRCM */
			set_reset_flag(vte, set, FLAG_NATIONAL_CHARSET_MODE);
			continue;

/* 45: reverse wrap-around */

		case 47: /* Alternate screen buffer */
			if (vte->flags & FLAG_TITE_INHIBIT_MODE)
				continue;

			if (set)
				arcan_tui_set_flags(vte->con, TUI_ALTERNATE);
			else
				arcan_tui_reset_flags(vte->con, TUI_ALTERNATE);
		continue;

/* 59: kanji terminal
 * 66: app keypad
 * 67: backspace as bs not del
 * 69: l/r margins */

		case 1000:
			vte->mstate = MOUSE_BUTTON;
			if (0)
		case 1002:
			vte->mstate = MOUSE_DRAG;
			if (0)
		case 1003:
			vte->mstate = MOUSE_MOTION;
			vte->mstate |= MOUSE_X10;
			if (!set)
				vte->mstate = 0;
			continue;
		case 1006:
			vte->mstate = (vte->mstate & (~MOUSE_PROTO)) |
				( set ? MOUSE_SGR : MOUSE_X10);
			continue;
		case 1015:
			vte->mstate = (vte->mstate & (~MOUSE_PROTO)) |
				( set ? MOUSE_RXVT : MOUSE_X10);
		break;

/* 1001: x-mouse highlight
 * 1004: report focus event
 * 1005: UTF-8 mouse mode
 * 1012: set home on input
 * 1015: mouse-ext
 */
		case 1047: /* Alternate screen buffer with post-erase */
			if (vte->flags & FLAG_TITE_INHIBIT_MODE)
				continue;

			if (set) {
				arcan_tui_set_flags(vte->con, TUI_ALTERNATE);
			} else {
				arcan_tui_erase_screen(vte->con, false);
				arcan_tui_reset_flags(vte->con, TUI_ALTERNATE);
			}
			continue;
		case 1048: /* Set/Reset alternate-screen buffer cursor */
			if (vte->flags & FLAG_TITE_INHIBIT_MODE)
				continue;

			if (set) {
					arcan_tui_cursorpos(vte->con, &vte->alt_cursor_x, &vte->alt_cursor_y);
			} else {
				arcan_tui_move_to(vte->con, vte->alt_cursor_x, vte->alt_cursor_y);
			}
			continue;
		case 1049: /* Alternate screen buffer with pre-erase+cursor */
			if (vte->flags & FLAG_TITE_INHIBIT_MODE)
				continue;

			if (set) {
				arcan_tui_cursorpos(vte->con, &vte->alt_cursor_x, &vte->alt_cursor_y);
				arcan_tui_set_flags(vte->con, TUI_ALTERNATE);
				arcan_tui_erase_screen(vte->con, false);
			} else {
				arcan_tui_erase_screen(vte->con, false);
				arcan_tui_reset_flags(vte->con, TUI_ALTERNATE);
				arcan_tui_move_to(vte->con, vte->alt_cursor_x, vte->alt_cursor_y);
			}
			continue;
		case 2004: /* Bracketed paste mode, pref.postf.paste with \e[200~ \e[201~ */
			set_reset_flag(vte, set, FLAG_PASTE_BRACKET);
			continue;
		default:
			DEBUG_LOG(vte, "unknown DEC %set-Mode %d",
				   set?"S":"Res", vte->csi_argv[i]);
			continue;
		}
	}
}

static void csi_dev_attr(struct tsm_vte *vte)
{
	if (vte->csi_argc <= 1 && vte->csi_argv[0] <= 0) {
		if (vte->csi_flags == 0) {
			send_primary_da(vte);
			return;
		} else if (vte->csi_flags & CSI_GT) {
			vte_write(vte, "\e[>1;1;0c", 9);
			return;
		}
	}

	DEBUG_LOG(vte, "unhandled DA: %x %d %d %d...", vte->csi_flags,
		   vte->csi_argv[0], vte->csi_argv[1], vte->csi_argv[2]);
}

static void csi_dsr(struct tsm_vte *vte)
{
	char buf[64];
	size_t x, y, len;

	if (vte->csi_argv[0] == 5) {
		vte_write(vte, "\e[0n", 4);
	} else if (vte->csi_argv[0] == 6) {
		arcan_tui_cursorpos(vte->con, &x, &y);
		len = snprintf(buf, sizeof(buf), "\e[%zu;%zuR", y+1, x+1);
		if (len >= sizeof(buf))
			vte_write(vte, "\e[0;0R", 6);
		else
			vte_write(vte, buf, len);
	}
}

static void do_csi(struct tsm_vte *vte, uint32_t data)
{
	int num, upper, lower;
	int x, y;
	bool protect;

	if (vte->csi_argc < CSI_ARG_MAX)
		vte->csi_argc++;

	switch (data) {
	case 'A': /* CUU */
		/* move cursor up */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_move_up(vte->con, num, false);
		break;
	case 'B': /* CUD */
		/* move cursor down */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_move_down(vte->con, num, false);
		break;
	case 'C': /* CUF */
		/* move cursor forward */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_move_right(vte->con, num);
		break;
	case 'D': /* CUB */
		/* move cursor backward */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_move_left(vte->con, num);
		break;
	case 'd':{ /* VPA */
		/* Vertical Line Position Absolute */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		size_t cx, cy;
		arcan_tui_cursorpos(vte->con, &cx, &cy);
		x = cx; y = cy;
		arcan_tui_move_to(vte->con, x, num - 1);
		break;
	}
	case 'e':{ /* VPR */
		/* Vertical Line Position Relative */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		size_t cx, cy;
		arcan_tui_cursorpos(vte->con, &cx, &cy);
		x = cx; y = cy;
		arcan_tui_move_to(vte->con, x, y + num);
	break;
	}
	case 'H': /* CUP */
	case 'f': /* HVP */
		/* position cursor */
		x = vte->csi_argv[0];
		if (x <= 0)
			x = 1;
		y = vte->csi_argv[1];
		if (y <= 0)
			y = 1;
		arcan_tui_move_to(vte->con, y - 1, x - 1);
		break;
	case 'G':{ /* CHA */
		/* Cursor Character Absolute */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		size_t cx, cy;
		arcan_tui_cursorpos(vte->con, &cx, &cy);
		x = cx; y = cy;
		arcan_tui_move_to(vte->con, num - 1, y);
	break;
	}
	case 'J':
		if (vte->csi_flags & CSI_WHAT)
			protect = true;
		else
			protect = false;

		if (vte->csi_argv[0] <= 0)
			arcan_tui_erase_cursor_to_screen(vte->con,
							      protect);
		else if (vte->csi_argv[0] == 1)
			arcan_tui_erase_screen_to_cursor(vte->con,
							      protect);
		else if (vte->csi_argv[0] == 2)
			arcan_tui_erase_screen(vte->con, protect);
		else
			DEBUG_LOG(vte, "unknown parameter to CSI-J: %d",
				   vte->csi_argv[0]);
		break;
	case 'K':
		if (vte->csi_flags & CSI_WHAT)
			protect = true;
		else
			protect = false;

/*CTE: con, x, y, size_x - 1, cursor_y, protect) */
		if (vte->csi_argv[0] <= 0)
			arcan_tui_erase_cursor_to_end(vte->con, protect);
		else if (vte->csi_argv[0] == 1)
/* HTC: 0, cursor_y, cursor_x, cursor_y, protet) */
			arcan_tui_erase_home_to_cursor(vte->con, protect);
		else if (vte->csi_argv[0] == 2)
/* CL: 0, y, size_x - 1, y, protect */
			arcan_tui_erase_current_line(vte->con, protect);
		else
			DEBUG_LOG(vte, "unknown parameter to CSI-K: %d",
				   vte->csi_argv[0]);
		break;
	case 'X': /* ECH */
		/* erase characters */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_erase_chars(vte->con, num);
		break;
	case 'm':
		csi_attribute(vte);
		break;
	case 'p':
		if (vte->csi_flags & CSI_GT) {
			/* xterm: select X11 visual cursor mode */
			csi_soft_reset(vte);
		} else if (vte->csi_flags & CSI_BANG) {
			/* DECSTR: Soft Reset */
			csi_soft_reset(vte);
		} else if (vte->csi_flags & CSI_CASH) {
			/* DECRQM: Request DEC Private Mode */
			/* If CSI_WHAT is set, then enable,
			 * otherwise disable */
			csi_soft_reset(vte);
		} else {
			/* DECSCL: Compatibility Level */
			/* Sometimes CSI_DQUOTE is set here, too */
			csi_compat_mode(vte);
		}
		break;
	case 'h': /* SM: Set Mode */
		csi_mode(vte, true);
		break;
	case 'l': /* RM: Reset Mode */
		csi_mode(vte, false);
		break;
	case 'r': /* DECSTBM */
		/* set margin size */
		upper = vte->csi_argv[0];
		if (upper < 0)
			upper = 0;
		lower = vte->csi_argv[1];
		if (lower < 0)
			lower = 0;
		arcan_tui_set_margins(vte->con, upper, lower);
		break;
	case 'c': /* DA */
		/* device attributes */
		csi_dev_attr(vte);
		break;
	case 'L': /* IL */
		/* insert lines */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_insert_lines(vte->con, num);
		break;
	case 'M': /* DL */
		/* delete lines */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_delete_lines(vte->con, num);
		break;
	case 'g': /* TBC */
		/* tabulation clear */
		num = vte->csi_argv[0];
		if (num <= 0)
			arcan_tui_reset_tabstop(vte->con);
		else if (num == 3)
			arcan_tui_reset_all_tabstops(vte->con);
		else
			DEBUG_LOG(vte, "invalid parameter %d to TBC CSI", num);
		break;
	case '@': /* ICH */
		/* insert characters */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_insert_chars(vte->con, num);
		break;
	case 'P': /* DCH */
		/* delete characters */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_delete_chars(vte->con, num);
		break;
	case 'Z': /* CBT */
		/* cursor horizontal backwards tab */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_tab_left(vte->con, num);
		break;
	case 'I': /* CHT */
		/* cursor horizontal forward tab */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_tab_right(vte->con, num);
		break;
	case 'n': /* DSR */
		/* device status reports */
		csi_dsr(vte);
		break;
	case 'S': /* SU */
		/* scroll up */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_scroll_up(vte->con, num);
		break;
	case 'T': /* SD */
		/* scroll down */
		num = vte->csi_argv[0];
		if (num <= 0)
			num = 1;
		arcan_tui_scroll_down(vte->con, num);
		break;
	default:
		DEBUG_LOG(vte, "unhandled CSI sequence %c", data);
	}
}

/* map a character according to current GL and GR maps */
static uint32_t vte_map(struct tsm_vte *vte, uint32_t val)
{
	/* 32, 127, 160 and 255 map to identity like all values >255 */
	switch (val) {
	case 33 ... 126:
		if (vte->glt) {
			val = (**vte->glt)[val - 32];
			vte->glt = NULL;
		} else {
			val = (**vte->gl)[val - 32];
		}
		break;
	case 161 ... 254:
		if (vte->grt) {
			val = (**vte->grt)[val - 160];
			vte->grt = NULL;
		} else {
			val = (**vte->gr)[val - 160];
		}
		break;
	}

	return val;
}

/* perform parser action */
static void do_action(struct tsm_vte *vte, uint32_t data, int action)
{
	tsm_symbol_t sym;
	if (vte->debug && vte->debug_verbose && action != ACTION_PRINT){
		DEBUG_LOG(vte, "%s(%"PRIu32")", action_lut[action], data);
	}

	switch (action) {
		case ACTION_NONE:
			/* do nothing */
			return;
		case ACTION_IGNORE:
			/* ignore character */
			break;
		case ACTION_PRINT:
			sym = tsm_symbol_make(vte_map(vte, data));
			write_console(vte, sym);
			break;
		case ACTION_EXECUTE:
			do_execute(vte, data);
			break;
		case ACTION_CLEAR:
			do_clear(vte);
			break;
		case ACTION_COLLECT:
			do_collect(vte, data);
			break;
		case ACTION_PARAM:
			do_param(vte, data);
			break;
		case ACTION_ESC_DISPATCH:
			do_esc(vte, data);
			break;
		case ACTION_CSI_DISPATCH:
			do_csi(vte, data);
			break;
		case ACTION_DCS_START:
			break;
		case ACTION_DCS_COLLECT:
			break;
		case ACTION_DCS_END:
			break;
/* just dumbly buffer these and callback- forward to the frontend */
		case ACTION_OSC_START:
			vte->colbuf_pos = 0;
			break;
		case ACTION_OSC_COLLECT:
			vte->colbuf[vte->colbuf_pos] = data;
			if (vte->colbuf_pos < vte->colbuf_sz-1)
				vte->colbuf_pos++;
			break;
		case ACTION_OSC_END:
			if (vte->colbuf_pos && vte->strcb){
				vte->colbuf[vte->colbuf_pos] = '\0';
				vte->strcb(vte, TSM_GROUP_OSC, vte->colbuf, vte->colbuf_pos+1,
					vte->colbuf_pos == vte->colbuf_sz, vte->strcb_data);
			}
			break;
		default:
			DEBUG_LOG(vte, "invalid action %d", action);
	}
}

/* entry actions to be performed when entering the selected state */
static const int entry_action[] = {
	[STATE_CSI_ENTRY] = ACTION_CLEAR,
	[STATE_DCS_ENTRY] = ACTION_CLEAR,
	[STATE_DCS_PASS] = ACTION_DCS_START,
	[STATE_ESC] = ACTION_CLEAR,
	[STATE_OSC_STRING] = ACTION_OSC_START,
	[STATE_NUM] = ACTION_NONE,
};

/* exit actions to be performed when leaving the selected state */
static const int exit_action[] = {
	[STATE_DCS_PASS] = ACTION_DCS_END,
	[STATE_OSC_STRING] = ACTION_OSC_END,
	[STATE_NUM] = ACTION_NONE,
};

bool tsm_vte_inseq(struct tsm_vte *vte)
{
	return (vte->state != STATE_NONE && vte->state != STATE_GROUND);
}

/* perform state transition and dispatch related actions */
static void do_trans(struct tsm_vte *vte, uint32_t data, int state, int act)
{
	if (state != STATE_NONE) {
		/* A state transition occurs. Perform exit-action,
		 * transition-action and entry-action. Even when performing a
		 * transition to the same state as the current state we do this.
		 * Use STATE_NONE if this is not the desired behavior.
		 */
		do_action(vte, data, exit_action[vte->state]);
		do_action(vte, data, act);
		do_action(vte, data, entry_action[state]);
		vte->state = state;
	} else {
		do_action(vte, data, act);
	}
}

/*
 * Escape sequence parser
 * This parses the new input character \data. It performs state transition and
 * calls the right callbacks for each action.
 */
static void parse_data(struct tsm_vte *vte, uint32_t raw)
{
	/* events that may occur in any state */
	switch (raw) {
		case 0x18:
		case 0x1a:
		case 0x80 ... 0x8f:
		case 0x91 ... 0x97:
		case 0x99:
		case 0x9a:
		case 0x9c:
			do_trans(vte, raw, STATE_GROUND, ACTION_EXECUTE);
			return;
		case 0x1b:
			do_trans(vte, raw, STATE_ESC, ACTION_NONE);
			return;
		case 0x98:
		case 0x9e:
		case 0x9f:
			do_trans(vte, raw, STATE_ST_IGNORE, ACTION_NONE);
			return;
		case 0x90:
			do_trans(vte, raw, STATE_DCS_ENTRY, ACTION_NONE);
			return;
		case 0x9d:
			do_trans(vte, raw, STATE_OSC_STRING, ACTION_NONE);
			return;
		case 0x9b:
			do_trans(vte, raw, STATE_CSI_ENTRY, ACTION_NONE);
			return;
	}

	/* events that depend on the current state */
	switch (vte->state) {
	case STATE_GROUND:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
		case 0x80 ... 0x8f:
		case 0x91 ... 0x9a:
		case 0x9c:
			do_trans(vte, raw, STATE_NONE, ACTION_EXECUTE);
			return;
		case 0x20 ... 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_PRINT);
			return;
		}
		do_trans(vte, raw, STATE_NONE, ACTION_PRINT);
		return;
	case STATE_ESC:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
			do_trans(vte, raw, STATE_NONE, ACTION_EXECUTE);
			return;
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_ESC_INT, ACTION_COLLECT);
			return;
		case 0x30 ... 0x4f:
		case 0x51 ... 0x57:
		case 0x59:
		case 0x5a:
		case 0x5c:
		case 0x60 ... 0x7e:
			do_trans(vte, raw, STATE_GROUND, ACTION_ESC_DISPATCH);
			return;
		case 0x5b:
			do_trans(vte, raw, STATE_CSI_ENTRY, ACTION_NONE);
			return;
		case 0x5d:
			do_trans(vte, raw, STATE_OSC_STRING, ACTION_NONE);
			return;
		case 0x50:
			do_trans(vte, raw, STATE_DCS_ENTRY, ACTION_NONE);
			return;
		case 0x58:
		case 0x5e:
		case 0x5f:
			do_trans(vte, raw, STATE_ST_IGNORE, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_ESC_INT, ACTION_COLLECT);
		return;
	case STATE_ESC_INT:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
			do_trans(vte, raw, STATE_NONE, ACTION_EXECUTE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_NONE, ACTION_COLLECT);
			return;
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x30 ... 0x7e:
			do_trans(vte, raw, STATE_GROUND, ACTION_ESC_DISPATCH);
			return;
		}
		do_trans(vte, raw, STATE_NONE, ACTION_COLLECT);
		return;
	case STATE_CSI_ENTRY:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
			do_trans(vte, raw, STATE_NONE, ACTION_EXECUTE);
			return;
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_CSI_INT, ACTION_COLLECT);
			return;
		case 0x3a:
			do_trans(vte, raw, STATE_CSI_IGNORE, ACTION_NONE);
			return;
		case 0x30 ... 0x39:
		case 0x3b:
			do_trans(vte, raw, STATE_CSI_PARAM, ACTION_PARAM);
			return;
		case 0x3c ... 0x3f:
			do_trans(vte, raw, STATE_CSI_PARAM, ACTION_COLLECT);
			return;
		case 0x40 ... 0x7e:
			do_trans(vte, raw, STATE_GROUND, ACTION_CSI_DISPATCH);
			return;
		}
		do_trans(vte, raw, STATE_CSI_IGNORE, ACTION_NONE);
		return;
	case STATE_CSI_PARAM:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
			do_trans(vte, raw, STATE_NONE, ACTION_EXECUTE);
			return;
		case 0x30 ... 0x39:
		case 0x3b:
			do_trans(vte, raw, STATE_NONE, ACTION_PARAM);
			return;
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x3a:
		case 0x3c ... 0x3f:
			do_trans(vte, raw, STATE_CSI_IGNORE, ACTION_NONE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_CSI_INT, ACTION_COLLECT);
			return;
		case 0x40 ... 0x7e:
			do_trans(vte, raw, STATE_GROUND, ACTION_CSI_DISPATCH);
			return;
		}
		do_trans(vte, raw, STATE_CSI_IGNORE, ACTION_NONE);
		return;
	case STATE_CSI_INT:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
			do_trans(vte, raw, STATE_NONE, ACTION_EXECUTE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_NONE, ACTION_COLLECT);
			return;
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x30 ... 0x3f:
			do_trans(vte, raw, STATE_CSI_IGNORE, ACTION_NONE);
			return;
		case 0x40 ... 0x7e:
			do_trans(vte, raw, STATE_GROUND, ACTION_CSI_DISPATCH);
			return;
		}
		do_trans(vte, raw, STATE_CSI_IGNORE, ACTION_NONE);
		return;
	case STATE_CSI_IGNORE:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
			do_trans(vte, raw, STATE_NONE, ACTION_EXECUTE);
			return;
		case 0x20 ... 0x3f:
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x40 ... 0x7e:
			do_trans(vte, raw, STATE_GROUND, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
		return;
	case STATE_DCS_ENTRY:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x3a:
			do_trans(vte, raw, STATE_DCS_IGNORE, ACTION_NONE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_DCS_INT, ACTION_COLLECT);
			return;
		case 0x30 ... 0x39:
		case 0x3b:
			do_trans(vte, raw, STATE_DCS_PARAM, ACTION_PARAM);
			return;
		case 0x3c ... 0x3f:
			do_trans(vte, raw, STATE_DCS_PARAM, ACTION_COLLECT);
			return;
		case 0x40 ... 0x7e:
			do_trans(vte, raw, STATE_DCS_PASS, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_DCS_PASS, ACTION_NONE);
		return;
	case STATE_DCS_PARAM:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x30 ... 0x39:
		case 0x3b:
			do_trans(vte, raw, STATE_NONE, ACTION_PARAM);
			return;
		case 0x3a:
		case 0x3c ... 0x3f:
			do_trans(vte, raw, STATE_DCS_IGNORE, ACTION_NONE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_DCS_INT, ACTION_COLLECT);
			return;
		case 0x40 ... 0x7e:
			do_trans(vte, raw, STATE_DCS_PASS, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_DCS_PASS, ACTION_NONE);
		return;
	case STATE_DCS_INT:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x20 ... 0x2f:
			do_trans(vte, raw, STATE_NONE, ACTION_COLLECT);
			return;
		case 0x30 ... 0x3f:
			do_trans(vte, raw, STATE_DCS_IGNORE, ACTION_NONE);
			return;
		case 0x40 ... 0x7e:
			do_trans(vte, raw, STATE_DCS_PASS, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_DCS_PASS, ACTION_NONE);
		return;
	case STATE_DCS_PASS:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
		case 0x20 ... 0x7e:
			do_trans(vte, raw, STATE_NONE, ACTION_DCS_COLLECT);
			return;
		case 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x9c:
			do_trans(vte, raw, STATE_GROUND, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_NONE, ACTION_DCS_COLLECT);
		return;
	case STATE_DCS_IGNORE:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
		case 0x20 ... 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x9c:
			do_trans(vte, raw, STATE_GROUND, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
		return;
	case STATE_OSC_STRING:
		switch (raw) {
		case 0x00 ... 0x06:
		case 0x08 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x20 ... 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_OSC_COLLECT);
			return;
		case 0x07:
		case 0x9c:
			do_trans(vte, raw, STATE_GROUND, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_NONE, ACTION_OSC_COLLECT);
		return;
	case STATE_ST_IGNORE:
		switch (raw) {
		case 0x00 ... 0x17:
		case 0x19:
		case 0x1c ... 0x1f:
		case 0x20 ... 0x7f:
			do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
			return;
		case 0x9c:
			do_trans(vte, raw, STATE_GROUND, ACTION_NONE);
			return;
		}
		do_trans(vte, raw, STATE_NONE, ACTION_IGNORE);
		return;
	}

	DEBUG_LOG(vte, "unhandled input %u in state %d", raw, vte->state);
}

SHL_EXPORT
void tsm_vte_input(struct tsm_vte *vte, const char *u8, size_t len)
{
	int state;
	uint32_t ucs4;
	size_t i;

	if (!vte || !vte->con)
		return;

	++vte->parse_cnt;
	for (i = 0; i < len; ++i) {
		if (vte->flags & FLAG_7BIT_MODE) {
			if (u8[i] & 0x80)
				DEBUG_LOG(vte, "receiving 8bit character U+%d from pty while in 7bit mode",
					   (int)u8[i]);
			parse_data(vte, u8[i] & 0x7f);
		} else if (vte->flags & FLAG_8BIT_MODE) {
			parse_data(vte, u8[i]);
		} else {
			state = tsm_utf8_mach_feed(vte->mach, u8[i]);
			if (state == TSM_UTF8_ACCEPT ||
			    state == TSM_UTF8_REJECT) {
				ucs4 = tsm_utf8_mach_get(vte->mach);
				parse_data(vte, ucs4);
			}
		}
	}
}

static void on_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	struct tsm_vte* in = t;
	if (keysym == TUIK_TAB){
		in->debug_verbose = !in->debug_verbose;
	}
	else if (keysym == TUIK_J || keysym == TUIK_DOWN){
		in->debug_ofs++;
	}
	else if (keysym == TUIK_K || keysym == TUIK_UP){
		if (in->debug_ofs > 0)
			in->debug_ofs--;
	}
	else if (keysym == TUIK_ESCAPE){
		for (size_t i = 0; i < DEBUG_HISTORY; i++){
			if (in->debug_lines[i]){
				free(in->debug_lines[i]);
				in->debug_lines[i] = NULL;
			}
		}
		in->debug_ofs = 0;
		in->debug_pos = 0;
	}
}

SHL_EXPORT void tsm_vte_debug(struct tsm_vte* in, arcan_tui_conn* conn)
{
/* don't need any callbacks as the always do a full reprocess in update_debug,
 * where the processing etc. takes place */
	struct tui_cbcfg cbcfg = {
		.tag = in,
		.input_key = on_key
	};
	struct tui_settings cfg = arcan_tui_defaults(conn, in->con);
	struct tui_context* newctx =
		arcan_tui_setup(conn, &cfg, &cbcfg, sizeof(cbcfg));

	if (!newctx)
		return;

/* already have one, release the old */
	if (in->debug){
		arcan_tui_destroy(newctx, NULL);
		return;
	}

/* no cursor, no scrollback, synch resize */
	in->debug = newctx;
	arcan_tui_set_flags(in->debug, TUI_ALTERNATE | TUI_HIDE_CURSOR);

	tsm_vte_update_debug(in);
}

SHL_EXPORT
void tsm_set_strhandler(struct tsm_vte *vte, tsm_str_cb cb, size_t limit, void* data)
{
	if (vte->strcb)
		vte->strcb(vte, TSM_GROUP_FREE, NULL, 0, false, vte->strcb_data);

	free(vte->colbuf);
	vte->colbuf = NULL;
	if (!cb)
		return;

	vte->colbuf = malloc(limit);
	if (!vte->colbuf){
		vte->strcb(vte, TSM_GROUP_FREE, NULL, 0, false, data);
		return;
	}

	vte->colbuf_sz = limit;
	vte->colbuf_pos = 0;
	vte->colbuf[0] = '\0';
	vte->strcb = cb;
	vte->strcb_data = data;
}

SHL_EXPORT
bool tsm_vte_handle_keyboard(struct tsm_vte *vte, uint32_t keysym,
			     uint32_t ascii, unsigned int mods,
			     uint32_t unicode)
{
	char val, u8[4];
	size_t len;
	uint32_t sym;

	/* MOD1 (mostly labeled 'Alt') prepends an escape character to every
	 * input that is sent by a key.
	 * TODO: Transform this huge handler into a lookup table to save a lot
	 * of code and make such modifiers easier to implement.
	 * Also check whether altSendsEscape should be the default (xterm
	 * disables this by default, why?) and whether we should implement the
	 * fallback shifting that xterm does. */
	if (mods & TSM_ALT_MASK)
		vte->flags |= FLAG_PREPEND_ESCAPE;

	/* A user might actually use multiple layouts for keyboard input. The
	 * @keysym variable contains the actual keysym that the user used. But
	 * if this keysym is not in the ascii range, the input handler does
	 * check all other layouts that the user specified whether one of them
	 * maps the key to some ASCII keysym and provides this via @ascii.
	 * We always use the real keysym except when handling CTRL+<XY>
	 * shortcuts we use the ascii keysym. This is for compatibility to xterm
	 * et. al. so ctrl+c always works regardless of the currently active
	 * keyboard layout.
	 * But if no ascii-sym is found, we still use the real keysym. */
	sym = ascii;
	if (!sym)
		sym = keysym;

	if (mods & TSM_CONTROL_MASK) {
		switch (sym) {
		case TUIK_2:
		case TUIK_SPACE:
			vte_write(vte, "\x00", 1);
			return true;
		case TUIK_A:
			vte_write(vte, "\x01", 1);
			return true;
		case TUIK_B:
			vte_write(vte, "\x02", 1);
			return true;
		case TUIK_C:
			vte_write(vte, "\x03", 1);
			return true;
		case TUIK_D:
			vte_write(vte, "\x04", 1);
			return true;
		case TUIK_E:
			vte_write(vte, "\x05", 1);
			return true;
		case TUIK_F:
			vte_write(vte, "\x06", 1);
			return true;
		case TUIK_G:
			vte_write(vte, "\x07", 1);
			return true;
		case TUIK_H:
			vte_write(vte, "\x08", 1);
			return true;
		case TUIK_I:
			vte_write(vte, "\x09", 1);
			return true;
		case TUIK_J:
			vte_write(vte, "\x0a", 1);
			return true;
		case TUIK_K:
			vte_write(vte, "\x0b", 1);
			return true;
		case TUIK_L:
			vte_write(vte, "\x0c", 1);
			return true;
		case TUIK_M:
			vte_write(vte, "\x0d", 1);
			return true;
		case TUIK_N:
			vte_write(vte, "\x0e", 1);
			return true;
		case TUIK_O:
			vte_write(vte, "\x0f", 1);
			return true;
		case TUIK_P:
			vte_write(vte, "\x10", 1);
			return true;
		case TUIK_Q:
			vte_write(vte, "\x11", 1);
			return true;
		case TUIK_R:
			vte_write(vte, "\x12", 1);
			return true;
		case TUIK_S:
			vte_write(vte, "\x13", 1);
			return true;
		case TUIK_T:
			vte_write(vte, "\x14", 1);
			return true;
		case TUIK_U:
			vte_write(vte, "\x15", 1);
			return true;
		case TUIK_V:
			vte_write(vte, "\x16", 1);
			return true;
		case TUIK_W:
			vte_write(vte, "\x17", 1);
			return true;
		case TUIK_X:
			vte_write(vte, "\x18", 1);
			return true;
		case TUIK_Y:
			vte_write(vte, "\x19", 1);
			return true;
		case TUIK_Z:
			vte_write(vte, "\x1a", 1);
			return true;
		case TUIK_3:
		case TUIK_KP_LEFTBRACE:
			vte_write(vte, "\x1b", 1);
			return true;
		case TUIK_4:
		case TUIK_BACKSLASH:
			vte_write(vte, "\x1c", 1);
			return true;
		case TUIK_5:
		case TUIK_KP_RIGHTBRACE:
			vte_write(vte, "\x1d", 1);
			return true;
		case TUIK_6:
		case TUIK_GRAVE:
			vte_write(vte, "\x1e", 1);
			return true;
		case TUIK_7:
		case TUIK_SLASH:
			vte_write(vte, "\x1f", 1);
			return true;
		case TUIK_8:
			vte_write(vte, "\x7f", 1);
			return true;
		}
	}

/* NOTE: arcan >typically< (this varies between platform ,but ideally) does NOT
 * deal with numlock as a valid state (or caps lock for that matter). Such
 * state is up to the running set of scripts to maintain. Therefore, the
 * translation here ACT as numlock and is always in its "special keys" mode and
 * the numbers should be provided in the UTF8 field rather than as state
 * dependent keysyms */
	switch (keysym) {
		case TUIK_BACKSPACE:
			vte_write(vte, "\x08", 1);
			return true;
		case TUIK_TAB:
			vte_write(vte, "\x09", 1);
			return true;
/*
 * Some X keysyms that we don't have access to:
 * LINEFEED, LeftTab
		case TUIK_ISO_Left_Tab:
			vte_write(vte, "\e[Z", 3);
			return true;
		case TUIK_RETURN:
			vte_write(vte, "\x0a", 1);
			return true;
*/
		case TUIK_CLEAR:
			vte_write(vte, "\x0b", 1);
			return true;
		/*
		 TODO: What should we do with this key? Sending XOFF is awful as
		       there is no simple way on modern keyboards to send XON
		       again. If someone wants this, we can re-eanble it and set
		       some flag.
		case TUIK_Pause:
			vte_write(vte, "\x13", 1);
			return true;
		*/
		/*
		 TODO: What should we do on scroll-lock? Sending 0x14 is what
		       the specs say but it is not used today the way most
		       users would expect so we disable it. If someone wants
		       this, we can re-enable it and set some flag.
		case TUIK_Scroll_Lock:
			vte_write(vte, "\x14", 1);
			return true;
		*/
		case TUIK_SYSREQ:
			vte_write(vte, "\x15", 1);
			return true;
		case TUIK_ESCAPE:
			vte_write(vte, "\x1b", 1);
			return true;
		case TUIK_KP_ENTER:
			if (vte->flags & FLAG_KEYPAD_APPLICATION_MODE) {
				vte_write(vte, "\eOM", 3);
				return true;
			}
			/* fallthrough */
		case TUIK_RETURN:
			if (vte->flags & FLAG_LINE_FEED_NEW_LINE_MODE)
				vte_write(vte, "\x0d\x0a", 2);
			else
				vte_write(vte, "\x0d", 1);
			return true;
		case TUIK_HOME:
		case TUIK_KP_7:
			if (vte->flags & FLAG_CURSOR_KEY_MODE)
				vte_write(vte, "\eOH", 3);
			else
				vte_write(vte, "\e[H", 3);
			return true;
		case TUIK_INSERT:
		case TUIK_KP_0:
			vte_write(vte, "\e[2~", 4);
			return true;
		case TUIK_DELETE:
		case TUIK_KP_PERIOD:
			vte_write(vte, "\e[3~", 4);
			return true;
		case TUIK_END:
		case TUIK_KP_1:
			if (vte->flags & FLAG_CURSOR_KEY_MODE)
				vte_write(vte, "\eOF", 3);
			else
				vte_write(vte, "\e[F", 3);
			return true;
		case TUIK_PAGEUP:
		case TUIK_KP_9:
			vte_write(vte, "\e[5~", 4);
			return true;
		case TUIK_PAGEDOWN:
		case TUIK_KP_3:
			vte_write(vte, "\e[6~", 4);
			return true;
		case TUIK_UP:
		case TUIK_KP_8:
			if (vte->flags & FLAG_CURSOR_KEY_MODE)
				vte_write(vte, "\eOA", 3);
			else
				vte_write(vte, "\e[A", 3);
			return true;
		case TUIK_DOWN:
		case TUIK_KP_2:
			if (vte->flags & FLAG_CURSOR_KEY_MODE)
				vte_write(vte, "\eOB", 3);
			else
				vte_write(vte, "\e[B", 3);
			return true;
		case TUIK_RIGHT:
		case TUIK_KP_6:
			if (vte->flags & FLAG_CURSOR_KEY_MODE)
				vte_write(vte, "\eOC", 3);
			else
				vte_write(vte, "\e[C", 3);
			return true;
		case TUIK_LEFT:
		case TUIK_KP_4:
			if (vte->flags & FLAG_CURSOR_KEY_MODE)
				vte_write(vte, "\eOD", 3);
			else
				vte_write(vte, "\e[D", 3);
			return true;
		case TUIK_KP_5:
			if (vte->flags & FLAG_KEYPAD_APPLICATION_MODE)
				vte_write(vte, "\eOu", 3);
			else
				vte_write(vte, "5", 1);
			return true;
		case TUIK_KP_MINUS:
			if (vte->flags & FLAG_KEYPAD_APPLICATION_MODE)
				vte_write(vte, "\eOm", 3);
			else
				vte_write(vte, "-", 1);
			return true;
		case TUIK_KP_EQUALS:
		case TUIK_KP_DIVIDE:
			if (vte->flags & FLAG_KEYPAD_APPLICATION_MODE)
				vte_write(vte, "\eOj", 3);
			else
				vte_write(vte, "/", 1);
			return true;
		case TUIK_KP_MULTIPLY:
			if (vte->flags & FLAG_KEYPAD_APPLICATION_MODE)
				vte_write(vte, "\eOo", 3);
			else
				vte_write(vte, "*", 1);
			return true;
		case TUIK_KP_PLUS:
			if (vte->flags & FLAG_KEYPAD_APPLICATION_MODE)
				vte_write(vte, "\eOk", 3);
			else
				vte_write(vte, "+", 1);
			return true;
/*		case TUIK_KP_Space:
			vte_write(vte, " ", 1);
			return true;
 */
	/* TODO: check what to transmit for functions keys when
		 * shift/ctrl etc. are pressed. Every terminal behaves
		 * differently here which is really weird.
		 * We now map F4 to F14 if shift is pressed and so on for all
		 * keys. However, such mappings should rather be done via
		 * xkb-configurations and we should instead add a flags argument
		 * to the CSIs as some of the keys here already do. */
		case TUIK_F1:
			if (mods & TSM_SHIFT_MASK)
				vte_write(vte, "\e[23~", 5);
			else
				vte_write(vte, "\eOP", 3);
			return true;
		case TUIK_F2:
			if (mods & TSM_SHIFT_MASK)
				vte_write(vte, "\e[24~", 5);
			else
				vte_write(vte, "\eOQ", 3);
			return true;
		case TUIK_F3:
			if (mods & TSM_SHIFT_MASK)
				vte_write(vte, "\e[25~", 5);
			else
				vte_write(vte, "\eOR", 3);
			return true;
		case TUIK_F4:
			if (mods & TSM_SHIFT_MASK)
				//vte_write(vte, "\e[1;2S", 6);
				vte_write(vte, "\e[26~", 5);
			else
				vte_write(vte, "\eOS", 3);
			return true;
		case TUIK_F5:
			if (mods & TSM_SHIFT_MASK)
				//vte_write(vte, "\e[15;2~", 7);
				vte_write(vte, "\e[28~", 5);
			else
				vte_write(vte, "\e[15~", 5);
			return true;
		case TUIK_F6:
			if (mods & TSM_SHIFT_MASK)
				//vte_write(vte, "\e[17;2~", 7);
				vte_write(vte, "\e[29~", 5);
			else
				vte_write(vte, "\e[17~", 5);
			return true;
		case TUIK_F7:
			if (mods & TSM_SHIFT_MASK)
				//vte_write(vte, "\e[18;2~", 7);
				vte_write(vte, "\e[31~", 5);
			else
				vte_write(vte, "\e[18~", 5);
			return true;
		case TUIK_F8:
			if (mods & TSM_SHIFT_MASK)
				//vte_write(vte, "\e[19;2~", 7);
				vte_write(vte, "\e[32~", 5);
			else
				vte_write(vte, "\e[19~", 5);
			return true;
		case TUIK_F9:
			if (mods & TSM_SHIFT_MASK)
				//vte_write(vte, "\e[20;2~", 7);
				vte_write(vte, "\e[33~", 5);
			else
				vte_write(vte, "\e[20~", 5);
			return true;
		case TUIK_F10:
			if (mods & TSM_SHIFT_MASK)
				//vte_write(vte, "\e[21;2~", 7);
				vte_write(vte, "\e[34~", 5);
			else
				vte_write(vte, "\e[21~", 5);
			return true;
		case TUIK_F11:
			if (mods & TSM_SHIFT_MASK)
				vte_write(vte, "\e[23;2~", 7);
			else
				vte_write(vte, "\e[23~", 5);
			return true;
		case TUIK_F12:
			if (mods & TSM_SHIFT_MASK)
				vte_write(vte, "\e[24;2~", 7);
			else
				vte_write(vte, "\e[24~", 5);
			return true;
	}

	if (unicode != TSM_VTE_INVALID) {
		if (vte->flags & FLAG_7BIT_MODE) {
			val = unicode;
			if (unicode & 0x80) {
				DEBUG_LOG(vte, "invalid keyboard input in 7bit mode U+%x; mapping to '?'",
					   unicode);
				val = '?';
			}
			vte_write(vte, &val, 1);
		} else if (vte->flags & FLAG_8BIT_MODE) {
			val = unicode;
			if (unicode > 0xff) {
				DEBUG_LOG(vte, "invalid keyboard input in 8bit mode U+%x; mapping to '?'",
					   unicode);
				val = '?';
			}
			vte_write_raw(vte, &val, 1);
		}
/*
		this should already be handled in arcan- vte
		else {
			len = tsm_ucs4_to_utf8(tsm_symbol_make(unicode), u8);
			vte_write_raw(vte, u8, len);
		}
 */
		return true;
	}

	vte->flags &= ~FLAG_PREPEND_ESCAPE;
	return false;
}
