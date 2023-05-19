/*
  SDL_ttf:  A companion library to SDL for working with TrueType (tm) fonts
  Copyright (C) 2001-2012 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
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
  3. This notice may not be removed or altered from any source distribution.
*/

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include FT_STROKER_H
#include FT_GLYPH_H
#include FT_BITMAP_H
#include FT_TRUETYPE_IDS_H
#include FT_LCD_FILTER_H

#if defined(SHMIF_TTF)
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#endif

#include "external/stb_image_resize.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_ttf.h"

/* FIXME: Right now we assume the gray-scale renderer Freetype is using
   supports 256 shades of gray, but we should instead key off of num_grays
   in the result FT_Bitmap after the FT_Render_Glyph() call. */
#define NUM_GRAYS       256

#define FONT_CACHE_SIZE  128

/* Handy routines for converting from fixed point */
#define FT_FLOOR(X)	((X & -64) / 64)
#define FT_CEIL(X)	(((X + 63) & -64) / 64)

#define CACHED_METRICS	0x10
#define CACHED_BITMAP	0x01
#define CACHED_PIXMAP	0x02

/* Cached glyph information */
typedef struct cached_glyph {
	int stored;
	FT_UInt index;
	FT_Bitmap bitmap;
	FT_Bitmap pixmap;
	int minx;
	int maxx;
	int miny;
	int maxy;
	int yoffset;
	int advance;
	uint32_t cached;

/* special case, set this to true when we deal with non- scalable fonts with
 * embedded bitmaps where we scale to fit the set pt- size (or, with a
 * render-chain, the cached height of the main font */
	bool manual_scale;

} c_glyph;

/* The structure used to hold internal font information */
struct _TTF_Font {
	/* Freetype2 maintains all sorts of useful info itself */
	FT_Face face;

/* We'll cache these ourselves */
	int height;
	int ascent;
	int descent;
	int lineskip;

	/* The font style */
	int face_style;
	int style;
	int outline;

	/* Whether kerning is desired */
	int kerning;

	/* Extra width in glyph bounds for text styles */
	int glyph_overhang;
	float glyph_italics;

	/* Information in the font for underlining */
	int underline_offset;
	int underline_height;

	/* Cache for style-transformed glyphs */
	c_glyph *current;
	c_glyph cache[257]; /* 257 is a prime */

	/* We are responsible for closing the font stream */
	FILE* src;
	int freesrc;
	FT_Open_Args args;

	/* For non-scalable formats, we must remember which font index size */
	int font_size_family;
	int ptsize;

	/* really just flags passed into FT_Load_Glyph */
	int hinting;

	int cached_height;
	int cached_width;
};

/* Font cache entry */
typedef struct c_font {
	struct _TTF_Font* font;

	/* If this font is derived from other */
	struct c_font* original;

	dev_t dev;
	ino_t ino;
	int ptsize;
	uint16_t hdpi;
	uint16_t vdpi;
	unsigned int ref_count;
} c_font;

/* Font cache reference */
typedef struct c_font_ref {
	struct _TTF_Font* font;
	c_font* cache_entry;
} c_font_ref;

/* Handle a style only if the font does not already handle it */
#define TTF_HANDLE_STYLE_BOLD(font) (((font)->style & TTF_STYLE_BOLD) && \
                                    !((font)->face_style & TTF_STYLE_BOLD))
#define TTF_HANDLE_STYLE_ITALIC(font) (((font)->style & TTF_STYLE_ITALIC) && \
                                      !((font)->face_style & TTF_STYLE_ITALIC))
#define TTF_HANDLE_STYLE_UNDERLINE(font) ((font)->style & TTF_STYLE_UNDERLINE)
#define TTF_HANDLE_STYLE_STRIKETHROUGH(font) ((font)->style & TTF_STYLE_STRIKETHROUGH)

/* Font styles that does not impact glyph drawing */
#define TTF_STYLE_NO_GLYPH_CHANGE	(TTF_STYLE_UNDERLINE | TTF_STYLE_STRIKETHROUGH)

/* The FreeType font engine/library */
static _Thread_local FT_Library library;
static _Thread_local int TTF_initialized = 0;

static c_font font_cache[FONT_CACHE_SIZE];
static int font_cache_usage = 0;

bool TTF_FontIsEqual(const struct _TTF_Font* a, const struct _TTF_Font* b)
{
	return
		a->face == b->face &&
		a->height == b->height &&
		a->ascent == b->ascent &&
		a->descent == b->descent &&
		a->lineskip == b->lineskip &&
		a->face_style == b->face_style &&
		a->style == b->style &&
		a->outline == b->outline &&
		a->kerning == b->kerning &&
		a->glyph_overhang == b->glyph_overhang &&
		a->glyph_italics == b->glyph_italics &&
		a->underline_offset == b->underline_offset &&
		a->underline_height == b->underline_height &&
		a->font_size_family == b->font_size_family &&
		a->ptsize == b->ptsize &&
		a->hinting == b->hinting;
}

c_font* TTF_FindCachedFont(dev_t dev, ino_t ino, int ptsize, uint16_t hdpi, uint16_t vdpi)
{
	for (int i=0; i<font_cache_usage; i++) {
		c_font* f = &font_cache[i];

		if (f->original)
			continue;

		if (f->dev == dev &&
		    f->ino == ino &&
		    f->ptsize == ptsize &&
		    f->hdpi == hdpi &&
		    f->vdpi == vdpi) {

			f->ref_count++;
			TRACE_MARK_ONESHOT("font", "cache-hit", TRACE_SYS_DEFAULT, 0, 0, "");
			return f;
		}
	}

	for (int i=0; i<FONT_CACHE_SIZE; i++) {
		if (font_cache[i].font != NULL)
			continue;

		c_font* f = &font_cache[i];
		f->dev = dev;
		f->ino = ino;
		f->ptsize = ptsize;
		f->hdpi = hdpi;
		f->vdpi = vdpi;
		f->original = NULL;
		f->ref_count = 1;

		if (i + 1 > font_cache_usage) {
			font_cache_usage = i + 1;
		}

		TRACE_MARK_ONESHOT("font", "cache-miss", TRACE_SYS_DEFAULT, 0, 0, "");
		return f;
	}

	TRACE_MARK_ONESHOT("font", "cache-overrun", TRACE_SYS_WARN, 0, 0, "");
	return NULL;
}

c_font* TTF_FindOrForkCachedFont(c_font* original, const struct _TTF_Font* template)
{
	c_font* result = NULL;

	for (int i=0; i<font_cache_usage; i++) {
		if (font_cache[i].font == NULL)
			continue;

		if (!TTF_FontIsEqual(font_cache[i].font, template))
			continue;

		result = &font_cache[i];
		break;
	}

	if (!result) {
		for (int i=0; i<FONT_CACHE_SIZE; i++) {
			if (font_cache[i].font != NULL)
				continue;

			result = &font_cache[i];

			if (i + 1 > font_cache_usage) {
				font_cache_usage = i + 1;
			}
			break;
		}
	}

	if (!result)
		return NULL;

	if (result->font != NULL) {
		result->ref_count++;
		TRACE_MARK_ONESHOT("font", "cache-hit", TRACE_SYS_DEFAULT, 0, 0, "fork");
		return result;
	}
	TRACE_MARK_ONESHOT("font", "cache-miss", TRACE_SYS_DEFAULT, 0, 0, "fork");

	*result = *original;
	result->original = original;
	result->ref_count = 1;

	struct _TTF_Font* forked = malloc(sizeof (struct _TTF_Font));
	if (!forked) {
		result->font = NULL;
		return NULL;
	}

	*forked = *original->font;
	forked->freesrc = 0;
	forked->args.stream = NULL; // If it exists, parent should free it
	forked->cached_height = 0;
	forked->cached_width = 0;

	// Reset glyph cache
	forked->current = forked->cache;
	int glyph_cache_size = sizeof( forked->cache ) / sizeof( forked->cache[0] );
	for (int i=0; i<glyph_cache_size; i++) {
		c_glyph* glyph = &forked->cache[i];
		glyph->cached = 0;
		glyph->stored = 0;
		glyph->index = 0;
		glyph->bitmap.buffer = NULL;
		glyph->pixmap.buffer = NULL;
	}

	result->font = forked;
	return result;
}

