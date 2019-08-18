struct agp_vstore;
#include <inttypes.h>
#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#define SHMIF_TTF
#include "arcan_ttf.h"
#include "../tui_int.h"
#include "draw.h"
#include "raster.h"
#include "pixelfont.h"

struct cell {
	shmif_pixel fc;
	shmif_pixel bc;
	uint32_t ucs4;
	uint8_t attr;
};

struct tui_raster_context {
	struct tui_font* fonts[4];
	int last_style;
	int cursor_state;

	shmif_pixel cc;

	size_t cell_w;
	size_t cell_h;

	size_t min_x, min_y;
	size_t max_x, max_y;
};

void tui_raster_setfont(
	struct tui_raster_context* ctx, struct tui_font** src, size_t n_fonts)
{
	for (size_t i = 0; i < 4; i++)
		ctx->fonts[i] = i < n_fonts ? src[i] : NULL;
	ctx->last_style = -1;
}

struct tui_raster_context* tui_raster_setup(size_t cell_w, size_t cell_h)
{
	struct tui_raster_context* res = malloc(sizeof(struct tui_raster_context));
	if (!res)
		return NULL;

	*res = (struct tui_raster_context){
		.cell_w = cell_w,
		.cell_h = cell_h,
		.cc = SHMIF_RGBA(0x00, 0xaa, 0x00, 0xff),
		.last_style = -1
	};

	return res;
}

void tui_raster_cell_size(struct tui_raster_context* ctx, size_t w, size_t h)
{
	ctx->cell_w = w;
	ctx->cell_h = h;
}

void unpack_u32(uint32_t* dst, uint8_t* inbuf)
{
	*dst =
		((uint64_t)inbuf[0] <<  0) |
		((uint64_t)inbuf[1] <<  8) |
		((uint64_t)inbuf[2] << 16) |
		((uint64_t)inbuf[3] << 24);
}

static void unpack_cell(uint8_t unpack[static 12], struct cell* dst, uint8_t alpha)
{
	dst->fc = SHMIF_RGBA(unpack[0], unpack[1], unpack[2], 0xff);
	dst->bc = SHMIF_RGBA(unpack[3], unpack[4], unpack[5], alpha);
	dst->attr = unpack[6];
	unpack_u32(&dst->ucs4, &unpack[8]);
}

static void linehint(struct tui_raster_context* ctx, struct cell* cell,
	shmif_pixel* vidp, size_t pitch, int x, int y, size_t maxx, size_t maxy,
	bool strikethrough, bool underline)
{
	if (underline){
		int n_lines = (int)(ctx->cell_h * 0.05) | 1;
		draw_box_px(vidp, pitch, maxx, maxy,
			x, y + ctx->cell_h - n_lines, ctx->cell_w, n_lines, cell->fc);
	}

	if (strikethrough){
		int n_lines = (int)(ctx->cell_h * 0.05) | 1;
		draw_box_px(vidp, pitch, maxx, maxy,
			x, y + (ctx->cell_h >> 1) - (n_lines >> 1),
			ctx->cell_w, n_lines, cell->fc);
	}
}

