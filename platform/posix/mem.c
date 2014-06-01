/* Arcan-fe (OS/device platform), scriptable front-end endinge
 *
 * Arcan-fe is the legal property of its developers, please refer to
 * the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <unistd.h>

#include <sys/mman.h>

#include <arcan_math.h>
#include <arcan_general.h>

#ifdef MADV_DONTDUMP
#define NO_DUMPFLAG MADV_DONTDUMP
#else
#define	NO_DUMPFLAG MADV_NOCORE
#endif

struct mempool_meta {
/*	mempool_hook_t alloc;
	  mempool_hook_t free; */

	size_t alloc_cnt;
	size_t dealloc_cnt;
	size_t in_use;
	size_t monitor_sz;
	size_t n_pages;
};

/* pool behaviors:
 * [ SENSITIVE is always a special case ]
 *   |-> pages will remain mapped in dumps, but data will be
 *       written over with the guard byte.
 *
 * ARCAN_MEM_VBUFFER =>
 *  - assume large continous blocks are beneficial,
 *    initialize with 0xff so that rendering an uninitialized
 *    block will yield something visible, tightly pack within
 *    pools, don't use any guard or additional tracking.
 *
 *    hope is that MEM_VBUFFER + READONLY can be used with
 *    future low-level graphics interfaces to directly map
 *    and manage GPU resources.
 *
 * ARCAN_MEM_VSTRUCT =>
 *  - scratch-page + tightly packed ring-buffer, 16-byte align
 *    base, guardint and checksum as the buffer is tracked.
 *
 * ARCAN_MEM_EXTSTRUCT =>
 *  - same as VSTRUCT but different pool
 *
 * ARCAN_MEM_ABUFFER => 
 *  - similar to VBUFFER but smaller blocks (multiples of 64k)
 *    and no 0xff initialization
 *
 * ARCAN_MEM_STRINGBUF =>
 *  - plan is to require additional meta (i.e. encoding)
 *    aggressively verify checksums (as we know there's little 
 *    data but high risk), dynamically tagged readonly/ sensitive,
 *    also gets all access tracked (in more paranoid settings,
 *    madv. use should also be covered but we don't have the
 *    mechanisms in place for that) by getting the pagefaults
 *    and checking source. 
 *
 * ARCAN_MEM_VTAG/ATAG => 
 *  - similar to EXTSTRUCT we know that the source is not 
 *    connected to external behaviors 
 *
 * ARCAN_MEM_BINDING =>
 *  - 64k pages managed by additional memory managers,
 *    e.g. allocation calls to virtual machines. Possibly 
 *    connected to a JITing source(!),  
 *
 * ARCAN_MEM_MODELDATA =>
 *  - similar to VBUFFER but smaller allocation blocks
 *
 *	ARCAN_MEM_THREADCTX => 
 *   - few allocations (should correlate to number of threads)
 *   - assumed shorter life-span
 *   - guard pages separate each allocation
 */

int system_page_size = 4096;

/*
 * map initial pools, pre-fill some video buffers, 
 * get limits and assert that our build-time minimal
 * and maximal settings fit.
 */
void arcan_mem_init()
{
}

/*static void sigsegv_hand(int sig, siginfo_t* si, void* unused)
{
*/
/* 
 * sweep SENSITIVE marked areas and replace with the guard pattern
 * 
 */ 

/*
 * unmap VBUFFER, ABUFFER, MODELDATA 
 */

/* 
 * Propagate the segmentation fault so the core gets dumped.
 *
 * Should do an integrity sweep and exfiltrate additional
 * crash information
	struct sigaction sa;
 */

void* arcan_alloc_mem(size_t nb,
	enum arcan_memtypes type, enum arcan_memhint hint, enum arcan_memalign align)
{
	void* rptr = NULL;
	size_t header_sz = 0;
	size_t footer_sz = 0;
	size_t padding_sz = 0;
	size_t total;

	switch (type){
	case ARCAN_MEM_BINDING:
	case ARCAN_MEM_THREADCTX:
	case ARCAN_MEM_VBUFFER:
	case ARCAN_MEM_ABUFFER:
	case ARCAN_MEM_MODELDATA:
	case ARCAN_MEM_VSTRUCT:
	case ARCAN_MEM_EXTSTRUCT:
	case ARCAN_MEM_STRINGBUF:
	case ARCAN_MEM_VTAG:
	case ARCAN_MEM_ATAG:

		total = header_sz + footer_sz + padding_sz + nb;

		switch(align){
		case ARCAN_MEMALIGN_NATURAL:
			rptr = malloc(total);
		break;

		case ARCAN_MEMALIGN_PAGE:
			if (-1 == posix_memalign(&rptr, system_page_size, total))
				rptr = NULL;
		break;
		
		case ARCAN_MEMALIGN_SIMD:
			if (-1 == posix_memalign(&rptr, 16, total))
				rptr = NULL;
		break;
		}
	break;
		
	case ARCAN_MEM_ENDMARKER:
	default:
			abort();
	}		

	if (!rptr){
		if ((hint & ARCAN_MEM_NONFATAL) == 0)
			arcan_fatal("arcan_alloc_mem(), out of memory.\n");
		return NULL;
	}

	if (hint & ARCAN_MEM_BZERO){
		memset(rptr, '\0', total);
	}

	return rptr;
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
/* lock then free */
/* depending on type and flag, verify integrity,
 * then cleanup. VBUFFER for instance doesn't 
 * automatically shrink, but rather reset and flag 
 * as unused */
	free(inptr);
}

