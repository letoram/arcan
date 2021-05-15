/*
 * Stub implementation of the TTF calls that would otherwise pull in
 * a dependency to freetype et al. Used when TUI is built with
 * TUI_RASTER_NO_TTF and defined as such in shmif/CMakeLists.txt
 */

#include <inttypes.h>
#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"

#define SHMIF_TTF
#include "arcan_ttf.h"

void TTF_ProbeFont(TTF_Font* font, size_t* dw, size_t* dh)
{
	*dw = 0;
	*dh = 0;
}

/* open font using a preexisting file descriptor, takes ownership of fd */
TTF_Font* TTF_OpenFontFD(int fd, int ptsize, uint16_t hdpi, uint16_t vdpi)
{
	close(fd);
	return NULL;
}

void TTF_CloseFont(TTF_Font* font)
{
}

TTF_Font* TTF_FindGlyph(TTF_Font** fonts, int n, uint32_t ch, int want, bool by_ind)
{
	return NULL;
}

bool TTF_RenderUNICODEglyph(PIXEL* dst,
	size_t width, size_t height, int stride, TTF_Font** font, size_t n,
	uint32_t ch, unsigned* xstart, uint8_t fg[4], uint8_t bg[4],
	bool usebg, bool use_kerning, int style,
	int* advance, unsigned* prev_index)
{
	return false;
}

void TTF_SetFontHinting(TTF_Font *font, int hinting)
{
}

void TTF_SetFontStyle(TTF_Font *font, int style)
{
}

void TTF_FontStyle(TTF_Font* font, int style)
{
}
