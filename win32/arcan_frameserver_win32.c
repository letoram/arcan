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

#include "../arcan_general.h"
#include "../arcan_frameserver_decode.h"
#include "../arcan_frameserver_backend_shmpage.h"

/* functions used by the "frameserver_decode.h" */
static FILE* logdev = NULL;
#define LOG(...) ( fprintf(logdev, __VA_ARGS__) )
static HWND parent = 0;

/* little linking hack .. */
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

bool semcheck(sem_handle semaphore)
{
	bool rv = true;
	int rc;

	do {
		rc = arcan_sem_timedwait(semaphore, 1000);
		if (-1 == rc){
				if (errno == EINVAL){
					LOG("arcan_frameserver -- fatal error while waiting for semaphore (%i)\n", errno);
					break; /* propagates outward from _decode_(video,audo) -> decode_frame -> main */
				}
		}
	} while (rc != 0 && (rv = parent_alive()) );

	return rv;
}

static bool setup_shm_ipc(arcan_ffmpeg_context* dstctx, HANDLE key)
{
	/* step 1, request allocation, PTS + video-frame + audio-buffer + (padding) */

	void* buf = (void*) MapViewOfFile(key, FILE_MAP_ALL_ACCESS, 0, 0, MAX_SHMSIZE);

	if (buf == NULL) {
		LOG("fatal: Couldn't map the allocated shared memory buffer (%i) => error: %i\n", key, GetLastError());
		fflush(NULL);
		CloseHandle(key);
		return false;
	}

	/* step 2, buffer all set-up, map it to the shared structure */
	dstctx->shared = (struct frameserver_shmpage*) buf;
	dstctx->shared->w = dstctx->width;
	dstctx->shared->h = dstctx->height;
	dstctx->shared->bpp = dstctx->bpp;
	dstctx->shared->vready = false;
	dstctx->shared->aready = false;
	dstctx->shared->channels = dstctx->channels;
	dstctx->shared->frequency = dstctx->samplerate;
	dstctx->shared->abufbase = 0;
	dstctx->shared->abufofs = dstctx->shared->vbufofs + 4 + dstctx->shared->w * dstctx->shared->h * dstctx->shared->bpp;

	/* step 3, send user message to parent --
	* now its safe to get mapping and start reading from it */
	arcan_sem_post(dstctx->shared->vsyncc);

	return true;
}

/* args accepted;
 * fname
 * parent window handle
 * semaphore handle (one for vid, one for aud) (passed by parent in CreateProcess)
 * in-frameserver loop
 */
int main(int argc, char* argv[])
{
	arcan_ffmpeg_context* vidctx;

#ifndef _DEBUG
/*	_set_invalid_parameter_handler(inval_param_handler) */
	DWORD dwMode = SetErrorMode(SEM_NOGPFAULTERRORBOX);
	SetErrorMode(dwMode | SEM_NOGPFAULTERRORBOX);
#endif

	if (2 != argc)
		return 1;
		
	char* fname = argv[0];
	HANDLE shmh = (HANDLE) strtoul(argv[1], NULL, 10);
	
	/* create a window, hide it and transfer the hwnd in the SHM,
	 * use this HWND for sleeping / waking between frame transfers */
	vidctx = ffmpeg_preload(fname);

	if (vidctx != NULL && setup_shm_ipc(vidctx, shmh)) {
		struct frameserver_shmpage* page = vidctx->shared;
		parent = page->parent;
		/* reuse the shmpage, anyhow, the main app should support
		 * relaunching the frameserver when looping to cover for
		 * memory leaks, crashes and other ffmpeg goodness */

		while (ffmpeg_decode(vidctx) && page->loop) {
			ffmpeg_cleanup(vidctx);
			vidctx = ffmpeg_preload(fname);

			/* sanity check, file might have changed between loads */
			if (!vidctx ||
			        vidctx->width != page->w ||
			        vidctx->height != page->h ||
			        vidctx->bpp != page->bpp)
				break;

			vidctx->shared = page;
		}
	}

	return 0;
}
