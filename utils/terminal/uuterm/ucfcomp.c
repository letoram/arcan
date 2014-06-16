#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

struct gmap
{
	struct gmap *next, *prev;
	int glyph;
	int width;
	unsigned char rules[4*8];
	int len;
	int offset;
};

static struct gmap *ctab[0x30000];

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

static void put_u32(int n)
{
	putchar(n>>24);
	putchar(n>>16);
	putchar(n>>8);
	putchar(n);
}

int main()
{
	char buf[256], *s;
	int i;
	int ch;
	struct gmap *gm;
	int type, begin, len;
	int w=8, h=16;
	unsigned char gbuf[32];
	char tmp[3];
	int width;
	int nglyphs = 0;
	unsigned char *glyphs = 0;
	struct { unsigned begin, len, rel; } *ranges = 0;
	int nranges = 0;
	int ctab_len = 0;
	int gmap_len = 0;

	while ((s=fgets(buf, sizeof buf, stdin))) {
		if (*s++ != ':') continue;
		for (tmp[2]=i=0; i<sizeof gbuf && isxdigit(tmp[0]=*s++) && isxdigit(tmp[1]=*s++); i++)
			gbuf[i] = strtol(tmp, NULL, 16);
		if (i == 32) {
			unsigned char gbuf_tmp[32];
			width = 2;
			for (i=0; i<16; i++) gbuf_tmp[i] = gbuf[2*i];
			for (i=0; i<16; i++) gbuf_tmp[16+i] = gbuf[2*i+1];
			memcpy(gbuf, gbuf_tmp, 32);
		} else if (i == 16) { width = 1;
		} else exit(1);
		glyphs = realloc(glyphs, 16*(width+nglyphs));
		memcpy(glyphs + 16*nglyphs, gbuf, 16*width);
		nglyphs += width;
		for (;;) {
			for (; isspace(*s); s++);
			if (!*s) break;
			ch = strtol(s, &s, 16);
			gm = calloc(1, sizeof(struct gmap));
			gm->glyph = nglyphs-width;
			gm->width = width;
			gm->next = 0;
			gm->prev = ctab[ch];
			if (ctab[ch]) ctab[ch]->next = gm;
			ctab[ch] = gm;
			i=0;
			while(i<sizeof(gm->rules)-12 && *s && !isspace(*s)) {
				switch (*s++) {
				case '+': type = RULE_WITH_ATTACHED; break;
				case '-': type = RULE_ATTACHED_TO; break;
				case '<': type = RULE_PRECEDES; break;
				case '>': type = RULE_FOLLOWS; break;
				default: exit(1);
				}
				if (*s == '[') {
					begin = strtol(++s, &s, 16);
					if (*s++ != '-') exit(1);
					len = strtol(s, &s, 16) - begin + 1;
					if (*s++ != ']') exit(1);
					gm->rules[i++] = type;
					gm->rules[i++] = begin>>16;
					gm->rules[i++] = begin>>8;
					gm->rules[i++] = begin;
					gm->rules[i++] = RULE_RANGE;
					gm->rules[i++] = len>>16;
					gm->rules[i++] = len>>8;
					gm->rules[i++] = len;
				} else if (isxdigit(*s)) {
					begin = strtol(s, &s, 16);
					gm->rules[i++] = type;
					gm->rules[i++] = begin>>16;
					gm->rules[i++] = begin>>8;
					gm->rules[i++] = begin;
				} else exit(1);
			}
			gm->rules[i++] = GMAP_GLYPH1 | (gm->width-1);
			gm->rules[i++] = (gm->glyph)>>16;
			gm->rules[i++] = (gm->glyph)>>8;
			gm->rules[i++] = (gm->glyph);
			gm->len = i;
		}
	}

	/* Count total glyph mapping rules and figure the table offsets */
	for (ch=0; ch < sizeof(ctab)/sizeof(ctab[0]); ch++) {
		for (gm = ctab[ch]; gm && gm->prev; gm = gm->prev);
		/* Exclude rules that can be replaced by a trivial mapping */
		if (!gm || (!gm->next && gm->len == 4)) {
			if (gm) gm->len = 0;
			continue;
		}
		for (ctab[ch] = gm; gm; gm = gm->next) {
			/* Terminate the rules list */
			if (!gm->next) gm->rules[gm->len-4] &= GMAP_WIDTH;
			gm->offset = gmap_len;
			gmap_len += gm->len;
		}
	}

	/* Compact empty intervals and intervals with trivial glyph mapping */
	begin = 1;
	for (ch=1; ch <= sizeof(ctab)/sizeof(ctab[0]); ch++) {
		if (ch == sizeof(ctab)/sizeof(ctab[0])
		 || (ctab[ch-1] != ctab[ch]
		 &&(!ctab[ch-1] || !ctab[ch]
		 || ctab[ch-1]->prev || ctab[ch-1]->len > 4
		 || ctab[ch]->prev   || ctab[ch]->len > 4
		 || ctab[ch]->glyph != ctab[ch-1]->glyph + ctab[ch-1]->width
		 || ctab[ch]->width != ctab[ch-1]->width))) {
			if (ch - begin >= 1024) {
				ranges = realloc(ranges, sizeof(ranges[0])*(nranges+1));
				ranges[nranges].begin = begin;
				ranges[nranges++].len = ch-begin;
			}
			begin = ch+1;
		}
	}
	ranges[nranges-1].len = 0x110000;

	/* Count total size of the character table */
	ranges[0].rel = ranges[0].begin;
	ctab_len = 1 + nranges*2 + ranges[0].begin;
	for (i=1; i<nranges; i++)
		ctab_len += ranges[i].rel = ranges[i].begin - (ranges[i-1].begin+ranges[i-1].len);
	ctab_len *= 4;

	// offset 0: magic and version (0.1.0.0)
	fwrite("ucf\300\000\001\000\000", 1, 8, stdout);
	// offset 8
	putchar(8);
	putchar(16);
	putchar(0);
	putchar(0);
	putchar(0);
	putchar(0);
	putchar(0);
	putchar(0);
	// offset 16
	put_u32(0); // metadata offset
	put_u32(32); // ctab offset
	put_u32(32+ctab_len); // gmap offset
	put_u32(32+ctab_len+gmap_len); // glyph bitmaps
	// offset 32
	put_u32(nranges);
	for (i=0; i<nranges; i++) {
		put_u32(ranges[i].rel);
		put_u32(ranges[i].len);
	}
	for (i=ch=0; ch<sizeof(ctab)/sizeof(ctab[0]); ch++) {
		if (ch == ranges[i].begin) {
			ch += ranges[i++].len-1;
			continue;
		}
		if (!ctab[ch])
			put_u32(-1);
		else if (ctab[ch]->len == 0)
			put_u32(ctab[ch]->glyph | ctab[ch]->width-1<<30);
		else
			put_u32(ctab[ch]->offset | 0x80000000);
	}
	// offset 32 + ctab_len
	for (ch=0; ch < sizeof(ctab)/sizeof(ctab[0]); ch++)
		for (gm = ctab[ch]; gm; gm = gm->next)
			fwrite(gm->rules, 1, gm->len, stdout);
	// offset 30 + ctab_len + gmap_len
	fwrite(glyphs, 16, nglyphs, stdout);

	return 0;
}
