/*
 * Copyright 2008-2016, Björn Ståhl
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

#ifndef ARCAN_FONT_CACHE_LIMIT
#define ARCAN_FONT_CACHE_LIMIT 8
#endif

#define ARCAN_TTF

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_ttf.h"

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
	uint8_t usecount;
};

struct text_format {
/* font specification */
	struct font_entry* font;
	uint8_t col[4];
	uint8_t bgcol[4];
	int style;
	uint8_t alpha;

/* for forced loading of images */
	struct {
		size_t w, h;
		av_pixel* buf;
	} surf;
	img_cons imgcons;

/* pointer into line of text where the format was extracted,
 * only temporary use */
	char* endofs;

/* metrics */
	int height;
	int skip;
	int ascent;

/* whitespace management */
	bool cr;
	uint8_t tab;
	uint8_t newline;
};

static int default_hint = TTF_HINTING_NORMAL;

static struct text_format last_style = {
	.col = {0xff, 0xff, 0xff, 0xff},
	.bgcol = {0xaa, 0xaa, 0xaa, 0xaa}
};

static unsigned int font_cache_size = ARCAN_FONT_CACHE_LIMIT;
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
 * each element can EITHER modfiy to current cursor position OR represent
 * a rendered surface.

 * (b) take the linked list, sweep through it and figure out which dimensions
 * it requires, allocate a corresponding storage object.

 * (c) sweep the list yet again, render to the storage object.
*/

// TTF_FontHeight sets line-spacing.

