/* stdlib */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <strings.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>
#include <Windows.h>
#include <tchar.h>

/* libFFMPEG */
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "../frameserver/arcan_frameserver.h"
#include "../frameserver/arcan_frameserver_libretro.h"
#include "../frameserver/arcan_frameserver_decode.h"
#include "../arcan_frameserver_shmpage.h"

FILE* logdev = NULL;
static HWND parent = 0;
static sem_handle async, vsync, esync;

/* linking hacks .. */
void arcan_frameserver_free(void* dontuse){}

bool stdout_redirected;
bool stderr_redirected;

char* arcan_resourcepath;
char* arcan_libpath;
char* arcan_themepath;
char* arcan_binpath;
char* arcan_themename;

/*void inval_param_handler(const wchar_t* expression,
   const wchar_t* function, 
   const wchar_t* file, 
   unsigned int line, 
   uintptr_t pReserved)
{
   wprintf(L"Invalid parameter detected in function %s."
            L" File: %s Line: %d\n", function, file, line);
   wprintf(L"Expression: %s\n", expression);
   abort();
}*/

static bool parent_alive()
{
	LOG("parent alive? %i, %i\n", IsWindow(parent), parent);
	return IsWindow(parent);
}

/* any unrecoverable errors will lead to an exit(),
 * add an exit handler if chances are we might lose data. */
int frameserver_semcheck(sem_handle semaphore, int timeoutms)
{
	bool rv = true;
	int rc = 0;

	do {
		rc = arcan_sem_timedwait(semaphore, timeoutms);

		if (-1 == rc){
				if (errno == EINVAL){
					LOG("arcan_frameserver -- fatal error while waiting for semaphore (%i)\n", errno);
					exit(1);
				} else
					break; /* EINTR isn't valid on win32 */
		}

/* shouldn't be needed, WaitForSingleObject should be subject to an abandoned- error 
		if (!parent_alive())
		{
			LOG("arcan_frameserver -- parent died, giving up.\n");
			exit(1); 
		} */

	} while (rc != 0);

	return rc;
}

struct frameserver_shmcont frameserver_getshm(const char* shmkey, unsigned width, unsigned height, unsigned bpp, unsigned nchan, unsigned freq)
{
	struct frameserver_shmcont res = {0};
	HANDLE shmh = (HANDLE) strtoul(shmkey, NULL, 10);
	res.addr = (struct frameserver_shmpage*) MapViewOfFile(shmh, FILE_MAP_ALL_ACCESS, 0, 0, MAX_SHMSIZE);

	if ( res.addr == NULL ) {
		LOG("fatal: Couldn't map the allocated shared memory buffer (%i) => error: %i\n", shmkey, GetLastError());
		CloseHandle(shmh);
		return res;
	}

	res.asem = async;
	res.vsem = vsync;
	res.esem = esync;
	res.addr->w = width;
	res.addr->h = height;
	res.addr->bpp = bpp;
	res.addr->vready = false;
	res.addr->aready = false,
	res.addr->vbufofs = sizeof(struct frameserver_shmpage);
	res.addr->channels = nchan;
	res.addr->frequency =freq;
	res.addr->abufofs = res.addr->vbufofs + (res.addr->w * res.addr->h * res.addr->bpp);
	parent = res.addr->parent;

	LOG("arcan_frameserver() -- shmpage configured and filled.\n");
	return res;
}

void* frameserver_getrawfile(const char* resource, ssize_t* ressize)
{
	HANDLE fh = CreateFile( resource, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL );
	if (!fh)
		return NULL;

	HANDLE fmh = CreateFileMapping(fh, NULL, PAGE_READONLY, 0, 0, NULL);
	if (!fmh)
		return NULL;

	void* res = (void*) MapViewOfFile(fmh, FILE_MAP_READ, 0, 0, 0);
	if (ressize)
		*ressize = (size_t) GetFileSize(fh, NULL);

	return res;
}

int main(int argc, char* argv[])
{
#ifndef _DEBUG
/*	_set_invalid_parameter_handler(inval_param_handler) */
	DWORD dwMode = SetErrorMode(SEM_NOGPFAULTERRORBOX);
	SetErrorMode(dwMode | SEM_NOGPFAULTERRORBOX);
#endif

/* quick tracing */
/*	logdev = fopen("output.log", "w");  */
	LOG("arcan_frameserver(win32) -- launched with %d args.\n", argc);

/* map cmdline arguments (resource, shmkey, vsem, asem, esem, mode),
 * parent is retrieved from shmpage */
	if (6 != argc)
		return 1;

	vsync = (HANDLE) strtoul(argv[2], NULL, 10);
	async = (HANDLE) strtoul(argv[3], NULL, 10);
	esync = (HANDLE) strtoul(argv[4], NULL, 10);
	char* resource = argv[0];
	char* fsrvmode = argv[5];
	char* shmkey   = argv[1];

	LOG("arcan_frameserver(win32) -- initial argcheck OK, %s:%s\n", fsrvmode, resource);
	if (strcmp(fsrvmode, "movie") == 0 || strcmp(fsrvmode, "audio") == 0)
		arcan_frameserver_ffmpeg_run(resource, shmkey);
	else if (strcmp(fsrvmode, "libretro") == 0)
		arcan_frameserver_libretro_run(resource, shmkey);
	else if (strcmp(fsrvmode, "streamserve") == 0)
/*		mode_streamserv(fname, shmh) */ ;
	else;

	return 0;
}
