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

