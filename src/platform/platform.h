/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * This file should define the generic types (and possibly header files) needed
 * for building / porting to a different platform. A working combination of all
 * platform/.h defined headers are needed for system integration.
 */
#ifndef HAVE_PLATFORM_HEADER
#define HAVE_PLATFORM_HEADER

#include "video_platform.h"

#define BADFD -1
#include <pthread.h>
#include <semaphore.h>

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

typedef int pipe_handle;
typedef int file_handle;
typedef pid_t process_handle;
typedef sem_t* sem_handle;

int arcan_sem_post(sem_handle sem);
int arcan_sem_unlink(sem_handle sem, char* key);
int arcan_sem_wait(sem_handle sem);
int arcan_sem_trywait(sem_handle sem);
int arcan_sem_init(sem_handle*, unsigned value);
int arcan_sem_destroy(sem_handle);

typedef int8_t arcan_errc;
typedef int arcan_aobj_id;

unsigned long long arcan_timemillis();

/*
 * Both these functions expect [argv / envv] to be modifiable and their
 * internal contents dynamically allocated (hence will possible replace / free
 * existing ones due to platform specific expansion rules
 */

/*
 * Execute and wait- for completion for the specified target.  This will shut
 * down as much engine- locked resources as possible while still possible to
 * revert to the state- pre exection.
 *
 * It returns the time spent waiting (in milliseconds) and the
 * return-code/exit-status in exitc.
 */
struct arcan_strarr;
struct arcan_evctx;

unsigned long arcan_target_launch_external(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs,
	int* exitc
);

/*
 * Launch the specified program and bind its resources and control to the
 * returned frameserver instance (NULL if spawn was not possible for some
 * reason, e.g. missing binaries).
 */
struct arcan_frameserver;
struct arcan_frameserver* arcan_target_launch_internal(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs
);

/*
 * return a string (can be empty) matching the existing and allowed frameserver
 * archetypes (a filtered version of the FRAMSESERVER_MODESTRING buildtime var.
 * and which ones that resolve to valid and existing executables)
 */
const char* arcan_frameserver_atypes();

/* estimated time-waster in milisecond resolution, little reason for this
 * to be exact, but undershooting rather than overshooting is important */
void arcan_timesleep(unsigned long);

/*
 * A lot of frameserver/client communication is on the notion that we can
 * push and fetch some kind of context handle between processes. The exact
 * means and mechanics vary with operating system, but typically through a
 * special socket or as a member of the event queue.
 */
file_handle arcan_fetchhandle(int insock, bool block);
bool arcan_pushhandle(int fd, int channel);

/*
 * This is a nasty little function, but used as a safe-guard in the fork()+
 * exec() case ONLY. There should be no risk of syslog or other things
 * corrupting future descriptors. On linux etc. this is implemented as an empty
 * poll on a rlimit- full set and using that to close()
 */
void arcan_closefrom(int num);

/*
 * Don't have much need for more fine-grained data model in regards to the
 * filesystem other than 'is it possible that this, at the moment, refers
 * to a file (loadable resource) or a container of files? Trace calls to this
 * function for verifying against TOCTU vulns.
 * Depending on how the windows platform develops, we should consider moving
 * this in hardening phase to return descriptor to dir/file instead
 */
bool arcan_isfile(const char*);
bool arcan_isdir(const char*);

/*
 * get a NULL terminated list of input- platform specific environment options
 * will only be presented to the user in a CLI like setting.
 */
const char** platform_input_envopts();

/*
 * implemented in <platform>/warning.c regular fprintf(stderr, style trace
 * output logging.  slated for REDESIGN/REFACTOR.
 */
void arcan_warning(const char* msg, ...);
void arcan_fatal(const char* msg, ...);

enum ARCAN_ANALOGFILTER_KIND {
	ARCAN_ANALOGFILTER_NONE = 0,
	ARCAN_ANALOGFILTER_PASS = 1,
	ARCAN_ANALOGFILTER_AVG  = 2,
 	ARCAN_ANALOGFILTER_ALAST = 3
};

/*
 * Some platforms can statically/dynamically determine what kinds of events
 * they are capable of emitting. This is helpful when determining what input
 * mode to expect (window manager that requires translated inputs and waits
 * because none are available
 */
enum PLATFORM_EVENT_CAPABILITIES {
	ACAP_TRANSLATED = 1,
	ACAP_MOUSE = 2,
	ACAP_GAMING = 4,
	ACAP_TOUCH = 8,
	ACAP_POSITION = 16,
	ACAP_ORIENTATION = 32
};
enum PLATFORM_EVENT_CAPABILITIES platform_input_capabilities();

/*
 * Update/get the active filter setting for the specific devid / axis (-1 for
 * all) lower_bound / upper_bound sets the [lower < n < upper] where only n
 * values are passed into the filter core (and later on, possibly as events)
 *
 * Buffer_sz is treated as a hint of how many samples in should be considered
 * before emitting a sample out.
 *
 * The implementation is left to the respective platform/input code to handle.
 */
void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind);

arcan_errc platform_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode);

/*
 * returns a [caller-managed COPY] of a OS- specific safe (read/writeable) path
 * to the database to use unless one has been provided at the command-line.
 */
char* platform_dbstore_path();

/*
 * poll / flush all incoming platform input event into specified context.
 */
void platform_event_process(struct arcan_evctx* ctx);

/*
 * Some platforms have a costly and intrusive detection process for new devices
 * and in such cases, this should be invoked explicitly in safe situations when
 * the render-loop is permitted to stall.
 */
void platform_event_rescan_idev(struct arcan_evctx* ctx);

/*
 * Legacy for translated devices, features like this should most of the time be
 * implemented at a higher layer, state tracking + clock is sufficient to do so
 * The default state for any input platform should be no-repeat.
 * period = 0, disable
 * period | delay < 0, query only
 * returns old value in argument
 */
void platform_event_keyrepeat(struct arcan_evctx*, int* period, int* delay);

/*
 * Some kind of string representation for the device, it may well  be used for
 * identification and tracking purposes so it is desired that this is device
 * specific rather than port specific.
 */
const char* platform_event_devlabel(int devid);

/*
 * Quick-helper to toggle all analog device samples on / off. If mouse is set
 * the action will also be toggled on mouse x / y. This will keep track of the
 * old state, but repeating the same toggle will flush state memory. All
 * devices (except mouse) start in off mode. Devices that are connected after
 * this has been set should use it as a global state identifier (so that we
 * don't saturate or break when a noisy device is plugged in).
 */
void platform_event_analogall(bool enable, bool mouse);

/*
 * Used for recovery handover where a full deinit would be damaging or has
 * some connection to the video layer. One example is for egl-dri related
 * pseudo-terminal management where some IOCTLs affect graphics state.
 */
void platform_event_reset();

/*
 * Special controls for devices that sample relative values but report
 * absolute values based on an internal tracking value and we might need to
 * 'warp' for device control.
 */
void platform_event_samplebase(int devid, float xyz[3]);
#endif
