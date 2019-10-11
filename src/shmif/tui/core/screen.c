#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"
#include "../screen/libtsm.h"
#include <pthread.h>
#include <assert.h>

typedef void* TTF_Font;
#include "../raster/raster.h"
#include "../raster/draw.h"

/*
 * This is used to translate from the virtual screen in TSM to our own front/back
 * buffer structure that is then 'rendered' into the packing format used in
 * tui_raster.c
 *
 * Eventually this will be entirely unnecessary and we can rightfully kill off
 * TSM and ust draw into our buffers directly, as the line wrapping / tracking
 * behavior etc. doesn't really match how things are structured anymore
 */
static int tsm_draw_callback(struct tsm_screen* screen, uint32_t id,
	const uint32_t* ch, size_t len, unsigned width, unsigned x, unsigned y,
	const struct tui_screen_attr* attr, tsm_age_t age, void* data)
{
	struct tui_context* tui = data;

	if (!(age && tui->age && age <= tui->age) && x < tui->cols && y < tui->rows){
		size_t pos = y * tui->cols + x;
		tui->front[pos].draw_ch = tui->front[pos].ch = *ch;
		tui->front[pos].attr = *attr;
		tui->front[pos].fstamp = tui->fstamp;
		tui->dirty |= DIRTY_PARTIAL;
	}

	return 0;
}

static void resize_cellbuffer(struct tui_context* tui)
{
	if (tui->base){
		free(tui->base);
		if (!tui->rbuf_fwd)
			free(tui->rbuf);
	}

	tui->base = NULL;

	size_t buffer_sz = 2 * tui->rows * tui->cols * sizeof(struct tui_cell);
	size_t rbuf_sz =
		sizeof(struct tui_raster_header) + /* always there */
		((tui->rows * tui->cols + 2) * raster_cell_sz) + /* worst case, includes cursor */
		((tui->rows+2) * sizeof(struct tui_raster_line))
	;

	if (!tui->rbuf_fwd){
		tui->rbuf = NULL;
		tui->rbuf = malloc(rbuf_sz);
		if (!tui->rbuf){
			LOG("couldn't allocate output text buffer\n");
			return;
		}
	}

	tui->base = malloc(buffer_sz);
	if (!tui->base){
		free(tui->rbuf);
		tui->rbuf = NULL;
		LOG("couldn't allocate screen buffers\n");
		return;
	}

	memset(tui->base, '\0', buffer_sz);
	memset(tui->rbuf, '\0', rbuf_sz);

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

static size_t cell_to_rcell(
struct tui_cell* tcell, uint8_t* outb, uint8_t has_cursor)
{
/* inverse isn't an attribute on the packing level, we simply modify the colors
 * as the 'inverse' attribute is a left-over from the terminal emulation days */
	if (tcell->attr.inverse){
/* use the tactic of picking 'new foreground / background' based on the
 * intensity of the current-cell colours rather than say, fg <=> bg */
		float intens =
			(0.299f * tcell->attr.fc[0] +
			 0.587f * tcell->attr.fc[1] +
			 0.114f * tcell->attr.fc[2]) / 255.0f;

		if (intens < 0.5f){
			*outb++ = 0xff; *outb++ = 0xff; *outb++ = 0xff;
		}
		else {
			*outb++ = 0x00; *outb++ = 0x00; *outb++ = 0x00;
		}
		*outb++ = tcell->attr.fc[0];
		*outb++ = tcell->attr.fc[1];
		*outb++ = tcell->attr.fc[2];
	}
	else {
		*outb++ = tcell->attr.fc[0];
		*outb++ = tcell->attr.fc[1];
		*outb++ = tcell->attr.fc[2];
		*outb++ = tcell->attr.bc[0];
		*outb++ = tcell->attr.bc[1];
		*outb++ = tcell->attr.bc[2];
	}

/* this deviates from the tui cell here, the terminal- legacy blink and
 * protect bits are not kept, and the 2 MSBs are reserved for the time being */
	*outb++ = (
		tcell->attr.bold << 0 |
		tcell->attr.underline << 1 |
		tcell->attr.italic << 2 |
		tcell->attr.strikethrough << 3 |
		tcell->attr.shape_break << 4 |
		has_cursor << 5
	);

/* the reserved font-control byte kept zero for the time being */
	*outb++ = 0x00;
	pack_u32(tcell->ch, outb);
	return raster_cell_sz;
}

static int build_raster_buffer(
	struct tui_context* tui, uint8_t** rbuf, size_t* rbuf_sz)
{
/* start with header */
	int rv = 0;
	if (tui->dirty == DIRTY_NONE)
		return rv;

/* header gets written to the buffer last */
	struct tui_raster_header hdr = {};
	arcan_tui_get_color(tui, TUI_COL_BG, hdr.bgc);
	hdr.bgc[3] = tui->alpha;

	uint8_t* out = tui->rbuf;
	size_t outsz = sizeof(hdr);

/* this is set on a manual invalidate, or a screen or cell resize */
	if (tui->dirty & DIRTY_FULL){
		struct tui_cell* front = tui->front;
		struct tui_cell* back = tui->back;

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
				*back = *front;
				outsz += cell_to_rcell(front, &out[outsz], 0);
				back++;
				front++;
			}
		}
		rv = 2;
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
				tui->back[row_base + ofs] = *attr;
				line.ncells++;
				outsz += cell_to_rcell(attr, &out[outsz], 0);
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
			assert(outsz == raster_hdr_sz + raster_line_sz * hdr.lines + raster_cell_sz * hdr.cells);
		}

		hdr.flags |= RPACK_DFRAME;
		rv = 1;
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
			rv = 1;
		}

