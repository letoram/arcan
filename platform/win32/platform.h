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

/* OS specific definitions */
/* some missing defines that doesn't seem to be included in the
 * headers of mingw but still exported in the linked libraries, hmm */
extern char* strdup(const char*);
extern double round(double x);
FILE* fdopen(int, const char*);
int strcasecmp(const char*, const char*);

typedef int pipe_handle;
typedef HANDLE file_handle;
typedef HANDLE sem_handle;

typedef void* process_handle;
typedef struct {
	struct frameserver_shmpage* ptr;
	void* handle;
	void* synch;
	char* key;
	size_t shmsize;
} shm_handle;

#endif