void TTF_ResetCachedFont(c_font* font)
{
	if (!font)
		return;

	int i;
	for (i=0; i<font_cache_usage; i++) {
		if (&font_cache[i] != font)
			continue;

		TRACE_MARK_ONESHOT("font", "cache-release", TRACE_SYS_DEFAULT, 0, 0, "");

		font_cache[i].font = NULL;

		if (i + 1 == font_cache_usage) {
			font_cache_usage--;
		}

		return;
	}

	TRACE_MARK_ONESHOT("font", "cache-release-fail", TRACE_SYS_ERROR, 0, 0, "");
}

void TTF_SetError(const char* msg){
}

/* Gets the top row of the underline. The outline
   is taken into account.
*/
int TTF_underline_top_row(TTF_Font *font_ref)
{
	/* With outline, the underline_offset is underline_offset+outline. */
	/* So, we don't have to remove the top part of the outline height. */
	return font_ref->font->ascent - font_ref->font->underline_offset - 1;
}

void* TTF_GetFtFace(TTF_Font* font_ref)
{
	if (!font_ref || !font_ref->font)
		return NULL;

	return (void*)font_ref->font->face;
}

/* Gets the bottom row of the underline. The outline
   is taken into account.
*/
int TTF_underline_bottom_row(TTF_Font *font_ref)
{
	int row = TTF_underline_top_row(font_ref) + font_ref->font->underline_height;
	if( font_ref->font->outline  > 0 ) {
		/* Add underline_offset outline offset and */
		/* the bottom part of the outline. */
		row += font_ref->font->outline * 2;
	}
	return row;
}

/* Gets the top row of the strikethrough. The outline
   is taken into account.
*/
int TTF_strikethrough_top_row(TTF_Font *font_ref)
{
	/* With outline, the first text row is 'outline'. */
	/* So, we don't have to remove the top part of the outline height. */
	return font_ref->font->height / 2;
}

static void TTF_SetFTError(const char *msg, FT_Error error)
{
#ifdef USE_FREETYPE_ERRORS
#undef FTERRORS_H
#define FT_ERRORDEF( e, v, s )  { e, s },
	static const struct
	{
	  int          err_code;
	  const char*  err_msg;
	} ft_errors[] = {
#include <freetype/fterrors.h>
	};
	int i;
	const char *err_msg;
	char buffer[1024];

	err_msg = NULL;
	for ( i=0; i<((sizeof ft_errors)/(sizeof ft_errors[0])); ++i ) {
		if ( error == ft_errors[i].err_code ) {
			err_msg = ft_errors[i].err_msg;
			break;
		}
	}
	if ( ! err_msg ) {
		err_msg = "unknown FreeType error";
	}
	sprintf(buffer, "%s: %s", msg, err_msg);
	TTF_SetError(buffer);
#else
	TTF_SetError(msg);
#endif /* USE_FREETYPE_ERRORS */
}

int TTF_Init( void )
{
	int status = 0;
	if ( ! TTF_initialized ) {
		FT_Error error = FT_Init_FreeType( &library );
		if ( error ) {
			TTF_SetFTError("Couldn't init FreeType engine", error);
			status = -1;
		}
		int errc = FT_Library_SetLcdFilter(library, FT_LCD_FILTER_DEFAULT);
		if (0 == errc){
/* weights from Skia@Android */
			static unsigned char gweights[] = {0x1a, 0x43, 0x56, 0x43, 0x1a};
			FT_Library_SetLcdFilterWeights(library, gweights);
		}
	}
	if ( status == 0 ) {
		++TTF_initialized;
	}
	return status;
}

static unsigned long ft_read(FT_Stream stream, unsigned long ofs,
	unsigned char* buf, unsigned long count)
{
	FILE* fpek = stream->descriptor.pointer;
	fseek(fpek, (int) ofs, SEEK_SET);
	if (count == 0)
		return 0;

	return fread(buf, 1, count, fpek);
}

static int ft_sizeind(FT_Face face, float ys)
{
	FT_Pos tgt = ys, em = 0;
	int ind = -1;

	for (int i = 0; i < face->num_fixed_sizes; i++){
		FT_Pos cem = face->available_sizes[i].y_ppem;
		if (cem == tgt){
			em = cem;
			ind = i;
			break;
		}

/* keep the largest, we'll have to scale ourselves */
		if (em < cem){
			em = cem;
			ind = i;
		}
	}

	if (-1 != ind){
		int errc = FT_Select_Size(face, ind);
		if (0 != errc){
			ind = -1;
		}
	}
	return ind;
}

void TTF_Resize(TTF_Font* font_ref, int ptsize, uint16_t hdpi, uint16_t vdpi)
{
	// This operation mutates FT_Face, which can not be cloned to ensure immutability
	TRACE_MARK_ONESHOT("font", "stub", TRACE_SYS_WARN, 0, 0, "TTF_Resize is stubbed due to font caching constraints");
	// float emsize = ptsize * 64.0;
	// FT_Set_Char_Size(font_ref->font->face, 0, emsize, hdpi, vdpi);
}

TTF_Font* TTF_OpenFontIndexRW( FILE* src, int freesrc, int ptsize,
	uint16_t hdpi, uint16_t vdpi, long index )
{
	struct _TTF_Font* font;
	c_font_ref* font_ref;
	FT_Error error;
	FT_Face face;
	FT_Fixed scale;
	FT_Stream stream;
	FT_CharMap found;
	int position, i;

	if (!src)
		return NULL;

	if ( ! TTF_initialized ) {
		TTF_Init();
	}

	/* Check to make sure we can seek in this stream */
	position = ftell(src);
	if ( position < 0 ) {
		TTF_SetError( "Can't seek in stream" );
		fclose(src);
		return NULL;
	}

	font_ref = (c_font_ref*) malloc(sizeof *font_ref);
	if ( font_ref == NULL ) {
		TTF_SetError( "Out of memory" );
		fclose(src);
		return NULL;
	}

	font = (struct _TTF_Font*) malloc(sizeof *font);
	if ( font == NULL ) {
		TTF_SetError( "Out of memory" );
		fclose(src);
		free(font_ref);
		return NULL;
	}
	memset(font, 0, sizeof(*font));

	font_ref->font = font;
	font_ref->cache_entry = 0;
	font->src = src;
	font->freesrc = freesrc;

	stream = (FT_Stream)malloc(sizeof(*stream));
	if ( stream == NULL ) {
		TTF_SetError( "Out of memory" );
		TTF_CloseFont( font_ref );
		return NULL;
	}
	memset(stream, 0, sizeof(*stream));

	stream->read = ft_read;
	stream->descriptor.pointer = src;
	stream->pos = (unsigned long)position;
	fseek(src, 0, SEEK_END);
	stream->size = (unsigned long)(ftell(src) - position);
	fseek(src, position, SEEK_SET);

	font->args.flags = FT_OPEN_STREAM;
	font->args.stream = stream;
	font->ptsize = ptsize;

	error = FT_Open_Face( library, &font->args, index, &font->face );
	if( error ) {
		TTF_SetFTError( "Couldn't load font file", error );
		TTF_CloseFont( font_ref );
		return NULL;
	}
	face = font->face;
	FT_Select_Charmap(face, FT_ENCODING_UNICODE);

	float emsize = ptsize * 64.0;

/* Make sure that our font face is scalable (global metrics) */
	if ( FT_IS_SCALABLE(face) ) {
/* Set the character size and use default DPI (72) */
		error = FT_Set_Char_Size( font->face, 0, emsize, hdpi, vdpi);
		if( error ) {
			TTF_SetFTError( "Couldn't set font size", error );
			TTF_CloseFont( font_ref );
			return NULL;
	  }

/* Get the scalable font metrics for this font */
	  scale = face->size->metrics.y_scale;
	  font->ascent  = FT_CEIL(FT_MulFix(face->ascender, scale));
	  font->descent = FT_CEIL(FT_MulFix(face->descender, scale));
	  font->height  = font->ascent - font->descent + /* baseline */ 1;
	  font->lineskip = FT_CEIL(FT_MulFix(face->height, scale));
	  font->underline_offset = FT_FLOOR(
			FT_MulFix(face->underline_position, scale));
	  font->underline_height = FT_FLOOR(
			FT_MulFix(face->underline_thickness, scale));
	}
/* for non-scalable (primarily bitmap) just get the bbox */
	else {
		int i = ft_sizeind(font->face, emsize);
		if (-1 != i){
			font->ascent = face->available_sizes[i].height * 0.5;
			font->descent = face->available_sizes[i].height - font->ascent - 1;
			font->height = face->available_sizes[i].height;
	  	font->lineskip = FT_CEIL(font->ascent);
	  	font->underline_offset = FT_FLOOR(face->underline_position);
	  	font->underline_height = FT_FLOOR(face->underline_thickness);
		}
		else {
			TTF_CloseFont(font_ref);
			return NULL;
		}
	}

	if ( font->underline_height < 1 ) {
		font->underline_height = 1;
	}

#ifdef DEBUG_FONTS
	printf("Font metrics:\n");
	printf("\tascent = %d, descent = %d\n",
		font->ascent, font->descent);
	printf("\theight = %d, lineskip = %d\n",
		font->height, font->lineskip);
	printf("\tunderline_offset = %d, underline_height = %d\n",
		font->underline_offset, font->underline_height);
	printf("\tunderline_top_row = %d, strikethrough_top_row = %d\n",
		TTF_underline_top_row(font), TTF_strikethrough_top_row(font));
#endif

	/* Initialize the font face style */
	font->face_style = TTF_STYLE_NORMAL;
	if ( font->face->style_flags & FT_STYLE_FLAG_BOLD ) {
		font->face_style |= TTF_STYLE_BOLD;
	}
	if ( font->face->style_flags & FT_STYLE_FLAG_ITALIC ) {
		font->face_style |= TTF_STYLE_ITALIC;
	}
	/* Set the default font style */
	font->style = font->face_style;
	font->outline = 0;
	font->kerning = 1;
	font->glyph_overhang = face->size->metrics.y_ppem / 10;
	/* x offset = cos(((90.0-12)/360)*2*M_PI), or 12 degree angle */
	font->glyph_italics = 0.207f;
	font->glyph_italics *= font->height;

	font->cached_width = 0;
	font->cached_height = 0;

	return font_ref;
}

