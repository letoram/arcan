#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"
#include <pthread.h>
#include <errno.h>
#include <assert.h>

typedef void* TTF_Font;
#include "../raster/raster.h"
#include "../raster/draw.h"

static void resize_cellbuffer(struct tui_context* tui)
{
	if (tui->base){
		free(tui->base);
	}

	tui->base = NULL;

	size_t buffer_sz = 2 * tui->rows * tui->cols * sizeof(struct tui_cell);
	size_t rbuf_sz = tui_screen_tpack_sz(tui);

	tui->base = malloc(buffer_sz);
	if (!tui->base){
		LOG("couldn't allocate screen buffers\n");
		return;
	}

	memset(tui->base, '\0', buffer_sz);

	if (tui->acon.vidb)
		memset(tui->acon.vidb, '\0', rbuf_sz);

	tui->front = tui->base;
	tui->back = &tui->base[tui->rows * tui->cols];
	tui->dirty |= DIRTY_FULL;
}

/* sweep a row from a start offset until the first deviation
 * between front and back offset */
static ssize_t find_row_ofs(
	struct tui_context* tui, size_t row, size_t ofs)
{
	size_t pos = row * tui->cols;
	struct tui_cell* front = &tui->front[pos];
	struct tui_cell* back = &tui->back[pos];

	for (pos = ofs; pos < tui->cols; pos++){
		if (!tui_attr_equal(front[pos].attr,
			back[pos].attr) || front[pos].ch != back[pos].ch){
			return pos;
		}
	}
	return -1;
}

static void pack_u32(uint32_t src, uint8_t* outb)
{
	outb[0] = (uint8_t)(src >> 0);
	outb[1] = (uint8_t)(src >> 8);
	outb[2] = (uint8_t)(src >> 16);
	outb[3] = (uint8_t)(src >> 24);
}

static void unpack_u32(uint32_t* dst, uint8_t* inbuf)
{
	*dst =
		((uint64_t)inbuf[0] <<  0) |
		((uint64_t)inbuf[1] <<  8) |
		((uint64_t)inbuf[2] << 16) |
		((uint64_t)inbuf[3] << 24);
}

static struct tui_cell rcell_to_cell(uint8_t unpack[static 12])
{
	struct tui_cell res = {0};

	res.attr.fc[0] = unpack[0];
	res.attr.fc[1] = unpack[1];
	res.attr.fc[2] = unpack[2];
	res.attr.bc[0] = unpack[3];
	res.attr.bc[1] = unpack[4];
	res.attr.bc[2] = unpack[5];
	res.attr.aflags = unpack[6];
	unpack_u32(&res.ch, &unpack[8]);

	return res;
}

static size_t cell_to_rcell(struct tui_context* tui,
struct tui_cell* tcell, uint8_t* outb, uint8_t has_cursor)
{
	uint8_t* fc = tcell->attr.fc;
	uint8_t* bc = tcell->attr.bc;

/* if indexed, then fc[0] and bc[0] refer to color index to draw rather
 * than the actual values */
	if (tcell->attr.aflags & TUI_ATTR_COLOR_INDEXED){
		fc = tui->colors[fc[0] % TUI_COL_LIMIT].rgb;
		bc = tui->colors[bc[0] % TUI_COL_LIMIT].bg;
	}

/* inverse isn't an attribute on the packing level, we simply modify the colors
 * as the 'inverse' attribute is a left-over from the terminal emulation days */
	if (tcell->attr.aflags & TUI_ATTR_INVERSE){
/* use the tactic of picking 'new foreground / background' based on the
 * intensity of the current-cell colours rather than say, fg <=> bg */
		float intens =
			(0.299f * fc[0] +
			 0.587f * fc[1] +
			 0.114f * fc[2]) / 255.0f;

		if (intens < 0.5f){
			*outb++ = 0xff; *outb++ = 0xff; *outb++ = 0xff;
		}
		else {
			*outb++ = 0x00; *outb++ = 0x00; *outb++ = 0x00;
		}
		*outb++ = fc[0];
		*outb++ = fc[1];
		*outb++ = fc[2];
	}
	else {
		*outb++ = fc[0];
		*outb++ = fc[1];
		*outb++ = fc[2];
		*outb++ = bc[0];
		*outb++ = bc[1];
		*outb++ = bc[2];
	}

/* this deviates from the tui cell here, the terminal- legacy blink
 * and protect bits are not kept */
	*outb++ = (
		CATTR_BOLD          * (!!(tcell->attr.aflags & TUI_ATTR_BOLD))          |
		CATTR_UNDERLINE     * (!!(tcell->attr.aflags & TUI_ATTR_UNDERLINE))     |
		CATTR_UNDERLINE_ALT * (!!(tcell->attr.aflags & TUI_ATTR_UNDERLINE_ALT)) |
		CATTR_ITALIC        * (!!(tcell->attr.aflags & TUI_ATTR_ITALIC))        |
		CATTR_STRIKETHROUGH * (!!(tcell->attr.aflags & TUI_ATTR_STRIKETHROUGH)) |
		CATTR_SHAPEBREAK    * (!!(tcell->attr.aflags & TUI_ATTR_SHAPE_BREAK))   |
		CATTR_CURSOR        * has_cursor
	);

