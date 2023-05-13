/*
 SDL_ttf: A companion library to SDL for working with TrueType (tm) fonts
 Copyright (C) 2001-2012 Sam Lantinga <slouken@libsdl.org>

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
 3. This notice may not be removed or altered from any source distribution.
*/

/* This library is a wrapper around the excellent FreeType 2.0 library,
  available at:
	http://www.freetype.org/
*/

/*
 * Arcan Modifications:
 *
 *  1. Removed dependency to SDL and a ton of related functions
 *  2. Added in-place rendering
 *  3. Switched to UTF8 at border, UCS4 Internally (no more UCS2)
 *  4. Added glyph selection from multiple font files
 *  5. Added support for multicolored output and subpixel hinting
 *
 *  Big Note: While still messy, this is slated for full replacement /
 *  deprecation to use something akin to freetype-gl (but with a similar
 *  interface for when/if we need raster fallback) so we can use bin-packing,
 *  distance field quality improvements and harfbuzz shaping.
 */

#ifndef _ARCAN_TTF_H
#define _ARCAN_TTF_H

/* The internal structure containing font information */
typedef struct c_font_ref TTF_Font;

typedef struct {
	uint8_t r, g, b;
} TTF_Color;


/* Initialize the TTF engine - returns 0 if successful, -1 on error */
int TTF_Init(void);

/* Open a font file and create a font of the specified point size.
 * Some .fon fonts will have several sizes embedded in the file, so the
 * point size becomes the index of choosing which size. If the value
 * is too high, the last indexed size will be the default. */
TTF_Font* TTF_OpenFont(const char *file, int ptsize, uint16_t hdpi, uint16_t vdpi);

TTF_Font* TTF_OpenFontIndex(const char *file, int ptsize,
	uint16_t hdpi, uint16_t vdpi, long index);
TTF_Font* TTF_OpenFontRW(FILE* src, int freesrc, int ptsize,
	uint16_t hdpi, uint16_t vdpi);
TTF_Font* TTF_OpenFontIndexRW(FILE* src, int freesrc, int ptsize,
	uint16_t hdpi, uint16_t vdpi, long index);

/* open font using a preexisting file descriptor, takes ownership of fd */
TTF_Font* TTF_OpenFontFD(int fd, int ptsize, uint16_t hdpi, uint16_t vdpi);

/* open font using a preexisting font for file, will close *src if needed */
TTF_Font* TTF_ReplaceFont(TTF_Font*, int pt, uint16_t hdpi, uint16_t vdpi);

void* TTF_GetFtFace(TTF_Font*);

int UTF8_to_UTF32(uint32_t* out, const uint8_t* in, size_t len);

void TTF_Resize(TTF_Font* font, int ptsize, uint16_t hdpi, uint16_t vdpi);

/* Set and retrieve the font style */
#define TTF_STYLE_NORMAL 0x00
#define TTF_STYLE_BOLD 0x01
#define TTF_STYLE_ITALIC 0x02
#define TTF_STYLE_UNDERLINE 0x04
#define TTF_STYLE_STRIKETHROUGH 0x08
int TTF_GetFontStyle(const TTF_Font *font);
void TTF_SetFontStyle(TTF_Font *font, int style);
int TTF_GetFontOutline(const TTF_Font *font);
void TTF_SetFontOutline(TTF_Font *font, int outline);

int TTF_underline_top_row(TTF_Font *font);
int TTF_underline_bottom_row(TTF_Font *font);

int TTF_strikethrough_top_row(TTF_Font *font);

/* Set and retrieve FreeType hinter settings */
#define TTF_HINTING_NORMAL  3
#define TTF_HINTING_LIGHT  2
#define TTF_HINTING_MONO   1
#define TTF_HINTING_NONE   0
#define TTF_HINTING_RGB 4
#define TTF_HINTING_VRGB 5

int TTF_GetFontHinting(const TTF_Font *font);
void TTF_SetFontHinting(TTF_Font *font, int hinting);

/* Get the total height of the font - usually equal to point size */
int TTF_FontHeight(const TTF_Font *font);

/* Get the offset from the baseline to the top of the font
 * This is a positive value, relative to the baseline.
 */
int TTF_FontAscent(const TTF_Font *font);