TTF_Font* TTF_OpenFontRW( FILE* src, int freesrc, int ptsize,
	uint16_t hdpi, uint16_t vdpi)
{
	return TTF_OpenFontIndexRW(src, freesrc, ptsize, hdpi, vdpi, 0);
}

TTF_Font* TTF_OpenFontIndex( const char *file, int ptsize,
	uint16_t hdpi, uint16_t vdpi, long index )
{
	struct stat f_stat;
	if (stat(file, &f_stat) != 0)
		return NULL;

	c_font* cached = TTF_FindCachedFont(f_stat.st_dev, f_stat.st_ino, ptsize, hdpi, vdpi);
	if (cached && cached->font) {
		c_font_ref* font_ref = malloc(sizeof(c_font_ref));

		if (!font_ref)
			return NULL;

		font_ref->font = cached->font;
		font_ref->cache_entry = cached;
		return font_ref;
	}

	FILE* rw = fopen(file, "r");
	if (!rw)
		// cached.font is still NULL so not releasing cache entry
		return NULL;

	fcntl(fileno(rw), F_SETFD, FD_CLOEXEC);

	TTF_Font* font_ref = TTF_OpenFontIndexRW(rw, 1, ptsize, hdpi, vdpi, index);

	if (cached) {
		cached->font = font_ref->font;
		font_ref->cache_entry = cached;
	}

	return font_ref;
}

TTF_Font* TTF_OpenFont( const char *file, int ptsize,
	uint16_t hdpi, uint16_t vdpi)
{
	return TTF_OpenFontIndex(file, ptsize, hdpi, vdpi, 0);
}

TTF_Font* TTF_ReplaceFont(TTF_Font* font_ref, int ptsize, uint16_t hdpi, uint16_t vdpi)
{
	int newfd = arcan_shmif_dupfd(fileno(font_ref->font->src), -1, true);
	if (-1 == newfd)
		return font_ref;

	TTF_Font* new = TTF_OpenFontFD(newfd, ptsize, hdpi, vdpi);
	close(newfd);

	if (!new){
		return font_ref;
	}

	TTF_CloseFont(font_ref);
	return new;
}

TTF_Font* TTF_OpenFontFD(int fd,
	int ptsize, uint16_t hdpi, uint16_t vdpi)
{
	if (-1 == fd)
		return NULL;

	struct stat fd_stat;
	if (fstat(fd, &fd_stat) != 0)
		return NULL;

	c_font* cached = TTF_FindCachedFont(fd_stat.st_dev, fd_stat.st_ino, ptsize, hdpi, vdpi);
	if (cached && cached->font) {
		c_font_ref* font_ref = malloc(sizeof(c_font_ref));

		if (!font_ref)
			return NULL;

		font_ref->font = cached->font;
		font_ref->cache_entry = cached;
		return font_ref;
	}

	int nfd = arcan_shmif_dupfd(fd, -1, true);
	if (-1 == nfd)
		return NULL;

	FILE* fstream = fdopen(nfd, "r");
	if (!fstream){
		close(nfd);
		return NULL;
	}

/* because dup doesn't give us a copy of file position, the reset of _ttf will
 * handle this though by ft_read being explicit about position (but not
 * thread-safe) */
	fseek(fstream, SEEK_SET, 0);
	TTF_Font* res = TTF_OpenFontIndexRW(fstream, 1, ptsize, hdpi, vdpi, 0);

	if (!res) {
		return NULL;
	}

	if (cached) {
		cached->font = res->font;
		res->cache_entry = cached;
	}

	return res;
}

static void Flush_Glyph( c_glyph* glyph )
{
	glyph->stored = 0;
	glyph->index = 0;
	if( glyph->bitmap.buffer ) {
		free( glyph->bitmap.buffer );
		glyph->bitmap.buffer = 0;
	}
	if( glyph->pixmap.buffer ) {
		free( glyph->pixmap.buffer );
		glyph->pixmap.buffer = 0;
	}
	glyph->cached = 0;
}

void TTF_Flush_Cache_Internal( struct _TTF_Font* font )
{
	int i;
	int size = sizeof( font->cache ) / sizeof( font->cache[0] );

	for( i = 0; i < size; ++i ) {
		if( font->cache[i].cached ) {
			Flush_Glyph( &font->cache[i] );
		}
	}
}

void TTF_Flush_Cache( TTF_Font* font_ref )
{
	TRACE_MARK_ONESHOT("font", "glyph-cache-flush", TRACE_SYS_DEFAULT, 0, 0, "");
	TTF_Flush_Cache_Internal( font_ref->font );
}

