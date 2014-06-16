/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#include <inttypes.h>
#include <string.h>

#include "uuterm.h"
#include "dblbuf.h"

static void blitline8(unsigned char *dest, unsigned char *src, unsigned long *colors, int w)
{
#define T(x) ~((x&8)*0xff>>3 | (x&4)*0xff<<6 | (x&2)*0xff<<15 | (x&1)*0xff<<24)
        static const uint32_t tab[16] = {
                T(0), T(1), T(2), T(3), T(4), T(5), T(6), T(7),
                T(8), T(9), T(10), T(11), T(12), T(13), T(14), T(15)
        };
#undef T
	uint32_t *dest4 = (uint32_t*)dest;
	for(; w--; dest4+=2, colors+=2) {
		int s = *src++;
		int t0 = tab[s>>4];
		int t1 = tab[s&15];
		dest4[0] = colors[0] ^ (colors[1] & t0);
		dest4[1] = colors[0] ^ (colors[1] & t1);
	}
}

static void blitline16(unsigned char *dest, unsigned char *src, unsigned long *colors, int w)
{
        static const union {
		unsigned char b[4];
		uint32_t w;
	} tab[4] = {
		{ { 0xff, 0xff, 0xff, 0xff } },
		{ { 0xff, 0xff, 0x00, 0x00 } },
		{ { 0x00, 0x00, 0xff, 0xff } },
		{ { 0x00, 0x00, 0x00, 0x00 } }
        };
	uint32_t *dest4 = (uint32_t*)dest;
	for(; w--; dest4+=4, colors+=2) {
		int s = *src++;
		uint32_t t0 = tab[s>>6].w;
		uint32_t t1 = tab[(s>>4)&3].w;
		uint32_t t2 = tab[(s>>2)&3].w;
		uint32_t t3 = tab[s&3].w;
		dest4[0] = colors[0] ^ (colors[1] & t0);
		dest4[1] = colors[0] ^ (colors[1] & t1);
		dest4[2] = colors[0] ^ (colors[1] & t2);
		dest4[3] = colors[0] ^ (colors[1] & t3);
	}
}

static void blit_slice(struct uudisp *d, int idx, int x1, int x2)
{
	struct dblbuf *b = (void *)&d->priv;
	int cs = (d->cell_w+7)>>3;
	int y = b->slices[idx].y;
	int w = x2 - x1 + 1;
	int s = d->w * cs;
	int i;

	unsigned char *dest = b->vidmem + y*b->row_stride
		+ x1*d->cell_w*b->bytes_per_pixel;
	unsigned char *src = b->slices[idx].bitmap + x1*cs;
	unsigned long *colors = b->slices[idx].colors + 2*x1;

	for (i=0; i<d->cell_h; i++) {
		if (b->bytes_per_pixel == 1)
			blitline8(dest, src, colors, w);
		else if (b->bytes_per_pixel == 2)
			blitline16(dest, src, colors, w);
		dest += b->line_stride;
		src += s;
	}
}

void clear_cells(struct uudisp *d, int idx, int x1, int x2)
{
	struct dblbuf *b = (void *)&d->priv;
	int i;
	int cs = d->cell_w+7 >> 3;
	int cnt = (x2 - x1 + 1) * cs;
	int stride = d->w * cs;
	unsigned char *dest = b->slices[idx].bitmap + x1 * cs;

	memset(b->slices[idx].colors + 2*x1, 0, (x2-x1+1)*2*sizeof(long));
	for (i=d->cell_h; i; i--, dest += stride)
		memset(dest, 0, cnt);
}

