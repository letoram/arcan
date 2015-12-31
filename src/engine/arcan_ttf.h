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
 * This version has been modified to strip down most of the SDL specific code,
 * as well as rendering modes other than blended, so TTF_Surface* and SDL_color
 * references have all been replaced.
 */

#ifndef _SDL_TTF_H
#define _SDL_TTF_H

/* ZERO WIDTH NO-BREAKSPACE (Unicode byte order mark) */
#define UNICODE_BOM_NATIVE	0xFEFF
#define UNICODE_BOM_SWAPPED	0xFFFE

/* This function tells the library whether UNICODE text is generally
  byteswapped. A UNICODE BOM character in a string will override
  this setting for the remainder of that string.
*/
void TTF_ByteSwappedUNICODE(int swapped);

/* The internal structure containing font information */
typedef struct _TTF_Font TTF_Font;

typedef struct {
    int width, height, stride;
    char bpp;
    char* data;
} TTF_Surface;

typedef struct {
    uint8_t r, g, b;
} TTF_Color;


/* Initialize the TTF engine - returns 0 if successful, -1 on error */
int TTF_Init(void);

/* Open a font file and create a font of the specified point size.
 * Some .fon fonts will have several sizes embedded in the file, so the
 * point size becomes the index of choosing which size. If the value
 * is too high, the last indexed size will be the default. */
TTF_Font* TTF_OpenFont(const char *file, int ptsize);

TTF_Font* TTF_OpenFontIndex(const char *file, int ptsize, long index);
TTF_Font* TTF_OpenFontRW(FILE* src, int freesrc, int ptsize);
TTF_Font* TTF_OpenFontIndexRW(FILE* src, int freesrc, int ptsize, long index);

/* open font using a preexisting file descriptor, takes ownership of fd */
TTF_Font* TTF_OpenFontFD(int fd, int ptsize);

/* Set and retrieve the font style */
#define TTF_STYLE_NORMAL	0x00
#define TTF_STYLE_BOLD		0x01
#define TTF_STYLE_ITALIC	0x02
#define TTF_STYLE_UNDERLINE	0x04
#define TTF_STYLE_STRIKETHROUGH	0x08
int TTF_GetFontStyle(const TTF_Font *font);
void TTF_SetFontStyle(TTF_Font *font, int style);
int TTF_GetFontOutline(const TTF_Font *font);
void TTF_SetFontOutline(TTF_Font *font, int outline);

/* Set and retrieve FreeType hinter settings */
#define TTF_HINTING_NORMAL  0
#define TTF_HINTING_LIGHT   1
#define TTF_HINTING_MONO   2
#define TTF_HINTING_NONE   3
int TTF_GetFontHinting(const TTF_Font *font);
void TTF_SetFontHinting(TTF_Font *font, int hinting);

/* Get the total height of the font - usually equal to point size */
int TTF_FontHeight(const TTF_Font *font);

/* Get the offset from the baseline to the top of the font
  This is a positive value, relative to the baseline.
 */
int TTF_FontAscent(const TTF_Font *font);

/* Get the offset from the baseline to the bottom of the font
  This is a negative value, relative to the baseline.
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
int TTF_GlyphIsProvided(const TTF_Font *font, uint16_t ch);

/* Get the metrics (dimensions) of a glyph
  To understand what these metrics mean, here is a useful link:
  http://freetype.sourceforge.net/freetype2/docs/tutorial/step2.html
 */
int TTF_GlyphMetrics(TTF_Font *font, uint16_t ch, int *minx,
	int *maxx, int *miny, int *maxy, int *advance);

/* Get the dimensions of a rendered string of text */
int TTF_SizeText(TTF_Font *font, const char *text, int *w, int *h);
int TTF_SizeUTF8(TTF_Font *font, const char *text, int *w, int *h);
int TTF_SizeUNICODE(TTF_Font *font, const uint16_t *text, int *w, int *h);

TTF_Surface* TTF_RenderText(TTF_Font *font,
				const char *text, TTF_Color fg);
TTF_Surface* TTF_RenderUTF8(TTF_Font *font,
				const char *text, TTF_Color fg);
TTF_Surface* TTF_RenderUNICODE(TTF_Font *font,
				const uint16_t *text, TTF_Color fg);

/* Close an opened font file */
void TTF_CloseFont(TTF_Font *font);

/* De-initialize the TTF engine */
void TTF_Quit(void);

/* Check if the TTF engine is initialized */
int TTF_WasInit(void);

/* Get the kerning size of two glyphs */
int TTF_GetFontKerningSize(TTF_Font *font, int prev_index, int index);

#endif
