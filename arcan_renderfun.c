/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <stddef.h>
#include <math.h>
#include <assert.h>

#ifndef ARCAN_FONT_CACHE_LIMIT
#define ARCAN_FONT_CACHE_LIMIT 8
#endif

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_opengl.h>
#include <SDL_ttf.h>
#include <SDL_byteorder.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

struct text_format {
/* font specification */
	TTF_Font* font;
	SDL_Color col;
	int style;
	uint8_t alpha;

/* for forced loading of images */
	SDL_Surface* image;
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
static struct font_entry font_cache[ARCAN_FONT_CACHE_LIMIT] = {0};

/*
 * This one is a mess,
 * (a) begin by splitting the input string into a linked list of data elements.
 * each element can EITHER modfiy to current cursor position OR represent a rendered surface.

 * (b) take the linked list, sweep through it and figure out which dimensions it requires,
 * allocate a corresponding storage object.

 * (c) sweep the list yet again, render to the storage object.
*/

// TTF_FontHeight sets line-spacing.
struct rcell {
	bool surface;
	unsigned int width;
	unsigned int height;

	union {
		SDL_Surface* surf;

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
	int leasti = 0, i;
	const int nchannels_rgba = 4;

	if (!fname || !arcan_video_display.text_support)
		return NULL;

	for (i = 0; i < font_cache_size; i++) {
		/* (a) no need to look further, either empty slot or no font found. */
		if (font_cache[i].data == NULL)
			break;
		if (strcmp(fname, font_cache[i].identifier) == 0 &&
		        font_cache[i].size == size) {
			font_cache[i].usecount++;
			return font_cache[i].data;
		}

		if (font_cache[i].usecount < font_cache[leasti].usecount)
			leasti = i;
	}

	/* (b) no match, no empty slot. */
	if (font_cache[i].data != NULL) {
		free(font_cache[leasti].identifier);
		TTF_CloseFont(font_cache[leasti].data);
	}
	else
		i = leasti;

	/* load in new font */
	font_cache[i].data = TTF_OpenFont(fname, size);
	font_cache[i].identifier = strdup(fname);
	font_cache[i].usecount = 1;
	font_cache[i].size = size;

