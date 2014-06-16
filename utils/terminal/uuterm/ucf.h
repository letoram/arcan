/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#include <stddef.h>

struct ucf
{
	int w, h, s, S;
	const unsigned char *ranges, *ctab, *gmap, *glyphs;
	unsigned nranges, nglyphs;
};

int ucf_load(struct ucf *, const char *);
int ucf_init(struct ucf *, const unsigned char *, size_t);
int ucf_lookup(struct ucf *, int, const unsigned *,
	const unsigned *, const unsigned *, int);
