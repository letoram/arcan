/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#include <stddef.h>
#include <stdint.h>

#include "decomp.h"

int uu_decompose_char(unsigned c, unsigned *d, unsigned max)
{
	unsigned p;
	const uint32_t *page;

	if (!max) return 0;

	if (c-0xac00 <= 0xd7a3-0xac00) { /* hangul */
		int i = 1;
		c -= 0xac00;
		d[0] = 0x1100 + c/588;
		if (--max) d[i++] = 0x1161 + (c%588)/28;
		if (c % 28 && --max) d[i++] = 0x11a7 + (c%28);
		return i;
	}

	p = c>>8;
	if (p <= sizeof(pages)/sizeof(pages[0])) page = pages[p];
	else page = NULL;

	if (page && (page[c>>5 & 7] & 1<<(c&31))) {
		/* fixme: do binary search instead of linear.. */
		const unsigned short *tab;
		for (tab=decomp; *tab && *tab != c; tab+=3);
		if (*tab++) {
			int len = uu_decompose_char(*tab++, d, max);
			d += len; max -= len;
			return len + uu_decompose_char(*tab, d, max);
		}
	}
	*d = c;
	return 1;
}
