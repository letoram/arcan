/*
 Arcan Text-Oriented User Inteface Library, Text/Hex buffer window
 Copyright: Bjorn Stahl
 License: 3-clause BSD
*/

/*
 * Useful enhancements missing:
 *
 * - hookable input controls (vim/emacs/whatever mode, possibly just forward)
 *   to old_handler and check the return value for consumption
 *
 * - state- management (save / load from buffer) without client knowing
 * - status-row mouse action for controls (wrap, color, view)
 * - replace vs insert mode
 * - selection controls / mouse-forward mode
 * - expose scrollbar / progression status
 * - pattern matching / highlighting
 * - support alternate type-push window for accessibility, debug
 * - undo/redo controls
 * - dynamic buffer reading (streaming / external populate contents)
 * - align to cursor (set as window start ?)
 *
 * Minor nuissances:
 * - colors for UI elements etc. are incorrect
 * - cursor position on resize to small window is wrong
 * - cursor position/navigation on edit mode text scrolling is wrong
 */
#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../../arcan_tui_bufferwnd.h"
#include <errno.h>
#include <ctype.h>
#include <inttypes.h>
#include <stdint.h>
#include <assert.h>

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#define BUFFERWND_MAGIC 0xfadef00f
const int min_meta_rows = 7;

struct bufferwnd_meta {
	uint32_t magic;
	struct tui_cbcfg old_handlers;
	int exit_status;

	int old_flags;
	size_t row, col;
	bool invalidated;

	size_t row_bytelen;

/* Buffer window provided by caller, pos is relative to buffer, ofs is
 * relative within window up to buffer size.
 * Cursor(x,y) = F(buffer_ofs, mode) */
	uint8_t* buffer;
	size_t buffer_sz;
	size_t buffer_pos;
	size_t buffer_ofs;
	size_t buffer_lend;

/* window- local coordinates */
	size_t cursor_x, cursor_y;

/* buffer window constraints to handle cursor position clamping */
	size_t cursor_ofs_col;
	size_t cursor_ofs_row;
	size_t cursor_ofs_row_end;

/* tracked in hex-mode where there are two+pad cells per byte */
	bool cursor_halfb;

	size_t orig_w, orig_h;
	struct tui_bufferwnd_opts opts;
};

static size_t screen_to_pos(struct tui_context*, struct bufferwnd_meta*);

static bool validate_context(struct tui_context* T, struct bufferwnd_meta** M)
{
	if (!T)
		return false;

	struct tui_cbcfg handlers;
	arcan_tui_update_handlers(T, NULL, &handlers, sizeof(struct tui_cbcfg));

	struct bufferwnd_meta* ch = handlers.tag;
	if (!ch || ch->magic != BUFFERWND_MAGIC)
		return false;

	*M = ch;
	return true;
}

void arcan_tui_bufferwnd_release(struct tui_context* T)
{
	struct bufferwnd_meta* meta;
	if (!validate_context(T, &meta))
		return;

/* retrieve current handlers, get meta structure from the tag there and
 * use the handle- table in that structure to restore */

/* restore old flags */
	arcan_tui_set_flags(T, meta->old_flags);

/* requery label through original handles */
	arcan_tui_update_handlers(T, &meta->old_handlers, NULL, sizeof(struct tui_cbcfg));
	arcan_tui_reset_labels(T);

/* restore the wnd-size we had before */
	arcan_tui_wndhint(T, NULL,
		(struct tui_constraints){
			.min_cols = -1, .min_rows = -1,
			.max_cols = meta->orig_w, .max_rows = meta->orig_h,
			.anch_row = -1, .anch_col = -1
		}
	);

/* LTO could possibly do something about this, but basically just safeguard
 * on a safeguard (UAF detection) for the bufferwnd_meta after freeing it */
	*meta = (struct bufferwnd_meta){
		.magic = 0xdeadbeef
	};
	free(meta);
}

size_t arcan_tui_bufferwnd_tell(struct tui_context* T, struct tui_bufferwnd_opts* O)
{
	struct bufferwnd_meta* M;
	if (!validate_context(T, &M))
		return 0;

	if (O){
		*O = M->opts;
	}
	return M->buffer_ofs;
}

static void step_cursor_e(struct tui_context* T, struct bufferwnd_meta* M);

static bool has_cursor(struct bufferwnd_meta* M)
{
	return
		!M->opts.read_only || M->opts.view_mode == BUFFERWND_VIEW_HEX_DETAIL;
}

static void draw_hex_ch(struct tui_context* T,
	struct tui_screen_attr* attr, size_t x, size_t y, uint8_t ch)
{
	static char hlut[16] = {'0', '1', '2', '3', '4',
		'5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};

	uint8_t out[2] = {
		hlut[ch >> 4 & 0xf], hlut[ch >> 0 & 0xf]
	};

	arcan_tui_move_to(T, x, y);
	arcan_tui_writeu8(T, out, 2, attr);
}

static void write_mask(struct tui_context* T,
	const char* buf_1, struct tui_screen_attr* buf_1_attr,
	const char* buf_2, struct tui_screen_attr* buf_2_attr, size_t n)
{
	while (*buf_1 && *buf_2 && n--){
		if (*buf_1 && *buf_1 != ' ')
			arcan_tui_writeu8(T, (const uint8_t*) buf_1, 1, buf_1_attr);
		else
			arcan_tui_writeu8(T, (const uint8_t*) buf_2, 1, buf_2_attr);
		buf_1++;
		buf_2++;
	}
}

static void draw_header(
	struct tui_context* T, struct bufferwnd_meta* M, size_t row, size_t cols)
{
/*
 * just submit header with a possible prefix as the ident- of the tui window
 */
	struct tui_screen_attr attr = arcan_tui_defcattr(T, TUI_COL_UI);
	if (cols <= 1)
		return;

/* pad with ' ' */
	char buf[cols];
	memset(buf, ' ', cols);
	snprintf(buf, cols, "%"PRIx64"(%"PRIx64"+%"PRIx64")",
		(uint64_t) (M->opts.offset + M->buffer_pos + M->buffer_ofs),
		(uint64_t) (M->opts.offset + M->buffer_pos),
		(uint64_t) M->buffer_ofs
	);

/* drop the \0 */
	for (size_t i = 0; i < cols; i++)
		if (buf[i] == '\0'){
			buf[i] = ' ';
			break;
		}

