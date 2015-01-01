/*
 * Copyright 2008-2015, Björn Ståhl
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
	char* identifier;
	uint8_t size;
	uint8_t usecount;
};

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

/* Simple font-cache */
static TTF_Font* grab_font(const char* fname, uint8_t size)
{
	int leasti = 0, i, leastv = -1;

	if (!fname)
		return NULL;

	for (i = 0; i < font_cache_size && font_cache[i].data != NULL; i++){
		if (font_cache[i].usecount < leastv){
			leasti = i;
			leastv = font_cache[i].usecount;
		}
		if (font_cache[i].size == size && strcmp(font_cache[i].identifier,
		fname) == 0){
			font_cache[i].usecount++;
			return font_cache[i].data;
		}
	}

/* try to load */
	TTF_Font* font = TTF_OpenFont(fname, size);
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

	font_cache[i].identifier = strdup(fname);
	font_cache[i].usecount++;
	font_cache[i].size = size;
	font_cache[i].data = font;

	return font;
}

void arcan_video_reset_fontcache()
{
	for (int i = 0; i < ARCAN_FONT_CACHE_LIMIT; i++)
		if (font_cache[i].data){
			TTF_CloseFont(font_cache[i].data);
			free(font_cache[i].identifier);
			memset(&font_cache[i], '\0', sizeof(font_cache[0]));
		}
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
	char* path = arcan_find_resource(
		infn, RESOURCE_SYS_FONT | RESOURCE_APPL_SHARED | RESOURCE_APPL );

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
	char* imgbuf;
	int inw, inh;

	arcan_errc rv = arcan_img_decode(infn, inmem.ptr, inmem.sz, &imgbuf,
		&inw, &inh, &meta, false, malloc);

/* stretchblit is assumed to deal with the edgecase of
 * w ^ h being 0 */
	if (cons.w > TEXT_EMBEDDEDICON_MAXW || inw > TEXT_EMBEDDEDICON_MAXW)
		cons.w = TEXT_EMBEDDEDICON_MAXW;

	if (cons.h > TEXT_EMBEDDEDICON_MAXH || inh > TEXT_EMBEDDEDICON_MAXH)
		cons.h = TEXT_EMBEDDEDICON_MAXH;

	arcan_release_map(inmem);
	arcan_release_resource(&inres);

	if (imgbuf && rv == ARCAN_OK){
		TTF_Surface* res = malloc(sizeof(TTF_Surface));
		res->bpp    = GL_PIXEL_BPP;

		if ((cons.w != 0 && cons.h != 0) && (inw != cons.w || inh != cons.h)){
			uint32_t* scalebuf = malloc(cons.w * cons.h * GL_PIXEL_BPP);
			arcan_renderfun_stretchblit(
				imgbuf, inw, inh, scalebuf, cons.w, cons.h, false);
			free(imgbuf);
			res->width  = cons.w;
			res->height = cons.h;
			res->data   = (char*) scalebuf;
		} else {
			res->width  = inw;
			res->height = inh;
			res->data   = imgbuf;
		}

		res->stride = res->width * GL_PIXEL_BPP;
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
			arcan_warning("Warning: arcan_video_renderstring(),"
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

/* find fontname vs fontsize separator */
	while (*base != ',') {
		if (*base == 0) {
			arcan_warning("Warning: arcan_video_renderstring(), couldn't scan font "
				"directive '%s (%s)'\n", fontbase, orig);
			return NULL;
		}
		base++;
	}
	*base++ = 0;

/* fontbase points to full fontname, find the size */
	numbase = base;
	while (*base != 0 && isdigit(*base))
	base++;

/* error state, no size specifier */
	if (numbase == base)
		arcan_warning("Warning: arcan_video_renderstring(), missing size argument "
			"in font specification (%s).\n", orig);
	else {
		char ch = *base;
		*base = 0;

/*
 * Security note, TTF is a complex format with a history of decoding
 * vulnerabilities. To lessen this it is wise not to let third parties
 * define what font is going to get executed. The lines below ALLOW
 * appl- specified local fonts and appl- specified shared fonts.
 * In more strict environments, this could be changed to only
 * RESOURCE_SYS_FONT or move font rendering / packing as a sandboxed
 * process.
 */
		char* fname = arcan_find_resource(fontbase, RESOURCE_SYS_FONT |
			RESOURCE_APPL | RESOURCE_APPL_SHARED);

		TTF_Font* font = NULL;
		if (!fname){
			arcan_warning("Warning: arcan_video_renderstring(), couldn't find "
				"font (%s) (%s)\n", fontbase, orig);
			return NULL;
		}
/* load font */
		else if ((font = grab_font(fname, strtoul(numbase, NULL, 10))) == NULL){
			free(fname);
			return NULL;
		}
		else
			prev->font = font;

		free(fname);
		*base = ch;
	}

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
		arcan_warning("Warning: arcan_video_renderstring(),"
		"	missing resource name.\n");
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
		arcan_warning("Warning: arcan_video_renderstring(), width scan failed,"
			" premature end in sized image scan directive (%s)\n", widbase);
		return NULL;
	}
	forcew = strtol(widbase, 0, 10);
	if (forcew <= 0 || forcew > 1024){
		arcan_warning("Warning: arcan_video_renderstring(), width scan failed,"
			" unreasonable width (%d) specified in sized image scan "
			"directive (%s)\n", forcew, widbase);
		return NULL;
	}

	char* hghtbase = base;
	while (*base && *base != ',' && isdigit(*base)) base++;
	if (*base && strlen(hghtbase) > 0)
		*base++ = 0;
	else {
		arcan_warning("Warning: arcan_video_renderstring(), height scan failed, "
			"premature end in sized image scan directive (%s)\n", hghtbase);
		return NULL;
	}
	forceh = strtol(hghtbase, 0, 10);
	if (forceh <= 0 || forceh > 1024){
		arcan_warning("Warning: arcan_video_renderstring(), height scan failed, "
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
		arcan_warning("Warning: arcan_video_renderstring(), missing resource name"
			" terminator (,) in sized image scan directive (%s)\n", wbase);
		return NULL;
	}

	if (strlen(wbase) > 0){
		prev->imgcons.w = forcew;
		prev->imgcons.h = forceh;
		prev->image = text_loadimage(wbase, prev->imgcons);
		if (prev->image){
			prev->imgcons.w = prev->image->width;
			prev->imgcons.h = prev->image->height;
		}

		return base;
	}
	else{
		arcan_warning("Warning: arcan_video_renderstring()"
		", missing resource name.\n");
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
			arcan_warning("Warning: arcan_video_renderstring(), "
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
			arcan_warning("Warning: arcan_video_renderstring()"
				", broken font specifier.\n");
		}

		if (!cnode->data.surf)
			arcan_warning("Warning: arcan_video_renderstring()"
			", couldn't render node.\n");
	}

/* just figure out the dimensions */
	else if (curr_style->font){
		TTF_SetFontStyle(curr_style->font, curr_style->style);
		TTF_SizeUTF8(curr_style->font, base, (int*) &cnode->width,
			(int*) &cnode->height);

/* load only if we don't have a dimension specifier */
		if (curr_style->imgcons.w && curr_style->imgcons.h){
			cnode->width = curr_style->imgcons.w;
			cnode->height = curr_style->imgcons.h;
		}
	}
}

/* a */
static int build_textchain(char* message, struct rcell* root, bool sizeonly)
{
	int rv = 0;
	struct text_format* curr_style = &last_style;
	curr_style->col.r = curr_style->col.g = curr_style->col.b = 0xff;
	curr_style->style = 0;

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
				if (msglen > 0) {
					*current = 0;
/* render surface and slide window */
					currstyle_cnode(curr_style, base, cnode, sizeonly);
					if (!curr_style->font) {
						arcan_warning("Warning: arcan_video_renderstring(),"
							" no font specified / found.\n");
						return -1;
					}

/* slide- alloc list of rendered blocks */
					cnode = cnode->next =
						arcan_alloc_mem(sizeof(struct rcell), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

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
					cnode->surface = false;
					rv += curr_style->newline;
					cnode->data.format.newline = curr_style->newline;
					cnode->data.format.tab = curr_style->tab;
					cnode->data.format.cr = curr_style->cr;
					cnode = cnode->next =
						arcan_alloc_mem(sizeof(struct rcell), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
				}

				if (curr_style->image){
					currstyle_cnode(curr_style, base, cnode, sizeonly);
					cnode = cnode->next =
						arcan_alloc_mem(sizeof(struct rcell), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
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

	cnode = cnode->next = arcan_alloc_mem(
		sizeof(struct rcell), ARCAN_MEM_VSTRUCT,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

	cnode->data.format.newline = 1;
	rv++;

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
 * tabs are messier still,
 * for each format segment, there may be 'tabc' number of tabsteps,
 * these concern only the current text block and are thus calculated
 * from a fixed offset.
 * */
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

void arcan_video_stringdimensions(const char* message, int8_t line_spacing,
	int8_t tab_spacing, unsigned* tabs, unsigned* maxw, unsigned* maxh)
{
	if (!message)
		return;

	/* (A) */
	int chainlines;
	struct rcell root = {.surface = false};
	char* work = strdup(message);
	last_style.newline = 0;
	last_style.tab = 0;
	last_style.cr = false;

	if ((chainlines = build_textchain(work, &root, true)) > 0) {
		struct rcell* cnode = &root;
		*maxw = 0;
		*maxh = 0;

		int lineh = 0;
		int curw = 0;

		while (cnode) {
			if (cnode->width > 0) {
				if (cnode->height > lineh + line_spacing)
					lineh = cnode->height;

				curw += cnode->width;
			}
			else {
				if (cnode->data.format.cr)
					curw = 0;

				if (cnode->data.format.tab)
					curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

				if (cnode->data.format.newline > 0)
					for (int i = cnode->data.format.newline; i > 0; i--) {
						*maxh += lineh + line_spacing;
						lineh = 0;
					}
			}

			if (curw > *maxw)
				*maxw = curw;

			cnode = cnode->next;
		}
	}

	struct rcell* current = root.next;

	while (current){
		struct rcell* prev = current;
		current = current->next;
		prev->next = (void*) 0xdeadbeef;
		free(prev);
	}

	free(work);
}

/* assumes surf dimensions fit within dst without clipping */
static inline void copy_rect(TTF_Surface* surf, uint32_t* dst,
	int pitch, int x, int y)
{
	uint32_t* wrk = (uint32_t*) surf->data;

	for (int row = 0; row < surf->height; row++)
		memcpy( &dst[ (y + row) * pitch + x],
			&wrk[row * surf->width], surf->width * 4);
}

void* arcan_renderfun_renderfmtstr(const char* message,
	int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, bool pot,
	unsigned int* n_lines, unsigned int** lineheights,
	size_t* dw, size_t* dh, uint32_t* d_sz,
	size_t* maxw, size_t* maxh)
{
	if (!message)
		return NULL;

	uint32_t* raw = NULL;

/* (A) parse format string and build chains of renderblocks */
	int chainlines;
	struct rcell* root = arcan_alloc_mem(sizeof(struct rcell),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_NATURAL);

	char* work = strdup(message);
	last_style.newline = 0;
	last_style.tab = 0;
	last_style.cr = false;

	if ((chainlines = build_textchain(work, root, false)) > 0) {
/* (B) traverse the renderblocks and figure out constraints*/
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

		while (cnode) {
			if (cnode->surface) {
				assert(cnode->data.surf != NULL);
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

/* (C) render into destination buffers */
		*dw = pot ? nexthigher(*maxw) : *maxw;
		*dh = pot ? nexthigher(*maxh) : *maxh;

		*d_sz = *dw * *dh * GL_PIXEL_BPP;

		raw = arcan_alloc_mem(*d_sz, ARCAN_MEM_VBUFFER,
			ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

		memset(raw, '\0', *d_sz);

		if (!raw)
			goto cleanup;

		cnode = root;
		curw = 0;
		int line = 0;

		while (cnode) {
			if (cnode->surface) {
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
	}

	struct rcell* current;

cleanup:
	current = root;
	while (current){
		assert(current != (void*) 0xdeadbeef);
		if (current->surface && current->data.surf)
			arcan_mem_free(current->data.surf);

		struct rcell* prev = current;
		current = current->next;
		prev->next = (void*) 0xdeadbeef;
		arcan_mem_free(prev);
	}

	arcan_mem_free(work);
	return raw;
}

/*
 * Stripped down version of SDL rotozoomer, only RGBA<->RGBA upscale
 * this should -- really -- be replaced with something.. clean.
 */

/*
Copyright (C) 2001-2011  Andreas Schiffler

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

   1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.

   2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.

   3. This notice may not be removed or altered from any source
   distribution.

Andreas Schiffler -- aschiffler at ferzkopp dot net

*/

typedef struct tColorRGBA {
	uint8_t r;
	uint8_t g;
	uint8_t b;
	uint8_t a;
} tColorRGBA;

typedef struct tColorY {
	uint8_t y;
} tColorY;

int arcan_renderfun_stretchblit(char* src, int inw, int inh,
	uint32_t* dst, size_t dstw, size_t dsth, int flipy)
{
	int x, y, sx, sy, ssx, ssy, *sax, *say, *csax, *csay, *salast;
	int csx, csy, ex, ey, cx, cy, sstep, sstepx, sstepy;

	tColorRGBA *c00, *c01, *c10, *c11;
	tColorRGBA *sp, *csp, *dp;

	int spixelgap, spixelw, spixelh, dgap, t1, t2;

	if ((sax = arcan_alloc_mem((dstw + 1) * sizeof(uint32_t) * 2,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL | ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_PAGE)) == NULL)
		return -1;

	if ((say = arcan_alloc_mem((dstw + 1) * sizeof(uint32_t) * 2,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL | ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_PAGE)) == NULL){
		arcan_mem_free(say);
		return -1;
	}

	spixelw = (inw - 1);
	spixelh = (inh - 1);
	sx = (int) (65536.0 * (float) spixelw / (float) (dstw - 1));
	sy = (int) (65536.0 * (float) spixelh / (float) (dsth - 1));

/* Maximum scaled source size */
	ssx = (inw << 16) - 1;
	ssy = (inh << 16) - 1;

/* Precalculate horizontal row increments */
	csx = 0;
	csax = sax;
	for (x = 0; x <= dstw; x++) {
		*csax = csx;
		csax++;
		csx += sx;

/* Guard from overflows */
		if (csx > ssx) {
			csx = ssx;
		}
	}

/* Precalculate vertical row increments */
	csy = 0;
	csay = say;
	for (y = 0; y <= dsth; y++) {
		*csay = csy;
		csay++;
		csy += sy;

/* Guard from overflows */
		if (csy > ssy) {
			csy = ssy;
		}
	}

	sp = (tColorRGBA *) src;
	dp = (tColorRGBA *) dst;

	dgap = 0;
	spixelgap = inw;

	if (flipy)
		sp += (spixelgap * spixelh);

	csay = say;
	for (y = 0; y < dsth; y++) {
		csp = sp;
		csax = sax;
		for (x = 0; x < dstw; x++) {
			ex = (*csax & 0xffff);
			ey = (*csay & 0xffff);
			cx = (*csax >> 16);
			cy = (*csay >> 16);
			sstepx = cx < spixelw;
			sstepy = cy < spixelh;
			c00 = sp;
			c01 = sp;
			c10 = sp;

			if (sstepy) {
				if (flipy) {
				c10 -= spixelgap;
 			} else {
				c10 += spixelgap;
 				}
 			}

			c11 = c10;
			if (sstepx) {
				c01++;
				c11++;
			 }

			t1 = ((((c01->r - c00->r) * ex) >> 16) + c00->r) & 0xff;
			t2 = ((((c11->r - c10->r) * ex) >> 16) + c10->r) & 0xff;
			dp->r = (((t2 - t1) * ey) >> 16) + t1;
			t1 = ((((c01->g - c00->g) * ex) >> 16) + c00->g) & 0xff;
			t2 = ((((c11->g - c10->g) * ex) >> 16) + c10->g) & 0xff;
			dp->g = (((t2 - t1) * ey) >> 16) + t1;
			t1 = ((((c01->b - c00->b) * ex) >> 16) + c00->b) & 0xff;
			t2 = ((((c11->b - c10->b) * ex) >> 16) + c10->b) & 0xff;
			dp->b = (((t2 - t1) * ey) >> 16) + t1;
			t1 = ((((c01->a - c00->a) * ex) >> 16) + c00->a) & 0xff;
			t2 = ((((c11->a - c10->a) * ex) >> 16) + c10->a) & 0xff;
			dp->a = (((t2 - t1) * ey) >> 16) + t1;

			salast = csax;
			csax++;
			sstep = (*csax >> 16) - (*salast >> 16);
			sp += sstep;

			dp++;
		}

		salast = csay;
		csay++;
		sstep = (*csay >> 16) - (*salast >> 16);
		sstep *= spixelgap;
		if (flipy) {
			 sp = csp - sstep;
		} else {
			sp = csp + sstep;
		}

		dp = (tColorRGBA *) ((uint8_t *) dp + dgap);
	}

	arcan_mem_free(sax);
	arcan_mem_free(say);

	return 0;
}
