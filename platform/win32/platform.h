/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

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
int strcasecmp(const char*, const char*);
int random(void);

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

bool arcan_isdir(const char* path);
bool arcan_isfile(const char* path);

int setenv(const char* name, const char* value, int overwrite);
#endif