	arcan_tui_move_to(T, row, 0);
	arcan_tui_writeu8(T, (uint8_t*) buf, cols, &attr);
}

static void draw_footer(struct tui_context* T, struct bufferwnd_meta* M,
	size_t* row, size_t* col, size_t* rows, size_t* cols, bool mask_write)
{
/* reserve UI padding area */
	size_t n_reserved = 5;
	if (*rows - *row < n_reserved)
		return;

	if (mask_write){
		*rows -= n_reserved;
		return;
	}

/* define the UI region and clear */
	struct tui_screen_attr reset_def = arcan_tui_defattr(T, NULL);
	struct tui_screen_attr def = {
		.aflags = TUI_ATTR_COLOR_INDEXED,
		.fc = TUI_COL_UI,
		.bc = TUI_COL_UI
	};

	struct tui_screen_attr def_text = {
		.aflags = TUI_ATTR_COLOR_INDEXED,
		.fc = TUI_COL_TEXT,
		.bc = TUI_COL_TEXT
	};

/* no erase with attr */
	size_t c_row = *rows - n_reserved;
	arcan_tui_defattr(T, &def);
	arcan_tui_erase_region(T, 0, c_row, *cols, *rows, false);
	arcan_tui_defattr(T, &reset_def);

/* labels + values, draw in two passes so we get foreground / background */
	struct {
		union {
			char ch;
			uint8_t l8;
			int8_t s8;
			uint16_t l16;
			int16_t s16;
			uint32_t l32;
			int32_t s32;
			uint64_t l64;
			int64_t s64;
			float f;
			double lf;
		};
	} vbuf = {.l64 = 0};

	size_t w = *cols - *col;
	char work[w];
#define DO_ROW(lbl, data, ...) \
	snprintf(work, *cols, data, __VA_ARGS__);\
	arcan_tui_move_to(T, 0, c_row++);\
	write_mask(T, lbl, &def, work, &def_text, w);

	size_t buf_sz = M->buffer_sz - M->buffer_pos;
	memcpy(&vbuf, &M->buffer[M->buffer_pos + M->buffer_ofs],
		buf_sz < sizeof(vbuf) ? buf_sz : sizeof(vbuf));

	const char row1_label[] =
	"x8:     x16:       x32:            "
	"x64:                                ";

	const char row1_data[]  = "   %02"PRIxLEAST8"       %04"PRIxLEAST16
		"       %08"PRIxLEAST32"       %016"PRIxLEAST64;
	DO_ROW(row1_label, row1_data, vbuf.l8, vbuf.l16, vbuf.l32, vbuf.l64);

	const char row2_label[] =
	"u8:     u16:       u32:            "
	"u64:                                ";
	const char row2_data[]  = "   %03"PRIuLEAST8"      %05"PRIuLEAST16
		"    %012"PRIuLEAST32"      %020"PRIuLEAST64;
	DO_ROW(row2_label, row2_data, vbuf.l8, vbuf.l16, vbuf.l32, vbuf.l64);

	const char row3_label[] =
	"s8:     s16:       s32:            "
	"s64:                               ";
	const char row3_data[] = "   %04"PRIiLEAST8"     %06"PRIiLEAST16
		"     %011"PRIiLEAST32"     %021"PRIiLEAST64;
	DO_ROW(row3_label, row3_data, vbuf.s8, vbuf.s16, vbuf.s32, vbuf.s64);

	const char row4_label[] =
	"Float:                  "
	"Double:              "
	"ASCII:";
	const char row4_data[]  =
	"      %012g             "
  "%g                      "
  "                        ";
	DO_ROW(row4_label, row4_data, vbuf.f, vbuf.lf);

	size_t pos = sizeof(row4_label) - 1;
	arcan_tui_move_to(T, pos, c_row-1);
	for (size_t i = 0; i < *cols - pos && i < M->row_bytelen; i++){
		uint8_t ch = M->buffer[M->buffer_pos + M->buffer_ofs + i];
		if (!isprint(ch))
			ch = '_';
		arcan_tui_writeu8(T, &ch, 1, &def_text);
	}
	arcan_tui_move_to(T, 0, c_row);

	arcan_tui_writeu8(T, (const uint8_t*) "Binary:", 8, &def);

/* since the window might not fit all groups, we crop at the last one
 * and present with the closest byte at the brightest and dim thereafter */
	for (unsigned long long i = 1; i <= 64; i++){
		arcan_tui_writeu8(T,
			(const uint8_t*)((vbuf.l64 & (1ull << (i - 1))) ? "1" : "0"),
			1, &def_text
		);
		if (i % 8 == 0){
			def_text.fc[0] = def_text.fc[0] > 40 ? def_text.fc[0] - 20 : def_text.fc[0];
			def_text.fc[1] = def_text.fc[1] > 40 ? def_text.fc[1] - 20 : def_text.fc[1];
			def_text.fc[2] = def_text.fc[2] > 40 ? def_text.fc[2] - 20 : def_text.fc[2];

			arcan_tui_writeu8(T, (const uint8_t*) " ", 1, &def_text);
		}
	}

#undef DO_ROW

	*rows -= n_reserved;
}

/* see redraw_text */
static void redraw_hex(struct tui_context* T, struct bufferwnd_meta* M,
	size_t rows, size_t cols, size_t start_row, size_t start_col,
	bool detail, attr_lookup_fn color_lookup, bool mask_write,
	void (*on_offset)(struct tui_context* T, size_t x, size_t y),
	void (*on_position)(struct tui_context* T, size_t offset)
)
{
	struct tui_screen_attr def = arcan_tui_defattr(T, NULL);

/* In detail mode, we reserve space for address / inspection */
	if (detail){

/* with two different layouts, the three column:
 * "address hex data ascii- format */
		if (!mask_write)
			draw_header(T, M, start_row, cols);
		start_row++;

		draw_footer(T, M, &start_row, &start_col, &rows, &cols, mask_write);
	}

/* mask_write can early out so we don't want to use it as a boundary */
	if (!mask_write){
		M->row_bytelen = 0;
		M->cursor_ofs_row = start_row;
		M->cursor_ofs_row_end = rows - 1;
	}

	size_t draw_cols = cols;
	if (M->opts.hex_mode > BUFFERWND_HEX_BASIC){
		draw_cols = draw_cols - (draw_cols / 3);
	}

	if (!draw_cols)
		return;

	size_t i = 0;
	for (size_t row = start_row; row < rows && i < M->buffer_sz; row++){
		size_t start_i = i;

		for (size_t col = start_col; col < draw_cols-1 && i < M->buffer_sz;){
			if (i + M->buffer_pos >= M->buffer_sz){
				goto out;
			}

			if (on_position && row == M->cursor_y && col == M->cursor_x){
				on_position(T, i);
				goto out;
			}

			if (on_offset && i == M->buffer_ofs){
				on_offset(T, col, row);
				goto out;
			}

/* UI consideration, possible that we should 'background' in order to widen
 * cursor within the detailed +7 range including wrap, if so, just count down
 * from this match and set other background - another option would be cursor
 * controls tha actually sets the selection width */
			if (!mask_write && i == M->buffer_ofs){
				M->cursor_x = col + (M->cursor_halfb ? 1 : 0);
				M->cursor_y = row;
			}
			uint8_t ch = M->buffer[i + M->buffer_pos];

			struct tui_screen_attr cattr = def;

			if (!mask_write){
				uint32_t dch; /* only used with annotations */
				color_lookup(T, M->opts.cbtag, ch, i, &dch, &cattr);
				draw_hex_ch(T, &cattr, col, row, ch);
			}

			col += 3;
			i++;
		}

/* new add the annotation or side-ascii column for the row or the ascii- details */
		if (draw_cols != cols){
			for (size_t col = draw_cols + 1;
				col < cols && start_i < i && !mask_write; col++, start_i++){
				uint8_t ch = M->buffer[start_i + M->buffer_pos];
				uint32_t dch = ch;
				struct tui_screen_attr cattr = def;
				color_lookup(T, M->opts.cbtag, ch, start_i + M->buffer_pos, &dch, &cattr);

/* this seems to omit drawing the fake- cursor on non-visible cells though */
				if (start_i == M->buffer_ofs){
					arcan_tui_get_color(T, TUI_COL_CURSOR, cattr.bc);
				}

				arcan_tui_move_to(T, col, row);
				arcan_tui_write(T, dch, &cattr);
			}
		}

/* remembering this makes seek operations easier */
		if (!mask_write){
			if (row == start_row){
				M->row_bytelen = i;
			}
			M->buffer_lend = i + M->buffer_pos;
		}
	}

out:
	if (!mask_write)
		arcan_tui_move_to(T, M->cursor_x, M->cursor_y);
}

static bool step_col(
	struct tui_context* T, struct bufferwnd_meta* M,
	size_t rows, size_t cols, size_t start_row, size_t start_col,
	bool* new_row)
{
	*new_row = false;

/* next line */
	if (M->col + 1 >= cols){
		if (M->row + 1 >= rows){
			return false;
		}
		else{
			M->row++;
			*new_row = true;
		}

		M->col = 0;
	}
	else
		M->col++;

	arcan_tui_move_to(T, M->col, M->row);
	return true;
}

/*
 * Based on the state of [M], populate T, starting from start_col,row
 * respecting the optional texture filter [text_filter] and color/attr
 * helper [color_lookup], process buffer contents according to the
 * text display mode and the desired wrapping mode.
 *
 * if [mask_write] is set, the procedure is run in a 'dry-run' mode where
 * buffer contents won't be updated.
 * if [on_offset] is provided, the function will terminate at the current
 * M->buffer_ofs and provide the cell x/y that resolves to. use with mask
 * write.
 * if [on:position] is provided, the function will terminate at the x,y
 * cell position and provide the buffer offset that resolves to.
 */
static void redraw_text(struct tui_context* T, struct bufferwnd_meta* M,
	size_t rows, size_t cols, size_t start_row, size_t start_col,
	attr_lookup_fn color_lookup,
	void (*text_filter)(
		struct tui_context* T, char* wndbuf, size_t wndbuf_sz, size_t pos),
	bool mask_write,
	void (*on_offset)(struct tui_context* T, size_t x, size_t y),
	void (*on_position)(struct tui_context* T, size_t offset)
)
{
	M->row = start_row;
	M->col = start_col;
	if (!mask_write){
		M->row_bytelen = 0;
		M->cursor_ofs_row = start_row;
		M->cursor_ofs_row_end = rows - 1;
	}

	arcan_tui_move_to(T, M->row, M->col);
	size_t wndbuf_sz = rows * cols;

/* our text attribute, then apply colors */
	struct tui_screen_attr def = arcan_tui_defattr(T, NULL);

	bool new_row = false, first_row = true, cursor_found = false;
	for (size_t i = 0; i < wndbuf_sz && i + M->buffer_pos < M->buffer_sz; i++){
		struct tui_screen_attr cattr = def;
		uint8_t ch = M->buffer[i + M->buffer_pos];

/* tracking this makes row down easier */
		if (new_row && first_row && !mask_write){
			first_row = false;
			M->row_bytelen = i;
		}

/* mask-write / callback / break potions for coordinate translation */
	if (on_position && M->row == M->cursor_y && M->col == M->cursor_x){
		on_position(T, i);
		break;
	}

	if (on_offset && i == M->buffer_ofs){
		on_offset(T, M->col, M->row);
		break;
	}

/* possible that we should allow the lookup to access the entire attr to let
 * an external highlight engine underline etc. */
		if (!mask_write){
			uint32_t dch;
			color_lookup(T, M->opts.cbtag, ch, i + M->buffer_pos, &dch, &cattr);
		}

		if (M->opts.wrap_mode != BUFFERWND_WRAP_ALL){
			if (ch == '\n'){
				M->col = cols;
				if (!step_col(T, M, rows, cols, start_row, start_col, &new_row))
					break;

				continue;
			}
/* interpret CR as LF unless followed by LF, then just step */
			else if (ch == '\r' && M->opts.wrap_mode == BUFFERWND_WRAP_ACCEPT_CR_LF){
				if (i + M->buffer_pos + 1 < M->buffer_sz){
					if (M->buffer[i + M->buffer_pos + 1] == '\n'){
					}
					else {
						M->col = cols;
						if (!step_col(T, M, rows, cols, start_row, start_col, &new_row))
							break;
					}
					continue;
				}
			}
		}

/* UNICODE vs ASCII here */
		if (i == M->buffer_ofs && !mask_write){
			M->cursor_x = M->col;
			M->cursor_y = M->row;
			cursor_found = true;
		}

		if (!mask_write)
			arcan_tui_writeu8(T, &M->buffer[i + M->buffer_pos], 1, &cattr);

/* advance cursor position, take wrapping etc. into account */
		if (!step_col(T, M, rows, cols, start_row, start_col, &new_row))
			break;
	}

/* edge case where ofs would point outside of visible window from wrapping */
	if (!cursor_found && !mask_write){
		size_t cy = M->row;
		size_t cx = M->col;
		while(cx > 0){
			struct tui_cell cur = arcan_tui_getxy(T, cx, cy, false);
			if (cur.ch)
				break;
			cx -= 1;
		}
		M->cursor_x = cx;
		M->cursor_y = cy;
		M->buffer_ofs = screen_to_pos(T, M);
	}

	arcan_tui_move_to(T, M->cursor_x, M->cursor_y);
}

static void monochrome(struct tui_context* T, void* tag,
	uint8_t bytev, size_t pos, uint32_t* dch, struct tui_screen_attr* attr)
{
	attr->aflags |= TUI_ATTR_COLOR_INDEXED;
	attr->fc[0] = TUI_COL_TEXT;
	attr->bc[0] = TUI_COL_TEXT;
}

#include "hex_colors.h"
static uint8_t color_tbl[768];
static void build_color_lut()
{
	for (size_t i = 0; i < 256; i++){
		HEADER_PIXEL(header_data, (&color_tbl[i*3]));
	}
}

static void flt_ascii(
	struct tui_context* T, char* wndbuf, size_t wndbuf_sz, size_t pos)
{
/* note that this does not align on a utf8-boundary, separate mode for this? */
	for (size_t i = 0; i < wndbuf_sz; i++)
		if (!isascii(wndbuf[i]))
			wndbuf[i] = ' ';
}

static void flt_none(
	struct tui_context* T, char* wndbuf, size_t wndbuf_sz, size_t pos)
{

}

static void color_lut(struct tui_context* T, void* tag,
	uint8_t bytev, size_t pos, uint32_t* dch, struct tui_screen_attr* attr)
{
	memcpy(attr->fc, &color_tbl[bytev], 3);
	attr->aflags &= ~TUI_ATTR_COLOR_INDEXED;
	arcan_tui_get_bgcolor(T, TUI_COL_TEXT, attr->bc);
}

_Thread_local static struct
{
	size_t x;
	size_t y;
	size_t ofs;
} resolve_temp;

static void set_pos(struct tui_context* T, size_t x, size_t y)
{
	resolve_temp.x = x;
	resolve_temp.y = y;
}

static void set_ofs(struct tui_context* T, size_t ofs)
{
	resolve_temp.ofs = ofs;
}

static size_t screen_to_pos(
	struct tui_context* T, struct bufferwnd_meta* M)
{
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);

