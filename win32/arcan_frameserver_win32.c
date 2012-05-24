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
	dstctx->shared->vbufofs = sizeof(struct frameserver_shmpage);
	dstctx->shared->channels = dstctx->channels;
	dstctx->shared->frequency = dstctx->samplerate;
	dstctx->shared->abufbase = 0;
	dstctx->shared->abufofs = dstctx->shared->vbufofs + dstctx->width * dstctx->height * dstctx->bpp;
	dstctx->shared->resized = true;

	return true;
}

void mode_video(char* resource, HANDLE shmh, HANDLE semary[3])
{
	arcan_ffmpeg_context* vidctx;

	/* create a window, hide it and transfer the hwnd in the SHM,
	 * use this HWND for sleeping / waking between frame transfers */
	vidctx = ffmpeg_preload(resource);
	vidctx->async = semary[0];
	vidctx->vsync = semary[1];
	vidctx->esync = semary[2];

	if (vidctx != NULL && setup_shm_ipc(vidctx, shmh)) {
		struct frameserver_shmpage* page = vidctx->shared;
		parent = page->parent;
		vidctx->shared->resized = true;

		arcan_sem_post(vidctx->vsync);

		/* reuse the shmpage, anyhow, the main app should support
		 * relaunching the frameserver when looping to cover for
		 * memory leaks, crashes and other ffmpeg goodness */

		while (ffmpeg_decode(vidctx) && page->loop) {
			ffmpeg_cleanup(vidctx);
			vidctx = ffmpeg_preload(resource);

			/* sanity check, file might have changed between loads */
			if (!vidctx ||
			        vidctx->width != page->w ||
			        vidctx->height != page->h ||
			        vidctx->bpp != page->bpp)
				break;

			vidctx->shared = page;
		}
	}
}

/* [Required arguments] 
 *
 * resourcepath
 * parent window handle
 * vidsemh
 * audsemh
 * eventsemh
 * frameserver mode (movie, libretro, streamserve)
 */
int main(int argc, char* argv[])
{
#ifndef _DEBUG
/*	_set_invalid_parameter_handler(inval_param_handler) */
	DWORD dwMode = SetErrorMode(SEM_NOGPFAULTERRORBOX);
	SetErrorMode(dwMode | SEM_NOGPFAULTERRORBOX);
#endif


	if (6 != argc)
		return 1;

	char* fname = argv[0];
	char* fsrvmode = argv[5];
	HANDLE shmh = (HANDLE) strtoul(argv[1], NULL, 10);

/* semaphores were previously passed through shmpage, after refactoring,
 * they're not command-line arguments */
	HANDLE semary[3];
	semary[0] = (HANDLE) strtoul(argv[2], NULL, 10);
	semary[1] = (HANDLE) strtoul(argv[3], NULL, 10);
	semary[2] = (HANDLE) strtoul(argv[4], NULL, 10);

	if (strcmp(fsrvmode, "movie") == 0 || strcmp(fsrvmode, "audio") == 0)
		mode_video(fname, shmh, semary);
	else if (strcmp(fsrvmode, "libretro") == 0)
/*		mode_libretro(fname, shmh) */ ;
	else if (strcmp(fsrvmode, "streamserve") == 0)
/*		mode_streamserv(fname, shmh) */ ;
	else;

	return 0;
}