struct rcell {
	bool surface;
	unsigned int width;
	unsigned int height;
	int skipv;
	int ascent;

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

static void update_style(struct text_format* dst, struct font_entry* font)
{
	if (!font || !font->chain.data[0]){
		arcan_warning("renderfun(), tried to update from broken font\n");
		return;
	}

	dst->ascent = TTF_FontAscent(font->chain.data[0]);
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
	if (font)
		update_style(dst, font);
	else {
		dst->ascent = dst->height = dst->skip = 0;
	}
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

			if (font_cache[i].size == size){
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
			newch.data[count] = TTF_OpenFontFD(matchf->chain.fd[i], size);
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
		newch.data[0] = TTF_OpenFont(fname, size);
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
	TTF_Font* font = TTF_OpenFontFD(fd, sz);
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
	if (!init){
		init = true;
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

#ifndef RENDERFUN_NOSUBIMAGE
static void text_loadimage(struct text_format* dst,
	const char* const infn, img_cons cons)
{
	char* path = arcan_find_resource(infn,
		RESOURCE_SYS_FONT | RESOURCE_APPL_SHARED | RESOURCE_APPL, ARES_FILE);

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
	uint32_t* imgbuf;
	size_t inw, inh;

	arcan_errc rv = arcan_img_decode(infn, inmem.ptr,
		inmem.sz, &imgbuf, &inw, &inh, &meta, false);

/* stretchblit is assumed to deal with the edgecase of
 * w ^ h being 0 */
	if (cons.w > TEXT_EMBEDDEDICON_MAXW ||
		(cons.w == 0 && inw > TEXT_EMBEDDEDICON_MAXW))
		cons.w = TEXT_EMBEDDEDICON_MAXW;

	if (cons.h > TEXT_EMBEDDEDICON_MAXH ||
		(cons.h == 0 && inh > TEXT_EMBEDDEDICON_MAXH))
		cons.h = TEXT_EMBEDDEDICON_MAXH;

	arcan_release_map(inmem);
	arcan_release_resource(&inres);

	if (imgbuf && rv == ARCAN_OK){
		if ((cons.w != 0 && cons.h != 0) && (inw != cons.w || inh != cons.h)){
			dst->surf.buf = arcan_alloc_mem(cons.w * cons.h * sizeof(av_pixel),
				ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
			arcan_renderfun_stretchblit(
				(char*)imgbuf, inw, inh, dst->surf.buf, cons.w, cons.h, false);
			arcan_mem_free(imgbuf);
			dst->surf.w = cons.w;
			dst->surf.h = cons.h;
		}
		else {
			dst->surf.w = inw;
			dst->surf.h = inh;
			dst->surf.buf = imgbuf;
		}
	}
}
#endif

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

	struct font_entry* font = NULL;
	int font_sz = strtoul(numbase, NULL, 10);
	if (relsign != 0 || font_sz == 0)
		font_sz = font_cache[0].size + relsign * font_sz;

/*
 * use current 'default-font' if just size is provided
 */
	if (*fontbase == '\0'){
		font = grab_font(NULL, font_sz);
		*base = ch;
		if (font)
			update_style(prev, font);
		return base;
	}

/*
 * SECURITY NOTE, TTF is a complex format with a rich history of decoding
 * vulnerabilities. To lessen this we use a specific namespace for fonts.
 * This is currently not strongly enforced as it will break some older
 * applications.
 */
	char* fname = arcan_find_resource(fontbase,
		RESOURCE_SYS_FONT | RESOURCE_APPL_SHARED | RESOURCE_APPL, ARES_FILE);

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

#ifndef RENDERFUN_NOSUBIMAGE
static char* extract_image_simple(struct text_format* prev, char* base){
	char* wbase = base;

	while (*base && *base != ',') base++;
	if (*base)
		*base++ = 0;

	if (strlen(wbase) > 0){
		prev->imgcons.w = prev->imgcons.h = 0;
		prev->surf.buf = NULL;

		text_loadimage(prev, wbase, prev->imgcons);

		if (prev->surf.buf){
			prev->imgcons.w = prev->surf.w;
			prev->imgcons.h = prev->surf.h;
		}

		return base;
	}
	else{
		arcan_warning("arcan_video_renderstring(), missing resource name.\n");
		return NULL;
	}
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
#endif

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

/* all the supported formatting characters;
 * b = bold, i = italic, u = underline, n = newline, r = carriage return,
 * t = tab ! = inverse (bold,italic,underline), #rrggbb = setcolor,
 * fpath,size = setfont, Pwidth,height,fname(, or NULL) extract
 * pwidth,height = embedd image (width, height optional) */
	char cmd;

retry:
		cmd = *(base+1);
		base += 2;

		switch (cmd){
/* the ! prefix is a special case, meaning that we invert the next character */
		case '!': inv = true; base--; *base = '\\'; goto retry; break;
		case 't': prev.tab++; break;
		case 'n': prev.newline++; break;
		case 'r': prev.cr = true; break;
		case 'u': prev.style = (inv ? prev.style & TTF_STYLE_UNDERLINE :
				prev.style | TTF_STYLE_UNDERLINE); break;
		case 'b': prev.style = (inv ? prev.style & !TTF_STYLE_BOLD :
				prev.style | TTF_STYLE_BOLD); break;
		case 'i': prev.style = (inv ? prev.style & !TTF_STYLE_ITALIC :
				 prev.style | TTF_STYLE_ITALIC); break;
#ifndef RENDERFUN_NOSUBIMAGE
		case 'p': base = extract_image_simple(&prev, base); break;
		case 'P': base = extract_image(&prev, base); break;
#endif
		case '#': base = extract_color(&prev, base); break;
		case 'f': base = extract_font(&prev, base); break;

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

static bool render_alloc(struct rcell* cnode,
	const char* const base, struct text_format* style)
{
	int w, h;

	if (TTF_SizeUTF8chain(style->font->chain.data,
		style->font->chain.count, base, &w, &h, style->style)){
		arcan_warning("arcan_video_renderstring(), couldn't size node.\n");
		return false;
	}
/* easy to circumvent here by just splitting into larger nodes, need
 * to do some accumulation for this to be less pointless */
	if (w==0 || w > CONST_MAX_SURFACEW || h == 0 || h > CONST_MAX_SURFACEH){
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

	if (!TTF_RenderUTF8chain(cnode->data.surf.buf, w, h, w,
		style->font->chain.data, style->font->chain.count,
		base, style->col, style->style)){
		arcan_warning("arcan_video_renderstring(), failed to render.\n");
		arcan_mem_free(cnode->data.surf.buf);
		cnode->data.surf.buf = NULL;
		return false;
	}

	cnode->surface = true;
	cnode->data.surf.w = w;
	cnode->data.surf.h = h;
	cnode->ascent = style->ascent;
	cnode->height = style->height;
	cnode->skipv = style->skip;

	return true;
}

static inline void currstyle_cnode(struct text_format* curr_style,
	const char* const base, struct rcell* cnode, bool sizeonly)
{
	if (sizeonly){
		if (curr_style->font){
			int dw, dh;
			TTF_SizeUTF8chain(curr_style->font->chain.data,
				curr_style->font->chain.count, base, &dw, &dh, curr_style->style);
			cnode->ascent = TTF_FontAscent(curr_style->font->chain.data[0]);
			cnode->width = dw;
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

	if (!curr_style->font){
		arcan_warning("arcan_video_renderstring(), couldn't render node.\n");
		goto reset;
	}

	if (!render_alloc(cnode, base, curr_style))
		goto reset;

	return;
reset:
	set_style(&last_style, &font_cache[0]);
}

static struct rcell* trystep(struct rcell* cnode, bool force)
{
	if (force || cnode->surface)
	cnode = cnode->next = arcan_alloc_mem(sizeof(struct rcell),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO,
		ARCAN_MEMALIGN_NATURAL
	);
	return cnode;
}

/* a */
static int build_textchain(char* message, struct rcell* root,
	bool sizeonly, bool nolast)
{
	int rv = 0;
/*
 * if we don't want this to be stateful, we can just go:
 * set_style(&curr_style, font_cache[0].data);
 */
	struct text_format* curr_style = &last_style;

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
					if (!curr_style->font) {
						arcan_warning("arcan_video_renderstring(),"
							" no font specified / found.\n");
						return -1;
					}

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
	if (msglen && curr_style->font) {
		cnode->next = NULL;
		if (sizeonly){
			TTF_SizeUTF8chain(curr_style->font->chain.data,
				curr_style->font->chain.count, base, (int*) &cnode->width,
				(int*) &cnode->height, curr_style->style
			);
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

/*
 * tabs are messier still, for each format segment, there may be 'tabc' number
 * of tabsteps, these concern only the current text block and are thus
 * calculated from a fixed offset.  */
static unsigned int get_tabofs(int offset, int tabc, int8_t tab_spacing,
	unsigned int* tabs)
{
	if (!tabs || *tabs == 0) /* tabc will always be >= 1 */
		return tab_spacing ?
			round_mult(offset, tab_spacing) + ((tabc - 1) * tab_spacing) : offset;

/* find last matching tab pos first */
	while (*tabs && *tabs < offset)
		tabs++;

/* matching tab found */
	if (*tabs) {
		offset = *tabs;
		tabc--;
	}

	while (tabc--) {
		if (*tabs)
			offset = *tabs++;
		else
			offset += round_mult(offset, tab_spacing);
/* out of defined tabs, pad with default spacing */

	}

	return offset;
}

/*
 * should really have a fast blit path, but since font rendering is expected to
 * be mostly replaced/complemented with a mix of in-place rendering and proper
 * packing and vertex buffers in 0.6 or 0.5.1 we just leave it like this
 */
static inline void copy_rect(av_pixel* dst, struct rcell* surf,
	int width, int height, int x, int y)
{
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
		if (root->surface && root->data.surf.buf){
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
	size_t chainlines, bool norender,
	int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, bool pot,
	unsigned int* n_lines, struct renderline_meta** lineheights, size_t* dw,
	size_t* dh, uint32_t* d_sz, size_t* maxw, size_t* maxh)
{
	struct rcell* cnode = root;
	unsigned int linecount = 0;
	*maxw = 0;
	*maxh = 0;
	int lineh = 0, fonth = 0, ascenth = 0;
	int curw = 0;

	bool fixed_spacing = true;
	if (line_spacing == 0){
		fixed_spacing = false;
	}

/* note, linecount is overflow */
	struct renderline_meta* lines = arcan_alloc_mem(sizeof(
		struct renderline_meta) * (chainlines + 1), ARCAN_MEM_VSTRUCT,
		ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL
	);

/* (A) figure out visual constraints */
	while (cnode) {
		if (cnode->surface && cnode->data.surf.buf) {
			if (!fixed_spacing)
				line_spacing = cnode->skipv;

			if (lineh + line_spacing <= 0 || cnode->data.surf.h > lineh + line_spacing)
				lineh = cnode->data.surf.h;

			if (cnode->ascent > ascenth){
				ascenth = cnode->ascent;
				fonth = cnode->height;
			}

			curw += cnode->data.surf.w;
		}
		else {
			if (cnode->data.format.cr)
				curw = 0;

			if (cnode->data.format.tab)
				curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

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
		struct storage_info_t* s = dst->vstore;

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

	if (!raw)
		return (cleanup_chain(root), raw);

	memset(raw, '\0', *d_sz);
	cnode = root;
	curw = 0;
	int line = 0;

	while (cnode) {
		if (cnode->surface && cnode->data.surf.buf) {
			copy_rect(raw, cnode, *dw, *dh, curw, lines[line].ystart);
			curw += cnode->data.surf.w;
		}
		else {
			if (cnode->data.format.tab > 0)
				curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

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
	}

	return (cleanup_chain(root), raw);
}

av_pixel* arcan_renderfun_renderfmtstr_extended(const char** msgarray,
	arcan_vobj_id dstore, int8_t line_spacing, int8_t tab_spacing,
	unsigned int* tabs, bool pot,
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
			int nlines = build_textchain(work, cur, false, true);
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
		acc+1, norender, line_spacing, tab_spacing, tabs, pot, n_lines,
		lineheights, dw, dh, d_sz, maxw, maxh
	);
}

av_pixel* arcan_renderfun_renderfmtstr(const char* message,
	arcan_vobj_id dstore,
	int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, bool pot,
	unsigned int* n_lines, struct renderline_meta** lineheights,
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

	int chainlines = build_textchain(work, root, false, false);
	arcan_mem_free(work);

	if (chainlines > 0){
		raw = process_chain(root, arcan_video_getobject(dstore),
			chainlines, norender, line_spacing, tab_spacing,
			tabs, pot, n_lines, lineheights, dw, dh, d_sz,
			maxw, maxh
		);
	}

	return raw;
}

int arcan_renderfun_stretchblit(char* src, int inw, int inh,
	uint32_t* dst, size_t dstw, size_t dsth, int flipv)
{
	const int pack_tight = 0;
	const int rgba_ch = 4;

	if (1 == stbir_resize_uint8((unsigned char*)src, inw, inh, pack_tight,
		(unsigned char*)dst, dstw, dsth, pack_tight, rgba_ch)){

		if (flipv){
			uint32_t row[dstw];
			size_t stride = dstw * 4;
			for (size_t y = 0; y < dsth >> 1; y++){
				if (y == (dsth - 1 - y))
					continue;

				memcpy(row, &dst[y*dstw], stride);
				memcpy(&dst[y*dstw], &dst[(dsth-1-y)*dstw], stride);
				memcpy(&dst[(dsth-1-y)*dstw], row, stride);
			}
		}

		return 1;
	}
	return -1;
}
