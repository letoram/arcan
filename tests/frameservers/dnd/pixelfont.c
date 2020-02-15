/*
 * Single-header simple raster drawing functions
 */
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdlib.h>
#include <stdio.h>
#include <arcan_shmif.h>

/*
 * builtin- fonts to load on init, see tui_draw_init()
 */
#include "terminus_small.h"
#include "terminus_medium.h"
#include "terminus_large.h"
#include "pixelfont.h"
#include "draw.h"

#include "utf8.c"
#include "uthash.h"

struct glyph_ent {
	uint32_t codepoint;
	uint8_t* data;
	UT_hash_handle hh;
};

struct bitmap_font {
	uint8_t* fontdata;
	size_t chsz, w, h;
	size_t n_glyphs;
	struct glyph_ent glyphs[0];
};

static bool psf2_decode_header(
	const uint8_t* const buf, size_t buf_sz,
	size_t* glyph_count, size_t* glyph_bytes, size_t* w, size_t* h, size_t* ofs)
{
	if (buf_sz < 32)
		return false;

	uint32_t u32[8];
	memcpy(u32, buf, 32);

	if (buf[0] != 0x72 || buf[1] != 0xb5 || buf[2] != 0x4a || buf[3] != 0x86)
		return false;

	if (glyph_count)
		*glyph_count = u32[4];

	if (glyph_bytes)
		*glyph_bytes = u32[5];

	if (ofs)
		*ofs = u32[2];

	if (w)
		*w = u32[7];

	if (h)
		*h = u32[6];

	return true;
}

/*
 * support a subset of PSF(v2), no ranges in the unicode- table
 */
static struct bitmap_font* open_psf2(
	const uint8_t* const buf, size_t buf_sz, struct glyph_ent** ht)
{
	size_t glyph_count, glyph_bytes, w, h, ofs;

	if (!psf2_decode_header(buf, buf_sz, &glyph_count, &glyph_bytes, &w,&h,&ofs))
		return NULL;

	size_t pos = ofs;
	size_t glyphbuf_sz = glyph_count * glyph_bytes;
	size_t unicodecount = buf_sz - pos - glyphbuf_sz;

/* we overallocate as we need to support aliases and it's not many bytes */
	struct bitmap_font* res = malloc(
		sizeof(struct bitmap_font) +
		sizeof(struct glyph_ent) * unicodecount +
		glyphbuf_sz
	);

/* read in the raw font-data */
	res->chsz = glyph_bytes;
	res->w = w;
	res->h = h;
	res->n_glyphs = 0;

	res->fontdata = (uint8_t*) &res->glyphs[unicodecount];
	memcpy(res->fontdata, &buf[pos], glyphbuf_sz);
	pos = ofs + glyphbuf_sz;

/* the rest is UTF-8 sequences, build glyph_ent for these */
	uint32_t state = 0;
	uint32_t codepoint = 0;
	size_t ind = 0;

/* this format is:
 * [implicit, glyph index], UTF-8,
 * [0xfe or 0xff] fe = start sequence, ff = step index
 */
	while (pos < buf_sz && ind < glyph_count){
		if (buf[pos] == 0xff){
			ind++;
		}
		else if(buf[pos] == 0xfe){
			fprintf(stderr, "open_psf2() unicode- ranges not supported\n");
		}
		else if (utf8_decode(&state, &codepoint, buf[pos]) == UTF8_REJECT){
			fprintf(stderr, "open_psf2(), invalid UTF-8 sequence found\n");
			return res;
		}
		else if (state == UTF8_ACCEPT){
			res->glyphs[res->n_glyphs].hh = (struct UT_hash_handle){};
			res->glyphs[res->n_glyphs].codepoint = codepoint;
			res->glyphs[res->n_glyphs].data = &res->fontdata[glyph_bytes*ind];

			struct glyph_ent* repl;
			HASH_REPLACE_INT(*ht, codepoint, &res->glyphs[res->n_glyphs], repl);
			res->n_glyphs++;
			state = 0;
			codepoint = 0;
		}
		pos++;
	}

	return res;
}

