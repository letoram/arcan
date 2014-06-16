/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

/* note: the following implementation of ucf is NOT SECURE. malicious or
 * damaged files can cause it to crash or possibly enter into an infinite
 * loop, or cause other parts of the process core to be read as a font,
 * possibly leading to information leaks. however there is no possibility
 * of privilege elevation as ucf never writes to memory.
 *
 * users needing a robust implementation would be advised to simply run a
 * sanity check across the whole font file before accepting it, rather than
 * incurring large bounds-checking penalties at each glyph lookup.
 */

#include <stddef.h>
#include "ucf.h"

#define U24(p) ( ((p)[0]<<16) | ((p)[1]<<8) | (p)[2] )
#define U32(p) ( ((p)[0]<<24) | U24((p)+1) )

int ucf_init(struct ucf *f, const unsigned char *map, size_t len)
{
	size_t n;
	if (memcmp(map, "ucf\300\000\001\000\000", 8))
		return -1;
	f->w = map[8];
	f->h = map[9];
	f->s = (f->w+7)>>3;
	f->S = f->s * f->h;
	f->ranges = map + U32(map+20) + 4;
	f->gmap = map + U32(map+24);
	f->glyphs = map + U32(map+28);
	f->nglyphs = (len - (f->glyphs - map)) / f->S;
	f->ctab = f->ranges + 8*(f->nranges = U32(f->ranges - 4));
	return 0;
}

#define GMAP_WIDTH         1

#define GMAP_FINAL1        0
#define GMAP_FINAL2        1
#define GMAP_GLYPH1        2
#define GMAP_GLYPH2        3

#define RULE_RANGE         4
#define RULE_ATTACHED_TO   5
#define RULE_WITH_ATTACHED 6
#define RULE_FOLLOWS       7
#define RULE_PRECEDES      8

#define CTAB_MASK          0x3fffffff
#define CTAB_INDIRECT      0x80000000
#define CTAB_WIDTH         30

int ucf_lookup(struct ucf *f, int idx, const unsigned *cc,
	const unsigned *pc, const unsigned *nc, int width)
{
	unsigned ch = cc[idx];
	unsigned a, l, x, i;
	const unsigned *c;
	const unsigned char *p;

	for (p=f->ranges, a=0; ch>=(a+=U32(p)); p+=8) {
		if (ch-a < (l=U32(p+4))) {
			x = U32(f->ctab+4*(a-1));
			if (x>>30 != width-1)
				return -1;
			return (x & 0x3fffffff) + (ch-a)*width;
		}
		ch -= l;
	}
	x = U32(f->ctab+4*ch);
	if (!((x+1) & CTAB_INDIRECT)) {
		if (x>>CTAB_WIDTH != width-1) return -1;
		return x & CTAB_MASK;
	}
	x &= 0x7fffffff;
	i = idx;
	c = cc;
	for (p=f->gmap+x; ; p+=4) {
		if (*p <= GMAP_GLYPH2) {
			if ((*p & GMAP_WIDTH) == width-1) break;
			else if (*p <= GMAP_FINAL2) return -1;
			i = idx; c = cc;
			continue;
		}
		x = *p;
		a = U24(p+1);
		if (p[4] == RULE_RANGE) {
			p += 4;
			l = U24(p+1);
		} else l = 1;
		switch (x) {
		case RULE_ATTACHED_TO:
			if (i > idx) i = idx;
			if (i && c[--i]-a < l) continue;
			break;
		case RULE_WITH_ATTACHED:
			if (i < idx) i = idx;
			if (c[++i]-a < l) continue;
			break;
		case RULE_FOLLOWS:
			if ((c=pc)[i=0]-a < l) continue;
			break;
		case RULE_PRECEDES:
			if ((c=nc)[i=0]-a < l) continue;
			break;
		}
		/* Skip until the next mapping */
		for (; *p > GMAP_GLYPH2; p+=4);
		i = idx; c = cc;
	}
	return U24(p+1);
}

#if 0
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[])
{
	int i, j;
	struct ucf f;
	static char tmp[1000000];
	ucf_init(&f, tmp, fread(tmp, 1, sizeof tmp, stdin));
	for (i=1; i<argc; i++) {
		unsigned x[5] = { strtol(argv[i], NULL, 16), 0 };
		int g;
		if (i+1<argc) x[1] = strtol(argv[i+1], NULL, 16);
		printf("char %.4x maps to glyph %d\n", x[1], g=ucf_lookup(&f, 1, x, x+4, x+4, 1));
		if (g >= 0) for (j=0; j<16; j++)
			printf("%.2X", f.glyphs[16*g+j]);
		printf("\n");
	}
	return 0;
}
#endif
