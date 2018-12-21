/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_MEM
#define _HAVE_ARCAN_MEM

/*
 * Type / use hinted memory (de-)allocation routines.
 * The simplest version merely maps to malloc/memcpy family,
 * but local platforms can add reasonable protection (mprotect etc.)
 * where applicable, but also to take advantage of non-uniform
 * memory subsystems.
 * This also includes info-leak protections in the form of hinting to the
 * OS to avoid core-dumping certain pages.
 *
 * The values are structured like a bitmask in order
 * to hint / switch which groups we want a certain level of protection
 * for.
 *
 * The raw implementation for this is in the platform,
 * thus, any exotic approaches should be placed there (e.g.
 * installing custom SIGSEGV handler to zero- out important areas etc).
 *
 * Memory allocated in this way must also be freed using a similar function,
 * particularly to allow non-natural alignment (page, hugepage, simd, ...)
 * but also for the allocator to work in a more wasteful manner,
 * meaning to add usage-aware pre/post guard buffers.
 *
 * By default, an external out of memory condition is treated as a
 * terminal state transition (unless you specify ARCAN_MEM_NONFATAL)
 * and allocation therefore never returns NULL.
 *
 * The primary purposes of this wrapper is to track down and control
 * dynamic memory use in the engine, to ease distinguishing memory that
 * comes from the engine and memory that comes from libraries we depend on,
 * and make it easier to debug/detect memory- related issues. This is not
 * an effective protection against foreign code execution in process by
 * a hostile party.
 */

enum arcan_memtypes {
/*
 * Texture data, FBO storage, ...
 * Ranging from MEDIUM to HUGE (64k -> 16M)
 * should exploit the fact that many dimensions will be powers of 2.
 * Overflow behaviors are typically "safe" in the sense that it will
 * cause data corruption that will be highly visible but not overwrite
 * structures important for control- flow.
 */
	ARCAN_MEM_VBUFFER = 1,

/*
 * Management of the video-pipeline (render target, transforms etc.)
 * these are usually accessed often and very proximate to eachother.
 * TINY in size.
 */
	ARCAN_MEM_VSTRUCT,

/*
 * Used for external dependency handles, e.g. Sqlite3 database connection
 * Unknown range but should typically be small.
 */
	ARCAN_MEM_EXTSTRUCT,

/*
 * Audio buffers for samples and for frameserver transfers
 * SMALL to MEDIUM, >1M is a monitoring condition.
 */
	ARCAN_MEM_ABUFFER,

/*
 * Typically temporary buffers for building input/output strings
 * SMALL to TINY, > 64k is a monitoring condition.
 */
	ARCAN_MEM_STRINGBUF,

/*
 * Use- specific buffer associated with a video object (container
 * for 3d model, container for frameserver etc.) SMALL to TINY
 */
	ARCAN_MEM_VTAG,
	ARCAN_MEM_ATAG,

/*
 * Use for script interface bindings, thus may contain user-important
 * states, untrusted contents etc. Additional measures against
 * spraying based attacks should be, at the very least, a compile-time
 * option.
 */
	ARCAN_MEM_BINDING,

/*
 * Use for vertices, texture coordinates, ...
 */
	ARCAN_MEM_MODELDATA,

/* context that is used to pass data to a newly created thread */
	ARCAN_MEM_THREADCTX,
	ARCAN_MEM_ENDMARKER
};

/*
 * No memtype is exec unless explicitly marked as such,
 * and exec is always non-writable (use alloc_fillmem).
 */
enum arcan_memhint {
/* initialize to a known zero-state for the allocation type */
	ARCAN_MEM_BZERO = 1,

/* indicate that this memory should not allocated / in-use at the point
 * of the next invocation of arcan_mem_tick */
	ARCAN_MEM_TEMPORARY = 2,

/* indicate that this memory block should be marked as executable,
 * only allowed for arcan_mem_binding */
	ARCAN_MEM_EXEC = 4,

/* indicate that failure to allocate (i.e. allocation returning
 * NULL) is handled and should not generate a trap */
	ARCAN_MEM_NONFATAL = 8,

/* indicate that any writes to this block should trigger a trap,
 * should only be used with arcan_alloc_fillmem */
	ARCAN_MEM_READONLY = 16,

/* indicate that this memory block will carry user sensitive data,
 * (data from capture devices etc.) and should be replaced with a
 * known pattern when de-allocated.
 * key. */
	ARCAN_MEM_SENSITIVE = 32,

/*
 * Implies (ARCAN_MEM_SENSITIVE) and indicates that this will be
 * used for critical sensitive data and should only be accessible
 * through explicit use with a runtime cookie and use higher-
 * tier storage (i.e. trustzone) if possible.
 */
	ARCAN_MEM_LOCKACCESS = 33,
};

enum arcan_memalign {
/* memory block should be aligned on a architecture natural boundary */
	ARCAN_MEMALIGN_NATURAL,

/* memory block should be allocated to an appropriate page size */
	ARCAN_MEMALIGN_PAGE,

/* memory block should be aligned to be used for vector/streaming
 * instructions */
	ARCAN_MEMALIGN_SIMD
};

/*
 * align: 0 = natural, -1 = page
 */
void* arcan_alloc_mem(size_t,
	enum arcan_memtypes,
	enum arcan_memhint,
	enum arcan_memalign);

/*
 * Should be called before any other use of arcan_mem/arcan_alloc
 * functions. Initializes memory pools, XOR cookies etc.
 */
void arcan_mem_init();

struct arcan_strarr {
	size_t count;
	size_t limit;
	union{
		char** data;
		void** cdata;
	};
};

void arcan_mem_growarr(struct arcan_strarr*);
void arcan_mem_freearr(struct arcan_strarr*);

/*
 * NULL is allowed (and ignored), otherwise (src) must match
 * a block of memory previously obtained through (arcan_alloc_mem,
 * arcan_alloc_fillmem, arcan_mem_grow or arcan_mem_trunc).
 */
void arcan_mem_free(void* src);

/*
 * For memory blocks allocated with ARCAN_MEM_LOCKACCESS,
 * where some OS specific primitive is used for multithreaded
 * access, but also for some types (e.g. frobbed strings,
 * sensitive marked blocks)
 */
void arcan_mem_lock(void*);
void arcan_mem_unlock(void*);

/*
 * implemented in <platform>/mem.c
 * the distance (in time) between ticks determine how long buffers with
 * the flag ARCAN_MEM_TEMPORARY are allowed to live. Thus, whenever a
 * tick is processed, no such buffers should be allocated and it is considered
 * a terminal state condition if one is found.
 */
void arcan_mem_tick();

/*
 * implemented in <platform>/mem.c
 * aggregates a mem_alloc and a mem_copy from a source buffer.
 */
void* arcan_alloc_fillmem(const void*,
	size_t,
	enum arcan_memtypes,
	enum arcan_memhint,
	enum arcan_memalign);

#endif