/*
 * Fixed size font/glyph container
 */
#define MAX_BITMAP_FONTS 64
struct font_entry {
	size_t sz;
	struct bitmap_font* font;
	bool shared_ht;
	struct glyph_ent* ht;
};

struct tui_pixelfont {
	size_t n_fonts;
	struct font_entry* active_font;
	size_t active_font_px;
	struct font_entry fonts[];
};

bool tui_pixelfont_valid(uint8_t* buf, size_t buf_sz)
{
	return psf2_decode_header(buf, buf_sz, NULL, NULL, NULL, NULL, NULL);
}

/*
 * if there's a match for this size slot, then we share the hash lookup and the
 * new font act as an override for missing glyphs. This means that it is not
 * safe to just free a font (not that we do that anyhow).
 */
bool tui_pixelfont_load(struct tui_pixelfont* ctx,
	uint8_t* buf, size_t buf_sz, size_t px_sz, bool merge)
{
	struct glyph_ent** ht = NULL;

/* don't waste time with a font we can't decode */
	if (!psf2_decode_header(buf, buf_sz, NULL, NULL, NULL, NULL, NULL))
		return false;

/* if not merge, delete all for this size slot */
	if (!merge){
		for (size_t i = 0; i < ctx->n_fonts; i++){
			if (ctx->fonts[i].font && ctx->fonts[i].sz == px_sz){
				if (!ctx->fonts[i].shared_ht)
					HASH_CLEAR(hh, ctx->fonts[i].ht);
				free(ctx->fonts[i].font);
				ctx->fonts[i].font = NULL;
				ctx->fonts[i].sz = 0;
				ctx->fonts[i].shared_ht = false;
			}
		}
	}

/* find slot for font */
	struct font_entry* dst = NULL;
	for (size_t i = 0; i < ctx->n_fonts; i++){
		if (!ctx->fonts[i].font){
			dst = &ctx->fonts[i];
			break;
		}
	}
	if (!dst)
		return false;

/* find out if there's a hash-table to re-use */
	if (merge){
		for (size_t i = 0; i < ctx->n_fonts; i++){
			if (ctx->fonts[i].font && ctx->fonts[i].sz == px_sz){
				dst->shared_ht = true;
				dst->ht = ctx->fonts[i].ht;
				break;
			}
		}
	}

/* load it */
	dst->font = open_psf2(buf, buf_sz, &dst->ht);
	if (!dst->font){
		dst->shared_ht = false;
		dst->ht = NULL;
		return false;
	}
	dst->sz = px_sz;

	return true;
}

static void drop_font_context (struct tui_pixelfont* ctx)
{
	if (!ctx)
		return;

	for (size_t i = 0; i < ctx->n_fonts; i++){
		if (!ctx->fonts[i].font)
			continue;

/* some font slots share hash table with others, don't free those,
 * the real table slot won't be marked as shared */
		if (!ctx->fonts[i].shared_ht)
			HASH_CLEAR(hh, ctx->fonts[i].ht);

		free(ctx->fonts[i].font);
		ctx->fonts[i].font = NULL;
		ctx->fonts[i].sz = 0;
		ctx->fonts[i].shared_ht = false;
	}

	free(ctx);
}

/*
 * pick the nearest font for the requested size slot, set the sizes
 * used in *w and *h.
 */
void tui_pixelfont_setsz(struct tui_pixelfont* ctx, size_t px, size_t* w, size_t* h)
{
	int dist = abs((int)px - (int)ctx->active_font->sz);

/* only search if we aren't at that size already */
	if (ctx->active_font_px != px){
		for (size_t i = 0; i < ctx->n_fonts; i++){
			int nd = abs((int)px-(int)ctx->fonts[i].sz);
			if (ctx->fonts[i].font && nd < dist){
				dist = nd;
				ctx->active_font = &ctx->fonts[i];
			}
		}
	}

	*w = ctx->active_font->font->w;
	*h = ctx->active_font->font->h;
	ctx->active_font_px = px;
}