static FT_Error Load_Glyph(
	TTF_Font* font_ref, uint32_t ch, c_glyph* cached, int want, bool by_ind )
{
	struct _TTF_Font* font = font_ref->font;
	FT_Face face;
	FT_Error error;
	FT_GlyphSlot glyph;
	FT_Glyph_Metrics* metrics;
	FT_Outline* outline;

	if ( !font || !font->face ) {
		return FT_Err_Invalid_Handle;
	}

	face = font->face;

	/* Load the glyph */
	if ( ! cached->index ) {
		if (by_ind)
			cached->index = ch;
		else
			cached->index = FT_Get_Char_Index( face, ch );
		if (0 == cached->index)
			return -1;
	}
	error = FT_Load_Glyph( face, cached->index,
		(FT_LOAD_DEFAULT | FT_LOAD_COLOR | FT_LOAD_TARGET_(font->hinting))
		 & (~FT_LOAD_NO_BITMAP));

	if( error )
		return error;

	/* Get our glyph shortcuts */
	glyph = face->glyph;
	metrics = &glyph->metrics;
	outline = &glyph->outline;

	/* Get the glyph metrics if desired */
	if ( (want & CACHED_METRICS) && !(cached->stored & CACHED_METRICS) ) {
		if ( FT_IS_SCALABLE( face ) ) {
			/* Get the bounding box */
			cached->minx = FT_FLOOR(metrics->horiBearingX);
			cached->maxx = cached->minx + FT_CEIL(metrics->width);
			cached->maxy = FT_FLOOR(metrics->horiBearingY);
			cached->miny = cached->maxy - FT_CEIL(metrics->height);
			cached->yoffset = font->ascent - cached->maxy;
			cached->advance = FT_CEIL(metrics->horiAdvance);
			cached->manual_scale = false;
		}
		else {
/* Get the bounding box for non-scalable format.  Again, freetype2 fills in
 * many of the font metrics with the value of 0, so some of the values we need
 * must be calculated differently with certain assumptions about non-scalable
 * formats.  */
			FT_BBox bbox;
			FT_Glyph gglyph;
			FT_Get_Glyph( glyph, &gglyph );
			FT_Glyph_Get_CBox(gglyph, FT_GLYPH_BBOX_PIXELS, &bbox);
			cached->minx = bbox.xMin;
			cached->maxx = bbox.xMax;
			cached->miny = 0;
			cached->maxy = bbox.yMax - bbox.yMin;
			cached->manual_scale = true;
			cached->yoffset = 0;
			cached->advance = FT_CEIL(metrics->horiAdvance);
		}

		/* Adjust for bold and italic text */
		if( TTF_HANDLE_STYLE_BOLD(font) ) {
			cached->maxx += font->glyph_overhang;
		}
		if( TTF_HANDLE_STYLE_ITALIC(font) ) {
			cached->maxx += (int)ceil(font->glyph_italics);
		}
		cached->stored |= CACHED_METRICS;
	}

	if ( ((want & CACHED_BITMAP) && !(cached->stored & CACHED_BITMAP)) ||
	     ((want & CACHED_PIXMAP) && !(cached->stored & CACHED_PIXMAP)) ) {
		int mono = (want & CACHED_BITMAP);
		int i;
		FT_Bitmap* src;
		FT_Bitmap* dst;
		FT_Glyph bitmap_glyph = NULL;

		/* Handle the italic style */
		if( TTF_HANDLE_STYLE_ITALIC(font) ) {
			FT_Matrix shear;

			shear.xx = 1 << 16;
			shear.xy = (int) ( font->glyph_italics * ( 1 << 16 ) ) / font->height;
			shear.yx = 0;
			shear.yy = 1 << 16;

			FT_Outline_Transform( outline, &shear );
		}

		/* Render as outline */
		if( (font->outline > 0) && glyph->format != FT_GLYPH_FORMAT_BITMAP ) {
			FT_Stroker stroker;
			FT_Get_Glyph( glyph, &bitmap_glyph );
			error = FT_Stroker_New( library, &stroker );
			if( error ) {
				return error;
			}
			FT_Stroker_Set( stroker, font->outline * 64, FT_STROKER_LINECAP_ROUND,
				FT_STROKER_LINEJOIN_ROUND, 0 );
			FT_Glyph_Stroke( &bitmap_glyph, stroker, 1 /*delete the original glyph*/);
			FT_Stroker_Done( stroker );
			/* Render the glyph */
			error = FT_Glyph_To_Bitmap( &bitmap_glyph, font->hinting, 0, 1 );
			if( error ) {
				FT_Done_Glyph( bitmap_glyph );
				return error;
			}
			src = &((FT_BitmapGlyph)bitmap_glyph)->bitmap;
		} else {
/* Render the glyph */
			error = FT_Render_Glyph( glyph, font->hinting);
			if( error ) {
				return error;
			}
			src = &glyph->bitmap;
		}
		/* Copy over information to cache */
		if ( mono ) {
			dst = &cached->bitmap;
		} else {
			dst = &cached->pixmap;
		}
		memcpy( dst, src, sizeof( *dst ) );

/* FT_Render_Glyph() and .fon fonts always generate a two-color (black and
 * white) glyphslot surface, even when rendered in ft_render_mode_normal. */
/* FT_IS_SCALABLE() means that the font is in outline format, but does not
 * imply that outline is rendered as 8-bit grayscale, because embedded
 * bitmap/graymap is preferred (see FT_LOAD_DEFAULT section of FreeType2 API
 * Reference).  FT_Render_Glyph() canreturn two-color bitmap or 4/16/256- color
 * graymap according to the format of embedded bitmap/ graymap. */

/* For LCD hinting and BGRA, we don't need to do anything here, it's
 * in the later renderer where we need to repack and possibly scale */

		if ( src->pixel_mode == FT_PIXEL_MODE_MONO ) {
			dst->pitch *= 8;
		} else if ( src->pixel_mode == FT_PIXEL_MODE_GRAY2 ) {
			dst->pitch *= 4;
		} else if ( src->pixel_mode == FT_PIXEL_MODE_GRAY4 ) {
			dst->pitch *= 2;
		}
		else if (src->pixel_mode == FT_PIXEL_MODE_LCD ||
			src->pixel_mode == FT_PIXEL_MODE_LCD_V){
			dst->pitch *= 3;
		}

		/* Adjust for bold and italic text */
		if( TTF_HANDLE_STYLE_BOLD(font) ) {
			int bump = font->glyph_overhang;
			dst->pitch += bump;
			dst->width += bump;
		}
		if( TTF_HANDLE_STYLE_ITALIC(font) ) {
			int bump = (int)ceil(font->glyph_italics);
			dst->pitch += bump;
			dst->width += bump;
		}

		if (dst->rows != 0) {
			dst->buffer = (unsigned char *)malloc( dst->pitch * dst->rows );
			if( !dst->buffer ) {
				return FT_Err_Out_Of_Memory;
			}
			memset( dst->buffer, 0, dst->pitch * dst->rows );

			for( i = 0; i < src->rows; i++ ) {
				int soffset = i * src->pitch;
				int doffset = i * dst->pitch;
				if ( mono ) {
					unsigned char *srcp = src->buffer + soffset;
					unsigned char *dstp = dst->buffer + doffset;
					int j;
					if ( src->pixel_mode == FT_PIXEL_MODE_MONO ) {
						for ( j = 0; j < src->width; j += 8 ) {
							unsigned char c = *srcp++;
							*dstp++ = (c&0x80) >> 7;
							c <<= 1;
							*dstp++ = (c&0x80) >> 7;
							c <<= 1;
							*dstp++ = (c&0x80) >> 7;
							c <<= 1;
							*dstp++ = (c&0x80) >> 7;
							c <<= 1;
							*dstp++ = (c&0x80) >> 7;
							c <<= 1;
							*dstp++ = (c&0x80) >> 7;
							c <<= 1;
							*dstp++ = (c&0x80) >> 7;
							c <<= 1;
							*dstp++ = (c&0x80) >> 7;
						}
					}  else if ( src->pixel_mode == FT_PIXEL_MODE_GRAY2 ) {
						for ( j = 0; j < src->width; j += 4 ) {
							unsigned char c = *srcp++;
							*dstp++ = (((c&0xA0) >> 6) >= 0x2) ? 1 : 0;
							c <<= 2;
							*dstp++ = (((c&0xA0) >> 6) >= 0x2) ? 1 : 0;
							c <<= 2;
							*dstp++ = (((c&0xA0) >> 6) >= 0x2) ? 1 : 0;
							c <<= 2;
							*dstp++ = (((c&0xA0) >> 6) >= 0x2) ? 1 : 0;
						}
					} else if ( src->pixel_mode == FT_PIXEL_MODE_GRAY4 ) {
						for ( j = 0; j < src->width; j += 2 ) {
							unsigned char c = *srcp++;
							*dstp++ = (((c&0xF0) >> 4) >= 0x8) ? 1 : 0;
							c <<= 4;
							*dstp++ = (((c&0xF0) >> 4) >= 0x8) ? 1 : 0;
						}
					} else {
						for ( j = 0; j < src->width; j++ ) {
							unsigned char c = *srcp++;
							*dstp++ = (c >= 0x80) ? 1 : 0;
						}
					}
				} else if ( src->pixel_mode == FT_PIXEL_MODE_MONO ) {
/* This special case wouldn't be here if the FT_Render_Glyph() function wasn't
 * buggy when it tried to render a .fon font with 256 shades of gray.  Instead,
 * it returns a black and white surface and we have to translate it back to a
 * 256 gray shaded surface.  */
					unsigned char *srcp = src->buffer + soffset;
					unsigned char *dstp = dst->buffer + doffset;
					unsigned char c;
					int j, k;
					for ( j = 0; j < src->width; j += 8) {
						c = *srcp++;
						for (k = 0; k < 8; ++k) {
							if ((c&0x80) >> 7) {
								*dstp++ = NUM_GRAYS - 1;
							} else {
								*dstp++ = 0x00;
							}
							c <<= 1;
						}
					}
				} else if ( src->pixel_mode == FT_PIXEL_MODE_GRAY2 ) {
					unsigned char *srcp = src->buffer + soffset;
					unsigned char *dstp = dst->buffer + doffset;
					unsigned char c;
					int j, k;
					for ( j = 0; j < src->width; j += 4 ) {
						c = *srcp++;
						for ( k = 0; k < 4; ++k ) {
							if ((c&0xA0) >> 6) {
								*dstp++ = NUM_GRAYS * ((c&0xA0) >> 6) / 3 - 1;
							} else {
								*dstp++ = 0x00;
							}
							c <<= 2;
						}
					}
				} else if ( src->pixel_mode == FT_PIXEL_MODE_GRAY4 ) {
					unsigned char *srcp = src->buffer + soffset;
					unsigned char *dstp = dst->buffer + doffset;
					unsigned char c;
					int j, k;
					for ( j = 0; j < src->width; j += 2 ) {
						c = *srcp++;
						for ( k = 0; k < 2; ++k ) {
							if ((c&0xF0) >> 4) {
							    *dstp++ = NUM_GRAYS * ((c&0xF0) >> 4) / 15 - 1;
							} else {
								*dstp++ = 0x00;
							}
							c <<= 4;
						}
					}
				} else {
					memcpy(dst->buffer+doffset,
					       src->buffer+soffset, src->pitch);
				}
			}
		}

		/* Handle the bold style */
		if ( TTF_HANDLE_STYLE_BOLD(font) ) {
			int row;
			int col;
			int offset;
			int pixel;
			uint8_t* pixmap;

			/* The pixmap is a little hard, we have to add and clamp */
			for( row = dst->rows - 1; row >= 0; --row ) {
				pixmap = (uint8_t*) dst->buffer + row * dst->pitch;
				for( offset=1; offset <= font->glyph_overhang; ++offset ) {
					for( col = dst->width - 1; col > 0; --col ) {
						if( mono ) {
							pixmap[col] |= pixmap[col-1];
						} else {
							pixel = (pixmap[col] + pixmap[col-1]);
							if( pixel > NUM_GRAYS - 1 ) {
								pixel = NUM_GRAYS - 1;
							}
							pixmap[col] = (uint8_t) pixel;
						}
					}
				}
			}
		}

		/* Mark that we rendered this format */
		if ( mono ) {
			cached->stored |= CACHED_BITMAP;
		} else {
			cached->stored |= CACHED_PIXMAP;
		}

		/* Free outlined glyph */
		if( bitmap_glyph ) {
			FT_Done_Glyph( bitmap_glyph );
		}
	}

	/* We're done, mark this glyph cached */
	cached->cached = ch;

	return 0;
}