	switch (M->opts.view_mode){
	case BUFFERWND_VIEW_ASCII:
		redraw_text(T, M, rows, cols,
			0, 0, NULL, flt_ascii, true, NULL, set_ofs);
	break;
	case BUFFERWND_VIEW_UTF8:
		redraw_text(T, M, rows, cols, 0, 0,
			NULL, flt_none, true, NULL, set_ofs);
	break;
	case BUFFERWND_VIEW_HEX:
	case BUFFERWND_VIEW_HEX_DETAIL:
		redraw_hex(T, M, rows, cols, 0, 0, M->opts.view_mode ==
			BUFFERWND_VIEW_HEX_DETAIL, NULL, true, NULL, set_ofs);
	break;
	default:
	break;
	}

/* this re-implements the buffer stepping /traversal from the normal
 * drawing, it just cancels out when reaching the correct offset, and
 * no write calls are performed */
	return resolve_temp.ofs;
}

static void pos_to_screen(
	struct tui_context* T, struct bufferwnd_meta* M, size_t* x, size_t* y)
{
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);

	switch (M->opts.view_mode){
	case BUFFERWND_VIEW_ASCII:
		redraw_text(T, M, rows, cols,
			0, 0, NULL, flt_ascii, true, set_pos, NULL);
	break;
	case BUFFERWND_VIEW_UTF8:
		redraw_text(T, M, rows, cols, 0, 0,
			NULL, flt_none, true, set_pos, NULL);
	break;
	case BUFFERWND_VIEW_HEX:
	case BUFFERWND_VIEW_HEX_DETAIL:
		redraw_hex(T, M, rows, cols, 0, 0, M->opts.view_mode ==
			BUFFERWND_VIEW_HEX_DETAIL, NULL, true, set_pos, NULL);
	break;
	default:
	break;
	}

	*x = resolve_temp.x;
	*y = resolve_temp.y;
}