	*outb++ = (
		CEATTR_GLYPH_IND  * (!!(tcell->attr.aflags & TUI_ATTR_GLYPH_INDEXED))  |
		CEATTR_AGLYPH_IND * (!!(tcell->attr.aflags & TUI_ATTR_AGLYPH_INDEXED)) |
		CEATTR_BORDER_R   * (!!(tcell->attr.aflags & TUI_ATTR_BORDER_RIGHT))   |
		CEATTR_BORDER_D   * (!!(tcell->attr.aflags & TUI_ATTR_BORDER_DOWN))    |
		CEATTR_BORDER_L   * (!!(tcell->attr.aflags & TUI_ATTR_BORDER_LEFT))    |
		CEATTR_BORDER_T   * (!!(tcell->attr.aflags & TUI_ATTR_BORDER_TOP))
	);

	pack_u32(tcell->ch, outb);
	return raster_cell_sz;
}

size_t tui_screen_tpack_sz(struct tui_context* tui)
{
	return
		sizeof(struct tui_raster_header) + /* always there */
		((tui->rows * tui->cols + 2) * raster_cell_sz) + /* worst case, includes cursor */
		((tui->rows+2) * sizeof(struct tui_raster_line))
	;
}

size_t tui_screen_tpack(struct tui_context* tui,
	struct tpack_gen_opts opts, uint8_t* rbuf, size_t rbuf_sz)
{
/* start with header */
	if (!opts.full && tui->dirty == DIRTY_NONE)
		return 0;

/* header gets written to the buffer last */
	struct tui_raster_header hdr = {};
	arcan_tui_get_color(tui, TUI_COL_BG, hdr.bgc);
	hdr.bgc[3] = tui->alpha;

	uint8_t* out = rbuf;
	size_t outsz = sizeof(hdr) + 3; /* always send CURSOR_EXTHDRv1 */