static FT_Error Find_Glyph(
	TTF_Font* font_ref, uint32_t ch, int want, bool by_ind)
{
	struct _TTF_Font* font = font_ref->font;
	int retval = 0;
	int hsize = sizeof( font->cache ) / sizeof( font->cache[0] );

	int h = ch % hsize;
	font->current = &font->cache[h];

	if (font->current->cached != ch)
		Flush_Glyph( font->current );

	if ( (font->current->stored & want) != want ) {
		retval = Load_Glyph( font_ref, ch, font->current, want, by_ind );
	}
	return retval;
}

TTF_Font* TTF_FindGlyph(
	TTF_Font** fonts, int n, uint32_t ch, int want, bool by_ind)
{
	for (size_t i = 0; i < n; i++){
		if (Find_Glyph(fonts[i], ch, want, by_ind) != 0)
			continue;

		return fonts[i];
	}

	return NULL;
}

void TTF_CloseFontInternal( struct _TTF_Font* font, bool is_original )
{
	TTF_Flush_Cache_Internal( font );

	if (is_original) {
		if ( font->face )
			FT_Done_Face( font->face );

		if ( font->args.stream )
			free( font->args.stream );

		if ( font->freesrc )
			fclose( font->src );
	}

	free( font );
}

void TTF_CloseFont( TTF_Font* font_ref )
{
	if ( !font_ref )
		return;

	if ( !font_ref->font ) {
		free(font_ref);
		return;
	}

	if ( font_ref->cache_entry ) {
		c_font* current = font_ref->cache_entry;
		c_font* original = font_ref->cache_entry->original;

		current->ref_count--;

		if (current->ref_count == 0) {
			TTF_CloseFontInternal(current->font, original == NULL);
			TTF_ResetCachedFont(current);
		}

		if (original) {
			original->ref_count--;

			if (original->ref_count == 0) {
				TTF_CloseFontInternal(original->font, true);
				TTF_ResetCachedFont(original);
			}
		}
	} else {
		TTF_CloseFontInternal(font_ref->font, true);
	}

	free( font_ref );
}

/*
 * Normal license pollution ..
 *
 * Copyright 2001-2004 Unicode, Inc.
 *
 * Disclaimer
 *
 * This source code is provided as is by Unicode, Inc. No claims are
 * made as to fitness for any particular purpose. No warranties of any
 * kind are expressed or implied. The recipient agrees to determine
 * applicability of information provided. If this file has been
 * purchased on magnetic or optical media from Unicode, Inc., the
 * sole remedy for any claim will be exchange of defective media
 * within 90 days of receipt.
 *
 * Limitations on Rights to Redistribute This Code
 *
 * Unicode, Inc. hereby grants the right to freely use the information
 * supplied in this file in the creation of products supporting the
 * Unicode Standard, and to make copies of this file in any form
 * for internal or external distribution as long as this notice
 * remains attached.
 */

/*
 * Our UTF8- calls should come from pre-validated non-trucated
 * UTF8- sources so a few tricks and checks are omitted.
 */
static const char u8lenlut[256] = {
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
};

static const uint32_t u8ofslut[6] = {
	0x00000000UL, 0x00003080UL, 0x000E2080UL,
	0x03C82080UL, 0xFA082080UL, 0x82082080UL
};

int UTF8_to_UTF32(uint32_t* out, const uint8_t* const in, size_t len)
{
	int rc = 1;

	for (size_t i = 0; i < len;){
		uint32_t ch = 0;
		unsigned short nr = u8lenlut[in[i]];

		switch (nr) {
		case 5: ch += in[i++]; ch <<= 6;
		case 4: ch += in[i++]; ch <<= 6;
		case 3: ch += in[i++]; ch <<= 6;
		case 2: ch += in[i++]; ch <<= 6;
		case 1: ch += in[i++]; ch <<= 6;
		case 0: ch += in[i++];
		}
		ch -= u8ofslut[nr];

/* replace wrong plane (17+) and surrogate pairs with an error char */
		if (ch <= 0x0010FFFF){
			if (ch >= 0xD800 && ch <= 0xDFFF)
				*out++ = 0x0000FFD;
			else
				*out++ = ch;
		}
		else
			*out++ = 0x0000FFFD;
	}
	*out = 0;
	return rc;
}

int TTF_FontHeight(const TTF_Font *font_ref)
{
	return font_ref->font->height;
}

int TTF_FontAscent(const TTF_Font *font_ref)
{
	return font_ref->font->ascent;
}

int TTF_FontDescent(const TTF_Font *font_ref)
{
	return font_ref->font->descent;
}

int TTF_FontLineSkip(const TTF_Font *font_ref)
{
	return font_ref->font->lineskip;
}

int TTF_GetFontKerning(const TTF_Font *font_ref)
{
	return font_ref->font->kerning;
}

void TTF_SetFontKerning(TTF_Font *font_ref, int allowed)
{
	if (font_ref->font->kerning == allowed)
		return;

	if (font_ref->cache_entry) {
		struct _TTF_Font template = *font_ref->font;
		template.kerning = allowed;

		c_font* fork = TTF_FindOrForkCachedFont(font_ref->cache_entry, &template);

		if (!fork)
			return;

		font_ref->font = fork->font;
		font_ref->cache_entry = fork;
	}

	font_ref->font->kerning = allowed;
}

