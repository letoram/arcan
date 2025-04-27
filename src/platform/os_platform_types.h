#ifndef HAVE_OS_PLATFORM_TYPES
#define HAVE_OS_PLATFORM_TYPES

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>

// NOTE Posix specific! (seems to be supported by windows?)
#include <sys/types.h>

// NOTE Posix specific! used by sem_handle
#include <semaphore.h>

typedef int file_handle;
typedef pid_t process_handle;
typedef sem_t* sem_handle;

typedef struct {
	int fd;
	off_t start;
	off_t len;
	char* source;
} data_source;

typedef struct {
	union {
		char* ptr;
		uint8_t* u8;
	};
	char zbyte; /* 'guarantees' ptr/u8 has a 0-byte end */
	size_t sz;
	bool mmap;
} map_region;

/*
 * Editing this table will require modifications in individual
 * platform/path.c, platform/namespace.c and platform/appl.c.
 *
 * The enum should fullfill the criteria:
 * (index = sqrt(enumv)),
 * exclusive(mask) = mask & (mask - 1) == 0
 */
enum arcan_namespaces {
/*
 * like RESOURCE_APPL, but contents can potentially be
 * reset on exit / reload.
 */
	RESOURCE_APPL_TEMP = 1,

/* .lua parse/load/execute,
 * generic resource load
 * special resource save (screenshots, ...)
 * rawresource open/write */
	RESOURCE_APPL = 2,

/*
 * shared resources between all appls.
 */
	RESOURCE_APPL_SHARED = 4,

/*
 * eligible recipients for target snapshot/restore
 */
	RESOURCE_APPL_STATE = 8,

/*
 * These three categories correspond to the previous
 * ones, and act as a reference point to load new
 * applications from when an explicit switch is
 * required. Depending on developer preferences,
 * these can potentially map to the same folder and
 * should be defined/set/overridden in platform/paths.c
 */
	RESOURCE_SYS_APPLBASE = 16,
	RESOURCE_SYS_APPLSTORE = 32,
	RESOURCE_SYS_APPLSTATE = 64,

/*
 * formatstring \f domain, separated in part due
 * to the wickedness of font- file formats
 */
	RESOURCE_SYS_FONT = 128,

/*
 * frameserver binaries read/execute (write-protected),
 * possibly signature/verify on load/run as well,
 * along with preemptive alloc+lock/wait on low system
 * loads.
 */
	RESOURCE_SYS_BINS = 256,

/*
 * LD_PRELOAD only (write-protected), recommended use
 * is to also have a database matching program configuration
 * and associated set of libraries.
 */
	RESOURCE_SYS_LIBS = 512,

/*
 * frameserver log output, state dumps, write-only since
 * read-backs from script would possibly be usable for
 * obtaining previous semi-sensitive data.
 */
	RESOURCE_SYS_DEBUG = 1024,

/*
 * shared scripts that can be system_loaded, should be RO and
 * updated / controlled with distribution versioning or through
 * explicit developer overrides
 */
	RESOURCE_SYS_SCRIPTS = 2048,

/*
 * the label will be interpreted as having a possible namespace prefix,
 * e.g. [myns]somewhere/something.
 */
	RESOURCE_NS_USER = 4096,
/*
 * must be set to the vale of the last system element (NS_USER ignored)
 */
	RESOURCE_SYS_ENDM = 2048
};

enum resource_type {
	ARES_FILE = 1,
	ARES_FOLDER = 2,
	ARES_SOCKET = 3,
	ARES_CREATE = 256,
	ARES_RDONLY = 512
};

struct arcan_strarr {
	size_t count;
	size_t limit;
	union{
		char** data;
		void** cdata;
	};
};

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
 * Used for memory that needs to be shared/forked into a child process
 */
	ARCAN_MEM_SHARED,

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

struct arcan_userns {
	bool read;
	bool write;
	bool ipc;
	int dirfd;
	char label[64];
	char name[32];
	char path[256];
};

struct platform_timing {
	bool tickless;
	unsigned cost_us;
};

#endif
