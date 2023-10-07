/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_GENERAL
#define _HAVE_ARCAN_GENERAL

#define PRIxVOBJ "lld"
#include "../platform/platform.h"

/*
 * update rate of 25 ms / tick,which amounts to a logical time-span of 40 fps,
 * for lower power devices, this can be raised significantly,
 * just adjust INTERP_MINSTEP accordingly
 */
#ifndef ARCAN_TIMER_TICK
#define ARCAN_TIMER_TICK 25
#endif

/*
 * if we are more than this number of ticks behind (massive stall from
 * system clock adjustment, sleep / suspend problems etc.) then fast-forward
 * and process one tick.
 */
#ifndef ARCAN_TICK_THRESHOLD
#define ARCAN_TICK_THRESHOLD 100
#endif

/*
 * The engine interpolates animations between timesteps (timer_tick clock),
 * but only if n ms have progressed since the last rendered frame,
 * where n is defined as (INTERP_MINSTEP * ARCAN_TIMER_TICK) but
 * this is dictated by the synchronization strategy of the video platform
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

#include "arcan_mem.h"

#define NULFILE "/dev/null"
#define BROKEN_PROCESS_HANDLE -1

#include <semaphore.h>
#include <getopt.h>
struct shm_handle {
	struct arcan_shmif_page* ptr;
	int handle;
	void* synch;
	char* key;
	size_t shmsize;
};

typedef uint32_t arcan_tickv;

enum arcan_error {
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
 * slated to be moved to a utility library for
 * cryptography / data-passing primitives
 */
uint8_t* arcan_base64_decode(const uint8_t* instr,
	size_t* outsz, enum arcan_memhint);

uint8_t* arcan_base64_encode(const uint8_t* data,
	size_t inl, size_t* outl, enum arcan_memhint hint);

/*
 * implemented in engine/arcan_lua.c (slated for refactoring)
 * create a number of files in RESOURCE_SYS_DEBUG that
 * contains as much useful, non-intrusive (to whatever extent possible)
 * state as possible for debugging purposes.
 *
 * These files will be named according to <prefix_type_date.ext>
 * where <type and ext> are implementation defined.
 *
 * <key> is used as an identifier of the particular state dump,
 * and <src> is an estimation of the origin of the dump request
 * (e.g. stacktrace).
 */
void arcan_state_dump(const char* prefix, const char* key, const char* src);

/*
 * implemented in engine/arcan_event.c
 * basic timing and performance tracking measurements for A/V/Logic.
 */
void arcan_bench_register_tick(unsigned);
void arcan_bench_register_cost(unsigned);
void arcan_bench_register_frame();
arcan_benchdata* arcan_bench_data();

/*
 * used throughout the engine (if set), using macro form in order for high-
 * optimized builds that disable tracing entirely
 */
extern bool arcan_trace_enabled;

/*
 * enable collection buffer, collection will continue until the next call
 * to setbuffer or when the buffer is full. When that occurs finish_flag
 * is set to true and control over buf will be relinquished.
 *
 * the buffer will be packaged as follow:
 * [status flag] (1b) 0xff for complete, otherwise invalid and processing
 * can stop.
 * timestamp (uint64_t)
 * variable-length system marker (char*)
 * variable-length subsystem marker (char*)
 * tracelevel (uint8_t)
 * quantifier (uint32_t)
 * variable-length message (char*)
 */
void arcan_trace_setbuffer(uint8_t* buf, size_t buf_sz, bool* finish_flag);

/*
 * appends a plain log message to the trace buffer
 */
void arcan_trace_log(const char* message, size_t len);

/*
 * cleans up trace buffer and tracy zones
 */
void arcan_trace_close();

/* add a trace entry-point (though call through the TRACE_MARK macros),
 * sys returns to the main system group (graphics, video, 3d, ...) and
 * subsys for a group specific subsystem (where useful distinctions exist).
 *
 * trigger tells if this is a oneshot (0), enter (1) or exit (2) of the
 * specified subsystem. This is an important grouping to show when a set
 * of values logically belong together, and can be thought of as (unique)
 * <group> ... </group> entries in a markup language.
 *
 * tracelevel is to indicate if the typical path is executed or some
 * deviation (slow, warning, error) is triggered.
 *
 * identifier is some unspecified object identifier when there is a specific
 * object within the system/subsystem
 *
 * quant is some unspecified quantifier when there exist O(n) like relations
 * and the 'n' is dynamic between trace entries.
 *
 * message is some final user readable indicator. */
void arcan_trace_mark(
	const char* sys, const char* subsys,
	uint8_t trigger, uint8_t tracelevel,
	uint64_t identifier,
	uint32_t quant, const char* message,
	const char* file_name, const char* func_name,
	uint32_t line);

enum trace_level {
	TRACE_SYS_DEFAULT = 0,
	TRACE_SYS_SLOW = 1,
	TRACE_SYS_FAST = 2,
	TRACE_SYS_WARN = 3,
	TRACE_SYS_ERROR = 4
};

#ifndef TRACE_MARK_ENTER
#define TRACE_MARK_ENTER(A, B, C, D, E, F) do { \
	if (arcan_trace_enabled){ \
		arcan_trace_mark((A), (B), 1, (C), (D), (E), (F), __FILE__, __FUNCTION__, __LINE__);\
	}\
} while (0);
#endif

#ifndef TRACE_MARK_ONESHOT
#define TRACE_MARK_ONESHOT(A, B, C, D, E, F) do { \
	if (arcan_trace_enabled){ \
		arcan_trace_mark((A), (B), 0, (C), (D), (E), (F), __FILE__, __FUNCTION__, __LINE__);\
	}\
} while (0);
#endif

#ifndef TRACE_MARK_EXIT
#define TRACE_MARK_EXIT(A, B, C, D, E, F) do { \
	if (arcan_trace_enabled){ \
		arcan_trace_mark((A), (B), 2, (C), (D), (E), (F), __FILE__, __FUNCTION__, __LINE__);\
	}\
} while (0);
#endif

/*
 * LEGACY/REDESIGN
 * currently used as a hook for locking cursor devices to arcan
 * in externally managed windowed environments.
 */
void arcan_device_lock(int devind, bool state);

/*
 * These are slated for removal / replacement when
 * we add a real package format etc.
 */
extern int system_page_size;
#endif