long TTF_FontFaces(const TTF_Font *font_ref)
{
	return font_ref->font->face->num_faces;
}

int TTF_FontFaceIsFixedWidth(const TTF_Font *font_ref)
{
	return FT_IS_FIXED_WIDTH(font_ref->font->face);
}

char *TTF_FontFaceFamilyName(const TTF_Font *font_ref)
{
	return font_ref->font->face->family_name;
}

char *TTF_FontFaceStyleName(const TTF_Font *font_ref)
{
	return font_ref->font->face->style_name;
}

/*
int TTF_GlyphMetrics(TTF_Font *font, uint32_t ch,
                     int* minx, int* maxx, int* miny, int* maxy, int* advance)
{
	FT_Error error;

	error = Find_Glyph(font, ch, CACHED_METRICS);
	if ( error ) {
		TTF_SetFTError("Couldn't find glyph", error);
		return -1;
	}

	if ( minx ) {
		*minx = font->current->minx;
	}
	if ( maxx ) {
		*maxx = font->current->maxx;
		if( TTF_HANDLE_STYLE_BOLD(font) ) {
			*maxx += font->glyph_overhang;
		}
	}
	if ( miny ) {
		*miny = font->current->miny;
	}
	if ( maxy ) {
		*maxy = font->current->maxy;
	}
	if ( advance ) {
		*advance = font->current->advance;
		if( TTF_HANDLE_STYLE_BOLD(font) ) {
			*advance += font->glyph_overhang;
		}
	}
	return 0;
}
*/

void TTF_SetFontStyle( TTF_Font* font_ref, int style )
{
	int new_style = style | font_ref->font->face_style;

	if ( font_ref->font->style == new_style )
		return;

	if (font_ref->cache_entry) {
		struct _TTF_Font template = *font_ref->font;
		template.style = new_style;

		c_font* fork = TTF_FindOrForkCachedFont(font_ref->cache_entry, &template);

		if (!fork)
			return;

		font_ref->font = fork->font;
		font_ref->cache_entry = fork;
	}

	/* Flush the cache if the style has changed.
	* Ignore UNDERLINE which does not impact glyph drawning.
	* */
	int old_style = font_ref->font->style;
	font_ref->font->style = new_style;
	if ( (new_style | TTF_STYLE_NO_GLYPH_CHANGE) != (old_style | TTF_STYLE_NO_GLYPH_CHANGE ) ) {
		TTF_Flush_Cache( font_ref );
	}
}

_Thread_local static size_t pool_cnt;
_Thread_local static uint32_t* unicode_buf;

static void size_upool(int len)
{
	if (len <= 0)
		return;

	if (pool_cnt < len){
		free(unicode_buf);
		unicode_buf = malloc((len + 1) * sizeof(uint32_t));
		pool_cnt = len + 1;
	}
}

int TTF_SizeUTF8chain(TTF_Font** font,
	size_t n, const char* text, int *w, int *h, int style)
{
	int unicode_len = strlen(text);
	size_upool(unicode_len+1);

	if (!unicode_buf)
		return -1;

	int status;
	UTF8_to_UTF32(unicode_buf, (const uint8_t*)text, unicode_len);
	return TTF_SizeUNICODEchain(font, n, unicode_buf, w, h, style);
}

int TTF_SizeUTF8(TTF_Font *font, const char *text, int *w, int *h, int style)
{
	return TTF_SizeUTF8chain(&font, 1, text, w, h, style);
}

int TTF_SizeUNICODE(TTF_Font *font,
	const uint32_t* text, int *w, int *h, int style)
{
	return TTF_SizeUNICODEchain(&font, 1, text, w, h, style);
}

int TTF_SizeUNICODEchain(TTF_Font **font, size_t n,
	const uint32_t* text, int *w, int *h, int style)
{
	int status = 0;
	const uint32_t *ch;
	int x, z;
	int minx = 0, maxx = 0;
	int miny = 0, maxy = 0;
	c_glyph *glyph;
	FT_Error error;
	FT_Long use_kerning;
	FT_UInt prev_index = 0;
	int outline_delta = 0;

	if ( ! TTF_initialized ) {
		TTF_SetError( "Library not initialized" );
		return -1;
	}

/* dominant (first) font in chain gets to control dimensions */
	use_kerning = FT_HAS_KERNING( font[0]->font->face ) && font[0]->font->kerning;

/* Init outline handling */
	if ( font[0]->font->outline  > 0 ) {
		outline_delta = font[0]->font->outline * 2;
	}

	x= 0;
	for ( ch=text; *ch; ++ch ) {
/* we ignore BOMs here as we've gone from UTF8 to native
 * and stripped away other paths */
		uint32_t c = *ch;
		TTF_Font* outf = TTF_FindGlyph(font, n, c, CACHED_METRICS, false);
		if (!outf)
			continue;
		glyph = outf->font->current;

/* cheating with the manual_scale bitmap fonts */
		if (glyph->manual_scale){
			x += outf->font->ptsize;
			maxx += outf->font->ptsize;
			if (maxy < outf->font->ptsize)
				maxy = outf->font->ptsize;
			continue;
		}

/* kerning needs the index of the previous glyph and the current one */
		if ( use_kerning && prev_index && glyph->index ) {
			FT_Vector delta;
			FT_Get_Kerning( outf->font->face, prev_index,
				glyph->index, ft_kerning_default, &delta );
			x += delta.x >> 6;
		}

#if 0
		if ( (ch == text) && (glyph->minx < 0) ) {
		/* Fixes the texture wrapping bug when the first letter
		 * has a negative minx value or horibearing value.  The entire
		 * bounding box must be adjusted to be bigger so the entire
		 * letter can fit without any texture corruption or wrapping.
		 *
		 * Effects: First enlarges bounding box.
		 * Second, xstart has to start ahead of its normal spot in the
		 * negative direction of the negative minx value.
		 * (pushes everything to the right).
		 *
		 * This will make the memory copy of the glyph bitmap data
		 * work out correctly.
		 * */
			z -= glyph->minx;

		}
#endif

		z = x + glyph->minx;
		if ( minx > z ) {
			minx = z;
		}
		if ( TTF_HANDLE_STYLE_BOLD(outf->font) ) {
			x += outf->font->glyph_overhang;
		}
		if ( glyph->advance > glyph->maxx ) {
			z = x + glyph->advance;
		} else {
			z = x + glyph->maxx;
		}
		if ( maxx < z ) {
			maxx = z;
		}
		x += glyph->advance;

		if ( glyph->miny < miny ) {
			miny = glyph->miny;
		}
		if ( glyph->maxy > maxy ) {
			maxy = glyph->maxy;
		}
		prev_index = glyph->index;
	}

	/* Fill the bounds rectangle */
	if ( w ) {
		/* Add outline extra width */
		*w = (maxx - minx) + outline_delta;
	}
	if ( h ) {
		/* Some fonts descend below font height (FletcherGothicFLF) */
		/* Add outline extra height */
		*h = (font[0]->font->ascent - miny) + outline_delta;
		if ( *h < font[0]->font->height ) {
			*h = font[0]->font->height;
		}
		/* Update height according to the needs of the underline style */
		if( TTF_HANDLE_STYLE_UNDERLINE(font[0]->font) ) {
			int bottom_row = TTF_underline_bottom_row(font[0]);
			if ( *h < bottom_row ) {
				*h = bottom_row;
			}
		}
	}
	return status;
}

/*
 * Extended quickhack to allow UTF8 to render using the arcan or shmif
 * internal packing macro directly into a buffer without going through
 * an intermediate. These functions are in need of a more efficient
 * and clean rewrite. The 'direct' rendering mode in FreeType comes to
 * mind
 */
