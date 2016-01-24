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

struct text_format {
/* font specification */
	TTF_Font* font;
	TTF_Color col;
	int style;
	uint8_t alpha;

/* for forced loading of images */
	TTF_Surface* image;
	img_cons imgcons;

/* pointer into line of text where the format was extracted,
 * only temporary use */
	char* endofs;

/* whitespace management */
	bool cr;
	uint8_t tab;
	uint8_t newline;
};

struct font_entry {
	TTF_Font* data;
	file_handle fd;
	char* identifier;
	size_t size;
	uint8_t usecount;
};

static int default_hint = TTF_HINTING_NORMAL;

static struct text_format last_style = {
	.col = {.r = 0xff, .g = 0xff, .b = 0xff}
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

	union {
		TTF_Surface* surf;

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
		*fd = font_cache[0].fd;

	if (pt_sz)
		*pt_sz = font_cache[0].size;

	if (hint)
		*hint = default_hint;
}

/* Simple LRU font cache */
static TTF_Font* grab_font(const char* fname, size_t size)
{
	int leasti = 1, i, leastv = -1;
	TTF_Font* font;

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

		if (!arcan_video_defaultfont(fname, fd, size, 2))
			close(fd);
	}

/* match / track */
	file_handle matchfd = BADFD;
	for (i = 0; i < font_cache_size && font_cache[i].data != NULL; i++){
		if (i && font_cache[i].usecount < leastv &&
			font_cache[i].data != last_style.font){
			leasti = i;
			leastv = font_cache[i].usecount;
		}

		if (strcmp(font_cache[i].identifier, fname) == 0){
			if (font_cache[i].fd != BADFD){
				matchfd = font_cache[i].fd;
			}

			if (font_cache[i].size == size){
				font_cache[i].usecount++;
				font = font_cache[i].data;
				goto done;
			}
		}
	}

/* try to load */
	font = matchfd != BADFD ?
		TTF_OpenFontFD(matchfd, size) : TTF_OpenFont(fname, size);

	if (!font){
		arcan_warning("grab_font(), Open Font (%s,%d) failed\n", fname, size);
		return NULL;
	}

/* replace? */
	if (i == font_cache_size){
		i = leasti;
		free(font_cache[leasti].identifier);
		TTF_CloseFont(font_cache[leasti].data);
	}

/* update counters */
	font_cache[i].identifier = strdup(fname);
	font_cache[i].usecount++;
	font_cache[i].size = size;
	font_cache[i].data = font;

done:
	TTF_SetFontHinting(font, default_hint);
	return font;
}

static void zap_slot(int i)
{
	if (font_cache[i].fd != BADFD && font_cache[i].fd){
		close(font_cache[i].fd);
		font_cache[i].fd = BADFD;
	}

	if (font_cache[i].data){
		TTF_CloseFont(font_cache[i].data);
		free(font_cache[i].identifier);
		memset(&font_cache[i], '\0', sizeof(font_cache[0]));
	}
}

bool arcan_video_defaultfont(const char* ident,
	file_handle fd, int sz, int hint)
{
	if (BADFD == fd)
		return false;

/* try to load */
	TTF_Font* font = TTF_OpenFontFD(fd, sz);
	if (!font)
		return false;

	if (-1 != default_hint)
		default_hint = hint;

	zap_slot(0);

	font_cache[0].identifier = strdup(ident);
	font_cache[0].size = sz;
	font_cache[0].data = font;
	font_cache[0].fd = fd;

	last_style.font = font;

	return true;
}

void arcan_video_reset_fontcache()
{
	static bool init;
	if (!init){
		init = true;
		for (int i = 0; i < ARCAN_FONT_CACHE_LIMIT; i++)
			font_cache[i].fd = BADFD;
	}
	else
		for (int i = 0; i < ARCAN_FONT_CACHE_LIMIT; i++)
			zap_slot(i);
}

#ifndef TEXT_EMBEDDEDICON_MAXW
#define TEXT_EMBEDDEDICON_MAXW 256
#endif