void tui_pixelfont_close(struct tui_pixelfont* ctx)
{
	for (size_t i = 0; i < ctx->n_fonts; i++){
		if (!ctx->fonts[i].font)
			continue;

		if (!ctx->fonts[i].shared_ht)
			HASH_CLEAR(hh, ctx->fonts[i].ht);

			free(ctx->fonts[i].font);ctx->fonts[i].font = NULL;
			ctx->fonts[i].sz = 0;
			ctx->fonts[i].shared_ht = false;
	}
	free(ctx);
}

struct tui_pixelfont* tui_pixelfont_open(size_t lim)
{
	if (lim < 3)
		return NULL;

	size_t ctx_sz = sizeof(struct font_entry)*lim + sizeof(struct tui_pixelfont);
	struct tui_pixelfont* res = malloc(ctx_sz);
	if (!res)
		return NULL;
	memset(res, '\0', ctx_sz);
	res->n_fonts = lim;

	bool fontstatus = false;
	fontstatus |= tui_pixelfont_load(res,
		Lat15_Terminus32x16_psf, Lat15_Terminus32x16_psf_len, 32, false);

	fontstatus |= tui_pixelfont_load(res,
		Lat15_Terminus22x11_psf, Lat15_Terminus22x11_psf_len, 22, false);

	fontstatus |= tui_pixelfont_load(res,
		Lat15_Terminus12x6_psf, Lat15_Terminus12x6_psf_len, 12, false);

	if (!fontstatus){
		fprintf(stderr, "tui_draw_init(), builtin- fonts broken");
		free(res);
		return NULL;
	}

	res->active_font = &res->fonts[0];
	res->active_font->sz = res->active_font->font->h;

	return res;
}

bool tui_pixelfont_hascp(struct tui_pixelfont* ctx, uint32_t cp)
{
	if (!ctx->active_font)
		return false;

	struct glyph_ent* gent;
	HASH_FIND_INT(ctx->active_font->ht, &cp, gent);
	return gent != NULL;
}

void tui_pixelfont_draw(
	struct tui_pixelfont* ctx, shmif_pixel* c, size_t pitch,
	uint32_t cp, int x, int y, shmif_pixel fg, shmif_pixel bg,
	int maxx, int maxy, bool bgign)
{
	struct font_entry* font = ctx->active_font;
	struct glyph_ent* gent;
	if (font)
		HASH_FIND_INT(font->ht, &cp, gent);

	if (x >= maxx || y >= maxy)
		return;

	if (!font || !gent){
		size_t w = font->font->w;
		size_t h = font->font->h;
		if (w + x >= maxx)
			w = maxx - x;
		if (h + y >= maxy)
			h = maxy - y;
		if (!bgign)
			draw_box_px(c, pitch, maxx, maxy, x, y, w, h, bg);
		return;
	}

/*
 * handle partial- clipping against screen regions
 */
	uint8_t bind = 0;
	int row = 0;
	if (y < 0){
		row -= y;
		uint8_t bpr = font->font->w / 8;
		if (font->font->w % 8 != 0 || bpr == 0)
			bpr++;
		bind += -y * bpr;
		y = 0;
	}

	int colst = 0;
	if (x < 0){
		colst =-1*x;
		x = 0;
	}

	if (font->font->w + x > maxx || font->font->h + y > maxy)
		return;

	for (; row < font->font->h && y < maxy; row++, y++){
		shmif_pixel* pos = &c[y * pitch + x];
		for (int col = colst; col < font->font->w; bind++){
/* padding bits will just be 0 */
			int lx = x;
			for (
				int bit = 7;
				bit >= 0 && col < font->font->w && lx < maxx;
				bit--, col++, lx++)
			{
				if ((1 << bit) & gent->data[bind]){
					pos[col] = fg;
				}
				else if (!bgign){
					pos[col] = bg;
				}
			}
		}
	}
}