static inline av_pixel pack_pixel_bg(uint8_t fg[4], uint8_t bg[4], uint8_t a)
{
	if (0 == a)
		return PACK(bg[0], bg[1], bg[2], bg[3]);
	else if (255 == a)
		return PACK(fg[0], fg[1], fg[2], 0xff);
	else {
		uint32_t r = 0x80 + (a * fg[0]+bg[0]*(255-a));
		r = (r + (r >> 8)) >> 8;
		uint32_t g = 0x80 + (a * fg[1]+bg[1]*(255-a));
		g = (g + (g >> 8)) >> 8;
		uint32_t b = 0x80 + (a * fg[2]+bg[2]*(255-a));
		b = (b + (b >> 8)) >> 8;
		uint8_t av = (a < bg[3] || a - bg[3] < bg[3]) ? bg[3] : a;
		return PACK(r, g, b, av);
	}
}

static inline av_pixel pack_pixel(uint8_t fg[4], uint8_t a)
{
	uint8_t fa = a > 0;
	return PACK(fg[0] * fa, fg[1] * fa, fg[2] * fa, a);
}

static inline av_pixel pack_subpx_bg(uint8_t fg[4], uint8_t bg[4],
	uint8_t r, uint8_t g, uint8_t b)
{
	uint8_t a = (r + g + b) / 3;
/* should be rewritten as fixed prec. vectorized */
	if (a < 0xff){
		uint8_t nfg[4];
		uint32_t rr = 0x80 + (r * fg[0]);
		nfg[0] = (rr + (rr >> 8)) >> 8;
		uint32_t rg = 0x80 + (g * fg[1]);
		nfg[1] = (rg + (rg >> 8)) >> 8;
		uint32_t rb = 0x80 + (b * fg[2]);
		nfg[2] = (rb + (rb >> 8)) >> 8;
		nfg[3] = 0xff;
		return pack_pixel_bg(nfg, bg, a);
	}
	return pack_pixel(fg, a);
}

static inline av_pixel pack_subpx(uint8_t fg[4],
	uint8_t r, uint8_t g, uint8_t b)
{
	uint8_t a = (r + g + b) / 3;
/* should be rewritten as fixed prec. vectorized */
	if (a < 0xff){
		uint32_t rr = 0x80 + (r * fg[0]);
		r = (rr + (rr >> 8)) >> 8;
		uint32_t rg = 0x80 + (g * fg[1]);
		g = (rg + (rg >> 8)) >> 8;
		uint32_t rb = 0x80 + (b * fg[2]);
		b = (rb + (rb >> 8)) >> 8;
		return PACK(r, g, b, a);
	}
	else
		return PACK(fg[0], fg[1], fg[2], 0xff);
}

static void yfill(PIXEL* dst, PIXEL clr, int yfill, int w, int h, int stride)
{
	for (int br = 0, ur = h-1; br < yfill; br++, ur--){
		PIXEL* dr = &dst[br * stride];
		for (int col = 0; col < w; col++)
			*dr++ = clr;
		dr = &dst[ur * stride];
		for (int col = 0; col < w; col++)
			*dr++ = clr;
	}
}

static bool render_unicode(
	PIXEL* dst,
	size_t width, size_t height,
	int stride, TTF_Font **font, size_t n,
	TTF_Font* outf_ref,
	unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index)
{
	struct _TTF_Font* outf = outf_ref->font;
	PIXEL* ubound = dst + (height * stride) + width;
	c_glyph* glyph = outf->current;
	*advance = glyph->advance;

	int gwidth = 0;
	/* Ensure the width of the pixmap is correct. On some cases,
 * freetype may report a larger pixmap than possible.*/
	if (glyph->manual_scale){
		*advance = outf->ptsize;
		gwidth = outf->ptsize;
	}
	else {
		gwidth = glyph->pixmap.width;
		if (outf->outline <= 0 && width > glyph->maxx - glyph->minx)
			gwidth = glyph->maxx - glyph->minx;

/* do kerning, if possible AC-Patch */
		if ( use_kerning && *prev_index && glyph->index ) {
			FT_Vector delta;
			FT_Get_Kerning( outf->face, *prev_index,
				glyph->index, ft_kerning_default, &delta );
			*xstart += delta.x >> 6;
		}

/* Compensate for the wrap around bug with negative minx's
		if ( glyph->minx && *xstart > glyph->minx ){
			*xstart -= glyph->minx;
		}
	*/
	}

	if (glyph->pixmap.pixel_mode == FT_PIXEL_MODE_BGRA){
/* special cases for embedded glyphs of fixed sizes that we want mixed
 * with 'regular' text, so scale and just use center rather than try and
 * fit with other font baseline */
		if (glyph->manual_scale){
/* maintain AR and center around PTSIZE (as em = 1/72@72DPI = 1 px)	*/
			float ar = glyph->pixmap.rows / glyph->pixmap.width;
			int newh = font[0]->font->ptsize;
			int neww = newh * ar;
			int yshift = 0;

			if (neww > width){
				neww = width;
/*	uncomment to maintain aspect ratio
 *	newh = width / ar; */
			}
			if (newh >= height)
				newh = height;
			else{
				yshift = (height - newh) >> 1;
				yfill(dst, usebg ? PACK(bg[0], bg[1], bg[2], bg[3]) : 0,
					yshift, width, height, stride);
			}

/* this approach gives us the wrong packing for color channels, but we
 * repack after scale as it is fewer operations */
			stbir_resize_uint8(glyph->pixmap.buffer, glyph->pixmap.width,
				glyph->pixmap.rows, 0,
				(unsigned char*) &dst[*xstart], neww, newh, stride * 4, 4);

			for (int row = 0; row < outf->ptsize; row++){
				PIXEL* out = &dst[*xstart + ((row + yshift) * stride)];
				out = out < dst ? dst : out;

				for (int col = 0; col < neww; col++){
					uint8_t* in = (uint8_t*) out;
					uint8_t col[4];
					col[2] = *in++;
					col[1] = *in++;
					col[0] = *in++;
					col[3] = *in++;

					if (usebg)
						*out++ = pack_pixel_bg(col, bg, col[3]);
					else
						*out++ = PACK(col[0], col[1], col[2], col[3]);
				}
			}
		}
/* path should be pretty untraveled until FT itself supports color fonts */
		else{
			for (int row = 0; row < glyph->pixmap.rows; row++){
				if (row+glyph->yoffset < 0 || row+glyph->yoffset >= height)
					continue;

				PIXEL* out = &dst[(row+glyph->yoffset)*stride+(*xstart+glyph->minx)];
				out = out < dst ? dst : out;
				uint8_t* src = (uint8_t*)
					(glyph->pixmap.buffer + glyph->pixmap.pitch * row);

				for (int col = 0; col < gwidth && col < width; col++){
					int b = *src++;
					int g = *src++;
					int r = *src++;
					int a = *src++;
					*out++ = PACK(r,g,b,a);
				}
			}
		}
	}
/* similar to normal drawing, but 3 times as wide */
	else if (glyph->pixmap.pixel_mode == FT_PIXEL_MODE_LCD){
		for (int row = 0; row < glyph->pixmap.rows; ++row){
			if (row+glyph->yoffset < 0 || row+glyph->yoffset >= height)
				continue;

			PIXEL* out = &dst[(row+glyph->yoffset)*stride+(*xstart+glyph->minx)];
			uint8_t* src = (uint8_t*)(glyph->pixmap.buffer+glyph->pixmap.pitch*row);
			out = out < dst ? dst : out;

			for (int col = 0; col < gwidth && col < width && out < ubound; col++){
				uint8_t b = *src++;
				uint8_t g = *src++;
				uint8_t r = *src++;

				if (usebg)
					*out++ = pack_subpx_bg(fg, bg, r, g, b);
				else if (b|g|r)
					*out++ = pack_subpx(fg, r, g, b);
				else
					out++;
			}
		}
	}
	else if (glyph->pixmap.pixel_mode == FT_PIXEL_MODE_LCD_V){
		for (int row = 0; row < glyph->pixmap.rows; ++row){
			if (row+glyph->yoffset < 0 || row+glyph->yoffset >= height)
				continue;

			PIXEL* out = &dst[(row+glyph->yoffset)*stride+(*xstart+glyph->minx)];
			uint8_t* src = (uint8_t*)(glyph->pixmap.buffer+(glyph->pixmap.pitch*3)*row);
			out = out < dst ? dst : out;

			for (int col = 0; col < gwidth && col < width && out < ubound; col++){
				uint8_t b = *src;
				uint8_t g = *(src + glyph->pixmap.pitch);
				uint8_t r = *(src + glyph->pixmap.pitch + glyph->pixmap.pitch);

				if (usebg)
					*out++ = pack_subpx_bg(fg, bg, r, g, b);
				else if (b|g|r)
					*out++ = pack_subpx(fg, r, g, b);
				else
					out++;
			}
		}
	}
	else
	for (int row = 0; row < glyph->pixmap.rows; ++row){
		if (row+glyph->yoffset < 0 || row+glyph->yoffset >= height)
			continue;

/* this blit- routine is a bit worse - there's one strategy if we want to
 * blend against BG and one where we just want the foreground channel, but
 * also a number of color formats for the glyph. */
		PIXEL* out = &dst[(row+glyph->yoffset)*stride+(*xstart+glyph->minx)];
		uint8_t* src = (uint8_t*)(glyph->pixmap.buffer+glyph->pixmap.pitch * row);
		out = out < dst ? dst : out;
		for (int col = 0; col < gwidth && col < width && out < ubound; col++){
			uint8_t a = *src++;
			if (usebg)
				*out++ = pack_pixel_bg(fg, bg, a);
			else if (a)
				*out++ = pack_pixel(fg, a);
			else
				out++;
		}
	}

/* Underline / Strikethrough can be handled by the caller for this func
 * just getting toprow:
		row = TTF_underline_top_row(font);
		row = TTF_strikethrough_top_row(font);
*/

	if (TTF_HANDLE_STYLE_BOLD(outf))
		*xstart += outf->glyph_overhang;

	*prev_index = glyph->index;
	return true;
}

