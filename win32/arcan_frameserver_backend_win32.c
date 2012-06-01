/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <assert.h>
#include <sys/types.h>
#include <signal.h>
#include <errno.h>

#include <tchar.h>

/* libSDL */
#include <SDL.h>
#include <SDL_syswm.h>
#include <SDL_mutex.h>
#include <SDL_types.h>

/* arcan */
#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_framequeue.h"
#include "../arcan_video.h"
#include "../arcan_audio.h"
#include "../arcan_frameserver_backend.h"
#include "../arcan_event.h"
#include "../arcan_util.h"
#include "../arcan_frameserver_backend_shmpage.h"

static BOOL SafeTerminateProcess(HANDLE hProcess, UINT* uExitCode);

arcan_errc arcan_frameserver_free(arcan_frameserver* src, bool loop)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src) {
		src->playstate = loop ? ARCAN_PAUSED : ARCAN_PASSIVE;
		if (!loop)
			arcan_audio_stop(src->aid);
			
		if (src->vfq.alive)
			arcan_framequeue_free(&src->vfq);
		
		if (src->afq.alive)
			arcan_framequeue_free(&src->afq);

	/* might have died prematurely (framequeue cbs), no reason sending signal */
 		if (src->child_alive) {
			UINT ec;
			SafeTerminateProcess(src->child, &ec);
			src->child_alive = false;
			src->child = 0;
		}

		struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) src->shm.ptr;

		if (shmpage){
			arcan_frameserver_dropsemaphores(src);
		
			if (src->shm.ptr && false == UnmapViewOfFile((void*) shmpage))
				fprintf(stderr, "BUG -- arcan_frameserver_free(), munmap failed: %s\n", strerror(errno));

			CloseHandle(src->async);
			CloseHandle(src->vsync);
			CloseHandle(src->esync);
			CloseHandle( src->shm.handle );
			free(src->shm.key);
			
			src->shm.ptr = NULL;
		}
		
		rv = ARCAN_OK;
	}

	return rv;
}

/* Dr.Dobb, anno 99, because a working signaling system and kill is too clean */
static BOOL SafeTerminateProcess(HANDLE hProcess, UINT* uExitCode)
{
	DWORD dwTID, dwCode, dwErr = 0;
	HANDLE hProcessDup = INVALID_HANDLE_VALUE;
	HANDLE hRT = NULL;
	HINSTANCE hKernel = GetModuleHandle("Kernel32");
	BOOL bSuccess = FALSE;
	BOOL bDup = DuplicateHandle(GetCurrentProcess(),
	                            hProcess,
	                            GetCurrentProcess(),
	                            &hProcessDup,
	                            PROCESS_ALL_ACCESS,
	                            FALSE,
	                            0);

	if (GetExitCodeProcess((bDup) ? hProcessDup : hProcess, &dwCode) &&
	        (dwCode == STILL_ACTIVE)) {
		FARPROC pfnExitProc;
		pfnExitProc = GetProcAddress(hKernel, "ExitProcess");
		hRT = CreateRemoteThread((bDup) ? hProcessDup : hProcess,
		                         NULL,
		                         0,
		                         (LPTHREAD_START_ROUTINE)pfnExitProc,
		                         (PVOID)uExitCode, 0, &dwTID);

		if (hRT == NULL)
			dwErr = GetLastError();
	}
	else {
		dwErr = ERROR_PROCESS_ABORTED;
	}
	if (hRT) {
		WaitForSingleObject((bDup) ? hProcessDup : hProcess, INFINITE);
		CloseHandle(hRT);
		bSuccess = TRUE;
	}

	if (bDup)
		CloseHandle(hProcessDup);

	if (!bSuccess)
		SetLastError(dwErr);

	return bSuccess;
}

int check_child(arcan_frameserver* movie)
{
	int rv = -1;
	errno = EAGAIN;

	if (movie->child){
		DWORD exitcode;
		GetExitCodeProcess((HANDLE) movie->child, &exitcode);
		if (exitcode == STILL_ACTIVE); /* this was a triumph */
		else {
			errno = EINVAL;
			movie->child_alive = false;
		}
	}

	return rv;
}


static TCHAR* alloc_wchar(const char* key)
{
	CHAR* mskey = (TCHAR*) malloc((sizeof(TCHAR))*(strlen(key)));
	memset(mskey, 0, _tcslen(mskey));
	mbstowcs((wchar_t*)mskey, key, (strlen(key)));
	return mskey;
}

static const int8_t emptyvframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state){
	
	if (state.tag == ARCAN_TAG_FRAMESERV && state.ptr)
		switch (cmd){
			case ffunc_tick:
               arcan_frameserver_tick_control( (arcan_frameserver*) state.ptr);
                break;
                
			case ffunc_destroy:
				arcan_frameserver_free( (arcan_frameserver*) state.ptr, false);
                break;
                
			default:
                break;
		}
    
	return 0;
}