static size_t drawglyph(struct tui_raster_context* ctx, struct cell* cell,
	shmif_pixel* vidp, size_t pitch, int x, int y, size_t maxx, size_t maxy,
	bool delta)
{
/* draw glyph based on font state */
	if (!ctx->fonts[0]->vector){

/* mouse-cursor drawing in this mode is a bit primitive */
		if (cell->attr & (1 << CATTR_CURSOR)){
			if (ctx->cursor_state == CURSOR_ACTIVE){
				cell->bc = ctx->cc;
			}
		}

/* linear search for cp, on fail, fill with background */
		tui_pixelfont_draw(ctx->fonts[0]->bitmap,
			vidp, pitch, cell->ucs4, x, y, cell->fc, cell->bc, maxx, maxy, false);

/* add line-marks */
		if (cell->ucs4 &&
			cell->attr & ((1 << CATTR_STRIKETHROUGH) | (1 << CATTR_UNDERLINE)))
			linehint(ctx, cell, vidp, pitch, x, y, maxx, maxy,
				cell->attr & (1 << CATTR_STRIKETHROUGH),
				cell->attr & (1 << CATTR_UNDERLINE)
			);

		return ctx->cell_w;
	}

/* vector font drawing */
	size_t nfonts = 1;
	TTF_Font* fonts[2] = {ctx->fonts[0]->truetype, NULL};
	if (ctx->fonts[1]->vector && ctx->fonts[1]->truetype){
		nfonts = 2;
		fonts[1] = ctx->fonts[1]->truetype;
	}

/* Clear to bg-color as the glyph drawing with background won't pad,
 * except if it is the cursor color, then use that. We can't do the
 * fg/bg swap as even in unshaped the glyph might be conditionally
 * smaller than the cell size */
	shmif_pixel bc = cell->bc;
	if ((cell->attr & (1 << CATTR_CURSOR)) && ctx->cursor_state == CURSOR_ACTIVE)
		bc = ctx->cc;

	draw_box_px(vidp,
		pitch, maxx, maxy, x, y, ctx->cell_w, ctx->cell_h, bc);

/* fast-path, just clear to background */
	if (!cell->ucs4){
		return ctx->cell_w;
	}

	int prem = TTF_STYLE_NORMAL;
	prem |= TTF_STYLE_ITALIC * !!(cell->attr & (1 << CATTR_ITALIC));
	prem |= TTF_STYLE_BOLD * !!(cell->attr & (1 << CATTR_BOLD));

/* seriously expensive so only perform if we actually need to as it can cause a
 * glyph cache flush (bold / italic / ...), other option would be to run
 * separate glyph caches on the different style options.. */
	if (prem != ctx->last_style){
		ctx->last_style = prem;
		TTF_SetFontStyle(fonts[0], prem);
		if (fonts[1])
			TTF_SetFontStyle(fonts[1], prem);
	}

	uint8_t fg[4], bg[4];
	SHMIF_RGBA_DECOMP(cell->fc, &fg[0], &fg[1], &fg[2], &fg[3]);
	SHMIF_RGBA_DECOMP(bc, &bg[0], &bg[1], &bg[2], &bg[3]);

	/* these are mainly used as state machine for kernel / shaping,
	 * we need the 'x-start' position from the previous glyph and commit
	 * that to the line-offset table for coordinate translation */
	int adv = 0;
	unsigned xs = 0;
	unsigned ind = 0;
	TTF_RenderUNICODEglyph(&vidp[y * pitch + x],
		ctx->cell_w, ctx->cell_h, pitch, fonts, nfonts, cell->ucs4, &xs,
		fg, bg, true, true, ctx->last_style, &adv, &ind
	);

/* add line-marks, this actually does not belong here, it should be part
 * of the style marker to the TTF_RenderUNICODEglyph - the code should be
 * added as part of arcan_ttf.c */
	if (cell->ucs4 &&
		cell->attr & ((1 << CATTR_STRIKETHROUGH) | (1 << CATTR_UNDERLINE)))
		linehint(ctx, cell, vidp, pitch, x, y, maxx, maxy,
			cell->attr & (1 << CATTR_STRIKETHROUGH),
			cell->attr & (1 << CATTR_UNDERLINE)
		);

	return ctx->cell_w;
}

int tui_raster_render(struct tui_raster_context* ctx,
	struct arcan_shmif_cont* dst, uint8_t* buf, size_t buf_sz, bool update)
{
	if (!ctx || !dst || !ctx->fonts[0])
		return -1;

	struct tui_raster_header hdr;
	if (!buf_sz || buf_sz < sizeof(struct tui_raster_header))
		return -1;

	memcpy(&hdr, buf, sizeof(struct tui_raster_header));
	buf_sz -= sizeof(struct tui_raster_header);
	buf += sizeof(struct tui_raster_header);
	shmif_pixel bgc = SHMIF_RGBA(hdr.bgc[0], hdr.bgc[1], hdr.bgc[2], hdr.bgc[3]);

	ctx->cursor_state = hdr.cursor_state;