/* restore the last cursor position */
		if (tui->last_cursor.active){
			hdr.lines++;
			hdr.cells++;
			line.start_line = tui->last_cursor.row;
			line.offset = tui->last_cursor.col;

/* NOTE: REPLACE WITH PROPER PACKING */
			memcpy(&tui->rbuf[outsz], &line, sizeof(line));

			outsz += raster_line_sz;
			outsz += cell_to_rcell(&tui->front[
				line.start_line * tui->cols + line.offset], &out[outsz], 0);
		}

/* send the new cursor */
		hdr.lines++;
		hdr.cells++;
		tui->last_cursor.row = tsm_screen_get_cursor_y(tui->screen);
		tui->last_cursor.col = tsm_screen_get_cursor_x(tui->screen);
		line.start_line = tui->last_cursor.row;
		line.offset = tui->last_cursor.col;

/* NOTE: REPLACE WITH PROPER PACKING */
		memcpy(&tui->rbuf[outsz], &line, sizeof(line));
		outsz += raster_line_sz;
		outsz += cell_to_rcell(&tui->front[
			line.start_line * tui->cols + line.offset], &out[outsz], 1);

/* figure out what shape we want it in, style, blink rate etc. are
 * all controlled 'raster' side. */
		if (tui->cursor_off || tui->cursor_hard_off || tui->sbofs){
			hdr.cursor_state = CURSOR_NONE;
		}
		else {
			hdr.cursor_state = tui->defocus ? CURSOR_INACTIVE : CURSOR_ACTIVE;
		}

		assert(outsz == raster_hdr_sz + raster_line_sz * hdr.lines + raster_cell_sz * hdr.cells);
		tui->last_cursor.active = true;
	}

	hdr.data_sz = hdr.lines * raster_line_sz +
		hdr.cells * raster_cell_sz + raster_hdr_sz;

/* write the header and return */
/* NOTE: REPLACE WITH PROPER PACKING */
	memcpy(tui->rbuf, &hdr, sizeof(hdr));
	*rbuf_sz = outsz;
	*rbuf = tui->rbuf;
	return rv;
}