static attr_lookup_fn get_color_function(struct bufferwnd_meta* M)
{
	switch (M->opts.color_mode){
	case BUFFERWND_COLOR_PALETTE:
		return M->opts.view_mode < BUFFERWND_VIEW_HEX ? monochrome : color_lut;

	case BUFFERWND_COLOR_CUSTOM:
		if (M->opts.custom_attr)
			return M->opts.custom_attr;

	case BUFFERWND_COLOR_NONE:
	default:
		return monochrome;
	}
}

static void redraw_bufferwnd(struct tui_context* T, struct bufferwnd_meta* M)
{
	arcan_tui_erase_screen(T, false);
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);
	arcan_tui_set_flags(T, has_cursor(M) ? 0 : TUI_HIDE_CURSOR);

	switch (M->opts.view_mode){
	case BUFFERWND_VIEW_ASCII:
		redraw_text(T, M, rows, cols, 0, 0,
			get_color_function(M), flt_ascii, false, NULL, NULL);
	break;
	case BUFFERWND_VIEW_UTF8:
		redraw_text(T, M, rows, cols, 0, 0,
			get_color_function(M), flt_none, false, NULL, NULL);
	break;
	case BUFFERWND_VIEW_HEX:
		redraw_hex(T, M, rows, cols, 0, 0, false,
			monochrome, false, NULL, NULL);
	break;
/* always show cursor in hex detail mode */
	case BUFFERWND_VIEW_HEX_DETAIL:
		redraw_hex(T, M, rows, cols, 0, 0,
			rows > min_meta_rows, get_color_function(M), false, NULL, NULL);
	break;
	default:
	break;
	}
}

static void on_resized(struct tui_context* T,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	struct bufferwnd_meta* M = t;
	redraw_bufferwnd(T, M);
}

static void on_recolor(struct tui_context* T, void* t)
{
	struct bufferwnd_meta* M = t;
	redraw_bufferwnd(T, M);
}

static bool label_wrap_cycle(struct tui_context* T, struct bufferwnd_meta* M)
{
	switch (M->opts.wrap_mode){
	case BUFFERWND_WRAP_ACCEPT_CR_LF:
		M->opts.wrap_mode = BUFFERWND_WRAP_ALL;
	break;
	case BUFFERWND_WRAP_ACCEPT_LF:
		M->opts.wrap_mode = BUFFERWND_WRAP_ACCEPT_CR_LF;
	break;
	case BUFFERWND_WRAP_ALL:
		M->opts.wrap_mode = BUFFERWND_WRAP_ACCEPT_LF;
	break;
	}
	redraw_bufferwnd(T, M);
	return true;
}

