/*
 * Copyright 2008-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <stddef.h>
#include <math.h>
#include <unistd.h>
#include <assert.h>
#include <errno.h>

#ifndef ARCAN_FONT_CACHE_LIMIT
#define ARCAN_FONT_CACHE_LIMIT 8
#endif

#define ARCAN_TTF

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_ttf.h"
#include "arcan_shmif.h"

#define shmif_pixel av_pixel
#define TTF_Font TTF_Font
#define NO_ARCAN_SHMIF
#include "../shmif/tui/raster/pixelfont.h"
#include "../shmif/tui/raster/raster.h"
#undef TTF_Font

#include "arcan_renderfun.h"
#include "arcan_img.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#define STBIR_MALLOC(sz,ctx) arcan_alloc_mem(sz, ARCAN_MEM_VBUFFER, \
	ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE)
#define STBIR_FREE(ptr,ctx) arcan_mem_free(ptr)
#include "external/stb_image_resize.h"

struct font_entry_chain {
	TTF_Font* data[4];
	file_handle fd[4];
	size_t count;
};

struct font_entry {
	struct font_entry_chain chain;
	char* identifier;
	size_t size;
	float vdpi, hdpi;
	uint8_t usecount;
};

struct text_format {
/* font specification */
	struct font_entry* font;
	uint8_t col[4];
	int style;
	uint8_t alpha;

/* used in the fallback case when !font */
	size_t pt_size;
	size_t px_skip;

/* for forced loading of images */
	struct {
		size_t w, h;
		av_pixel* buf;
	} surf;
	img_cons imgcons;

/* temporary pointer-alias into line of text where the format was extracted */
	char* endofs;

/* metrics */
	int lineheight;
	int height;
	int skip;
	int ascent;
	int descent;

/* metric- overrides */
	size_t halign;

/* whitespace management */
	bool cr;
	uint8_t tab;
	uint8_t newline;
};

static int default_hint = TTF_HINTING_NORMAL;
static float default_vdpi = 72.0;
static float default_hdpi = 72.0;

/* for embedded blit */
static int64_t vid_ofs;

#define PT_TO_HPX(PT)((float)(PT) * (1.0f / 72.0f) * default_hdpi)
#define PT_TO_VPX(PT)((float)(PT) * (1.0f / 72.0f) * default_vdpi)

static struct text_format last_style = {
	.col = {0xff, 0xff, 0xff, 0xff},
};

static unsigned int font_cache_size = ARCAN_FONT_CACHE_LIMIT;
static struct tui_font builtin_bitmap;
static struct font_entry font_cache[ARCAN_FONT_CACHE_LIMIT] = {
};

static uint16_t nexthigher(uint16_t k)
{
	k--;
	for (int i=1; i < sizeof(uint16_t) * 8; i = i * 2)
		k = k | k >> i;
	return k+1;
}

/*
 * This one is a mess,
 * (a) begin by splitting the input string into a linked list of data elements.
 * each element can EITHER modfiy the current cursor position OR represent
 * a rendered surface.
 * (b) take the linked list, sweep through it and figure out which dimensions
 * it requires, allocate a corresponding storage object.
 * (c) sweep the list yet again, render to the storage object.
*/

/* TTF_FontHeight sets line-spacing. */

struct rcell {
	unsigned int width;
	unsigned int height;
	int skipv;
	int ascent;
	int descent;

	union {
		struct {
			size_t w, h;
			av_pixel* buf;
		} surf;

		struct {
			uint8_t newline;
			uint8_t tab;
			bool cr;
		} format;
	} data;

	struct rcell* next;
};

void arcan_video_fontdefaults(file_handle* fd, int* pt_sz, int* hint)
{
	if (fd)
		*fd = font_cache[0].chain.fd[0];

	if (pt_sz)
		*pt_sz = font_cache[0].size;

	if (hint)
		*hint = default_hint;
}

void arcan_renderfun_outputdensity(float hppcm, float vppcm)
{
	default_hdpi = vppcm > EPSILON ? 2.54 * vppcm : 72.0;
	default_vdpi = hppcm > EPSILON ? 2.54 * hppcm : 72.0;
}

void arcan_renderfun_vidoffset(int64_t ofs)
{
	vid_ofs = ofs;
}

/* chain functions work like normal, except that they take multiple
 * fonts and select / scale a fallback if a glyph is not found. */
int size_font_chain(
	struct text_format* cstyle, const char* base, int *w, int *h)
{
	if (cstyle->font && cstyle->font->chain.data[0]){
		return TTF_SizeUTF8chain(cstyle->font->chain.data,
			cstyle->font->chain.count, base, w, h, cstyle->style);
	}
	else {
		size_t len = strlen(base);
		*h = cstyle->height;
		*w = cstyle->px_skip * len;
		return 0;
	}
}

static void update_style(struct text_format* dst, struct font_entry* font)
{
/* if the font has not been set, use the built-in bitmap one - go from pt-size
 * over dpi to pixel size to whatever the closest built-in match is */
	if (!font || !font->chain.data[0]){
		size_t h = 0;
		size_t px_sz = PT_TO_HPX(dst->pt_size);
		tui_pixelfont_setsz(builtin_bitmap.bitmap, px_sz, &dst->px_skip, &h);
		dst->descent = dst->ascent = h >> 1;
		dst->height = h;
		dst->skip = (float)px_sz * 1.5 - px_sz;
		if (!dst->skip)
			dst->skip = 1;
		dst->font = NULL;
		return;
	}

/* otherwise query the font for the specific metrics */
	dst->ascent = TTF_FontAscent(font->chain.data[0]);
	dst->descent = -1 * TTF_FontDescent(font->chain.data[0]);
	dst->height = TTF_FontHeight(font->chain.data[0]);
	dst->skip = dst->height - TTF_FontLineSkip(font->chain.data[0]);
	dst->font = font;
}

static void zap_slot(int i)
{
	for (size_t j = 0; j < font_cache[i].chain.count; j++){
		if (font_cache[i].chain.fd[j] != BADFD){
			close(font_cache[i].chain.fd[j]);
			font_cache[i].chain.fd[j] = BADFD;
		}

		if (font_cache[i].chain.data[j])
			TTF_CloseFont(font_cache[i].chain.data[j]);
	}
	free(font_cache[i].identifier);
	memset(&font_cache[i], '\0', sizeof(font_cache[0]));
}

static void set_style(struct text_format* dst, struct font_entry* font)
{
	dst->newline = dst->tab = dst->cr = 0;
	dst->col[0] = dst->col[1] = dst->col[2] = dst->col[3] = 0xff;

/* if no font is specified, we fallback to the builtin- bitmap one */
	update_style(dst, font);
}