	ssize_t cur_y = -1;
	size_t last_line = 0;

/* pixel- rasterization over shmif should work with one big BB until we have
 * chain-mode. server-side, the vertex buffer slicing will just stream so not
 * much to care about there */
	if (!update){
		dst->dirty.x1 = 0;
		dst->dirty.y1 = 0;
		dst->dirty.x2 = dst->w;
		dst->dirty.y2 = dst->h;
	}
	else {
		dst->dirty.x1 = dst->w;
		dst->dirty.y1 = dst->h;
		dst->dirty.x2 = 0;
		dst->dirty.y2 = 0;
	}

	for (size_t i = 0; i < hdr.lines && buf_sz; i++){
		if (buf_sz < sizeof(struct tui_raster_line))
			return -1;

/* read / unpack line metadata */
		struct tui_raster_line line;

		memcpy(&line, buf, sizeof(struct tui_raster_line));
		buf += sizeof(line);

/* remember the lower line we were at, these are not always ordered */
		if (line.start_line > last_line)
			last_line = line.start_line;

/* respecting scrolling will need another drawing routine, as we need clipping
 * etc. and multiple lines can be scrolled, and that's better fixed when we
 * have an atlas to work from */

/* skip omitted lines */
		if (cur_y != line.start_line){

/* for full draw we fill in the skipped space with the background color */
			if (!update){
				draw_box(dst, 0,
					cur_y * ctx->cell_h, dst->w,
					ctx->cell_h * (line.start_line - cur_y), bgc
				);
			}
			cur_y = line.start_line;
		}

/* the line- raster routine isn't right, we actually need to unpack each line
 * into a local buffer, make not of actual offsets, and then two-pass with bg
 * first and then blend the glyphs on top of that - otherwise kerning, shapes
 * etc. looks bad. */
		if (cur_y * ctx->cell_h < dst->dirty.y1){
			dst->dirty.y1 = cur_y * ctx->cell_h;
		}

/* Shaping, BiDi, ... missing here now while we get the rest in place */
		size_t draw_x = line.offset * ctx->cell_w;

		if (update && dst->dirty.x1 > draw_x)
			dst->dirty.x1 = draw_x;

		for (size_t i = line.offset; line.ncells && buf_sz >= raster_cell_sz; i++){
			line.ncells--;

/* extract each cell */
			struct cell cell;
			unpack_cell(buf, &cell, hdr.bgc[3]);
			buf += raster_cell_sz;
			buf_sz -= raster_cell_sz;

/* skip bit is set, note that for a shaped line, this means that
 * we need to have an offset- map to advance correctly */
			if (cell.attr & (1 << CATTR_SKIP)){
				draw_x += ctx->cell_w;
				continue;
			}

/* blit or discard if OOB */
			if (draw_x < dst->w - ctx->cell_w){
				draw_x += drawglyph(ctx, &cell, dst->vidp, dst->pitch,
					draw_x, cur_y * ctx->cell_h, dst->w, dst->h, true);
			}
			else
				break;
		}
		if (dst->dirty.x2)
			dst->dirty.x2 = draw_x;

		cur_y++;
	}

	dst->dirty.y2 = (last_line + 1) * ctx->cell_h;

/* sweep through the context struct and blit the glyphs */
	arcan_shmif_signal(dst, SHMIF_SIGVID);
	return 1;
}

bool tui_raster_offset(
	struct tui_raster_context* ctx, size_t px_x, size_t row, size_t* offset)
{
	return false;
}

/*
 * Synch the raster state into the agp_store
 */
#ifdef HAVE_ARCAN_AGP
void tui_raster_renderagp(struct tui_raster_context* ctx,
	struct agp_vstore* dst, uint8_t* buf, size_t buf_sz, bool update)
{
/* Should do this slightly different than the raster- version in order to
 * deal with texture_atlas + vector, where we can just throw the entire
 * sliced thing over the fence - so retain a cell grid server side and
 * just apply the unpack over it and mark as dirty */

	if (!ctx || !dst)
		return;

}
#endif

/*
 * Free any buffers and resources bound to the raster
 */
void tui_raster_free(struct tui_raster_context* ctx)
{
	if (!ctx)
		return;

	free(ctx);
}