static bool label_color_cycle(struct tui_context* T, struct bufferwnd_meta* M)
{
	if (M->opts.color_mode == BUFFERWND_COLOR_NONE){
		M->opts.color_mode = BUFFERWND_COLOR_PALETTE;
	}
	else if (M->opts.color_mode == BUFFERWND_COLOR_PALETTE){
		if (M->opts.custom_attr)
			M->opts.color_mode = BUFFERWND_COLOR_CUSTOM;
		else
			M->opts.color_mode = BUFFERWND_COLOR_NONE;
	}

	redraw_bufferwnd(T, M);
	return true;
}

static bool label_hex_cycle(struct tui_context* T, struct bufferwnd_meta* M)
{
	M->opts.view_mode = BUFFERWND_VIEW_HEX;

	if (M->opts.hex_mode == BUFFERWND_HEX_BASIC){
		M->opts.hex_mode = BUFFERWND_HEX_ASCII;
	}
	else if (M->opts.hex_mode == BUFFERWND_HEX_ASCII){
		M->opts.hex_mode = BUFFERWND_HEX_BASIC;
	}
	else if (M->opts.hex_mode == BUFFERWND_HEX_ANNOTATE){
/* incomplete, needs a shadow buffer to store annotations */
	}
	else if (M->opts.hex_mode == BUFFERWND_HEX_META){
/* incomplete, needs an external oracle to provide metadata */
	}

	if (M->opts.view_mode >= BUFFERWND_VIEW_HEX){
		redraw_bufferwnd(T, M);
	}
	return true;
}

static bool label_view_cycle(struct tui_context* T, struct bufferwnd_meta* M)
{
/* could've just +1 % n:ed it all, but this is slightly clearer */
	M->cursor_halfb = false;
	switch (M->opts.view_mode){
	case BUFFERWND_VIEW_ASCII:
		M->opts.view_mode = BUFFERWND_VIEW_UTF8;
	break;
	case BUFFERWND_VIEW_UTF8:
		M->opts.view_mode = BUFFERWND_VIEW_HEX;
	break;
	case BUFFERWND_VIEW_HEX:
		M->opts.view_mode = BUFFERWND_VIEW_HEX_DETAIL;
	break;
	case BUFFERWND_VIEW_HEX_DETAIL:
		M->opts.view_mode = BUFFERWND_VIEW_ASCII;
	break;
	}
	redraw_bufferwnd(T, M);
	return true;
}

struct labelent {
	bool (* handler)(struct tui_context* T, struct bufferwnd_meta* M);
	struct tui_labelent ent;
};

#ifdef _DEBUG
static bool dump(struct tui_context* T, struct bufferwnd_meta* M)
{
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);
	for (size_t y = 0; y < rows; y++){
		for (size_t x = 0; x < cols; x++){
			struct tui_cell cur = arcan_tui_getxy(T, x, y, false);
			printf("%c", cur.ch);
		}
		printf("\n");
	}

	return true;
}
#endif

static struct labelent labels[] = {
	{
		.handler = label_wrap_cycle,
		.ent =
		{
			.label = "WRAP",
			.descr = "Cycle wrapping modes",
			.initial = TUIK_F3
		}
	},
	{
		.handler = label_view_cycle,
		.ent = {
			.label = "VIEW",
			.descr = "Cycle presentation modes (ASCII/UTF8/...)",
			.initial = TUIK_F4
		}
	},
	{
		.handler = label_color_cycle,
		.ent = {
			.label = "COLOR",
			.descr = "Cycle coloring modes (byte value, type, ...)",
			.initial = TUIK_F5
		}
	},
	{
		.handler = label_hex_cycle,
		.ent = {
			.label = "HEX_MODE",
			.descr = "Cycle hex modes (ascii column, annotations, ...)",
			.initial = TUIK_F6
		},
	},
#ifdef _DEBUG
	{
		.handler = dump,
		.ent = {
			.label = "DUMP",
			.descr = "Dump",
			.initial = TUIK_F7
		}
	}
#endif
};

static bool on_label_input(
	struct tui_context* T, const char* label, bool active, void* tag)
{
	if (!active)
		return true;

	for (size_t i = 0; i < COUNT_OF(labels); i++){
		if (strcmp(label, labels[i].ent.label) == 0)
			return labels[i].handler(T, (struct bufferwnd_meta*) tag);
	}

/* chain the input onwards */
	struct bufferwnd_meta* M = tag;
	if (M->old_handlers.input_label)
		return M->old_handlers.input_label(T, label, active, M->old_handlers.tag);

	return false;
}

static bool on_label_query(struct tui_context* T,
	size_t index, const char* country, const char* lang,
	struct tui_labelent* dstlbl, void* t)
{
	struct bufferwnd_meta* M = t;

/* let the old context also get a chance */
	if (COUNT_OF(labels) < index + 1){
		if (M->old_handlers.query_label)
			return M->old_handlers.query_label(T,
				index - COUNT_OF(labels) - 1, country, lang, dstlbl, M->old_handlers.tag);
		return false;
	}

	memcpy(dstlbl, &labels[index].ent, sizeof(struct tui_labelent));
	return true;
}

static bool on_subwindow(struct tui_context* T,
	arcan_tui_conn* conn, uint32_t id, uint8_t type, void* tag)
{
	struct bufferwnd_meta* M;
	if (!validate_context(T, &M))
		return false;

	if (M->old_handlers.subwindow){
		return M->old_handlers.subwindow(T, conn, id, type, M->old_handlers.tag);
	}
	else
		return false;
}

/*
 * UTF-8 input, when in read-only mode we only return so that the chain
 * progresses to the on_key where we can manage the normal arrows etc.
 */
