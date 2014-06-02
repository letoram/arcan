/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_GENERAL
#define _HAVE_ARCAN_GENERAL

/*
 * Some of these functions are shared between different platforms
 * and are implemented in arcan_general.c but are also cherry-picked
 * on a "function by function" bases from the corresponding names
 * in platform/system/functionname.c 
 */

/* refactor needs:
 * (a) stop typedef:ing structs
 * (b) continue evacuating ifdefs that aren't DEBUG
 */

#define PRIxVOBJ "lld"

#include PLATFORM_HEADER
#include "arcan_shmif.h"

#ifndef _WIN32

#if __APPLE__
	#define LIBNAME "libarcan_hijack.dylib"
#else
	#define LIBNAME "libarcan_hijack.so"
#endif

#define NULFILE "/dev/null"
#define BROKEN_PROCESS_HANDLE -1

#include <semaphore.h>
#include <getopt.h>
typedef struct {
	struct arcan_shmif_page* ptr;
	int handle;
	void* synch;
	char* key;
	size_t shmsize;
} shm_handle;

#endif

typedef int arcan_shader_id;
typedef unsigned int arcan_tickv;

enum arcan_errors {
	ARCAN_OK                       =   0,
	ARCAN_ERRC_NOT_IMPLEMENTED     =  -1,
	ARCAN_ERRC_CLONE_NOT_PERMITTED =  -2,
	ARCAN_ERRC_EOF                 =  -3,
	ARCAN_ERRC_UNACCEPTED_STATE    =  -4,
	ARCAN_ERRC_BAD_ARGUMENT        =  -5,
	ARCAN_ERRC_OUT_OF_SPACE        =  -6,
	ARCAN_ERRC_NO_SUCH_OBJECT      =  -7,
	ARCAN_ERRC_BAD_RESOURCE        =  -8,
	ARCAN_ERRC_BADVMODE            =  -9,
	ARCAN_ERRC_NOTREADY            = -10,
	ARCAN_ERRC_NOAUDIO             = -11,
	ARCAN_ERRC_UNSUPPORTED_FORMAT  = -12
};

typedef struct {
	float yaw, pitch, roll;
	quat quaternion;
} surface_orientation;

typedef struct {
	point position;
	scalefactor scale;
	float opa;
	surface_orientation rotation;
} surface_properties;

typedef struct {
	unsigned int w, h;
	uint8_t bpp;
} img_cons;

typedef struct {
	char* ptr;
	size_t sz;
	bool mmap;
} map_region;

typedef struct {
	file_handle fd;
	off_t start;
	off_t len;
	char* source;
} data_source;

enum arcan_resourcemask {
	ARCAN_RESOURCE_THEME = 1,
	ARCAN_RESOURCE_SHARED = 2
};

/* try to set the external chars for:
 * arcan_resourcepath
 * arcan_themepath
 * arcan_libpath (hijack)
 * arcan_binpath (frameserver)
 * best run before applying command-line overrides */
bool arcan_setpaths();

bool check_theme(const char*);
char* arcan_expand_resource(const char* label, bool global);
char* arcan_find_resource_path(const char* label, 
	const char* path, int searchmask);
char* arcan_find_resource(const char* label, int searchmask);
char* arcan_findshmkey(int* dhd, bool semalloc);
void arcan_dropshmkey(char* srckey);

const char* strip_traverse(const char* in);
/*
 * Open and map a resource description (from _expand, _find category 
 * of functions) and return in data_source structure.
 * On failure, fd will be BADFD and source NULL
 */
data_source arcan_open_resource(const char* uri);
void arcan_release_resource(data_source* sptr);
map_region arcan_map_resource(data_source* source, bool wr); 
bool arcan_release_map(map_region region);

/* 
 * Somewhat ad-hoc, mainly just used for mouse grab- style
 * global state changes for now.
 */
void arcan_device_lock(int devind, bool state);

void arcan_warning(const char* msg, ...);
void arcan_fatal(const char* msg, ...);

/* open a file using a format string (fmt + variadic), flags and mode 
 * matches regular open() semantics.
 * the file_handle wrapper is purposefully not used on this function 
 * and for Win32, is expected to be managed by _get_osfhandle */