static struct font_entry* grab_font(const char* fname, size_t size)
{
	int leasti = 1, i, leastv = -1;
	struct font_entry* font;

/* empty identifier - use default (slot 0) */
	if (!fname){
		fname = font_cache[0].identifier;

		if (!fname)
			return NULL;
	}
/* special case, set default slot to loaded font */
	else if (!font_cache[0].identifier){
		int fd = open(fname, O_RDONLY);
		if (BADFD == fd)
			return NULL;

		if (!arcan_video_defaultfont(fname, fd, size, 2, false))
			close(fd);
	}

/* match / track */
	struct font_entry* matchf = NULL;
	for (i = 0; i < font_cache_size && font_cache[i].chain.data[0] != NULL; i++){
		if (i && font_cache[i].usecount < leastv &&
			&font_cache[i] != last_style.font){
			leasti = i;
			leastv = font_cache[i].usecount;
		}

		if (strcmp(font_cache[i].identifier, fname) == 0){
			if (font_cache[i].chain.fd[0] != BADFD){
				matchf = &font_cache[i];
			}

			if (font_cache[i].size == size &&
				fabs(font_cache[i].vdpi - default_vdpi) < EPSILON &&
				fabs(font_cache[i].hdpi - default_hdpi) < EPSILON){
				font_cache[i].usecount++;
				font = &font_cache[i];
				goto done;
			}
		}
	}

/* we have an edge case here - there are fallback slots defined for the font
 * that was found but had the wrong size so we need to rebuild the entire
 * chain. Also note that not all (!default) slots have a font that is derived
 * from an accessible file descriptor. */
	struct font_entry_chain newch = {};

	if (matchf){
		if (i == font_cache_size){
			i = leasti;
		}
		int count = 0;
		for (size_t i = 0; i < matchf->chain.count; i++){
			newch.data[count] = TTF_OpenFontFD(
				matchf->chain.fd[i], size, default_hdpi, default_vdpi);
			newch.fd[count] = BADFD;
			if (!newch.data[count]){
				arcan_warning("grab font(), couldn't duplicate entire "
					"fallback chain (fail @ ind %d)\n", i);
			}
			else
				count++;
		}
		newch.count = count;
	}
	else {
		newch.data[0] = TTF_OpenFont(fname, size, default_hdpi, default_vdpi);
		newch.fd[0] = BADFD;
		if (newch.data[0])
			newch.count = 1;
	}

	if (newch.count == 0){
		arcan_warning("grab_font(), Open Font (%s,%d) failed\n", fname, size);
		return NULL;
	}

/* replace? */
	if (i == font_cache_size){
		i = leasti;
		zap_slot(i);
	}

/* update counters */
	font_cache[i].identifier = strdup(fname);
	font_cache[i].usecount++;
	font_cache[i].size = size;
	font_cache[i].vdpi = default_vdpi;
	font_cache[i].hdpi = default_hdpi;
	font_cache[i].chain = newch;
	font = &font_cache[i];

done:
	for (size_t i=0; i < font->chain.count; i++)
		TTF_SetFontHinting(font->chain.data[i], default_hint);
	return font;
}

bool arcan_video_defaultfont(const char* ident,
	file_handle fd, int sz, int hint, bool append)
{
	if (BADFD == fd)
		return false;

/* try to load */
	TTF_Font* font = TTF_OpenFontFD(fd, sz, default_hdpi, default_vdpi);
	if (!font)
		return false;

	if (-1 != default_hint){
		default_hint = hint;
	}

	if (!append){
		zap_slot(0);
		font_cache[0].identifier = strdup(ident);
		font_cache[0].size = sz;
		font_cache[0].chain.data[0] = font;
		font_cache[0].chain.fd[0] = fd;
		font_cache[0].chain.count = 1;
		set_style(&last_style, &font_cache[0]);
	}
	else{
		int dst_i = font_cache[0].chain.count;
		size_t lim = COUNT_OF(font_cache[0].chain.data);
		if (dst_i == lim){
			close(font_cache[0].chain.fd[dst_i-1]);
			TTF_CloseFont(font_cache[0].chain.data[dst_i-1]);
		}
		else
			dst_i++;

		font_cache[0].chain.count = dst_i;
		font_cache[0].chain.fd[dst_i-1] = fd;
		font_cache[0].chain.data[dst_i-1] = font;
	}

	return true;
}

void arcan_video_reset_fontcache()
{
	static bool init;

/* only first time, builtin- bitmap font will match application lifespan */
	if (!init){
		init = true;
		builtin_bitmap.bitmap = tui_pixelfont_open(64);
		for (int i = 0; i < ARCAN_FONT_CACHE_LIMIT; i++)
			font_cache[i].chain.fd[0] = BADFD;
	}
	else{
		for (int i = 0; i < ARCAN_FONT_CACHE_LIMIT; i++)
			zap_slot(i);
	}
}

#ifndef TEXT_EMBEDDEDICON_MAXW
#define TEXT_EMBEDDEDICON_MAXW 256
#endif

#ifndef TEXT_EMBEDDEDICON_MAXH
#define TEXT_EMBEDDEDICON_MAXH 256
#endif