static bool on_u8(struct tui_context* T, const char* u8, size_t len, void* tag)
{
	struct bufferwnd_meta* M = tag;
	if (M->opts.read_only)
		return false;

/* hex-mode / hex-detail mode?, check 0-9, a-f, change and advance one position */
	switch(M->opts.view_mode){

	case BUFFERWND_VIEW_ASCII:
		if (len != 1){
			return false;
		}
		if (M->opts.commit){
			if (!M->opts.commit(T, M->opts.cbtag,
				(const uint8_t*) u8, len, M->buffer_pos + M->buffer_ofs)){
				return true;
			}
		}
		M->buffer[M->buffer_pos + M->buffer_ofs] = *u8;
		step_cursor_e(T, M);
		redraw_bufferwnd(T, M);
	break;
	case BUFFERWND_VIEW_UTF8:
/* currently don't do anything for u8, there are a number of cases to
 * consider, i.e. "insert" vs. "replace" vs. "search/window" vs. "search/global",
 * variable length, forwarding higher level features and so on. */
		break;
	case BUFFERWND_VIEW_HEX:
	case BUFFERWND_VIEW_HEX_DETAIL:
		if (!isxdigit(*u8))
			return false;

		if (M->opts.commit){
			if (!M->opts.commit(T, M->opts.cbtag,
				(const uint8_t*) u8, len, M->buffer_pos + M->buffer_ofs)){
				return true;
			}
		}
		uint8_t ch = *u8;
		uint8_t inb = M->buffer[M->buffer_pos + M->buffer_ofs];
		if (ch >= '0' && ch <= '9'){
			ch = ch - '0';
		}
		else {
			ch = 10 + (tolower(ch) - 'a');
		}
		if (!M->cursor_halfb){
			ch = ch * 16 + (inb & 15);
		}
		else {
			ch = ch + (inb & 0xf0);
		}

		M->buffer[M->buffer_pos + M->buffer_ofs] = ch;
		step_cursor_e(T, M);
		redraw_bufferwnd(T, M);
		return true;
	break;
	default:
	break;
	}

	return false;
}

static void scroll_page_down(struct tui_context* T, struct bufferwnd_meta* M)
{
	switch (M->opts.view_mode){
	case BUFFERWND_VIEW_UTF8:
	case BUFFERWND_VIEW_ASCII:{
/* need to sweep the buffer in order to figure out where the 'page' starts
 * based on wrapping mode */
	}
	break;
	case BUFFERWND_VIEW_HEX:
	case BUFFERWND_VIEW_HEX_DETAIL:{
		size_t step = M->row_bytelen * (M->cursor_ofs_row_end - M->cursor_ofs_row);
		M->buffer_pos += M->row_bytelen * (M->cursor_ofs_row_end - M->cursor_ofs_row);
		if (M->buffer_pos + M->row_bytelen > M->buffer_sz)
			M->buffer_pos = M->buffer_sz - step;
	}
	break;
	}

	redraw_bufferwnd(T, M);
}

static void scroll_page_up(struct tui_context* T, struct bufferwnd_meta* M)
{
	switch (M->opts.view_mode){
	case BUFFERWND_VIEW_UTF8:
	case BUFFERWND_VIEW_ASCII:{
/* need to sweep the buffer in order to figure out where the 'page' starts
 * based on wrapping mode */
	}
	break;
	case BUFFERWND_VIEW_HEX:
	case BUFFERWND_VIEW_HEX_DETAIL:{
		size_t step = M->row_bytelen * (M->cursor_ofs_row_end - M->cursor_ofs_row);
		if (M->buffer_pos > step)
			M->buffer_pos -= step;
		else
			M->buffer_pos = 0;
	}
	break;
	}

	redraw_bufferwnd(T, M);
}

static void scroll_row_down(struct tui_context* T, struct bufferwnd_meta* M)
{
/* previous calls to redraw_bufferwnd keeps track on how many bytes were
 * consumed for the first row, so we can just forward that and align against
 * buffer size */
	switch (M->opts.view_mode){
	case BUFFERWND_VIEW_UTF8:
	case BUFFERWND_VIEW_ASCII:{
		M->cursor_x = 0;
		M->cursor_y = 1;
		size_t pos = screen_to_pos(T, M);
		if (M->buffer_pos + pos < M->buffer_sz){
			M->buffer_pos += pos;
		}
	}
	break;
	case BUFFERWND_VIEW_HEX:
	case BUFFERWND_VIEW_HEX_DETAIL:
		if (M->buffer_pos + M->row_bytelen < M->buffer_sz)
			M->buffer_pos += M->row_bytelen;
	break;
	}

	redraw_bufferwnd(T, M);
}

static void scroll_row_up(struct tui_context* T, struct bufferwnd_meta* M)
{
/* this one is easy for hex still, but for ASCII and UTF8 it is the worst
 * case as we need to take both linefeed mode into account and (UTF8) deal
 * with variability in glyph visible length */
	switch (M->opts.view_mode){

/* not correct for UTF8, but treat them similarly for now */
	case BUFFERWND_VIEW_UTF8:
	case BUFFERWND_VIEW_ASCII:{
		size_t cofs = 1;
		size_t rows, cols;
		bool in_linefeed = false;
		arcan_tui_dimensions(T, &rows, &cols);

		while (cofs < M->buffer_pos && cols){
/* we are already at a renderable / split point, so increment first */
			uint8_t ch = M->buffer[M->buffer_pos - cofs];

/* line-breaks, for UTF we'd need to also consider, at least, non-advancing
 * whitespace and all that kind of jazz */
			if (ch == '\n' || ch == '\r'){
				if (M->opts.wrap_mode != BUFFERWND_WRAP_ALL){
					if (in_linefeed){
						cofs--;
						break;
					}
					in_linefeed = true;
				}
			}
/* valid printable character (will need a utf-8 seekback etc. step here
 * as well, then the hairy problem of what to do with substitution table
 * or shaping functions */
			cols--;
			if (cols)
				cofs++;
		}
		M->buffer_pos -= M->buffer_pos > cofs ? cofs : M->buffer_pos;
	}
	break;
	case BUFFERWND_VIEW_HEX:
	case BUFFERWND_VIEW_HEX_DETAIL:
		M->buffer_pos -=
			M->buffer_pos > M->row_bytelen ? M->row_bytelen : M->buffer_pos;
	break;
	}

	redraw_bufferwnd(T, M);
}

static void realign_update(
	struct tui_context* T, struct bufferwnd_meta* M, size_t cx, size_t cy)
{
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);

/* re-align to nearest non- empty cell, this is actual RTL- LTR sensitive,
 * but we don't respect input/presentation locale at the moment */
	bool align = true;

	if (M->opts.view_mode == BUFFERWND_VIEW_UTF8 ||
		M->opts.view_mode == BUFFERWND_VIEW_ASCII){
		if (M->opts.wrap_mode == BUFFERWND_WRAP_ALL)
			align = false;
	}

	while(align && cx > 0){
		struct tui_cell cur = arcan_tui_getxy(T, cx, cy, false);
		if (cur.ch)
			break;
		cx -= 1;
	}

	M->cursor_x = cx;
	M->cursor_y = cy;
	M->buffer_ofs = screen_to_pos(T, M);

	arcan_tui_move_to(T, M->cursor_x, M->cursor_y);
}

