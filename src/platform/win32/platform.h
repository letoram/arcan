#ifndef _HAVE_PLATFORM
#define _HAVE_PLATFORM

#undef BADFD
#define BADFD INVALID_HANDLE_VALUE

#define LIBNAME "arcan_hijack.dll"
#define NULFILE "\\Device\\Null"

#include <Windows.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include "../video_platform.h"

#undef near
#undef far

/* OS specific definitions */
/*
 * some missing defines that doesn't seem to be included in the
 * headers of mingw but still exported in the linked libraries,
 */
extern char* strdup(const char*);
extern double round(double x);
FILE* fdopen(int, const char*);
int random(void);
int setenv(const char* name, const char* value, int overwrite);

typedef int pipe_handle;
typedef HANDLE file_handle;
typedef HANDLE sem_handle;
typedef void* process_handle;

#define BROKEN_PROCESS_HANDLE NULL

typedef struct {
	struct arcan_shmif_page* ptr;
	void* handle;
	void* synch;
	char* key;
	size_t shmsize;
} shm_handle;

/*
 * everything below is manually copied and synched with
 * ../platform.h
 */

int arcan_sem_post(sem_handle sem);
int arcan_sem_unlink(sem_handle sem, char* key);
int arcan_sem_wait(sem_handle sem);
int arcan_sem_trywait(sem_handle sem);
int arcan_sem_init(sem_handle*, unsigned value);
int arcan_sem_destroy(sem_handle);

typedef int8_t arcan_errc;
typedef long long arcan_vobj_id;
typedef int arcan_aobj_id;

long long int arcan_timemillis();
void arcan_timesleep(unsigned long);
file_handle arcan_fetchhandle(int insock);
bool arcan_pushhandle(file_handle in, int channel);

void arcan_warning(const char* msg, ...);
void arcan_fatal(const char* msg, ...);

enum ARCAN_ANALOGFILTER_KIND {
	ARCAN_ANALOGFILTER_NONE = 0,
	ARCAN_ANALOGFILTER_PASS = 1,
	ARCAN_ANALOGFILTER_AVG  = 2,
 	ARCAN_ANALOGFILTER_ALAST = 3
};
struct arcan_strarr;
unsigned long arcan_target_launch_external(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs,
	int* exitc
);
struct arcan_frameserver;
struct arcan_frameserver* arcan_target_launch_internal(
	const char* fname,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs
);
void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind);
arcan_errc platform_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode);
/* look for new joystick / analog devices */
struct arcan_evctx;
void platform_event_process(struct arcan_evctx* ctx);
void platform_event_rescan_idev(struct arcan_evctx* ctx);
void platform_event_keyrepeat(struct arcan_evctx*, unsigned rate);
const char* platform_event_devlabel(int devid);
void platform_event_analogall(bool enable, bool mouse);
void platform_event_analoginterval(int devid, int axisid,
	int enter, int exit, int subid);

#endif