int fmt_open(int flags, mode_t mode, const char* fmt, ...);

/* since mingw does not export a glob.h,
 * we have to write a lightweight globber */
unsigned arcan_glob(char* basename, int searchmask, 
	void (*cb)(char*, void*), void* tag);

const char* internal_launch_support();

/* update rate of 25 ms / tick,which amounts to a logical time-span of 40 fps,
 * for lower power devices, this can be raised signifantly, 
 * just adjust INTERP_MINSTEP accordingly */
#ifndef ARCAN_TIMER_TICK
#define ARCAN_TIMER_TICK 25
#endif

/*
 * The engine interpolates animations between timesteps (timer_tick clock), 
 * but only if n ms have progressed since the last rendered frame,
 * where n is defined as (INTERP_MINSTEP * ARCAN_TIMER_TICK)
 */
#ifndef INTERP_MINSTEP
#define INTERP_MINSTEP 0.15
#endif

/*
 * Regularly test by redefining this to something outside 1 <= n <= 64k and 
 * not -1, to ensure that no part of the engine or any user scripts rely
 * on hard-coded constants rather than their corresponding symbols.
 */
#define ARCAN_EID 0

#define CAP(X,L,H) ( (((X) < (L) ? (L) : (X)) > (H) ? (H) : (X)) )

/* 
 * found / implemented in arcan_event.c 
 */
typedef struct {
	bool bench_enabled;

	unsigned ticktime[32], tickcount;
	char tickofs;

	unsigned frametime[64], framecount;
	char frameofs;

	unsigned framecost[64], costcount;
	char costofs;
} arcan_benchdata;


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
 * states, untrusted contents etc.
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
	ARCAN_MEM_BZERO = 1,
	ARCAN_MEM_TEMPORARY = 2,
	ARCAN_MEM_EXEC = 4,
	ARCAN_MEM_NONFATAL = 8,
	ARCAN_MEM_READONLY = 16,
	ARCAN_MEM_SENSITIVE = 32,
	ARCAN_MEM_LOCKACCESS = 64
};

enum arcan_memalign {
	ARCAN_MEMALIGN_NATURAL,
	ARCAN_MEMALIGN_PAGE,
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
 * called early on application startup,
 * before any arcan_alloc_mem calls,
 * used to setup pools, prepare random seeds etc.
 */
void arcan_mem_init();

/*
 * NULL is allowed (and ignored),
 * otherwise 
 */
void arcan_mem_free(void*);

/*
 * For memory blocks allocated with ARCAN_MEM_LOCKACCESS,
 * where some OS specific primitive is used for multithreaded
 * access, but also for some types (e.g. frobbed strings,
 * sensitive marked blocks) 
 */
void arcan_mem_lock(void*);
void arcan_mem_unlock(void*);

/*
 * Support function for packing binary blobs as [a-Z0-9+/] 
 * at the expense of storage space. 
 */
uint8_t* arcan_base64_decode(const uint8_t* instr, 
	size_t* outsz, enum arcan_memhint);

uint8_t* arcan_base64_encode(const uint8_t* data, 
	size_t inl, size_t* outl, enum arcan_memhint hint);

/*
 * generate a LUA (and possibly other relevant states) dump
 * into resourcepath/logs/prefix_timestamp.exts
 * key is a message describing the reason,
 * src is ann estimation of the origin
 */
void arcan_state_dump(const char* prefix, const char* key, const char* src);

/*
 * Allocate memory intended for read-only or 
 * exec use (JIT, ...)
 */
void* arcan_alloc_fillmem(const void*,
	size_t,
	enum arcan_memtypes, 
	enum arcan_memhint, 
	enum arcan_memalign);

void arcan_bench_register_tick(unsigned);
void arcan_bench_register_cost(unsigned);
void arcan_bench_register_frame();

/*
 * These are slated for removal / replacement when
 * we add a real package format etc.
 */

extern int system_page_size;

extern char* arcan_themename;
extern char* arcan_resourcepath;
extern char* arcan_themepath;
extern char* arcan_binpath;
extern char* arcan_libpath;
extern char* arcan_fontpath;
#endif