static void step_cursor_s(struct tui_context* T, struct bufferwnd_meta* M)
{
/*
 * local copy of the current cursor position as the scroll_row call will
 * modify it, even though in that case we'd want it to stay in place
 */
	size_t cx = M->cursor_x;
	size_t cy = M->cursor_y;
	int vm = M->opts.view_mode;

	if (cy + 1 > M->cursor_ofs_row_end){
		scroll_row_down(T, M);
		return;
	}
	else
		cy = cy + 1;

/* halfb- step-left, screen based update, then reset to halfb position */
	if (M->cursor_halfb){
		if (cx)
			cx--;
		realign_update(T, M, cx, cy);
		M->cursor_x++;
		arcan_tui_move_to(T, M->cursor_x, M->cursor_y);
	}
	else
		realign_update(T, M, cx, cy);

	if (vm == BUFFERWND_VIEW_HEX_DETAIL)
		redraw_bufferwnd(T, M);
}

static void step_cursor_n(struct tui_context* T, struct bufferwnd_meta* M)
{
	size_t cx = M->cursor_x;
	size_t cy = M->cursor_y;
	int vm = M->opts.view_mode;

	if (cy == M->cursor_ofs_row){
		scroll_row_up(T, M);
		return;
	}
	else
		cy = cy - 1;

/* halfb- step-left, screen based update, then reset to halfb position */
	if (M->cursor_halfb){
		if (cx)
			cx--;
		realign_update(T, M, cx, cy);
		M->cursor_x++;
		arcan_tui_move_to(T, M->cursor_x, M->cursor_y);
	}
	else
		realign_update(T, M, cx, cy);

	if (vm == BUFFERWND_VIEW_HEX_DETAIL)
		redraw_bufferwnd(T, M);
}

static void step_cursor_w(struct tui_context* T, struct bufferwnd_meta* M)
{
/* for editability, we have a half-byte offset in edit+hex */
	int vm = M->opts.view_mode;
	ssize_t cofs = 0;

	if ((vm == BUFFERWND_VIEW_HEX ||
		vm == BUFFERWND_VIEW_HEX_DETAIL) && !M->opts.read_only){
		if (M->cursor_halfb){
			M->cursor_halfb = false;
			arcan_tui_move_to(T, --M->cursor_x, M->cursor_y);
			return;
		}
/* we step over a hex column spacer and the pos-screen realign then sets
 * the cursor at non-halfb position, so we need to nudge it back */
		else{
			M->cursor_halfb = true;
			cofs = 1;
		}
	}

/* here we just work on the cursor indicative bytes itself and use the
 * redraw option to realign cursor position etc. */
	if (M->buffer_ofs == 0){
		if (M->buffer_pos > 0){
			M->buffer_ofs = M->row_bytelen - 1;
			scroll_row_up(T, M);
		}
	}
	else {
		M->buffer_ofs = M->buffer_ofs - 1;
		pos_to_screen(T, M, &M->cursor_x, &M->cursor_y);
		M->cursor_x += cofs;
		arcan_tui_move_to(T, M->cursor_x, M->cursor_y);
	}

	if (vm == BUFFERWND_VIEW_HEX_DETAIL)
		redraw_bufferwnd(T, M);
}

static void step_cursor_e(struct tui_context* T, struct bufferwnd_meta* M)
{
	int vm = M->opts.view_mode;
	if ((vm == BUFFERWND_VIEW_HEX ||
		vm == BUFFERWND_VIEW_HEX_DETAIL) && !M->opts.read_only){
		if (!M->cursor_halfb){
			M->cursor_halfb = true;
			arcan_tui_move_to(T, ++M->cursor_x, M->cursor_y);
			return;
		}
		else
			M->cursor_halfb = false;
	}

/* step visible right or step row down and start at first (always visible) */
	if (M->buffer_ofs == M->buffer_lend-1){
		M->buffer_ofs -= M->row_bytelen - 1;
		step_cursor_s(T, M);
	}
	else {
		M->buffer_ofs++;
		pos_to_screen(T, M, &M->cursor_x, &M->cursor_y);
		arcan_tui_move_to(T, M->cursor_x, M->cursor_y);
	}

	if (vm == BUFFERWND_VIEW_HEX_DETAIL){
		redraw_bufferwnd(T, M);
	}
}

static void on_key_input(struct tui_context* T, uint32_t keysym,
	uint8_t scancode, uint16_t mods, uint16_t subid, void* tag)
{
	struct bufferwnd_meta* M = tag;
/* might want to provide the label based approach to these as well, UP/DOWN
 * are at least already registered and handled / forwarded from the base tui */
	if (keysym == TUIK_DOWN || keysym == TUIK_J){
		if (has_cursor(M))
			step_cursor_s(T, M);
		else
			scroll_row_down(T, M);
	}
	else if (keysym == TUIK_UP || keysym == TUIK_K){
		if (has_cursor(M))
			step_cursor_n(T, M);
		else
			scroll_row_up(T, M);
	}
	else if (keysym == TUIK_LEFT || keysym == TUIK_H){
		if (has_cursor(M))
			step_cursor_w(T, M);
		else
			scroll_row_up(T, M);
	}
	else if (keysym == TUIK_RIGHT || keysym == TUIK_L){
		if (has_cursor(M))
			step_cursor_e(T, M);
		else
			scroll_row_down(T, M);
	}
	else if (keysym == TUIK_PAGEDOWN){
		scroll_page_down(T, M);
	}
	else if (keysym == TUIK_PAGEUP){
		scroll_page_up(T, M);
	}
	else if (keysym == TUIK_ESCAPE ||
		(keysym == TUIK_RETURN && (mods & (TUIM_LSHIFT | TUIM_RSHIFT)) )
	){
		if (!M->opts.allow_exit)
			return;

		M->exit_status = keysym == TUIK_RETURN ? 0 : -1;
	}
	else
		;
}

void arcan_tui_bufferwnd_synch(
	struct tui_context* T, uint8_t* buf, size_t buf_sz, size_t prefix_ofs)
{
	struct bufferwnd_meta* M;
	if (!buf || !buf_sz || !validate_context(T, &M))
		return;

	M->buffer = buf;
	M->buffer_sz = buf_sz;
	M->buffer_ofs = 0;
	M->buffer_pos = 0;
	M->exit_status = 1;
	M->cursor_x = 0;
	M->cursor_y = 0;
	M->cursor_halfb = 0;
	M->cursor_ofs_col = 0;
	M->cursor_ofs_row = 0;
	M->cursor_ofs_row_end = 0;
	M->opts.offset = prefix_ofs;

	redraw_bufferwnd(T, M);
}

