/*
 * Arcan Hijack/Frameserver State Manager (incomplete)
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Still just a stub, nothing to see here. The plan is to add
 * per-session state tracking and use that to enable rewinding.
 */

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <stdbool.h>

#include "stateman.h"

struct stateman_ctx {
	int range_start, range_end;
};

struct stateman_ctx* stateman_setup(size_t state_sz,
	ssize_t limit, int precision){
	return NULL;
}

void stateman_feed(struct stateman_ctx* ctx, int tstamp, void* inbuf)
{
	if (!ctx)
		return;
}

bool stateman_seek(struct stateman_ctx* ctx, void* dstbuf, int tstamp, bool rel)
{
	return false;
}

void stateman_drop(struct stateman_ctx** dst)
{
	if (!dst || *dst == NULL)
		return;
}

