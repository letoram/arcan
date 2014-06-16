/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#include <string.h>

#include "uuterm.h"
#include "ucf.h"

static void extract_cell(unsigned *ch, size_t max, struct uucell *cell)
{
	int i, j, l;
	wchar_t ws[8];
	int attr = uucell_get_attr(cell);

	uucell_get_wcs(cell, ws, 8);

	for (i=j=0; ws[i]; i++) {
		l = uu_decompose_char(ws[i], ch, max);
		ch += l; max -= l;
	}
	if ((attr & UU_ATTR_UL) && max)
		max--, *ch++ = 0x0332;
	for (; max; max--) *ch++ = 0;
	ch[-1] = 0;
}

const void *ascii_get_glyph(unsigned);

static const void *lookup_glyph(struct ucf *f, int i, unsigned *this, unsigned *prev, unsigned *next, int width, int part)
{
	const unsigned char *a;
	static const unsigned c[2] = { 0xfffd, 0 };
	int g = ucf_lookup(f, i, this, prev, next, width);
	if (g<0 && !i) g = ucf_lookup(f, i, c, c, c, width);
	if (g>=0) return f->glyphs + f->S * (g + part);
	return 0;
}

#define CH_LEN 16
void uuterm_refresh_row(struct uudisp *d, struct uurow *row, int x1, int x2)
{
	unsigned ch[4][CH_LEN], *chp;
	int x, i;
	int width, part;

	if (x1) extract_cell(ch[(x1-1)&3], CH_LEN, &row->cells[x1-1]);
	else memset(ch[3], 0, sizeof(ch[3]));
	extract_cell(ch[x1&3], CH_LEN, &row->cells[x1]);

	for (x=x1; x<=x2; x++) {
		extract_cell(ch[(x+1)&3], CH_LEN, &row->cells[x+1]);
		if (ch[x&3][0] == UU_FULLWIDTH) {
			width = 2; part = 0; chp = ch[(x+1)&3];
		} else if (ch[(x+3)&3][0] == UU_FULLWIDTH) {
			width = 2; part = 1; chp = ch[x&3];
		} else {
			width = 1; part = 0; chp = ch[x&3];
		}
		uudisp_predraw_cell(d, row->idx, x, uucell_get_color(&row->cells[x]));
		for (i=0; i<sizeof(ch[0]) && chp[i]; i++) {
			const void *glyph = lookup_glyph(d->font, i, chp, ch[(x+3)&3], ch[(x+1)&3], width, part);
			if (glyph) uudisp_draw_glyph(d, row->idx, x, glyph);
		}
	}
}