static unsigned long expand_color(struct uudisp *d, int color)
{
	struct dblbuf *b = (void *)&d->priv;
	static const unsigned char cmap[8] = {0,4,2,6,1,5,3,7};
	static const unsigned char defpal[16][3] = {
#if 0
		{ 0,0,0 }, { 128,0,0 }, { 0,128,0 }, { 85,85,0 },
		{ 0,0,128 }, { 85,0,85 }, { 0,85,85 }, { 170,170,170 },
		{ 85,85,85 }, { 255,0,0 }, { 0,255,85 }, { 255,255,0 },
		{ 0,0,255 }, { 255,0,255 }, { 0,255,255 }, { 255,255,255 }
#else
		{ 0,0,0 }, { 96,0,0 }, { 0,96,0 }, { 85,85,0 },
		{ 0,0,144 }, { 96,0,96 }, { 0,96,96 }, { 170,170,170 },
		{ 85,85,85 }, { 255,85,85 }, { 85,255,85 }, { 255,255,85 },
		{ 85,85,255 }, { 255,85,255 }, { 85,255,255 }, { 255,255,255 }
#endif
	};
	if (b->bytes_per_pixel > 1) {
		int R = defpal[color][0];
		int G = defpal[color][1];
		int B = defpal[color][2];
		if (b->bytes_per_pixel == 2) {
			R >>= 3; G >>= 2; B >>= 3;
			return (B | G<<5 | R<<11)
				* (unsigned long)0x0001000100010001;
		} else if (b->bytes_per_pixel == 4)
			return (B | G<<8 | R<<16)
				* (unsigned long)0x0000000100000001;
	}
	color = (color&8) | cmap[color&7];
	return color * (unsigned long)0x0101010101010101;
}

void uudisp_predraw_cell(struct uudisp *d, int idx, int x, int color)
{
	struct dblbuf *b = (void *)&d->priv;

	b->slices[idx].colors[2*x] = expand_color(d, color&255);
	b->slices[idx].colors[2*x+1] = expand_color(d, color>>8) ^ b->slices[idx].colors[2*x];
}

void uudisp_draw_glyph(struct uudisp *d, int idx, int x, const void *glyph)
{
	struct dblbuf *b = (void *)&d->priv;
	int i;
	int cs = d->cell_w+7 >> 3;
	int stride = d->w * cs;
	unsigned char *src = (void *)glyph;
	unsigned char *dest = b->slices[idx].bitmap + cs * x;

	for (i=d->cell_h; i; i--, dest += stride)
		*dest |= *src++;
}

void uudisp_refresh(struct uudisp *d, struct uuterm *t)
{
	struct dblbuf *b = (void *)&d->priv;
	int h = t->h < d->h ? t->h : d->h;
	int x1, x2, idx, y;

	if (!b->active) return;
	if (b->repaint) {
		for (idx=0; idx<h; idx++) b->slices[idx].y = -1;
		b->repaint = 0;
	}

	/* Clean up cursor first.. */
	idx = t->rows[b->curs_y]->idx;
	if ((unsigned)b->slices[idx].y < d->h)
		blit_slice(d, idx, b->curs_x, b->curs_x);

	for (y=0; y<h; y++) {
		x1 = t->rows[y]->x1;
		x2 = t->rows[y]->x2;
		idx = t->rows[y]->idx;
		if (x2 >= x1) {
			clear_cells(d, idx, x1, x2);
			uuterm_refresh_row(d, t->rows[y], x1, x2);
			t->rows[y]->x1 = t->w;
			t->rows[y]->x2 = -1;
		}
		if (b->slices[idx].y != y) {
			b->slices[idx].y = y;
			x1 = 0;
			x2 = d->w-1;
		} else if (x2 < x1) continue;
		blit_slice(d, idx, x1, x2);
	}

	if (d->blink & 1) {
		unsigned long rev = expand_color(d, 15);
		int idx = t->rows[t->y]->idx;
		b->slices[idx].colors[2*t->x] ^= rev;
		blit_slice(d, idx, t->x, t->x);
		b->slices[idx].colors[2*t->x] ^= rev;
	}
	b->curs_x = t->x;
	b->curs_y = t->y;
}

struct slice *dblbuf_setup_buf(int w, int h, int cs, int ch, unsigned char *mem)
{
	struct slice *slices = (void *)mem;
	int i;

	mem += sizeof(slices[0]) * h;

	for (i=0; i<h; i++, mem += w*2*sizeof(long)) {
		slices[i].y = -1;
		slices[i].colors = (unsigned long *)mem;
	}
	w *= cs * ch;
	for (i=0; i<h; i++, mem += w)
		slices[i].bitmap = mem;

	return slices;
}