/* Get the offset from the baseline to the bottom of the font
 * This is a negative value, relative to the baseline.
 */
int TTF_FontDescent(const TTF_Font *font);

/* Get the recommended spacing between lines of text for this font */
int TTF_FontLineSkip(const TTF_Font *font);

/* Get/Set whether or not kerning is allowed for this font */
int TTF_GetFontKerning(const TTF_Font *font);
void TTF_SetFontKerning(TTF_Font *font, int allowed);

/* Get the number of faces of the font */
long TTF_FontFaces(const TTF_Font *font);

/* Get the font face attributes, if any */
int TTF_FontFaceIsFixedWidth(const TTF_Font *font);
char* TTF_FontFaceFamilyName(const TTF_Font *font);
char* TTF_FontFaceStyleName(const TTF_Font *font);

/* Check wether a glyph is provided by the font or not */
TTF_Font* TTF_FindGlyph(
	TTF_Font** fonts, int n, uint32_t ch, int want, bool by_ind);

/* Get the metrics (dimensions) of a glyph
 * To understand what these metrics mean, here is a useful link:
 * http://freetype.sourceforge.net/freetype2/docs/tutorial/step2.html
 */
int TTF_GlyphMetrics(TTF_Font *font, uint16_t ch, int *minx,
	int *maxx, int *miny, int *maxy, int *advance);

/* Get the dimensions of a rendered string of text */
int TTF_SizeUTF8(TTF_Font *font,
	const char *text, int *w, int *h, int style);
int TTF_SizeUNICODE(TTF_Font *font,
	const uint32_t *text, int *w, int *h, int style);

int TTF_SizeUNICODEchain(TTF_Font **font, size_t n,
	const uint32_t *text, int *w, int *h, int style);

/* This compilation unit is re-used by some frameservers as well,
 * in order to not mix and match types we need some trickery */
#ifdef SHMIF_TTF
#define PIXEL shmif_pixel
#define PACK(R, G, B, A) SHMIF_RGBA(R, G, B, A)
#else
#define PIXEL av_pixel
#define PACK(R, G, B, A) RGBA(R, G, B, A)
#endif

/* chain functions work like normal, except that they take multiple
 * fonts and select / scale a fallback if a glyph is not found. */
int TTF_SizeUTF8chain(TTF_Font **font, size_t n,
	const char *text, int *w, int *h, int style);

bool TTF_RenderUTF8chain(PIXEL* dst, size_t w, size_t h,
		int stride, TTF_Font **font, size_t n, const char* intext,
		uint8_t fg[4], int style
);

/*
 * RenderUTF8chain boils down to a number of these calls
 * [dst] buffer (possinly at offset) to render to
 * [width], [height] limitations to [dst] (in px)
 * [stride] number (of bytes) to step per row
 * [font] array of [n] TTF_Fonts for glyphs
 * [ch] UCS4 for unicode code point
 * [fg/bg] color (ignored on colored bitmaps)
 * [usebg] [usekerning] [style] drawing hints to font and positioning
 * [advance] incremental step write-back
 * [prev_index] state tracker for kerning
 */
bool TTF_RenderUNICODEglyph(PIXEL* dst,
	size_t width, size_t height, int stride,
	TTF_Font **font, size_t n,
	uint32_t ch,
	unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index
);

void TTF_Flush_Cache( TTF_Font* font );

/*
 * Same as TTF_RenderUNICODEglyph above, but 'ch' references the glyph index in
 * the font-chain, not the unicode codepoint.  This is only for special/trusted
 * contexts, e.g. shaping engines
 */
bool TTF_RenderUNICODEindex(PIXEL* dst,
	size_t width, size_t height, int stride,
	TTF_Font **font, size_t n,
	uint32_t ch,
	unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index
);

/* Close an opened font file */
void TTF_CloseFont(TTF_Font *font);

/* De-initialize the TTF engine */
void TTF_Quit(void);

/* Check if the TTF engine is initialized */
int TTF_WasInit(void);

/* Get the kerning size of two glyphs */
int TTF_GetFontKerningSize(TTF_Font *font, int prev_index, int index);

/* derive an 'ok' grid cell size for the font at its current size */
void TTF_ProbeFont(TTF_Font* font, size_t* dw, size_t* dh);

#endif
