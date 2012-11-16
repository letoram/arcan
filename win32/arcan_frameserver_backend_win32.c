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
#include <stdio.h>
#include <fcntl.h>
#include <assert.h>
#include <sys/types.h>
#include <signal.h>
#include <errno.h>

#include <tchar.h>

/* libSDL */
#include <SDL.h>
#define SDL_VIDEO_DRIVER_DDRAW
#include <SDL_syswm.h>
#include <SDL_mutex.h>
#include <SDL_types.h>

/* arcan */
#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_framequeue.h"
#include "../arcan_video.h"
#include "../arcan_audio.h"
#include "../arcan_event.h"
#include "../arcan_frameserver_backend.h"
#include "../arcan_event.h"
#include "../arcan_util.h"
#include "../arcan_frameserver_shmpage.h"

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

		if (src->lock_audb)
			SDL_DestroyMutex(src->lock_audb);

		struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) src->shm.ptr;

	/* might have died prematurely (framequeue cbs), no reason sending signal */
 		if (src->child_alive) {
			shmpage->dms = false;

			arcan_event exev = {
				.category = EVENT_TARGET,
				.kind = TARGET_COMMAND_EXIT
			};

			arcan_frameserver_pushevent(src, &exev);

			UINT ec;
			SafeTerminateProcess(src->child, &ec);
			src->child_alive = false;
			src->child = 0;
		}

		free(src->audb);

		if (shmpage){
			arcan_frameserver_dropsemaphores(src);

			if (src->shm.ptr && false == UnmapViewOfFile((void*) shmpage))
				arcan_warning("BUG -- arcan_frameserver_free(), munmap failed: %s\n", strerror(errno));

			CloseHandle(src->async);
			CloseHandle(src->vsync);
			CloseHandle(src->esync);
			CloseHandle( src->shm.handle );
			free(src->shm.key);

			src->shm.ptr = NULL;
		}

		if (!loop){
			vfunc_state emptys = {0};
			arcan_video_alterfeed(src->vid, arcan_video_emptyffunc(), emptys);
			memset(src, 0xaa, sizeof(arcan_frameserver));
			free(src);
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

	if (GetExitCodeProcess((bDup) ? hProcessDup : hProcess, &dwCode) && (dwCode == STILL_ACTIVE)) {
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

arcan_errc arcan_frameserver_pushfd(arcan_frameserver* fsrv, int fd)
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

	if (fsrv){
		HANDLE dh, childh, fdh;
		DWORD pid;

		childh = OpenProcess(PROCESS_DUP_HANDLE, FALSE, fsrv->childp);
		if (INVALID_HANDLE_VALUE == childh){
			arcan_warning("arcan_frameserver(win32)::push_handle, couldn't open child process (%ld)\n", GetLastError());
			return rv;
		}

/* assume valid input fd, 64bit issues with this one? */
		fdh = (HANDLE) _get_osfhandle(fd);

		if (DuplicateHandle(GetCurrentProcess(), fdh, childh, &dh, 0, FALSE, DUPLICATE_SAME_ACCESS)){
			arcan_event ev = {
				.category = EVENT_TARGET,
				.kind = TARGET_COMMAND_FDTRANSFER
			};

			ev.data.target.fh = dh;
			arcan_frameserver_pushevent( fsrv, &ev );
			rv = ARCAN_OK;
		}
		else {
			arcan_warning("arcan_frameserver(win32)::push_handle failed (%ld)\n", GetLastError() );
			rv = ARCAN_ERRC_BAD_ARGUMENT;
		}

/*	removed: likely suspect for a Windows Exception in zwClose and friends.	CloseHandle(fdh); */
		_close(fd);
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
		return res;
	}

error:
	arcan_warning("arcan_frameserver_spawn_server(), could't allocate shared memory.\n");
	return NULL;
}


/* unfortunate and temporary (0.2.3 cleanup) hack around linking shmpage */
sem_handle async, vsync, esync;
HANDLE parent;
FILE* logdev = NULL;

arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* ctx, struct frameserver_envp setup)
{
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};
	arcan_frameserver_meta vinfo = {0};
	size_t shmsize = MAX_SHMSIZE;

	HANDLE shmh;
	struct frameserver_shmpage* shmpage = setupshmipc(&shmh);

	if (!shmpage)
		goto error;

	SDL_SysWMinfo wmi;
	SDL_VERSION(&wmi.version);
	SDL_GetWMInfo(&wmi);
	HWND handle = wmi.window;

	ctx->launchedtime = arcan_frametime();

/* is the ctx in an uninitialized state? */
	if (ctx->vid == ARCAN_EID) {
		vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = ctx};
		ctx->source = strdup(setup.args.builtin.resource);
		ctx->vid = arcan_video_addfobject((arcan_vfunc_cb)arcan_frameserver_emptyframe, state, cons, 0);
		ctx->aid = ARCAN_EID;
	} else if (setup.custom_feed == false){
		vfunc_state* cstate = arcan_video_feedstate(ctx->vid);
		arcan_video_alterfeed(ctx->vid, (arcan_vfunc_cb)arcan_frameserver_emptyframe, *cstate); /* revert back to empty vfunc? */
	}

	ctx->vsync = CreateSemaphore(&nullsec_attr, 0, 1, NULL);
	ctx->async = CreateSemaphore(&nullsec_attr, 1, 1, NULL);
	ctx->esync = CreateSemaphore(&nullsec_attr, 1, 1, NULL);

	if (!ctx->vsync || !ctx->async ||!ctx->esync)
		arcan_fatal("arcan_frameserver(win32) couldn't allocate semaphores.\n");

	ctx->shm.key = strdup("win32_static");
	ctx->shm.ptr = (void*) shmpage;
	ctx->shm.shmsize = MAX_SHMSIZE;
	ctx->shm.handle = shmh;
	shmpage->parent = handle;

	arcan_frameserver_configure(ctx, setup);

	char cmdline[4196];
	snprintf(cmdline, sizeof(cmdline) - 1, "\"%s\" %i %i %i %i %s", setup.args.builtin.resource, shmh,
		ctx->vsync, ctx->async, ctx->esync, setup.args.builtin.mode);

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

/* anything else that can happen to the child at this point is handled in frameserver_tick_control */
		ctx->child = pi.hProcess;
		ctx->childp = pi.dwProcessId;

		arcan_sem_post(ctx->vsync);

		return ARCAN_OK;
	}
	else
		arcan_warning("arcan_frameserver_spawn_server(), couldn't spawn frameserver.\n");

error:
	arcan_warning("arcan_frameserver(win32): couldn't spawn frameserver session (out of shared memory?)\n");

	CloseHandle(ctx->async);
	CloseHandle(ctx->vsync);
	CloseHandle(ctx->esync);
	free(ctx->audb);

	if (shmpage)
		UnmapViewOfFile((void*) shmpage);

	if (shmh)
		CloseHandle(shmh);

	return ARCAN_ERRC_OUT_OF_SPACE;
}

