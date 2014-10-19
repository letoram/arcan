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
 * while still possible to revert to the state- pre exection
 */
int arcan_target_launch_external(
	const char* fname, char** argv, char** envv, char** libs);

/*
 * Launch the specified program and bind its resources and control
 * to the returned frameserver instance (NULL if spawn was not
 * possible for some reason, e.g. missing binaries).
 */
struct arcan_frameserver;
struct arcan_frameserver* arcan_target_launch_internal(
	const char* fname, char** argv, char** env, char** libs);

void arcan_timesleep(unsigned long);
file_handle arcan_fetchhandle(int insock);
bool arcan_pushhandle(file_handle in, int channel);

bool arcan_isdir(const char* path);
bool arcan_isfile(const char* path);

/*
 * implemented in <platform>/warning.c
 * regular fprintf(stderr, style trace output logging.
 * slated for REDESIGN/REFACTOR.
 */
void arcan_warning(const char* msg, ...);
void arcan_fatal(const char* msg, ...);
#endif