void arcan_tui_bufferwnd_seek(struct tui_context* T, size_t buf_pos)
{
	struct bufferwnd_meta* M;
	if (!validate_context(T, &M))
		return;

/* clamp */
	if (buf_pos >= M->buffer_sz)
		buf_pos = M->buffer_sz - 1;

/* cursor_ofs_row gives us starting row,
 * row_bytelen gives us the number of bytes per row
 * cursor_ofs_row_end gives us the last row line
 * so bytes per page:
 */
	size_t n_rows = M->cursor_ofs_row_end - M->cursor_ofs_row;
	size_t bpp = n_rows * M->row_bytelen;

/* first page */
	if (buf_pos < bpp){
		M->buffer_pos = 0;
		M->buffer_ofs = buf_pos;
	}
	else{
		M->buffer_pos = (buf_pos / bpp) * bpp;
		M->buffer_ofs = buf_pos - M->buffer_pos;
	}

	redraw_bufferwnd(T, M);
}

static void mouse_button(struct tui_context* T,
	int last_x, int last_y, int button, bool active, int modifiers, void* tag)
{
	struct bufferwnd_meta* M = tag;
	if (!active)
		return;

	if (button == TUIBTN_WHEEL_UP){
		step_cursor_n(T, M);
		return;
	}
	else if (button == TUIBTN_WHEEL_DOWN){
		step_cursor_s(T, M);
		return;
	}

/* find the closest fitting buffer offset */
	M->cursor_x = last_x;
	M->cursor_y = last_y;

/* for hex we know that the column should be % 3 == 0 */
	if (M->opts.view_mode == BUFFERWND_VIEW_HEX_DETAIL
		|| M->opts.view_mode == BUFFERWND_VIEW_HEX){
		if (M->cursor_x && M->cursor_x % 3 != 0)
			M->cursor_x -= M->cursor_x % 3;
	}

	size_t old_pos = M->buffer_ofs;
	M->buffer_ofs = screen_to_pos(T, M);

/* early out on nop */
	if (old_pos == M->buffer_ofs)
		return;

/* and re-align based on offset */
	size_t x, y;
	pos_to_screen(T, M, &x, &y);
	M->cursor_x = x;
	M->cursor_y = y;

/* and redraw for cursor to match */
	redraw_bufferwnd(T, M);
}

void arcan_tui_bufferwnd_setup(struct tui_context* T,
	uint8_t* buf, size_t buf_sz, struct tui_bufferwnd_opts* opts, size_t opt_sz)
{
	static bool first_call = true;
	if (first_call){
		build_color_lut();
		first_call = false;
	}

	struct bufferwnd_meta* meta = malloc(sizeof(struct bufferwnd_meta));
	if (!meta)
		return;

	*meta = (struct bufferwnd_meta){
		.magic = BUFFERWND_MAGIC,
		.buffer = buf,
		.buffer_sz = buf_sz,
		.exit_status = 1
	};

	arcan_tui_dimensions(T, &meta->orig_h, &meta->orig_w);

	if (meta->orig_w < 80 || meta->orig_h < 24){
		arcan_tui_wndhint(T, NULL,
			(struct tui_constraints){
				.min_cols = -1, .min_rows = -1,
				.max_cols = 80, .max_rows = 24,
				.anch_row = -1, .anch_col = -1
			}
		);
	}

	if (opts){
		meta->opts = *opts;
	}

	struct tui_cbcfg cbcfg = {
		.tag = meta,
		.resized = on_resized,
		.query_label = on_label_query,
		.input_label = on_label_input,
		.input_key = on_key_input,
		.input_mouse_button = mouse_button,
		.input_utf8 = on_u8,
		.subwindow = on_subwindow,
		.recolor = on_recolor
	};

/* save old flags and just set clean */
	meta->old_flags = arcan_tui_set_flags(T, TUI_ALTERNATE | TUI_MOUSE);

/* save old handlers */
	arcan_tui_update_handlers(T,
		&cbcfg, &meta->old_handlers, sizeof(struct tui_cbcfg));

	assert(meta->old_handlers.input_label != on_label_input);

	arcan_tui_reset_labels(T);
	redraw_bufferwnd(T, meta);
}

int arcan_tui_bufferwnd_status(struct tui_context* T)
{
	struct bufferwnd_meta* meta;
	if (!validate_context(T, &meta))
		return -1;

	return meta->exit_status;
}

#ifdef EXAMPLE
int main(int argc, char** argv)
{
	struct tui_cbcfg cbcfg = {};
	arcan_tui_conn* conn = arcan_tui_open_display("test", "");
	struct tui_context* tui = arcan_tui_setup(conn, NULL, &cbcfg, sizeof(cbcfg));
	struct tui_bufferwnd_opts opts = {
		.read_only = false,
		.view_mode = BUFFERWND_VIEW_HEX_DETAIL
	};

/* normal "hello world" example unless a file is provided */
	char* text_buffer = {
		"There once was this\n weird little test case that we wondered\n to see if it "
		"could be used to \r\n show with the help of my little friend"
	};

	char* dst_buf = text_buffer;
	size_t dst_buf_sz = strlen(text_buffer) + 1;

	if (argc > 1){
		char* infile = argv[1];
		if (infile[0] == '+'){
			opts.read_only = false;
			infile = &infile[1];
			fprintf(stdout, "opening %s in fake- rw mode\n", infile);
		}

		FILE* fpek = fopen(infile, "r");
		if (!fpek){
			fprintf(stderr, "couldn't open file: (%s)\n", argv[1]);
			return EXIT_FAILURE;
		}

		fseek(fpek, 0, SEEK_END);
		long pos = ftell(fpek);
		if (pos <= 0){
			fprintf(stderr, "invalid buffer size: %ld\n", pos);
			return EXIT_FAILURE;
		}

		char* buf = malloc(pos);
		if (!buf){
			fprintf(stderr, "couldn't prepare buffer of %ld bytes\n", pos);
			return EXIT_FAILURE;
		}

		fseek(fpek, 0, SEEK_SET);
		if (0 == fread(buf, pos, 1, fpek)){
			fprintf(stderr, "couldn't read %ld bytes from %s\n", pos, argv[1]);
			return EXIT_FAILURE;
		}

		fclose(fpek);
		dst_buf = buf;
		dst_buf_sz = pos;
	}

/* switch to bufferwnd mode */
	arcan_tui_bufferwnd_setup(tui, (uint8_t*) dst_buf,
		dst_buf_sz, &opts, sizeof(struct tui_bufferwnd_opts));

/* and normal processing loop */
	while(1){
		struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
				break;
		}
		else
			break;
	}

	arcan_tui_destroy(tui, NULL);
	return 0;
}
#endif
