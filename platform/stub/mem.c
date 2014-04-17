#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include <arcan_math.h>
#include <arcan_general.h>

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