	return font_cache[i].data;
}

SDL_Surface* text_loadimage(const char* const infn, img_cons constraints)
{
	SDL_Surface* res = NULL;
	char* fname = arcan_find_resource(infn, ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME);	
	
	if (fname && (res = IMG_Load(fname) )){
/* Might've specified a forced scale */
		if (constraints.w > 0 && constraints.h > 0){
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
			SDL_Surface* stretchcanv = SDL_CreateRGBSurface(SDL_SWSURFACE, constraints.w, constraints.h, 32, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
#else
			SDL_Surface* stretchcanv = SDL_CreateRGBSurface(SDL_SWSURFACE, constraints.w, constraints.h, 32, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
#endif

/* Can't allocate intermediate buffers? cleanup */
			if (!stretchcanv){
				arcan_warning("Warning: arcan_video_renderstring(), couldn't create intermediate stretchblit buffers, poor dimensions? (%d, %d)\n", res->w, res->h);

				if (stretchcanv) SDL_FreeSurface(stretchcanv);
				free(fname);
				return NULL;
			}

/* convert colourspace */
			SDL_Surface* basecanv = SDL_ConvertSurface(res, stretchcanv->format, SDL_SWSURFACE);
			SDL_FreeSurface(res);
			if (!basecanv){
				arcan_warning("Warning: arcan_video_renderstring(9, couldn't perform colorspace conversion.\n");
				SDL_FreeSurface(stretchcanv);
				free(fname);
				return NULL;
			}

			stretchblit(basecanv, stretchcanv->pixels, constraints.w, constraints.h, constraints.w * 4, false);
			SDL_FreeSurface(basecanv);
			
			res = stretchcanv;
		}
	}
	else
		arcan_warning("Warning: arcan_video_renderstring(), couldn't render image (IMG_Load failed on %s)\n", fname ? fname : infn);
	

	if (res)
		SDL_SetAlpha(res, 0, SDL_ALPHA_TRANSPARENT);

	free(fname);
	return res;
}

static char* extract_color(struct text_format* prev, char* base){
	char cbuf[3];

/* scan 6 characters to the right, check for valid hex */
	for (int i = 0; i < 6; i++) {
		if (!isxdigit(*base++)){
			arcan_warning("Warning: arcan_video_renderstring(), couldn't scan font colour directive (#rrggbb, 0-9, a-f)\n");
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
			arcan_warning("Warning: arcan_video_renderstring(), couldn't scan font directive '%s (%s)'\n", fontbase, orig);
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
		arcan_warning("Warning: arcan_video_renderstring(), missing size argument in font specification (%s).\n", orig);
	else {
		char ch = *base;
		*base = 0;

/* resolve resource */
		char* fname = arcan_find_resource(fontbase, ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME);
		TTF_Font* font = NULL;
		if (!fname){
			arcan_warning("Warning: arcan_video_renderstring(), couldn't find font (%s) (%s)\n", fontbase, orig);
			return NULL;
		}
/* load font */
		else if ((font = grab_font(fname, strtoul(numbase, NULL, 10))) == NULL){
			arcan_warning("Warning: arcan_video_renderstring(), couldn't open font (%s) (%s)\n", fname, orig);
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

static char* extract_image_simple(struct text_format* prev, char* base){
	char* wbase = base;

	while (*base && *base != ',') base++;
	if (*base) 
		*base++ = 0;
	
	if (strlen(wbase) > 0){
		prev->imgcons.w = prev->imgcons.h = 0;
		prev->image = text_loadimage(wbase, prev->imgcons);
		if (prev->image){
			prev->imgcons.w = prev->image->w;
			prev->imgcons.h = prev->image->h;
		}
		
		return base;
	}
	else{
		arcan_warning("Warning: arcan_video_renderstring(), missing resource name.\n");
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
		arcan_warning("Warning: arcan_video_renderstring(), width scan failed, premature end in sized image scan directive (%s)\n", widbase);
		return NULL;
	}
	forcew = strtol(widbase, 0, 10);
	if (forcew <= 0 || forcew > 1024){
		arcan_warning("Warning: arcan_video_renderstring(), width scan failed, unreasonable width (%d) specified in sized image scan directive (%s)\n", forcew, widbase);
		return NULL;
	}
	
	char* hghtbase = base;
	while (*base && *base != ',' && isdigit(*base)) base++;
	if (*base && strlen(hghtbase) > 0)
		*base++ = 0;
	else {
		arcan_warning("Warning: arcan_video_renderstring(), height scan failed, premature end in sized image scan directive (%s)\n", hghtbase);
		return NULL;
	}
	forceh = strtol(hghtbase, 0, 10);
	if (forceh <= 0 || forceh > 1024){
		arcan_warning("Warning: arcan_video_renderstring(), height scan failed, unreasonable height (%d) specified in sized image scan directive (%s)\n", forceh, hghtbase);
		return NULL;
	}

	char* wbase = base;
	while (*base && *base != ',') base++;
	if (*base == ','){
		*base++ = 0;
	}
	else {
		arcan_warning("Warning: arcan_video_renderstring(), missing resource name terminator (,) in sized image scan directive (%s)\n", wbase);
		return NULL;
	}
	
	if (strlen(wbase) > 0){
		prev->imgcons.w = forcew;
		prev->imgcons.h = forceh;
		prev->image = text_loadimage(wbase, prev->imgcons);
		if (prev->image){
			prev->imgcons.w = prev->image->w;
			prev->imgcons.h = prev->image->h;
		}
		
		return base;
	}
	else{
		arcan_warning("Warning: arcan_video_renderstring(), missing resource name.\n");
		return NULL;
	}
}

static struct text_format formatend(char* base, struct text_format prev, char* orig, bool* ok) {
	struct text_format failed = {0};
	prev.newline = prev.tab = prev.cr = 0; /* don't carry caret modifiers */
	bool inv = false;
	while (*base) {
/* skip whitespace */
		if (isspace(*base)) { base++; continue; }

/* out of formatstring */
		if (*base != '\\') { prev.endofs = base; break; }

/* all the supported formatting characters;
 * b = bold, i = italic, u = underline, n = newline, r = carriage return, t = tab
 * ! = inverse (bold,italic,underline), #rrggbb = setcolor, fpath,size = setfont,
 * Pwidth,height,fname(, or NULL) extract 
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
			case 'u': prev.style = (inv ? prev.style & TTF_STYLE_UNDERLINE : prev.style | TTF_STYLE_UNDERLINE); break;
			case 'b': prev.style = (inv ? prev.style & !TTF_STYLE_BOLD : prev.style | TTF_STYLE_BOLD); break;
			case 'i': prev.style = (inv ? prev.style & !TTF_STYLE_ITALIC : prev.style | TTF_STYLE_ITALIC); break;
			case 'p': base = extract_image_simple(&prev, base); break;
			case 'P': base = extract_image(&prev, base); break;
			case '#': base = extract_color(&prev, base); break;
			case 'f': base = extract_font(&prev, base); break;

			default:
				arcan_warning("Warning: arcan_video_renderstring(), unknown escape sequence: '\\%c' (%s)\n", *(base+1), orig);
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


static inline void currstyle_cnode(struct text_format* curr_style, const char* const base, struct rcell* cnode, bool sizeonly)
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
			cnode->data.surf = TTF_RenderUTF8_Blended(curr_style->font, base, curr_style->col);
		}
		else{
			arcan_warning("Warning: arcan_video_renderstring(), broken font specifier.\n");
		}

		if (!cnode->data.surf)
			arcan_warning("Warning: arcan_video_renderstring(), couldn't render text, possible reason: %s\n", TTF_GetError());
		else 
			SDL_SetAlpha(cnode->data.surf, 0, SDL_ALPHA_TRANSPARENT);
	}

/* just figure out the dimensions */
	else {
		TTF_SetFontStyle(curr_style->font, curr_style->style);
		TTF_SizeUTF8(curr_style->font, base, (int*) &cnode->width, (int*) &cnode->height);
		
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
				memmove(current, current+1, strlen(current)+1);
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
						arcan_warning("Warning: arcan_video_renderstring(), no font specified / found.\n");
						return -1;
					}

/* slide- alloc list of rendered blocks */
					cnode = cnode->next = (struct rcell*) calloc(sizeof(struct rcell), 1);
					*current = '\\';
				}

/* scan format- options and slide to end */
				bool okstatus;
				*curr_style = formatend(current, *curr_style, message, &okstatus);
				if (!okstatus)
					return -1;

/* caret modifiers need to be separately chained to avoid (three?) nasty little basecases */
				if (curr_style->newline || curr_style->tab || curr_style->cr) {
					cnode->surface = false;
					rv += curr_style->newline;
					cnode->data.format.newline = curr_style->newline;
					cnode->data.format.tab = curr_style->tab;
					cnode->data.format.cr = curr_style->cr;
					cnode = cnode->next = (void*) calloc(sizeof(struct rcell), 1);
				} 

				if (curr_style->image){
					currstyle_cnode(curr_style, base, cnode, sizeonly);
					cnode = cnode->next = (struct rcell*) calloc(sizeof(struct rcell), 1);
				}

				current = base = curr_style->endofs;
				if (current == NULL)
					return -1; /* note, may this be a condition for a break rather than a return? */

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
			TTF_SizeUTF8(curr_style->font, base, (int*) &cnode->width, (int*) &cnode->height);
		}
		else{
			cnode->surface = true;
			TTF_SetFontStyle(curr_style->font, curr_style->style);
			cnode->data.surf = TTF_RenderUTF8_Blended(curr_style->font, base, curr_style->col);
			SDL_SetAlpha(cnode->data.surf, 0, SDL_ALPHA_TRANSPARENT);
		}
	}

	cnode = cnode->next = (void*) calloc(sizeof(struct rcell), 1);
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

/* tabs are messier still,
 * for each format segment, there may be 'tabc' number of tabsteps,
 * these concern only the current text block and are thus calculated from a fixed offset. */
static unsigned int get_tabofs(int offset, int tabc, int8_t tab_spacing, unsigned int* tabs)
{
	if (!tabs || *tabs == 0) /* tabc will always be >= 1 */
		return tab_spacing ? round_mult(offset, tab_spacing) + ((tabc - 1) * tab_spacing) : offset;

	unsigned int lastofs = offset;

	/* find last matching tab pos first */
	while (*tabs && *tabs < offset)
		lastofs = *tabs++;

	/* matching tab found */
	if (*tabs) {
		offset = *tabs;
		tabc--;
	}

	while (tabc--) {
		if (*tabs)
			offset = *tabs++;
		else
			offset += round_mult(offset, tab_spacing); /* out of defined tabs, pad with default spacing */

	}

	return offset;
}

static void dumptchain(struct rcell* node)
{
	int count = 0;

	while (node) {
		if (node->surface) {
			printf("[%i] image surface\n", count++);
		}
		else {
			printf("[%i] format (%i lines, %i tabs, %i cr)\n", count++, node->data.format.newline, node->data.format.tab, node->data.format.cr);
		}
		node = node->next;
	}
}

void arcan_video_stringdimensions(const char* message, int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, unsigned int* maxw, unsigned int* maxh)
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
		unsigned int linecount = 0;
		bool flushed = false;
		*maxw = 0;
		*maxh = 0;
		
		int lineh = 0;
		int curw = 0;
		int curh = 0;
		
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
	
/* note: currently does not obey restrictions placed on texturemode (i.e. everything is padded to power of two and txco hacked) */
arcan_vobj_id arcan_video_renderstring(const char* message, int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, unsigned int* n_lines, unsigned int** lineheights)
{
	arcan_vobj_id rv = ARCAN_EID;
	if (!message)
		return rv;
	
/* (A) */
	int chainlines;
	struct rcell* root = calloc( sizeof(struct rcell), 1);
	
	char* work = strdup(message);
	last_style.newline = 0;
	last_style.tab = 0;
	last_style.cr = false;

	if ((chainlines = build_textchain(work, root, false)) > 0) {
		/* (B) */
		/*		dumptchain(&root); */
		struct rcell* cnode = root;
		unsigned int linecount = 0;
		bool flushed = false;
		int maxw = 0;
		int maxh = 0;
		int lineh = 0;
		int curw = 0;
		int curh = 0;
		/* note, linecount is overflow */
		unsigned int* lines = (unsigned int*) calloc(sizeof(unsigned int), chainlines + 1);
		unsigned int* curr_line = lines;

		while (cnode) {
			if (cnode->surface) {
				assert(cnode->data.surf != NULL);
				if (cnode->data.surf->h > lineh + line_spacing)
					lineh = cnode->data.surf->h;

				curw += cnode->data.surf->w;
			}
			else {
				if (cnode->data.format.cr)
					curw = 0;

				if (cnode->data.format.tab)
					curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

				if (cnode->data.format.newline > 0)
					for (int i = cnode->data.format.newline; i > 0; i--) {
						lines[linecount++] = maxh;
						maxh += lineh + line_spacing;
						lineh = 0;
					}
			}

			if (curw > maxw)
				maxw = curw;

			cnode = cnode->next;
		}
		
		/* (C) */
		/* prepare structures */
		arcan_vobject* vobj = arcan_video_newvobject(&rv);
		if (!vobj){
			arcan_fatal("Fatal: arcan_video_renderstring(), couldn't allocate video object. Out of Memory or out of IDs in current context. There is likely a resource leak in the scripts of the current theme.\n");
		}

		int storw = nexthigher(maxw);
		int storh = nexthigher(maxh);
		vobj->gl_storage.w = storw;
		vobj->gl_storage.h = storh;
		vobj->default_frame.s_raw = storw * storh * 4;
		vobj->default_frame.raw = (uint8_t*) calloc(vobj->default_frame.s_raw, 1);
		vobj->feed.state.tag = ARCAN_TAG_TEXT;
		vobj->blendmode = blend_force;
		vobj->origw = maxw;
		vobj->origh = maxh;
		glGenTextures(1, &vobj->gl_storage.glid);
		glBindTexture(GL_TEXTURE_2D, vobj->gl_storage.glid);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

		/* find dimensions and cleanup */
		cnode = root;
		curw = 0;
		int yofs = 0;

		SDL_Surface* canvas =
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
		    SDL_CreateRGBSurface(SDL_SWSURFACE, storw, storh, 32, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
#else
		    SDL_CreateRGBSurface(SDL_SWSURFACE, storw, storh, 32, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
#endif
		if (canvas == NULL)
			arcan_fatal("Fatal: arcan_video_renderstring(); couldn't build canvas.\n\t Input string (%d x %d) is probably unreasonably large wide (len: %zi curw: %i)\n", storw, storh, strlen(message), curw);

		int line = 0;

		while (cnode) {
			if (cnode->surface) {
				SDL_Rect dstrect = {.x = curw, .y = lines[line]};
				SDL_BlitSurface(cnode->data.surf, 0, canvas, &dstrect);
				curw += cnode->data.surf->w;
			}
			else {
				if (cnode->data.format.tab > 0)
					curw = get_tabofs(curw, cnode->data.format.tab, tab_spacing, tabs);

				if (cnode->data.format.cr)
					curw = 0;

				if (cnode->data.format.newline > 0) {
					line += cnode->data.format.newline;
				}
			}
			
			cnode = cnode->next;
		}
	
	/* upload */
		memcpy(vobj->default_frame.raw, canvas->pixels, canvas->w * canvas->h * 4);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_PIXEL_FORMAT, canvas->w, canvas->h, 0, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, vobj->default_frame.raw);
		glBindTexture(GL_TEXTURE_2D, 0);

		float wv = (float)maxw / (float)vobj->gl_storage.w;
		float hv = (float)maxh / (float)vobj->gl_storage.h;

		generate_basic_mapping(vobj->txcos, wv, hv);
		arcan_video_attachobject(rv);
		
		SDL_FreeSurface(canvas);

		if (n_lines)
			*n_lines = linecount;

		if (lineheights)
			*lineheights = lines;
		else
			free(lines);
	}
	
	struct rcell* current;

cleanup:
	current = root;
	while (current){
		assert(current != (void*) 0xdeadbeef);
		if (current->surface && current->data.surf)
			SDL_FreeSurface(current->data.surf);
			
		struct rcell* prev = current;
		current = current->next;
		prev->next = (void*) 0xdeadbeef;
		free(prev);
	}
	
	free(work);

	return rv;
}

/*  
 * Stripped down version of SDL rotozoomer, only RGBA<->RGBA upscale
 *
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
	Uint8 r;
	Uint8 g;
	Uint8 b;
	Uint8 a;
} tColorRGBA;

typedef struct tColorY {
	Uint8 y;
} tColorY;

int stretchblit(SDL_Surface* src, uint32_t* dst, int dstw, int dsth, int dstpitch, int flipy)
{
	int x, y, sx, sy, ssx, ssy, *sax, *say, *csax, *csay, *salast;
	int csx, csy, ex, ey, cx, cy, sstep, sstepx, sstepy;

	tColorRGBA *c00, *c01, *c10, *c11;
	tColorRGBA *sp, *csp, *dp;
	
	int spixelgap, spixelw, spixelh, dgap, t1, t2;

	if ((sax = (int *) malloc((dstw + 1) * sizeof(Uint32))) == NULL) {
		return (-1);
	}
	if ((say = (int *) malloc((dsth + 1) * sizeof(Uint32))) == NULL) {
		free(sax);
		return (-1);
	}

	spixelw = (src->w - 1);
	spixelh = (src->h - 1);
	sx = (int) (65536.0 * (float) spixelw / (float) (dstw - 1));
	sy = (int) (65536.0 * (float) spixelh / (float) (dsth - 1));
	
	/* Maximum scaled source size */
	ssx = (src->w << 16) - 1;
	ssy = (src->h << 16) - 1;
	
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

	sp = (tColorRGBA *) src->pixels;
	dp = (tColorRGBA *) dst;
	dgap = dstpitch - dstw * 4;
	spixelgap = src->pitch/4;

	if (flipy) sp += (spixelgap * spixelh);

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

		dp = (tColorRGBA *) ((Uint8 *) dp + dgap);
	}

	free(sax);
	free(say);

	return (0);
}