	if (opts.back){
		opts.full = true;
		opts.synch = false;
	}

/* this is set on a manual invalidate, or a screen or cell resize */
	if (opts.full || (tui->dirty & DIRTY_FULL)){
		struct tui_cell* front = tui->front;
		struct tui_cell* back = tui->back;
		if (opts.back)
			front = tui->back;

/* cursor is guaranteed to be overdrawn */
		tui->last_cursor.active = false;

		hdr.flags |= RPACK_IFRAME;
		hdr.lines = tui->rows;
		hdr.cells = tui->rows * tui->cols;

/* on delta we need to scan the row before writing the header, here
 * we can just precompute everything */
		for (size_t row = 0; row < tui->rows; row++){
			struct tui_raster_line line = {
				.start_line = row,
				.ncells = tui->cols,
			};
			memcpy(&out[outsz], &line, sizeof(line));
			outsz += sizeof(line);

/* when updating, synch front/back cell buffer so partials can
 * be generated later */
			for (size_t col = 0; col < tui->cols; col++){
				struct tui_screen_attr* attr = &front->attr;
				if (opts.synch)
					*back = *front;
				outsz += cell_to_rcell(tui, front, &out[outsz], 0);
				back++;
				front++;
			}
		}
	}

/* delta update, find_row_ofs gives the next mismatch on the row */
	else if (tui->dirty & DIRTY_PARTIAL){
		for (size_t row = 0; row < tui->rows; row++){
			ssize_t ofs = find_row_ofs(tui, row, 0);
			if (-1 == ofs)
				continue;

			size_t row_base = row * tui->cols;

/* if we overdraw the save-cursor position, don't emit the glyph again */
			if (tui->last_cursor.active &&
				tui->last_cursor.row == row && tui->last_cursor.col == ofs)
				tui->last_cursor.active = false;

/* we forward all lines where there is some kind of difference,
 * assuming most follow the pattern -----XXXXXX----- XXXXXXXXXX,
 * with the worst- case being X-------------X that gets 'full-line
 * with skip-cells'). */
			struct tui_raster_line line = {
				.start_line = row,
				.offset = ofs
			};

/* alias line header position */
			size_t line_dst = outsz;
			outsz += sizeof(line);

			while(ofs != -1 && ofs < tui->cols){
				struct tui_cell* attr = &tui->front[row_base + ofs];

				if (opts.synch)
					tui->back[row_base + ofs] = *attr;

				line.ncells++;
				outsz += cell_to_rcell(tui, attr, &out[outsz], 0);
/* iterate forward */
				ssize_t last_ofs = ofs;
				ofs = find_row_ofs(tui, row, ofs+1);
				if (-1 == ofs)
					break;

/* encode 'skip-draw' cell for the ones that don't matter,
 * just set the most significant attribute bit (ignore) */
				for (; last_ofs + 1 != ofs; last_ofs++){
					memset(&out[outsz], '\0', raster_cell_sz);
					out[outsz + 6] = 128;
					out[outsz + 7] = 0;
					outsz += raster_cell_sz;
					line.ncells++;
				}
			}

			memcpy(&out[line_dst], &line, sizeof(struct tui_raster_line));
			hdr.cells += line.ncells;
			hdr.lines++;
		}

		hdr.flags |= RPACK_DFRAME;
	}

/* cursor management may expose 2 separate line + cell updates (less
 * code on the renderer side than having a special header and send the
 * data there).:
 * line 1. original glyph with cursor attr set.
 * line 2. previous cursor position)
 */
	if (tui->dirty & DIRTY_CURSOR){
/* the correct line-attribute should be resolved here as well */
		struct tui_raster_line line = {
			.ncells = 1
		};

		if (tui->dirty == DIRTY_CURSOR){
			hdr.flags |= RPACK_DFRAME;
		}

/* restore the last cursor position, since that is a cell attribute and there
 * can be multiple simultaneous cursors the original cell states need to be
 * restored rather than letting tpack track it */
		if (tui->last_cursor.active &&
			(tui->last_cursor.col != tui->cx || tui->last_cursor.row != tui->cy)){
			hdr.lines++;
			hdr.cells++;
			line.start_line = tui->last_cursor.row;
			line.offset = tui->last_cursor.col;

/* NOTE: REPLACE WITH PROPER PACKING */
			memcpy(&rbuf[outsz], &line, sizeof(line));

			outsz += raster_line_sz;
			outsz += cell_to_rcell(tui, &tui->front[
				line.start_line * tui->cols + line.offset], &out[outsz], 0);
		}

/* send the new cursor */
		hdr.lines++;
		hdr.cells++;

		size_t x = tui->cx, y = tui->cy;
		if (tui->hooks.cursor_lookup)
			tui->hooks.cursor_lookup(tui, &x, &y);

		tui->last_cursor.row = y;
		tui->last_cursor.col = x;

		line.start_line = tui->last_cursor.row;
		line.offset = tui->last_cursor.col;

/* NOTE: REPLACE WITH PROPER PACKING */
		memcpy(&rbuf[outsz], &line, sizeof(line));
		outsz += raster_line_sz;
		outsz += cell_to_rcell(tui, &tui->front[
			line.start_line * tui->cols + line.offset], &out[outsz], 1);

/* figure out what shape we want it in, style, blink rate etc. are
 * all controlled 'raster' side. */
		if (tui->cursor_off || tui->cursor_hard_off || tui->sbofs){
			hdr.cursor_state = CURSOR_NONE;
		}
		else {
			hdr.cursor_state = tui->defocus ? CURSOR_INACTIVE : CURSOR_ACTIVE;
		}

		tui->last_cursor.active = true;
	}

