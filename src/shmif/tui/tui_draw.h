/*
 * Single-header simple raster drawing functions
 */

/*
 * builtin- fonts to load on init, see tui_draw_init()
 */
#include "terminus_small.h"
#include "terminus_medium.h"
#include "terminus_large.h"

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

static bool draw_box(struct arcan_shmif_cont* c,
	int x, int y, int w, int h, shmif_pixel col)
{
	if (x >= c->addr->w || y >= c->addr->h)
		return false;

	if (x < 0){
		w += x;
		x = 0;
	}

	if (y < 0){
		h += y;
		y = 0;
	}

	if (w < 0 || h < 0)
		return false;

	int ux = x + w > c->addr->w ? c->addr->w : x + w;
	int uy = y + h > c->addr->h ? c->addr->h : y + h;

	for (int cy = y; cy != uy; cy++)
		for (int cx = x; cx != ux; cx++)
			c->vidp[ cy * c->addr->w + cx ] = col;

	return true;
}

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

struct tui_font_ctx {
	size_t n_fonts;
	struct font_entry* active_font;
	struct font_entry fonts[];
};

/*
 * if there's a match for this size slot, then we share the hash lookup and the
 * new font act as an override for missing glyphs. This means that it is not
 * safe to just free a font (not that we do that anyhow).
 */
static bool load_bitmap_font(struct tui_font_ctx* ctx,
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

static void drop_font_context (struct tui_font_ctx* ctx)
{
	if (!ctx)
		return;

	for (size_t i = 0; i < ctx->n_fonts; i++){
		if (!ctx->fonts[i].font)
			continue;
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
static void switch_bitmap_font(
	struct tui_font_ctx* ctx, size_t px, size_t* w, size_t* h)
{
	int dist = abs((int)px - (int)ctx->active_font->sz);

	for (size_t i = 0; i < ctx->n_fonts; i++){
		int nd = abs((int)px-(int)ctx->fonts[i].sz);
		if (ctx->fonts[i].font && nd < dist){
			dist = nd;
			ctx->active_font = &ctx->fonts[i];
		}
	}

	*w = ctx->active_font->font->w;
	*h = ctx->active_font->font->h;
}

static struct tui_font_ctx* tui_draw_init(size_t lim)
{
	if (lim < 3)
		return NULL;

	size_t ctx_sz = sizeof(struct font_entry)*lim + sizeof(struct tui_font_ctx);
	struct tui_font_ctx* res = malloc(ctx_sz);
	if (!res)
		return NULL;
	memset(res, '\0', ctx_sz);
	res->n_fonts = lim;

	bool fontstatus = false;
	fontstatus |= load_bitmap_font(res,
		Lat15_Terminus32x16_psf, Lat15_Terminus32x16_psf_len, 32, false);

	fontstatus |= load_bitmap_font(res,
		Lat15_Terminus22x11_psf, Lat15_Terminus22x11_psf_len, 22, false);

	fontstatus |= load_bitmap_font(res,
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

static bool has_ch_u32(struct tui_font_ctx* ctx, uint32_t cp)
{
	if (!ctx->active_font)
		return false;

	struct glyph_ent* gent;
	HASH_FIND_INT(ctx->active_font->ht, &cp, gent);
	return gent != NULL;
}

static void draw_ch_u32(struct tui_font_ctx* ctx,
	struct arcan_shmif_cont* c, uint32_t cp,
	int x, int y, shmif_pixel fg, shmif_pixel bg,
	int maxx, int maxy)
{
	struct font_entry* font = ctx->active_font;
	struct glyph_ent* gent;
	if (font)
		HASH_FIND_INT(font->ht, &cp, gent);

	if (x >= maxx || y >= maxy)
		return;

	if (!font || !gent){
		draw_box(c, x, y, font->font->w, font->font->h, bg);
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

	for (; row < font->font->h && y < maxy; row++, y++){
		shmif_pixel* pos = &c->vidp[c->pitch * y + x];
		for (int col = colst; col < font->font->w;){
/* padding bits will just be 0 */
			int lx = x;
			for (int bit = 7; bit >= 0 &&
				col < font->font->w && lx < maxx; bit--, col++, lx++){
				pos[col] = ((1 << bit) & gent->data[bind]) ? fg : bg;
			}
			bind++;
		}
	}
}
