/*
 * This is replicated in engine/renderfun.c as part of a staged refactor,
 * eventually when we switch rasterization off in TUI entirely - we still
 * need some font management to determine if a glyph exists or not without
 * enforcing a round-trip, same for substitutions.
 *
 * The plan is to have a simplified format of just a list of glyph-IDs
 * and for substitution tables.
 */
#include <math.h>

struct agp_vstore;
#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "arcan_ttf.h"
#include "../tui_int.h"
#include "pixelfont.h"
#include "raster.h"

static bool tryload_truetype(struct tui_context* tui,
	int fd, int mode, size_t pt_size, float dpi)
{
	int slot = mode == 0 ? 0 : 1;

/* first make sure we can load */
	TTF_Font* font = TTF_OpenFontFD(fd, pt_size, dpi, dpi);
	if (!font)
		return false;

	LOG("open_font(%zu pt, %f dpi)\n", pt_size, dpi);

/* free pre-existing font / cache */
	if (tui->font[slot]->vector){
		TTF_CloseFont(tui->font[slot]->truetype);
	}
	else if (tui->font[slot]->bitmap){
		tui_pixelfont_close(tui->font[slot]->bitmap);
	}

	tui->font[slot]->truetype = font;
	tui->font[slot]->fd = fd;
	tui->font[slot]->vector = true;
	TTF_SetFontStyle(font, TTF_STYLE_NORMAL);
	TTF_SetFontHinting(font, tui->hint);

/* the first slot determines cell size */
	if (mode == 0){
		size_t dw = 0, dh = 0;
		TTF_ProbeFont(tui->font[0]->truetype, &dw, &dh);
		if (dw && dh && !tui->cell_auth){
			tui->cell_w = dw;
			tui->cell_h = dh;
		}
		LOG("open_font::probe(%zu, %zu)\n", dw, dh);
/* optimization here is that in tui cell mode, we only really need the
 * font to determine the presence of a glyph, so maybe there are caches
 * to flush in ttf renderer */
	}

	return true;
}

/*
 * Treat the descriptor (fd) as a pixel font that is added for the pixel
 * size slot [px_sz] acting as primary or supplementary set of glyphs [mode > 0]
 */
static bool tryload_bitmap(struct tui_context* tui, int fd, int mode, size_t px_sz)
{
	int work = dup(fd);
	bool rv = false;

	if (-1 == work)
		return false;

/* just read all of it */
	FILE* fpek = fdopen(work, "r");
	if (!fpek)
		return false;

	fseek(fpek, 0, SEEK_END);
	size_t buf_sz = ftell(fpek);
	fseek(fpek, 0, SEEK_SET);

	uint8_t* buf = malloc(buf_sz);
	if (!buf)
		goto out;

/* not bitmap? return so we can try freetype */
	if (1 != fread(buf, buf_sz, 1, fpek))
		goto out;
	fseek(fpek, 0, SEEK_SET);

	if (!tui_pixelfont_valid(buf, buf_sz))
		goto out;

/* loading a bitmap, flush any existing vector fonts */
	if (tui->font[0]->vector){
		if (tui->font[0]->truetype)
			TTF_CloseFont(tui->font[0]->truetype);
		tui->font[0]->vector = false;
		tui->font[0]->bitmap = tui_pixelfont_open(64);
		if (!tui->font[0]->bitmap)
			goto out;
	}

/* slot 1 isn't used on bitmap as we support merging directly */
	if (tui->font[1] && tui->font[1]->vector){
		tui->font[1]->vector = false;
		if (tui->font[1]->truetype)
			TTF_CloseFont(tui->font[1]->truetype);
		tui->font[1]->vector = false;
		tui->font[1]->bitmap = NULL;
	}

	rv = tui_pixelfont_load(tui->font[0]->bitmap, buf, buf_sz, px_sz, mode == 1);

out:
	free(buf);
	fclose(fpek);
	return rv;
}

/*
 * modes supported now is 0 (default), 1 (append)
 * font size specified in mm, will be converted to 1/72 inch pt as per
 * the current displayhint density in pixels-per-centimeter.
 */
