/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include <arcan_math.h>
#include <arcan_general.h>

#ifndef REALLOC_STEP
#define REALLOC_STEP 16
#endif

void* arcan_alloc_mem(size_t nb,
	enum arcan_memtypes type, enum arcan_memhint hint, enum arcan_memalign align)
{
	void* buf = malloc(nb);

	if (!buf && (hint & ARCAN_MEM_NONFATAL) == 0)
		arcan_fatal("arcan_alloc_mem(), out of memory.\n");

	if (hint & ARCAN_MEM_BZERO)
		memset(buf, '\0', nb);

	return buf;
}

void arcan_mem_tick()
{
}

void arcan_mem_growarr(struct arcan_strarr* res)
{
/* _alloc functions lacks a grow at the moment,
 * after that this should ofc. be replaced. */
	char** newbuf = arcan_alloc_mem(
		(res->limit + REALLOC_STEP) * sizeof(char*),
		ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

	memcpy(newbuf, res->data, res->limit * sizeof(char*));
	arcan_mem_free(res->data);
	res->data= newbuf;
	res->limit += REALLOC_STEP;
}

void arcan_mem_freearr(struct arcan_strarr* res)
{
	if (!res || !res->data)
		return;

	char** cptr = res->data;
	while (cptr && *cptr)
		arcan_mem_free(*cptr++);

	arcan_mem_free(res->data);

	memset(res, '\0', sizeof(struct arcan_strarr));
}

/*
 * Allocate memory intended for read-only or
 * exec use (JIT, ...)
 */
void* arcan_alloc_fillmem(const void* data,
	size_t ds,
	enum arcan_memtypes type,
	enum arcan_memhint hint,
	enum arcan_memalign align)
{
	void* buf = arcan_alloc_mem(ds, type, hint, align);

	if (!buf)
		return NULL;

	memcpy(buf, data, ds);
	return buf;
}

void arcan_mem_free(void* inptr)
{
	free(inptr);
}

