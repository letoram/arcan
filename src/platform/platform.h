/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * This file should define the generic types (and possibly header files)
 * needed for building / porting to a different platform.
 *
 * In addition, the video and event layers will also need to be implemented.
 */

#ifndef HAVE_PLATFORM_HEADER
#define HAVE_PLATFORM_HEADER

#include "video_platform.h"

#define BADFD -1
#include <pthread.h>
#include <semaphore.h>

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

long long int arcan_timemillis();

/*
 * Both these functions expect [argv / envv] to be modifiable
 * and their internal contents dynamically allocated (hence
 * will possible replace / free existing ones due to platform
 * specific expansion rules
 */

/*
 * Execute and wait- for completion for the specified target.
 * This will shut down as much engine- locked resources as possible
 * while still possible to revert to the state- pre exection.
 *
 * It returns the time spent waiting (in milliseconds) and
 * the return-code/exit-status in exitc.
 */
struct arcan_strarr;
unsigned long arcan_target_launch_external(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs,
	int* exitc
);

/*
 * Launch the specified program and bind its resources and control
 * to the returned frameserver instance (NULL if spawn was not
 * possible for some reason, e.g. missing binaries).
 */
struct arcan_frameserver;
struct arcan_frameserver* arcan_target_launch_internal(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs
);

void arcan_timesleep(unsigned long);
file_handle arcan_fetchhandle(int insock);
bool arcan_pushhandle(file_handle in, int channel);

bool arcan_isfile(const char*);
bool arcan_isdir(const char*);

/*
 * get a NULL terminated list of input- platform
 * specific environment options
 */
const char** platform_input_envopts();

/*
 * implemented in <platform>/warning.c
 * regular fprintf(stderr, style trace output logging.
 * slated for REDESIGN/REFACTOR.
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
 * Update/get the active filter setting for the specific
 * devid / axis (-1 for all) lower_bound / upper_bound sets the
 * [lower < n < upper] where only n values are passed into the filter core
 * (and later on, possibly as events)
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

/* look for new joystick / analog devices */
struct arcan_evctx;

/*
 * poll / flush all incoming platform input event into
 * specified context.
 */
void platform_event_process(struct arcan_evctx* ctx);

/*
 * slated for refactor deprecation when we have a better
 * shared synch/polling section for hotplug- kind of
 * events.
 */
void platform_event_rescan_idev(struct arcan_evctx* ctx);

void platform_event_keyrepeat(struct arcan_evctx*, unsigned rate);

const char* platform_event_devlabel(int devid);

/*
 * Quick-helper to toggle all analog device samples on / off
 * If mouse is set the action will also be toggled on mouse x / y
 * This will keep track of the old state, but repeating the same
 * toggle will flush state memory. All devices (except mouse) start
 * in off mode.
 */
void platform_event_analogall(bool enable, bool mouse);

/*
 * Set A/D mappings, when the specific dev/axis enter or exit
 * the set interval, a digital press/release event with the
 * set subid will be emitted. This is intended for analog sticks/buttons,
 * not touch- class displays that need a more refined classification/
 * remapping system.
 *
 * The implementation is left to the respective platform/input code to handle.
 */
void platform_event_analoginterval(int devid, int axisid,
	int enter, int exit, int subid);
#endif