bool TTF_RenderUNICODEindex(PIXEL* dst,
	size_t width, size_t height,
	int stride, TTF_Font **font, size_t n,
	uint32_t ch,
	unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index)
{
	TTF_Font* outf = TTF_FindGlyph(font,
		n, ch, CACHED_METRICS | CACHED_PIXMAP, true);
	if (!outf)
		return false;
	return render_unicode(dst, width, height, stride, font, n,
	outf, xstart, fg, bg, usebg, use_kerning, style, advance, prev_index);
}

bool TTF_RenderUNICODEglyph(PIXEL* dst,
	size_t width, size_t height,
	int stride, TTF_Font **font, size_t n,
	uint32_t ch,
	unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index)
{
	TTF_Font* outf = TTF_FindGlyph(font,
		n, ch, CACHED_METRICS|CACHED_PIXMAP, false);
	if (!outf)
		return false;
	return render_unicode(dst, width, height, stride, font, n,
	outf, xstart, fg, bg, usebg, use_kerning, style, advance, prev_index);
}

bool TTF_RenderUTF8chain(PIXEL* dst, size_t width, size_t height,
	int stride, TTF_Font **font, size_t n,
	const char* intext, uint8_t fg[4], int style)
{
	unsigned xstart;
	const uint32_t* ch;
	unsigned prev_index = 0;

	if (!intext || intext[0] == '\0')
		return true;

/* Copy the UTF-8 text to a UNICODE text buffer, naive size */
	int unicode_len = strlen(intext);

/* Note that this buffer is shared and grows! */
	size_upool(unicode_len+1);
	if (!unicode_buf)
		return false;

	uint32_t* text = unicode_buf;
	UTF8_to_UTF32(text, (const uint8_t*) intext, unicode_len);

/* Load and render each character */
	xstart = 0;

	for (ch=text; *ch; ++ch){
		int advance = 0;

		TTF_RenderUNICODEglyph(dst, width, height, stride,
			font, n, *ch, &xstart, fg, fg,
			false, FT_HAS_KERNING(font[0]->font->face) && font[0]->font->kerning, style,
			&advance, &prev_index
		);

		xstart += advance;
	}

	return true;
}

int TTF_GetFontStyle( const TTF_Font* font )
{
	return font->font->style;
}

void TTF_SetFontOutline( TTF_Font* font_ref, int outline )
{
	if (font_ref->font->outline == outline)
		return;

	if (font_ref->cache_entry) {
		struct _TTF_Font template = *font_ref->font;
		template.outline = outline;

		c_font* fork = TTF_FindOrForkCachedFont(font_ref->cache_entry, &template);

		if (!fork)
			return;

		font_ref->font = fork->font;
		font_ref->cache_entry = fork;
	}

	if (font_ref->font->outline != outline) {
		font_ref->font->outline = outline;
		TTF_Flush_Cache( font_ref );
	}
}

int TTF_GetFontOutline( const TTF_Font* font_ref )
{
	return font_ref->font->outline;
}

void TTF_SetFontHinting( TTF_Font* font_ref, int hinting )
{
	int new_hinting;
	if (hinting == TTF_HINTING_LIGHT)
		new_hinting = FT_RENDER_MODE_LIGHT;
	else if (hinting == TTF_HINTING_MONO)
		new_hinting = FT_RENDER_MODE_MONO;
	else if (hinting == TTF_HINTING_NONE)
		new_hinting = FT_RENDER_MODE_MONO;
	else if (hinting == TTF_HINTING_RGB)
		new_hinting = FT_RENDER_MODE_LCD;
	else if (hinting == TTF_HINTING_VRGB)
		new_hinting = FT_RENDER_MODE_LCD_V;
	else
		new_hinting = FT_RENDER_MODE_NORMAL;

	if (font_ref->font->hinting == new_hinting)
		return;

	if (font_ref->cache_entry) {
		struct _TTF_Font template = *font_ref->font;
		template.hinting = new_hinting;

		c_font* fork = TTF_FindOrForkCachedFont(font_ref->cache_entry, &template);

		if (!fork)
			return;

		font_ref->font = fork->font;
		font_ref->cache_entry = fork;
	}

	if (font_ref->font->hinting != new_hinting) {
		font_ref->font->hinting = new_hinting;
		TTF_Flush_Cache( font_ref );
	}
}

int TTF_GetFontHinting( const TTF_Font* font_ref )
{
	int hinting = font_ref->font->hinting;
	if (hinting == FT_LOAD_TARGET_LIGHT)
		return TTF_HINTING_LIGHT;
	else if (hinting == FT_LOAD_TARGET_MONO)
		return TTF_HINTING_MONO;
	else if (hinting == FT_LOAD_NO_HINTING)
		return TTF_HINTING_NONE;
	else if (hinting == FT_RENDER_MODE_LCD)
		return TTF_HINTING_RGB;
	else if (hinting == FT_RENDER_MODE_LCD_V)
		return TTF_HINTING_VRGB;
	else
		return TTF_HINTING_NORMAL;
}

void TTF_Quit( void )
{
	if ( TTF_initialized ) {
		if ( --TTF_initialized == 0 ) {
			FT_Done_FreeType( library );
		}
	}
}

int TTF_WasInit( void )
{
	return TTF_initialized;
}

int TTF_GetFontKerningSize(TTF_Font* font_ref, int prev_index, int index)
{
	FT_Vector delta;
	FT_Get_Kerning( font_ref->font->face, prev_index, index, ft_kerning_default, &delta );
	return (delta.x >> 6);
}

void TTF_ProbeFont(TTF_Font* font_ref, size_t* dw, size_t* dh)
{
	if (font_ref->font->cached_width > 0 && font_ref->font->cached_height > 0) {
		*dw = font_ref->font->cached_width;
		*dh = font_ref->font->cached_height;
		return;
	}

	static const char* msg[] = {
		"A", "a", "!", "_", "J", "j", "G", "g", "M", "m", "`", "-", "=", NULL
	};

	TTF_Color fg = {.r = 0xff, .g = 0xff, .b = 0xff};
	int w = 1, h = 1;

/*
 * Flush the cache so we're not biased or collide with byIndex or byValue
 */
	TTF_Flush_Cache(font_ref);

	for (size_t i = 0; msg[i]; i++){
		TTF_SizeUTF8(font_ref, msg[i], &w, &h, TTF_STYLE_BOLD | TTF_STYLE_UNDERLINE);

		if (font_ref->font->hinting == TTF_HINTING_RGB)
			w++;

		if (w > *dw)
			*dw = w;

		if (h > *dh)
			*dh = h;
	}

	font_ref->font->cached_width = *dw;
	font_ref->font->cached_height = *dh;
}