static void text_loadimage(struct text_format* dst,
	const char* const infn, img_cons cons)
{
	char* path =
		arcan_find_resource(infn,
			RESOURCE_SYS_FONT |
			RESOURCE_APPL_SHARED |
			RESOURCE_APPL, ARES_FILE, NULL
		);

	data_source inres = arcan_open_resource(path);

	free(path);
	if (inres.fd == BADFD)
		return;

	map_region inmem = arcan_map_resource(&inres, false);
	if (inmem.ptr == NULL){
		arcan_release_resource(&inres);
		return;
	}

	struct arcan_img_meta meta = {0};
	uint32_t* imgbuf; /* set in _decode */
	size_t inw, inh;

	arcan_errc rv = arcan_img_decode(infn, inmem.ptr,
		inmem.sz, &imgbuf, &inw, &inh, &meta, false);

	arcan_release_map(inmem);
	arcan_release_resource(&inres);

/* repack if the system format doesn't match */
	if (imgbuf)
		imgbuf = arcan_img_repack(imgbuf, inw, inh);

	if (!imgbuf || rv != ARCAN_OK)
		return;

	if (cons.w > TEXT_EMBEDDEDICON_MAXW ||
		(cons.w == 0 && inw > TEXT_EMBEDDEDICON_MAXW))
		cons.w = TEXT_EMBEDDEDICON_MAXW;

	if (cons.h > TEXT_EMBEDDEDICON_MAXH ||
		(cons.h == 0 && inh > TEXT_EMBEDDEDICON_MAXH))
		cons.h = TEXT_EMBEDDEDICON_MAXH;

/* if blit to a specific size is requested, use that */
	if ((cons.w != 0 && cons.h != 0) && (inw != cons.w || inh != cons.h)){
		dst->surf.buf = arcan_alloc_mem(cons.w * cons.h * sizeof(av_pixel),
			ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
		arcan_renderfun_stretchblit(
			(char*)imgbuf, inw, inh, dst->surf.buf, cons.w, cons.h, false);
		arcan_mem_free(imgbuf);
		dst->surf.w = cons.w;
		dst->surf.h = cons.h;
	}
/* otherwise just keep the entire buffer */
	else {
		dst->surf.w = inw;
		dst->surf.h = inh;
		dst->surf.buf = imgbuf;
	}
}

static char* extract_color(struct text_format* prev, char* base){
	char cbuf[3];

/* scan 6 characters to the right, check for valid hex */
	for (int i = 0; i < 6; i++) {
		if (!isxdigit(*base++)){
			arcan_warning("arcan_video_renderstring(),"
				"couldn't scan font colour directive (#rrggbb, 0-9, a-f)\n");
			return NULL;
		}
	}

/* now we know 6 valid chars are there, time to collect. */
	cbuf[0] = *(base - 6); cbuf[1] = *(base - 5); cbuf[2] = 0;
	prev->col[0] = strtol(cbuf, 0, 16);

	cbuf[0] = *(base - 4); cbuf[1] = *(base - 3); cbuf[2] = 0;
	prev->col[1] = strtol(cbuf, 0, 16);

	cbuf[0] = *(base - 2); cbuf[1] = *(base - 1); cbuf[2] = 0;
	prev->col[2] = strtol(cbuf, 0, 16);

	return base;
}

static char* extract_font(struct text_format* prev, char* base){
	char* fontbase = base, (* numbase), (* orig) = base;

	int relsign = 0;
/* find fontname vs fontsize separator */
	while (*base != ',') {
		if (*base == 0) {
			arcan_warning("arcan_video_renderstring(), couldn't scan font "
				"directive '%s (%s)'\n", fontbase, orig);
			return NULL;
		}
		base++;
	}
	*base++ = 0;

	if (*base == '+'){
		relsign = 1;
		base++;
	}
	else if (*base == '-'){
		relsign = -1;
		base++;
	}

/* fontbase points to full fontname, find the size */
	numbase = base;
	while (*base != 0 && isdigit(*base))
		base++;

/* error state, no size specifier */
	if (numbase == base){
		arcan_warning("arcan_video_renderstring(), missing size argument "
			"in font specification (%s).\n", orig);
		return base;
	}

	char ch = *base;
	*base = 0;

/* we allow a 'default font size' \f,+n or \f,-n where n is relative
 * to the default set font and size */
	struct font_entry* font = NULL;
	int font_sz = strtoul(numbase, NULL, 10);
	if (relsign != 0 || font_sz == 0)
		font_sz = font_cache[0].size + relsign * font_sz;

/* but also force a sane default if that becomes problematic, 9 pt is
 * a common UI element standard font size */
	if (!font_sz)
		font_sz = 9;

/*
 * use current 'default-font' if just size is provided
 */
	if (*fontbase == '\0'){
		font = grab_font(NULL, font_sz);
		*base = ch;
		prev->pt_size = font_sz;
		update_style(prev, font);
		return base;
	}

/*
 * SECURITY NOTE, TTF is a complex format with a rich history of decoding
 * vulnerabilities. To lessen this we use a specific namespace for fonts.
 * This is currently not strongly enforced as it will break some older
 * applications.
 */
	char* fname = arcan_find_resource(
		fontbase,
		RESOURCE_SYS_FONT |
		RESOURCE_APPL_SHARED |
		RESOURCE_APPL, ARES_FILE,
		NULL
	);

	if (!fname)
		arcan_warning("arcan_video_renderstring(), couldn't find "
			"font (%s) (%s)\n", fontbase, orig);
	else if (!font && !(font = grab_font(fname, font_sz)))
		arcan_warning("arcan_video_renderstring(), couldn't load "
			"font (%s) (%s), (%d)\n", fname, orig, font_sz);
	else
		update_style(prev, font);

	arcan_mem_free(fname);
	*base = ch;
	return base;
}

static bool getnum(char** base, unsigned long* dst)
{
	char* wbase = *base;

	while(**base && isdigit(**base))
		(*base)++;

	if (strlen(wbase) == 0)
		return false;

	char ch = **base;
	**base = '\0';
	*dst = strtoul(wbase, NULL, 10);
	**base = ch;
	(*base)++;
	return true;
}

static char* extract_vidref(struct text_format* prev, char* base, bool ext)
{
	unsigned long vid;
	if (!getnum(&base, &vid)){
		arcan_warning("arcan_video_renderstring(\\evid), missing vid-ref\n");
		return NULL;
	}

	arcan_vobject* vobj = arcan_video_getobject(vid - vid_ofs);
	if (!vobj){
		arcan_warning(
			"arcan_video_renderstring(\\evid), missing or bad vid-ref (%lu)\n", vid);
		return NULL;
	}

	struct agp_vstore* vs = vobj->vstore;
	if (vs->txmapped != TXSTATE_TEX2D){
		arcan_warning(
			"arcan_video_renderstring(\\evid), invalid backing store for vid-ref\n");
		return NULL;
	}

/* get w, h */
	unsigned long w, h;
	if (!getnum(&base, &w) || !getnum(&base, &h)){
		arcan_warning("arcan_video_renderstring(\\evid,w,h) couldn't get dimension\n");
		return NULL;
	}

/* if ext, also get x1, y1, x2, y2 */
	unsigned long x1 = 0, y1 = 0, x2 = 0, y2 = 0;
	if (ext){
		if (
			!getnum(&base, &x1) || !getnum(&base, &y1) ||
			!getnum(&base, &x2) || !getnum(&base, &y2)){
			arcan_warning("arcan_video_renderstring("
				"\\E,w,h,x1,y1,x2,y2 - couldn't get dimensions\n");
			return NULL;
		}
	}

/* no local copy? readback - the 'nice' thing here for memory conservative use
 * would be to drop the cpu- local copy as well, but for something like an icon
 * blit-copy-cache, it might not be worthwhile */
	if (!vs->vinf.text.raw){
		agp_readback_synchronous(vs);
		if (!vs->vinf.text.raw){
			arcan_warning("arcan_video_renderstring(), couldn't synch vid-ref store\n");
			return NULL;
		}
	}

	size_t dw = w, dh = h;
	if (w > TEXT_EMBEDDEDICON_MAXW ||
		(w == 0 && vs->w > TEXT_EMBEDDEDICON_MAXW))
		dw = TEXT_EMBEDDEDICON_MAXW;
	else if (w == 0)
		dw = vs->w;

	if (h > TEXT_EMBEDDEDICON_MAXH ||
		(h == 0 && vs->h > TEXT_EMBEDDEDICON_MAXH))
		dh = TEXT_EMBEDDEDICON_MAXH;
	else if (h == 0)
		dh = vs->h;

	unsigned char* inbuf = (unsigned char*) vs->vinf.text.raw;

/* stretch + copy or just copy */
	size_t dsz = dw * dh * sizeof(av_pixel);
	prev->surf.buf = arcan_alloc_mem(dsz,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
	if (!prev->surf.buf)
		return NULL;

	if (!ext && dw == vs->w && dh == vs->h){
		memcpy(prev->surf.buf, vs->vinf.text.raw, dsz);
		prev->surf.w = dw;
		prev->surf.h = dh;
		return base;
	}

/* adjust offsets to match x1/y1/x2/y2 */
	size_t stride = 0;
	if (ext){
/* but first clamp */
		if (x1 > x2)
			x1 = 0;
		if (y1 > y2)
			y1 = 0;
		if (y2 > vs->h || y2 == 0)
			y2 = vs->h;
		if (x2 > vs->w || x2 == 0)
			x2 = vs->w;

		stride = vs->w * sizeof(av_pixel);
		inbuf += y1 * stride + x1 * sizeof(av_pixel);
	}
	else {
		x2 = vs->w;
		y2 = vs->h;
	}
/* and blit */
	stbir_resize_uint8(inbuf, (x2 - x1), (y2 - y1), stride,
		(unsigned char*) prev->surf.buf, dw, dh, 0, sizeof(av_pixel));

	prev->surf.w = dw;
	prev->surf.h = dh;
	prev->imgcons.w = prev->surf.w;
	prev->imgcons.h = prev->surf.h;

	return base;
}

static char* extract_image_simple(struct text_format* prev, char* base){
	char* wbase = base;

	while (*base && *base != ',') base++;
	if (*base)
		*base++ = 0;

	if (!strlen(wbase)){
		arcan_warning("arcan_video_renderstring(), missing resource name.\n");
		return NULL;
	}

	prev->imgcons.w = prev->imgcons.h = 0;
	prev->surf.buf = NULL;

	text_loadimage(prev, wbase, prev->imgcons);

	if (prev->surf.buf){
		prev->imgcons.w = prev->surf.w;
		prev->imgcons.h = prev->surf.h;
	}
	else
		arcan_warning(
			"arcan_video_renderstring(), couldn't load icon (%s)\n", wbase);

	return base;
}

static char* extract_image(struct text_format* prev, char* base)
{
	int forcew = 0, forceh = 0;

	char* widbase = base;
	while (*base && *base != ',' && isdigit(*base)) base++;
	if (*base && strlen(widbase) > 0)
		*base++ = 0;
	else {
		arcan_warning("arcan_video_renderstring(), width scan failed,"
			" premature end in sized image scan directive (%s)\n", widbase);
		return NULL;
	}
	forcew = strtol(widbase, 0, 10);
	if (forcew <= 0 || forcew > 1024){
		arcan_warning("arcan_video_renderstring(), width scan failed,"
			" unreasonable width (%d) specified in sized image scan "
			"directive (%s)\n", forcew, widbase);
		return NULL;
	}

	char* hghtbase = base;
	while (*base && *base != ',' && isdigit(*base)) base++;
	if (*base && strlen(hghtbase) > 0)
		*base++ = 0;
	else {
		arcan_warning("arcan_video_renderstring(), height scan failed, "
			"premature end in sized image scan directive (%s)\n", hghtbase);
		return NULL;
	}
	forceh = strtol(hghtbase, 0, 10);
	if (forceh <= 0 || forceh > 1024){
		arcan_warning("arcan_video_renderstring(), height scan failed, "
			"unreasonable height (%d) specified in sized image scan "
			"directive (%s)\n", forceh, hghtbase);
		return NULL;
	}

	char* wbase = base;
	while (*base && *base != ',') base++;
	if (*base == ','){
		*base++ = 0;
	}
	else {
		arcan_warning("arcan_video_renderstring(), missing resource name"
			" terminator (,) in sized image scan directive (%s)\n", wbase);
		return NULL;
	}

	if (strlen(wbase) > 0){
		prev->imgcons.w = forcew;
		prev->imgcons.h = forceh;
		prev->surf.buf = NULL;
		text_loadimage(prev, wbase, prev->imgcons);

		return base;
	}
	else{
		arcan_warning("arcan_video_renderstring(), missing resource name.\n");
		return NULL;
	}
}

static struct text_format formatend(char* base, struct text_format prev,
	char* orig, bool* ok) {
	struct text_format failed = {0};
/* don't carry caret modifiers */
	prev.newline = prev.tab = prev.cr = 0;
	bool inv = false;
	bool whskip = false;

	while (*base) {
/* skip first whitespace (avoid situation where;
 * \ffonts/test,181889 when writing 1889.. and still
 * allow for dynamic input dialogs etc. */
		if (whskip == false && isspace(*base)) {
			base++;
			whskip = true;
			continue;
		}

/* out of formatstring */
		if (*base != '\\') { prev.endofs = base; break; }

	char cmd;

retry:
		cmd = *(base+1);
		base += 2;

		switch (cmd){
/* the ! prefix is a special case, meaning that we invert the next character */
		case '!':
			inv = true;
			base--; *base = '\\';
			goto retry;
		break;
		case 't':
			prev.tab++;
		break;
		case 'n':
			prev.newline++;
		break;
		case 'r':
			prev.cr = true;
		break;
		case 'u':
			prev.style = (inv ?
				prev.style & TTF_STYLE_UNDERLINE : prev.style | TTF_STYLE_UNDERLINE);
		break;
		case 'b':
			prev.style = (inv ?
				prev.style & !TTF_STYLE_BOLD : prev.style | TTF_STYLE_BOLD);
		break;
		case 'i': prev.style = (inv ?
			prev.style & !TTF_STYLE_ITALIC : prev.style | TTF_STYLE_ITALIC);
		break;
		case 'e':
			base = extract_vidref(&prev, base, false);
		break;
		case 'E':
			base = extract_vidref(&prev, base, true);
		break;
		case 'v':
		break;
		case 'T':
		break;
		case 'H':
		break;
		case 'V':
		break;
		case 'p':
			base = extract_image_simple(&prev, base);
		break;
		case 'P':
			base = extract_image(&prev, base);
		break;
		case '#':
			base = extract_color(&prev, base);
		break;
		case 'f':
			base = extract_font(&prev, base);
		break;
		default:
			arcan_warning("arcan_video_renderstring(), "
				"unknown escape sequence: '\\%c' (%s)\n", *(base+1), orig);
			*ok = false;
			return failed;
		}

		if (!base){
			*ok = false;
			return failed;
		}

		inv = false;
	}

	if (*base == 0)
		prev.endofs = base;

	*ok = true;
	return prev;
}

/*
 * arcan_lua.c
 */
#ifndef CONST_MAX_SURFACEW
#define CONST_MAX_SURFACEW 8192
#endif

#ifndef CONST_MAX_SURFACEH
#define CONST_MAX_SURFACEH 4096
#endif

/* in arcan_ttf.c */
static void draw_builtin(struct rcell* cnode,
	const char* const base, struct text_format* style, int w, int h)
{
/* set size will have been called for the destination already as part
 * of size chain that is used for allocation */
	size_t len = strlen(base);
	uint32_t ucs4[len+1];
	UTF8_to_UTF32(ucs4, (const uint8_t* const) base, len);

	for(size_t i = 0; i < len; i++){
		tui_pixelfont_draw(
			builtin_bitmap.bitmap, cnode->data.surf.buf, w, ucs4[i], i * style->px_skip, 0,
			RGBA(style->col[0], style->col[1], style->col[2], style->col[3]),
			0, w, h, true
		);
	}
}

static bool render_alloc(struct rcell* cnode,
	const char* const base, struct text_format* style)
{
	int w, h;

	if (size_font_chain(style, base, &w, &h)){
		arcan_warning("arcan_video_renderstring(), couldn't size node.\n");
		return false;
	}
/* easy to circumvent here by just splitting into larger nodes, need
 * to do some accumulation for this to be less pointless */
	if (w == 0 || w > CONST_MAX_SURFACEW || h == 0 || h > CONST_MAX_SURFACEH){
		return false;
	}

	cnode->data.surf.buf = arcan_alloc_mem(w * h * sizeof(av_pixel),
		ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
	if (!cnode->data.surf.buf){
		arcan_warning("arcan_video_renderstring(%d,%d), failed alloc.\n",w, h);
		return false;
	}

/* we manually clear the buffer here because BZERO on VBUFFER sets FULLALPHA,
 * that means we need to repack etc. to handle kerning and that costs more */
	for (size_t i=0; i < w * h; i++)
		cnode->data.surf.buf[i] = 0;

/* if there is no font, we use the built-in default */
	if (!style->font){
		draw_builtin(cnode, base, style, w, h);
	}
	else if (!TTF_RenderUTF8chain(cnode->data.surf.buf, w, h, w,
		style->font->chain.data, style->font->chain.count,
		base, style->col, style->style)){
		arcan_warning("arcan_video_renderstring(), failed to render.\n");
		arcan_mem_free(cnode->data.surf.buf);
		cnode->data.surf.buf = NULL;
		return false;
	}

	cnode->data.surf.w = w;
	cnode->data.surf.h = h;
	cnode->ascent = style->ascent;
	cnode->height = style->height;
	cnode->descent = style->descent;
	cnode->skipv = style->skip;

	return true;
}

static inline void currstyle_cnode(struct text_format* curr_style,
	const char* const base, struct rcell* cnode, bool sizeonly)
{
	if (sizeonly){
		if (curr_style->font){
			int dw, dh;
			size_font_chain(curr_style, base, &dw, &dh);
			cnode->ascent = TTF_FontAscent(curr_style->font->chain.data[0]);
			cnode->width = dw;
			cnode->descent = TTF_FontDescent(curr_style->font->chain.data[0]);
			cnode->height = TTF_FontHeight(curr_style->font->chain.data[0]);
		}
		else{
			cnode->width = curr_style->imgcons.w;
			cnode->height = curr_style->imgcons.h;
		}
		return;
	}

/* image or render font */
	if (curr_style->surf.buf){
		cnode->data.surf.buf = curr_style->surf.buf;
		cnode->data.surf.w = curr_style->surf.w;
		cnode->data.surf.h = curr_style->surf.h;
		curr_style->surf.buf = NULL;
		return;
	}

	if (!render_alloc(cnode, base, curr_style))
		goto reset;

	return;
reset:
	set_style(&last_style, &font_cache[0]);
}

static struct rcell* trystep(struct rcell* cnode, bool force)
{
	if (force || cnode->data.surf.buf)
	cnode = cnode->next = arcan_alloc_mem(sizeof(struct rcell),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO,
		ARCAN_MEMALIGN_NATURAL
	);
	return cnode;
}

/* a */
static int build_textchain(char* message,
	struct rcell* root, bool sizeonly, bool nolast, bool reset)
{
	int rv = 0;
/*
 * if we don't want this to be stateful, we can just go:
 * set_style(&curr_style, font_cache[0].data);
 */
	struct text_format* curr_style = &last_style;
	if (reset)
		set_style(curr_style, &font_cache[0]);

	struct rcell* cnode = root;
	char* current = message;
	char* base = message;
	int msglen = 0;

/* outer loop, find first split- point */
	while (*current) {
		if (*current == '\\') {
/* special case, escape \ */
			if (*(current+1) == '\\') {
				memmove(current, current+1, strlen(current));
				current += 1;
				msglen++;
			}
/* split-point (one or several formatting arguments) found */
			else {
				if (msglen > 0){
					*current = 0;
/* render surface and slide window */
					currstyle_cnode(curr_style, base, cnode, sizeonly);

/* slide- alloc list of rendered blocks */
					cnode = trystep(cnode, false);
					*current = '\\';
				}

/* scan format- options and slide to end */
				bool okstatus;
				*curr_style = formatend(current, *curr_style, message, &okstatus);
				if (!okstatus)
					return -1;

/* caret modifiers need to be separately chained to avoid (three?) nasty
 * little edge conditions */
				if (curr_style->newline || curr_style->tab || curr_style->cr) {
					cnode = trystep(cnode, false);
					rv += curr_style->newline;
					cnode->data.format.newline = curr_style->newline;
					cnode->data.format.tab = curr_style->tab;
					cnode->data.format.cr = curr_style->cr;
					cnode = trystep(cnode, true);
				}

				if (curr_style->surf.buf){
					currstyle_cnode(curr_style, base, cnode, sizeonly);
					cnode = trystep(cnode, false);
				}

				current = base = curr_style->endofs;
/* note, may this be a condition for a break rather than a return? */
				if (current == NULL)
					return -1;

				msglen = 0;
			}
		}
		else {
			msglen += 1;
			current++;
		}
	}

/* last element .. */
	if (msglen) {
		cnode->next = NULL;
		if (sizeonly){
			size_font_chain(curr_style, base, (int*) &cnode->width, (int*) &cnode->height);
		}
		else
			render_alloc(cnode, base, curr_style);
	}

/* special handling needed for longer append chains */
	if (!nolast){
		cnode = trystep(cnode, true);
		cnode->data.format.newline = 1;
		rv++;
	}

	return rv;
}

static unsigned int round_mult(unsigned num, unsigned int mult)
{
	if (num == 0 || mult == 0)
		return mult; /* intended ;-) */
	unsigned int remain = num % mult;
	return remain ? num + mult - remain : num;
}

static unsigned int get_tabofs(int offset, int tabc, int8_t tab_spacing)
{
	return PT_TO_HPX( tab_spacing ?
			round_mult(offset, tab_spacing) + ((tabc - 1) * tab_spacing) : offset );

	return PT_TO_HPX(offset);
}

/*
 * should really have a fast blit path, but since font rendering is expected to
 * be mostly replaced/complemented with a mix of in-place rendering and proper
 * packing and vertex buffers in 0.7ish we just leave it like this
 */
static inline void copy_rect(av_pixel* dst, size_t dst_sz,
	struct rcell* surf, int width, int height, int x, int y)
{
	uintptr_t high = (sizeof(av_pixel) * height * width);
	if (high > dst_sz){
		arcan_warning("arcan_video_renderstring():copy_rect OOB, %zu/%zu\n",
			high, dst_sz);
		return;
	}

	for (int row = 0; row < surf->data.surf.h && row < height - y; row++)
		memcpy(
			&dst[(y+row)*width+x],
			&surf->data.surf.buf[row*surf->data.surf.w],
			surf->data.surf.w * sizeof(av_pixel)
		);
}

static void cleanup_chain(struct rcell* root)
{
	while (root){
		assert(root != (void*) 0xdeadbeef);
		if (root->data.surf.buf){
			arcan_mem_free(root->data.surf.buf);
			root->data.surf.buf = (void*) 0xfeedface;
		}

		struct rcell* prev = root;
		root = root->next;
		prev->next = (void*) 0xdeadbeef;
		arcan_mem_free(prev);
	}
}

static av_pixel* process_chain(struct rcell* root, arcan_vobject* dst,
	size_t chainlines, bool norender, bool pot,
	unsigned int* n_lines, struct renderline_meta** lineheights, size_t* dw,
	size_t* dh, uint32_t* d_sz, size_t* maxw, size_t* maxh)
{
	struct rcell* cnode = root;
	unsigned int linecount = 0;
	*maxw = 0;
	*maxh = 0;
	int lineh = 0, fonth = 0, ascenth = 0, descenth = 0;
	int curw = 0;

	int line_spacing = 0;
	bool fixed_spacing = false;
/*	if (line_spacing == 0){
		fixed_spacing = false;
	} */

/* note, linecount is overflow */
	struct renderline_meta* lines = arcan_alloc_mem(sizeof(
		struct renderline_meta) * (chainlines + 1), ARCAN_MEM_VSTRUCT,
		ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL
	);

/* (A) figure out visual constraints */
	struct rcell* linestart = cnode;

	while (cnode) {
/* data node */
		if (cnode->data.surf.buf) {
			if (!fixed_spacing)
				line_spacing = cnode->skipv;

			if (lineh + line_spacing <= 0 || cnode->data.surf.h > lineh + line_spacing)
				lineh = cnode->data.surf.h;

			if (cnode->ascent > ascenth){
				ascenth = cnode->ascent;
			}

			if (cnode->descent > descenth){
				descenth = cnode->descent;
			}

			if (cnode->height > fonth){
				fonth = cnode->height;
			}

/* track dimensions, may want to use them later */
			curw += cnode->data.surf.w;
		}
/* format node */
		else {
			if (cnode->data.format.cr){
				curw = 0;
			}

			if (cnode->data.format.tab)
				curw = get_tabofs(curw, cnode->data.format.tab, /* tab_spacing */ 0);

			if (cnode->data.format.newline > 0)
				for (int i = cnode->data.format.newline; i > 0; i--) {
					lines[linecount].ystart = *maxh;
					lines[linecount].height = fonth;
					lines[linecount++].ascent = ascenth;
					*maxh += lineh + line_spacing;
					ascenth = fonth = lineh = 0;
				}
		}

		if (curw > *maxw)
			*maxw = curw;

		cnode = cnode->next;
	}

/* (B) render into destination buffers, possibly pad to reduce number
 * of needed relocations on dynamic resizing from small changes */
	*dw = pot ? nexthigher(*maxw) : *maxw;
	*dh = pot ? nexthigher(*maxh) : *maxh;

	*d_sz = *dw * *dh * sizeof(av_pixel);

	if (norender)
		return (cleanup_chain(root), NULL);

/* if we have a vobj set, re-use that backing store, and treat
 * it as a source-stream resize (so scaling factors etc. get reapplied) */

	av_pixel* raw = NULL;

	if (dst){
/* manually resize the local buffer so the video_resizefeed call won't
 * do dual agp_update_vstore synchs */
		struct agp_vstore* s = dst->vstore;

		if (s->vinf.text.raw)
			arcan_mem_free(s->vinf.text.raw);

	 	raw = s->vinf.text.raw = arcan_alloc_mem(*d_sz,
			ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);
		s->vinf.text.s_raw = *d_sz;
		s->w = *dw;
		s->h = *dh;
	}
	else{
		raw = arcan_alloc_mem(*d_sz, ARCAN_MEM_VBUFFER,
			ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
	}

	if (!raw || !*d_sz)
		return (cleanup_chain(root), raw);

	memset(raw, '\0', *d_sz);
	cnode = root;
	curw = 0;
	int line = 0;

	while (cnode) {
		if (cnode->data.surf.buf) {
			copy_rect(raw, *d_sz, cnode, *dw, *dh, curw, lines[line].ystart);
			curw += cnode->data.surf.w;
		}
		else {
			if (cnode->data.format.tab > 0)
				curw = get_tabofs(curw, cnode->data.format.tab, /* tab_spacing */ 0);

			if (cnode->data.format.cr)
				curw = 0;

			if (cnode->data.format.newline > 0)
				line += cnode->data.format.newline;
		}
		cnode = cnode->next;
	}

	if (n_lines)
		*n_lines = linecount;

	if (lineheights)
		*lineheights = lines;
	else
		arcan_mem_free(lines);

	if (dst){
		agp_resize_vstore(dst->vstore, *dw, *dh);
		dst->vstore->vinf.text.hppcm = default_hdpi / 2.54;
		dst->vstore->vinf.text.vppcm = default_vdpi / 2.54;
	}

	return (cleanup_chain(root), raw);
}

av_pixel* arcan_renderfun_renderfmtstr_extended(const char** msgarray,
	arcan_vobj_id dstore, bool pot,
	unsigned int* n_lines, struct renderline_meta** lineheights, size_t* dw,
	size_t* dh, uint32_t* d_sz, size_t* maxw, size_t* maxh, bool norender)
{
	struct rcell* root = arcan_alloc_mem(sizeof(struct rcell),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_NATURAL
	);
	if (!root || !msgarray || !msgarray[0])
		return NULL;

	last_style.newline = 0;
	last_style.tab = 0;
	last_style.cr = false;

/* %2, build as text-chain, accumulate linechain view */
	size_t acc = 0, ind = 0;

	struct rcell* cur = root;
	while (msgarray[ind]){
		if (msgarray[ind][0] == 0){
			ind++;
			continue;
		}

		if (ind % 2 == 0){
			char* work = strdup(msgarray[ind]);
			int nlines = build_textchain(work, cur, false, true, ind == 0);
			arcan_mem_free(work);
			if (-1 == nlines)
				break;
			acc += nlines;
			while (cur->next != NULL)
				cur = cur->next;
		}
/* %2+1, no format-string input, just treat as text */
		else{
			cur = cur->next = arcan_alloc_mem(sizeof(struct rcell),
				ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
				ARCAN_MEMALIGN_NATURAL
			);
			currstyle_cnode(&last_style, msgarray[ind], cur, false);
		}
		ind++;
	}

/* append newline */
	cur = cur->next = arcan_alloc_mem(
		sizeof(struct rcell), ARCAN_MEM_VSTRUCT,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO,
		ARCAN_MEMALIGN_NATURAL
	);
	cur->data.format.newline = 1;

	return process_chain(root, arcan_video_getobject(dstore),
		acc+1, norender, pot, n_lines,
		lineheights, dw, dh, d_sz, maxw, maxh
	);
}

av_pixel* arcan_renderfun_renderfmtstr(const char* message,
	arcan_vobj_id dstore,
	bool pot, unsigned int* n_lines, struct renderline_meta** lineheights,
	size_t* dw, size_t* dh, uint32_t* d_sz,
	size_t* maxw, size_t* maxh, bool norender)
{
	if (!message)
		return NULL;

	av_pixel* raw = NULL;

/* (A) parse format string and build chains of renderblocks */
	struct rcell* root = arcan_alloc_mem(sizeof(struct rcell),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_NATURAL
	);

	char* work = strdup(message);
	last_style.newline = 0;
	last_style.tab = 0;
	last_style.cr = false;

	int chainlines = build_textchain(work, root, false, false, true);
	arcan_mem_free(work);

	if (chainlines > 0){
		raw = process_chain(root, arcan_video_getobject(dstore),
			chainlines, norender, pot, n_lines, lineheights,
			dw, dh, d_sz, maxw, maxh
		);
	}

	return raw;
}

int arcan_renderfun_stretchblit(char* src, int inw, int inh,
	uint32_t* dst, size_t dstw, size_t dsth, int flipv)
{
	const int pack_tight = 0;
	const int rgba_ch = 4;

	if (1 != stbir_resize_uint8((unsigned char*)src,
		inw, inh, pack_tight, (unsigned char*)dst, dstw, dsth, pack_tight, rgba_ch))
		return -1;

	if (!flipv)
		return 1;

	uint32_t row[dstw];
	size_t stride = dstw * 4;
	for (size_t y = 0; y < dsth >> 1; y++){
		if (y == (dsth - 1 - y))
			continue;

		memcpy(row, &dst[y*dstw], stride);
		memcpy(&dst[y*dstw], &dst[(dsth-1-y)*dstw], stride);
		memcpy(&dst[(dsth-1-y)*dstw], row, stride);
	}

	return 1;
}

struct arcan_renderfun_fontgroup {
	struct tui_font* font;
	struct tui_raster_context* raster;
	size_t used;
	size_t w, h;
	float ppcm;
	float size_mm;

/* when adding atlas support, reference the internal font here instead */
};

static void build_font_group(
	struct arcan_renderfun_fontgroup* grp, int* fds, size_t n_fonts);

static void close_font_slot(struct arcan_renderfun_fontgroup* grp, int slot)
{
	if (!(grp->font[slot].fd && grp->font[slot].fd != BADFD) ||
		grp->font == &builtin_bitmap)
		return;

	close(grp->font[slot].fd);
	grp->font[slot].fd = -1;
	if (grp->font[slot].vector){
		TTF_CloseFont(grp->font[slot].truetype);
		grp->font[slot].truetype = NULL;
	}
	else{
		tui_pixelfont_close(grp->font[slot].bitmap);
		grp->font[slot].bitmap = NULL;
	}
}

static int consume_pixel_font(struct arcan_renderfun_fontgroup* grp, int fd)
{
	data_source src = {
		.fd = fd,
		.source = NULL
	};

	map_region map = arcan_map_resource(&src, false);
	if (!map.ptr || map.sz < 32 || !tui_pixelfont_valid(map.u8, 23)){
		arcan_release_map(map);
		return 0;
	}

/* prohibit mixing and matching vector/bitmap */
	if (grp->font[0].truetype && grp->font[0].vector){
		close_font_slot(grp, 0);
		grp->font[0].vector = false;
	}

	for (size_t i = 1; i < grp->used; i++){
		close_font_slot(grp, i);
	}

/* re-use current bitmap group or build one if it isn't there */
	if (!grp->font[0].bitmap &&
		!(grp->font[0].bitmap = tui_pixelfont_open(64))){
		close(fd);
		arcan_release_map(map);
		return -1;
	}

	close(fd);
	return 1;
}

static void font_group_ptpx(
	struct arcan_renderfun_fontgroup* grp, size_t* pt, size_t* px)
{
	float pt_size = roundf((float)grp->size_mm * 2.8346456693f);
	if (pt_size < 4)
		pt_size = 4;

	if (pt)
		*pt = pt_size;

	if (px)
		*px = roundf((float)pt_size * 0.03527778 * grp->ppcm);
}

static void set_font_slot(
	struct arcan_renderfun_fontgroup* grp, int slot, int fd)
{
/* don't do anything to a bad font */
	if (fd == -1)
		return;

/* the builtin- bitmap is immutable */
	if (grp->font == &builtin_bitmap){
		close(fd);
		return;
	}

/* first check for a supported pixel font format, early-out on found/io error */
	int pfstat = consume_pixel_font(grp, fd);
	if (pfstat)
		return;

/* assume vector and try TTF - next step here is to use this to resolve the
 * font / size against the existing cache using the inode, careful with the
 * refcount in that case though */
	size_t pt_sz;
	font_group_ptpx(grp, &pt_sz, NULL);
	float dpi = grp->ppcm * 2.54f;

/* OpenFontFD duplicates internally */
	grp->font[slot].truetype = TTF_OpenFontFD(fd, pt_sz, dpi, dpi);
	if (!grp->font[slot].truetype){
		close(fd);
		grp->font[slot].vector = false;
		grp->font[slot].fd = -1;
		return;
	}

	grp->font[slot].fd = fd;
	grp->font[slot].vector = true;
	TTF_SetFontStyle(grp->font[slot].truetype, TTF_STYLE_NORMAL);
	TTF_SetFontStyle(grp->font[slot].truetype, TTF_HINTING_NORMAL);
}

/* option to consider is if we do refcount + sharing of group, or do that
 * on the font level, likely the latter given how that worked out for vobjs
 * with null_surface sharing vstores vs. the headache that was instancing */
struct arcan_renderfun_fontgroup* arcan_renderfun_fontgroup(int* fds, size_t n_fonts)
{
/* we take ownership of descriptors */
	struct arcan_renderfun_fontgroup* grp =
		arcan_alloc_mem(
			sizeof(struct arcan_renderfun_fontgroup),
			ARCAN_MEM_VSTRUCT,
			ARCAN_MEM_BZERO,
			ARCAN_MEMALIGN_NATURAL
		);

	if (!grp)
		return NULL;

	build_font_group(grp, fds, n_fonts);

	return grp;
}

void arcan_renderfun_fontgroup_replace(
	struct arcan_renderfun_fontgroup* group, int slot, int new)
{
	if (!group)
		return;

/* always invalidate any cached raster */
	if (group->raster){
		tui_raster_free(group->raster);
		group->raster = NULL;
	}

/* can't accomodate, ignore */
	if (slot >= group->used){
		if (new != -1)
			close(new);
		return;
	}

	set_font_slot(group, slot, new);
}

void arcan_renderfun_release_fontgroup(struct arcan_renderfun_fontgroup* group)
{
	if (!group)
		return;

	for (size_t i = 0; i < group->used; i++)
		close_font_slot(group, i);

	group->used = 0;

	tui_raster_free(group->raster);

	if (group->font != &builtin_bitmap){
		arcan_mem_free(group->font);
	}
	arcan_mem_free(group);
}

void arcan_renderfun_fontgroup_size(
	struct arcan_renderfun_fontgroup* group,
	float size_mm, float ppcm, size_t* w, size_t* h)
{

/* the 'raster' context derives from the group in a certain state, and can be
 * dependent on a shared glyph atlas that changes between invocations - so
 * invalidate on size change */
	if (group->raster){
		tui_raster_free(group->raster);
		group->raster = NULL;
	}

	if (size_mm > EPSILON)
		group->size_mm = size_mm;

	if (ppcm > EPSILON)
		group->ppcm = ppcm;

/* recalculate new sizes so that we can update the group itself */
	size_t pt, px;
	font_group_ptpx(group, &pt, &px);
	float dpi = group->ppcm * 2.54;

/* re-open each font for the new pt */
	for (size_t i = 0; i < group->used; i++){
		if (group->font[i].vector && group->font[i].truetype)
		{
			group->font[i].truetype =
				TTF_ReplaceFont(group->font[i].truetype, pt, dpi, dpi);
		}
	}

/* reprobe based on first slot */
	if (group->font[0].vector){
		group->w = group->h = 0;
		TTF_ProbeFont(group->font[0].truetype, &group->w, &group->h);
	}
	else {
		tui_pixelfont_setsz(group->font[0].bitmap, px, &group->w, &group->h);
	}

	*w = group->w;
	*h = group->h;
}

struct tui_raster_context*
	arcan_renderfun_fontraster(struct arcan_renderfun_fontgroup* group)
{
/* if we don't have a valid font in the font group, the raster is pointless */
	if ((group->font[0].vector && !group->font[0].truetype) ||
		(!group->font[0].vector && !group->font[0].bitmap))
		return NULL;

/* if we have a cached raster, return */
	if (group->raster){
		return group->raster;
	}

/* otherwise, build a new list (_setup will copy internally) */
	struct tui_font* lst[group->used];
	for (size_t i = 0; i < group->used; i++){
		lst[i] = &group->font[i];
	}

	group->raster = tui_raster_setup(group->w, group->h);
	tui_raster_setfont(group->raster, lst, group->used);

	return group->raster;
}

static void build_font_group(
	struct arcan_renderfun_fontgroup* grp, int* fds, size_t n_fonts)
{
/* safe defaults */
	grp->ppcm = 37.795276;
	grp->size_mm = 3.527780;

/* default requested */
	if (!n_fonts || fds[0] == -1)
		goto fallback_bitmap;

	grp->used = n_fonts;
	grp->font = arcan_alloc_mem(
		sizeof(struct tui_font) * n_fonts,
		ARCAN_MEM_VSTRUCT,
		ARCAN_MEM_BZERO,
		ARCAN_MEMALIGN_NATURAL
	);
	if (!grp->font)
		goto fallback_bitmap;

/* probe types, fill out the font structure accordingly */
	for (size_t i = 0; i < n_fonts; i++){
		set_font_slot(grp, i, fds[i]);
	}
	return;

fallback_bitmap:
	grp->used = 1;
	arcan_mem_free(grp->font);
	grp->font = &builtin_bitmap;
}