static void update_screen(struct tui_context* tui, bool ign_inact)
{
/* don't redraw while we have an update pending or when we
 * are in an invisible state */
	if (tui->inactive && !ign_inact)
		return;

/* dirty will be set from screen resize, fix the pad region */
	if (tui->dirty & DIRTY_FULL){
		tsm_screen_selection_reset(tui->screen);
	}
	else
/* "always" erase previous cursor, except when cfg->nal screen state explicitly
 * say that cursor drawing should be turned off */
		;

	/* basic safe-guard */
	if (!tui->front)
		return;
}

void tui_screen_resized(struct tui_context* tui)
{
	int cols = tui->acon.w / tui->cell_w;
	int rows = tui->acon.h / tui->cell_h;
	LOG("update screensize (%d * %d), (%d * %d)\n",
		cols, rows, (int)tui->acon.w, (int)tui->acon.h);

/* calculate the rpad/bpad regions based on the desired output size and
 * the amount consumed by the aligned number of cells */
	tui->pad_w = tui->acon.w - (cols * tui->cell_w);
	tui->pad_h = tui->acon.h - (rows * tui->cell_h);

	if (tui->rbuf_fwd){
		tui->rbuf = tui->acon.vidb;
	}

/* if the number of cells has actually changed, we need to propagate */
	if (cols != tui->cols || rows != tui->rows){
		tui->cols = cols;
		tui->rows = rows;

		if (tui->handlers.resize)
			tui->handlers.resize(tui,
			tui->acon.w, tui->acon.h, cols, rows, tui->handlers.tag);

		tsm_screen_resize(tui->screen, cols, rows);
		resize_cellbuffer(tui);

		if (tui->handlers.resized)
			tui->handlers.resized(tui,
				tui->acon.w, tui->acon.h, cols, rows, tui->handlers.tag);
	}

	if (!tui->rbuf_fwd){
/* fill the padding areas if there are any, this is an intermediate step that
 * can be dropped when shmif supports the tui packing format, then we just swap
 * out rbuf with vidb */
		uint8_t col[3];
		arcan_tui_get_color(tui, TUI_COL_BG, col);
		shmif_pixel bg = SHMIF_RGBA(col[0], col[1], col[2], tui->alpha);
		draw_box_px(tui->acon.vidp, tui->acon.pitch,
			tui->acon.w, tui->acon.h, 0, 0, tui->acon.w, tui->acon.h, bg);
	}

	tui->dirty |= DIRTY_FULL;
	update_screen(tui, true);
}

int tui_screen_refresh(struct tui_context* tui)
{
/* synch vscreen -> screen buffer */
	tui->flags = tsm_screen_get_flags(tui->screen);

/* quick hack until we rewrite the renderer, release the context for other
 * threads to modify as it is only the shmif cont state that is blocking */
	if (tui->vsynch)
		pthread_mutex_lock(tui->vsynch);

/* this will repeatedly call tsm_draw_callback which, in turn, will update
 * the front buffer with new glyphs. */
	tui->age = tsm_screen_draw(tui->screen, tsm_draw_callback, tui);

	uint8_t* rbuf;
	size_t rbuf_sz;
	int rv = build_raster_buffer(tui, &rbuf, &rbuf_sz);
	tui->dirty = DIRTY_NONE;

/* Release the update lock so other threads may continue to update /
 * process while we are busy forwarding and synching. */
	if (tui->vsynch)
		pthread_mutex_unlock(tui->vsynch);

/* if we raster locally or server- side is determined by the rbuf_fwd flag */
	if (rv){
		if (!tui->rbuf_fwd){
			if (1 != tui_raster_render(tui->raster, &tui->acon, rbuf, rbuf_sz))
				return 0;
		}

		arcan_shmif_signal(&tui->acon, SHMIF_SIGVID);
	}

	return 0;
}