#ifndef TEXT_EMBEDDEDICON_MAXH
#define TEXT_EMBEDDEDICON_MAXH 256
#endif

#ifndef RENDERFUN_NOSUBIMAGE
TTF_Surface* text_loadimage(const char* const infn, img_cons cons)
{
	char* path = arcan_find_resource(infn,
		RESOURCE_SYS_FONT | RESOURCE_APPL_SHARED | RESOURCE_APPL, ARES_FILE);

	data_source inres = arcan_open_resource(path);

	free(path);
	if (inres.fd == BADFD)
		return NULL;

	map_region inmem = arcan_map_resource(&inres, false);
	if (inmem.ptr == NULL){
		arcan_release_resource(&inres);
		return NULL;
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
		TTF_Surface* res = malloc(sizeof(TTF_Surface));
		res->bpp = sizeof(av_pixel);

		if ((cons.w != 0 && cons.h != 0) && (inw != cons.w || inh != cons.h)){
			uint32_t* scalebuf = malloc(cons.w * cons.h * sizeof(av_pixel));
			arcan_renderfun_stretchblit(
				(char*)imgbuf, inw, inh, scalebuf, cons.w, cons.h, false);
			arcan_mem_free(imgbuf);
			res->width  = cons.w;
			res->height = cons.h;
			res->data = (char*) scalebuf;
		}
		else {
			res->width  = inw;
			res->height = inh;
			res->data = (char*) imgbuf;
		}

		res->stride = res->width * sizeof(av_pixel);
		return res;
	}

	return NULL;
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
	prev->col.r = strtol(cbuf, 0, 16);

	cbuf[0] = *(base - 4); cbuf[1] = *(base - 3); cbuf[2] = 0;
	prev->col.g = strtol(cbuf, 0, 16);

	cbuf[0] = *(base - 2); cbuf[1] = *(base - 1); cbuf[2] = 0;
	prev->col.b = strtol(cbuf, 0, 16);

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

	TTF_Font* font = NULL;
	int font_sz = strtoul(numbase, NULL, 10);
	if (relsign != 0 || font_sz == 0)
		font_sz = font_cache[0].size + relsign * font_sz;

/*
 * use current 'default-font' if just size is provided
 */
	if (*fontbase == '\0'){
		font = grab_font(NULL, font_sz);
		*base = ch;
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
		prev->font = font;

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
		prev->image = text_loadimage(wbase, prev->imgcons);

		if (prev->image){
			prev->imgcons.w = prev->image->width;
			prev->imgcons.h = prev->image->height;
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
		prev->image = text_loadimage(wbase, prev->imgcons);

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

static inline void currstyle_cnode(struct text_format* curr_style,
	const char* const base, struct rcell* cnode, bool sizeonly)
{
	if (!sizeonly){
		cnode->surface = true;

/* image or render font */
		if (curr_style->image){
			cnode->data.surf = curr_style->image;
			curr_style->image = NULL;
		}
		else if (curr_style->font){
			TTF_SetFontStyle(curr_style->font, curr_style->style);
			cnode->data.surf = TTF_RenderUTF8(curr_style->font,base,curr_style->col);
		}
		else{
			arcan_warning("arcan_video_renderstring(), broken font specifier.\n");
			goto reset;
		}

		if (!cnode->data.surf){
			arcan_warning("arcan_video_renderstring(), couldn't render node.\n");
			goto reset;
		}
	}

/* just figure out the dimensions */
	else if (curr_style->font){
		int dw, dh;
		TTF_SetFontStyle(curr_style->font, curr_style->style);
		TTF_SizeUTF8(curr_style->font, base, &dw, &dh);
		cnode->width = dw;
		cnode->height = dh;

/* load only if we don't have a dimension specifier */
		if (curr_style->imgcons.w && curr_style->imgcons.h){
			cnode->width = curr_style->imgcons.w;
			cnode->height = curr_style->imgcons.h;
		}
	}

	return;
reset:
	last_style.newline = 0;
	last_style.tab = 0;
	last_style.cr = false;
	last_style.font = font_cache[0].data;
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
	struct text_format* curr_style = &last_style;
/* curr_style->col.r = curr_style->col.g = curr_style->col.b = 0xff;
	curr_style->style = 0; */

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

				if (curr_style->image){
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
			TTF_SetFontStyle(curr_style->font, curr_style->style);
			TTF_SizeUTF8(curr_style->font, base, (int*) &cnode->width,
				(int*) &cnode->height);
		}
		else{
			cnode->surface = true;
			TTF_SetFontStyle(curr_style->font, curr_style->style);
			cnode->data.surf = TTF_RenderUTF8(curr_style->font, base,
				curr_style->col);
		}
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
 * be mostly replaced/complemented with a mix of in-place rendering and
 * proper packing and vertex buffers in 0.6 or 0.5.1 dso just leave it like this
 */
static inline void copy_rect(TTF_Surface* surf, av_pixel* dst,
	int width, int x, int y)
{
	uint32_t* wrk = (uint32_t*) surf->data;
	if (sizeof(av_pixel) != 4){
		for (size_t row = 0; row < surf->height; row++)
			for (size_t col = 0; col < surf->width; col++){
				uint32_t pack = wrk[row * surf->width + col];
				dst[(row + y) * width + x + col] = RGBA(
					(pack & 0x000000ff), (pack & 0x0000ff00) >> 8,
					(pack & 0x00ff0000) >> 16, (pack & 0xff000000) >> 24);
			}
	}
	else
		for (int row = 0; row < surf->height; row++)
			memcpy( &dst[ (y + row) * width + x],
				&wrk[row * surf->width], surf->width * 4);
}

static void cleanup_chain(struct rcell* root)
{
	while (root){
		assert(root != (void*) 0xdeadbeef);
		if (root->surface && root->data.surf)
			arcan_mem_free(root->data.surf);

		struct rcell* prev = root;
		root = root->next;
		prev->next = (void*) 0xdeadbeef;
		arcan_mem_free(prev);
	}
}

static av_pixel* process_chain(struct rcell* root, arcan_vobject* dst,
	size_t chainlines, bool norender,
	int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, bool pot,
	unsigned int* n_lines, unsigned int** lineheights, size_t* dw,
	size_t* dh, uint32_t* d_sz, size_t* maxw, size_t* maxh)
{
	struct rcell* cnode = root;
	unsigned int linecount = 0;
	*maxw = 0;
	*maxh = 0;
	int lineh = 0;
	int curw = 0;

/* note, linecount is overflow */
	unsigned int* lines = arcan_alloc_mem(sizeof(unsigned) * (chainlines + 1),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_NATURAL
	);

/* (A) figure out visual constraints */
	while (cnode) {
		if (cnode->surface && cnode->data.surf) {
			if (cnode->data.surf->height > lineh + line_spacing)
				lineh = cnode->data.surf->height;

			curw += cnode->data.surf->width;
		}
		else {
			if (cnode->data.format.cr)
				curw = 0;

			if (cnode->data.format.tab)
				curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

			if (cnode->data.format.newline > 0)
				for (int i = cnode->data.format.newline; i > 0; i--) {
					lines[linecount++] = *maxh;
					*maxh += lineh + line_spacing;
					lineh = 0;
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
		if (cnode->surface && cnode->data.surf) {
			copy_rect(cnode->data.surf, raw, *dw, curw, lines[line]);
			curw += cnode->data.surf->width;
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
	unsigned int* n_lines, unsigned int** lineheights, size_t* dw,
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
	unsigned int* n_lines, unsigned int** lineheights,
	size_t* dw, size_t* dh, uint32_t* d_sz,
	size_t* maxw, size_t* maxh, bool norender)
{
	if (!message)
		return NULL;

	av_pixel* raw = NULL;

/* (A) parse format string and build chains of renderblocks */
	struct rcell* root = arcan_alloc_mem(sizeof(struct rcell),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_NATURAL);

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