static bool setup_font(
	struct tui_context* tui, int fd, float font_sz, int mode)
{
	if (!(font_sz > 0))
		font_sz = tui->font_sz;
	tui->font_sz = font_sz;

/* bitmap font need the nearest size in px, with ttf we convert to pt */
	size_t pt_size = roundf((float)font_sz * 2.8346456693f);
	size_t px_sz = ceilf((float)pt_size * 0.03527778 * tui->ppcm);

/* clamp or we'll drop into inf/invisible */
	if (pt_size < 4)
		pt_size = 4;

/* clamp font mode to 1 (alt) or 0 (primary), try and load if provided */
	int modeind = mode >= 1 ? 1 : 0;
	bool bitmap = false;

/* if a descriptor and slot is provided, we will try and open / append */
	if (fd != BADFD){
		if (tryload_bitmap(tui, fd, modeind, px_sz)){
			size_t w, h;
			tui_pixelfont_setsz(tui->font[0]->bitmap, px_sz, &w, &h);
			tui->cell_w = w;
			tui->cell_h = h;
		}
/* and if not, go with freetype */
		else {
			if (tryload_truetype(tui, fd, mode, pt_size, tui->ppcm * 2.54f)){

			}
		}
	}

/* otherwise we just switch the size on whatever is the current default */
	else {
		if (tui->font[0]->vector){
			tryload_truetype(tui, tui->font[0]->fd, 0, pt_size, tui->ppcm * 2.54f);
		}
		else {
			size_t w = 0, h = 0;
			tui->font[0]->bitmap = tui_pixelfont_open(64);
			tui_pixelfont_setsz(tui->font[0]->bitmap, px_sz, &w, &h);
			tui->cell_w = w;
			tui->cell_h = h;
		}
	}

	return true;
}

bool tui_fontmgmt_hasglyph(struct tui_context* c, uint32_t cp)
{
	if (!c->font[0])
		return false;

	if (c->font[0]->vector){
		TTF_Font* ary[2] = {c->font[0]->truetype, NULL};
		size_t count = 1;

		if (c->font[1]->truetype){
			ary[1] = c->font[1]->truetype;
			count++;
		}
		return TTF_FindGlyph(ary, count, cp, 0, false);
	}

	return c->font[0]->bitmap ?
		tui_pixelfont_hascp(c->font[0]->bitmap, cp) :
		true;
}

/*
 * font-related code that needs to be run on the client side
 */
void tui_fontmgmt_fonthint(struct tui_context* tui, struct arcan_tgtevent* ev)
{
	int fd = BADFD;
	if (ev->ioevs[0].iv != BADFD)
		fd = arcan_shmif_dupfd(ev->ioevs[0].iv, -1, true);

	switch(ev->ioevs[3].iv){
	case -1: break;
/* happen to match TTF_HINTING values, though LED layout could be
 * modified through DISPLAYHINT but in practice, not so much. */
	default:
		tui->hint = ev->ioevs[3].iv;
	break;
	}

/* unit conversion again, we get the size in cm, truetype wrapper takes pt,
 * (at 0.03527778 cm/pt), then update_font will take ppcm into account */
	setup_font(tui, fd, ev->ioevs[2].fv > 0 ? ev->ioevs[2].fv : 0, ev->ioevs[4].iv);
	tui->dirty = DIRTY_FULL;
	tui_raster_cell_size(tui->raster, tui->cell_w, tui->cell_h);
	tui_screen_resized(tui);
}

void tui_fontmgmt_invalidate(struct tui_context* tui)
{
	setup_font(tui, BADFD, tui->font_sz, 0);
	tui_raster_cell_size(tui->raster, tui->cell_w, tui->cell_h);
	tui_screen_resized(tui);
	tui->dirty = DIRTY_FULL;
}

void tui_fontmgmt_inherit(struct tui_context* tui, struct tui_context* parent)
{
}

void tui_fontmgmt_setup(
	struct tui_context* tui, struct arcan_shmif_initial* init)
{
/* we track the allocation here in order to not have to pull in TTF_Font, ...
 * in all of the translation units, keeping tui_font opaque in tui_init, it's
 * part of the refactoring bits in that fontmgmt itself can be removed when
 * server-side */
	size_t font_sz = sizeof(struct tui_font) * 2;
	struct tui_font* fonts = malloc(font_sz);
	if (!fonts)
		return;

	memset(fonts, '\0', font_sz);
	tui->font[0] = &fonts[0];
	tui->font[1] = &fonts[1];
	tui->hint = TTF_HINTING_NORMAL;

	if (init){
		setup_font(tui, init->fonts[0].fd, init->fonts[0].size_mm, 0);
		init->fonts[0].fd = -1;

		if (init->fonts[1].fd != -1){
			setup_font(tui, init->fonts[1].fd, init->fonts[0].size_mm, 1);
			init->fonts[1].fd = -1;
		}
	}
	else {
		setup_font(tui, -1, 3.527780, 0);
	}

	tui->raster = tui_raster_setup(tui->cell_w, tui->cell_h);
	tui_raster_setfont(tui->raster, tui->font, 2);
}