	hdr.data_sz = hdr.lines * raster_line_sz +
		hdr.cells * raster_cell_sz + raster_hdr_sz + 3;

	hdr.cursor_state |= CURSOR_EXTHDRv1;

	if (!tui->cursor)
		hdr.cursor_state |= CURSOR_BLOCK;
	else
		hdr.cursor_state |=
			(tui->cursor & (CURSOR_BLOCK | CURSOR_BAR | CURSOR_UNDER | CURSOR_HOLLOW));

/* write the header and return */
/* NOTE: REPLACE WITH PROPER PACKING */
	memcpy(rbuf, &hdr, sizeof(hdr));
	if (tui->cursor_color_override){
		rbuf[sizeof(hdr)+0] = tui->cursor_color[0];
		rbuf[sizeof(hdr)+1] = tui->cursor_color[1];
		rbuf[sizeof(hdr)+2] = tui->cursor_color[2];
	}
	else {
		rbuf[sizeof(hdr)+0] = tui->colors[TUI_COL_CURSOR].rgb[0];
		rbuf[sizeof(hdr)+1] = tui->colors[TUI_COL_CURSOR].rgb[1];
		rbuf[sizeof(hdr)+2] = tui->colors[TUI_COL_CURSOR].rgb[2];
	}

	return outsz;
}

void tui_screen_resized(struct tui_context* tui)
{
	int cols = tui->acon.w / tui->cell_w;
	int rows = tui->acon.h / tui->cell_h;

	LOG("update screensize (%d * %d), (%d * %d)\n",
		rows, cols, (int)tui->acon.w, (int)tui->acon.h);

/* calculate the rpad/bpad regions based on the desired output size and the
 * amount consumed by the aligned number of cells, this should ideally be zero */
	tui->pad_w = tui->acon.w - (cols * tui->cell_w);
	tui->pad_h = tui->acon.h - (rows * tui->cell_h);

/* if the number of cells has actually changed, we need to propagate */
	if (cols != tui->cols || rows != tui->rows){
		if (tui->handlers.resize)
			tui->handlers.resize(tui,
				tui->acon.w, tui->acon.h, cols, rows, tui->handlers.tag);

		tui->cols = cols;
		tui->rows = rows;

		resize_cellbuffer(tui);

		if (tui->hooks.resize){
			tui->hooks.resize(tui);
		}

		if (tui->handlers.resized)
			tui->handlers.resized(tui,
				tui->acon.w, tui->acon.h, cols, rows, tui->handlers.tag);
	}

	tui->dirty |= DIRTY_FULL;
}