static SECURITY_ATTRIBUTES nullsec_attr;
static struct frameserver_shmpage* setupshmipc(HANDLE* dfd)
{
	struct frameserver_shmpage* res = NULL;

	nullsec_attr.nLength = sizeof(SECURITY_ATTRIBUTES);
	nullsec_attr.lpSecurityDescriptor = NULL;
	nullsec_attr.bInheritHandle = TRUE;
	
	*dfd = CreateFileMapping(INVALID_HANDLE_VALUE,  /* hack for specifying shm */
		&nullsec_attr, /* security, want to inherit */
		PAGE_READWRITE, /* access */
	    0, /* big-endian size? */
		MAX_SHMSIZE, /* little-endian size */
		NULL /* null, pass by inheritance */
	);

	if (*dfd != NULL && (res = MapViewOfFile(*dfd, FILE_MAP_ALL_ACCESS, 0, 0, MAX_SHMSIZE))){
		memset(res, 0, sizeof(struct frameserver_shmpage));
		res->vbufofs = sizeof(struct frameserver_shmpage);
		return res;
	}

error:
	fprintf(stderr, "arcan_frameserver_spawn_server(), could't allocate shared memory.\n");
	return NULL;
}

arcan_frameserver* arcan_frameserver_spawn_server(char* fname, bool extcc, bool loop, arcan_frameserver* res, char* mode)
{
/* if res is non-null, we have a server context already set up, 
 * just need to reset the frame-server */
	bool restart = res != NULL;
	char* rmode = mode ? mode : "movie";
	
/* even if we're looping, it's assumed that the frameserver resources have been free:ed (with loop args) */
	HANDLE shmh;
	struct frameserver_shmpage* shmpage = setupshmipc(&shmh);

	if (!shmpage)
		goto error;

	SDL_SysWMinfo wmi;
	SDL_VERSION(&wmi.version);
	SDL_GetWMInfo(&wmi);
	HWND handle = wmi.window;

/* if we have run out of unnamed semaphores, we're in pretty much an unrecoverable / crashstate anyhow */
	sem_handle vsync = CreateSemaphore(&nullsec_attr, 1, 0, NULL);
	sem_handle async = CreateSemaphore(&nullsec_attr, 1, 1, NULL);
	sem_handle esync = CreateSemaphore(&nullsec_attr, 1, 1, NULL);

/* b: spawn the child process */
	char cmdline[4196];
	snprintf(cmdline, sizeof(cmdline) - 1, "\"%s\" %i %i %i %i %s", fname, shmh, vsync, async, esync, rmode);
	shmpage->loop = loop;
	shmpage->parent = handle;

	PROCESS_INFORMATION pi;
	STARTUPINFO si = {0};
	DWORD exitcode;

	si.cb = sizeof(si);
	if (CreateProcess(
	            "arcan_frameserver.exe", /* program name, if null it will be extracted from cmdline */
	            cmdline, /* will be mapped up to argv, frameserver takes; resource(fname), handle */
	            0, /* don't make the parent process handle inheritable */
	            0, /* don't make the parent thread handle(s) inheritable */
	            TRUE, /* inherit the rest (we want semaphore / shm handle) */
	            CREATE_NO_WINDOW, /* console application, however we don't need a console window spawned with it */
	            0, /* don't need an ENV[] */
	            0, /* don't change CWD */
	            &si, /* Startup info */
	            &pi /* process-info */)) {

			/* the child has successfully launched and provided the relevant video information */
			img_cons cons = { .w = 32, .h = 32, .bpp = 4};
			arcan_frameserver_meta vinfo = {0};
			arcan_errc err;

			if (!restart) {
				res = (arcan_frameserver*) calloc(sizeof(arcan_frameserver), 1);
				vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = res};
				res->source = strdup(fname);
	            res->vid = arcan_video_addfobject((arcan_vfunc_cb) emptyvframe, state, cons, 0);
				res->aid = ARCAN_EID;
			} else {
				vfunc_state* state = arcan_video_feedstate(res->vid);
				arcan_video_alterfeed(res->vid, (arcan_vfunc_cb) emptyvframe, *state);
			}

		res->vsync = vsync;
		res->async = async;
		res->esync = esync;

		res->child_alive = true;
		res->desc = vinfo;
		res->child = pi.hProcess;
		res->loop = loop;
		res->desc.width = cons.w;
		res->desc.height = cons.h;
		res->desc.bpp = cons.bpp;
		res->shm.key = strdup("win32_static");
		res->shm.ptr = (void*) shmpage;
		res->shm.shmsize = MAX_SHMSIZE;
		res->shm.handle = shmh;
 		res->desc.ready = true;

		return res;
	} else 
		fprintf(stderr, "arcan_frameserver_spawn_server(), couldn't spawn frameserver.\n");

error:
	if (shmpage) UnmapViewOfFile((void*) shmpage);
	if (shmh)
		CloseHandle(shmh);

	return NULL;
}