int tui_tpack_unpack(struct tui_context* C,
	uint8_t* buf, size_t buf_sz, size_t x, size_t y, size_t x2, size_t y2)
{
	struct tui_raster_header hdr;
	if (!buf_sz || buf_sz < sizeof(struct tui_raster_header))
		return -1;

/* just verbatim the same as raster_tobuf, but unpacks cell into C instead */
	memcpy(&hdr, buf, sizeof(struct tui_raster_header));

/* recalculate and compare */
	size_t hdr_ver_sz = hdr.lines * raster_line_sz +
		hdr.cells * raster_cell_sz + raster_hdr_sz;

	if (hdr.cursor_state & CURSOR_EXTHDRv1)
		hdr_ver_sz += 3;

	if (hdr.data_sz > buf_sz || hdr.data_sz != hdr_ver_sz){
		return -1;
	}

	buf_sz -= sizeof(struct tui_raster_header);
	buf += sizeof(struct tui_raster_header);

/* if it is not a delta frame, just clear region to bgcolor first and
 * make sure the window size match (unless w, h are set) */
	if (!(hdr.flags & RPACK_DFRAME)){
		if ( (!x2 || !y2) && (C->rows != hdr.lines || C->cols != hdr.cells)){
			size_t px_w = C->cell_w * hdr.cells;
			size_t px_h = C->cell_h * hdr.lines;
			x2 = hdr.cells;
			y2 = hdr.lines;

/* this is done on the 'shmif' level in order to behave as if the DISPLAYHINT
 * event was received, including event propagation to resize-resized etc. */
			bool resized = false;
			if (!C->acon.addr){
				C->acon.w = px_w;
				C->acon.h = px_h;
				tui_screen_resized(C);
				resized = true;
			}
			else
				resized = arcan_shmif_resize_ext(&C->acon, px_w, px_h,
				(struct shmif_resize_ext){
					.vbuf_cnt = -1,
					.abuf_cnt = -1,
					.rows = hdr.lines,
					.cols = hdr.cells
				});

			if (resized)
				tui_screen_resized(C);
		}

		struct tui_screen_attr empty = arcan_tui_defcattr(C, TUI_COL_BG);
		arcan_tui_eraseattr_region(C, x, y, x2, y2, false, empty);
	}

	if (!x2 || (x2 > C->cols))
		x2 = C->cols;

	if (!y2 || (y2 > C->rows))
		y2 = C->rows;

	for (size_t i = 0; i < hdr.lines; i++){
		if (buf_sz < sizeof(struct tui_raster_line))
			return -1;

/* read / unpack line metadata */
		struct tui_raster_line line;

		memcpy(&line, buf, sizeof(struct tui_raster_line));
		buf += sizeof(line);

		for (size_t i = line.offset; line.ncells && buf_sz >= raster_cell_sz; i++){
			line.ncells--;

/* extract each cell */
			struct tui_cell cell = rcell_to_cell(buf);
			buf += raster_cell_sz;
			buf_sz -= raster_cell_sz;

/* just write cell into C if it is within the clipping region */
			if (line.start_line < y2 && i < x2)
				C->front[line.start_line * C->cols + i] = cell;
		}
	}

	C->dirty = DIRTY_FULL;
	return 1;
}

int tui_screen_refresh(struct tui_context* tui)
{
	if (tui->hooks.refresh){
		tui->hooks.refresh(tui);
	}

	if (arcan_shmif_signalstatus(&tui->acon) != 0){
		errno = EAGAIN;
		return -1;
	}

	size_t rv = tui_screen_tpack(tui,
		(struct tpack_gen_opts){.synch = true}, tui->acon.vidb, tui->acon.vbufsize);
	tui->dirty = DIRTY_NONE;

	if (!rv)
		return 0;

/* Every frame gets synched in a mixed with a CSV
 * [screen_id;anch_x;anch_y;cols;rows;bytes;timestamp_ms]\n[n_bytes]
 *
 * To handle multiple screens, we work from the perspective of the child, go to
 * the parent, figure out our offset in its list of children and use that with
 * the last anchor hint.
 *
 * Embedded foreign windows won't be recorded in this way, hidden windows
 * are marked as such through the invalid dimensions and no contents.
 *
 * In order for playback to be timing-accurate we would need information about
 * when the window was actually mapped and try to account for delays introduced
 * by the display server taking more time processing the request for a new
 * window during playback. In reality it may make more sense to simply compose
 * subwindows for most playback scenarios, even though they won't match 100%.
 */
	if (tui->tpack_recdst){
		int sid = 0, anchor_x = 0, anchor_y = 0;
		size_t rows = tui->rows, cols = tui->cols;

		if (tui->parent){
			sid = -1;
			for (size_t i = 0; i < 256; i++)
				if (tui->parent->children[i] == tui){
					sid = i;
					anchor_x = tui->last_constraints.anch_col;
					anchor_y = tui->last_constraints.anch_row;
					break;
				}
		}

		if (-1 != sid){
			fprintf(
				tui->tpack_recdst,
				"%d;%d;%d;%d;%d;%zu;%zu\n",
				sid, anchor_x, anchor_y,
				tui->cols, tui->rows, rv, (size_t)arcan_timemillis()
			);
			fwrite(tui->acon.vidb, rv, 1, tui->tpack_recdst);
		}
	}

	arcan_shmif_signal(&tui->acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);

/* last offset feedback buffer can be read here for kernel offset / lookup, or
 * the translation should be made server side - it is somewhat up for grabs */

/* flush here when there is a stalled window anyhow */
	if (tui->tpack_recdst){
		fflush(tui->tpack_recdst);
	}
	return 0;
}
