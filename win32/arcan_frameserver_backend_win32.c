/* stdlib */
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
#include "../arcan_general.h"
#include "../arcan_framequeue.h"
#include "../arcan_video.h"
#include "../arcan_audio.h"
#include "../arcan_frameserver_backend.h"
#include "../arcan_event.h"
#include "../arcan_util.h"
#include "../arcan_frameserver_backend_shmpage.h"

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

bool check_child(arcan_frameserver* src)
{
	if (!src)
		return false;

	DWORD exitcode;
	GetExitCodeProcess((HANDLE) src->child, &exitcode);
	return exitcode == STILL_ACTIVE;
}

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

			CloseHandle( src->shm.handle );
			free(src->shm.key);
			
			src->shm.ptr = NULL;
		}
		
		rv = ARCAN_OK;
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

static struct frameserver_shmpage* setupshmipc(HANDLE* dfd, char** key)
{
	struct frameserver_shmpage* res = NULL;

	SECURITY_ATTRIBUTES sa;
	sa.nLength = sizeof(sa);
	sa.lpSecurityDescriptor = NULL;
	sa.bInheritHandle = TRUE;
	
	*dfd = CreateFileMapping(INVALID_HANDLE_VALUE,  /* hack for specifying shm */
		&sa, /* security, want to inherit */
		PAGE_READWRITE, /* access */
	    0, /* big-endian size? */
		MAX_SHMSIZE, /* little-endian size */
		NULL /* null, pass by inheritance */
	);

	if (*dfd != NULL && (res = MapViewOfFile(*dfd, FILE_MAP_ALL_ACCESS, 0, 0, MAX_SHMSIZE))){
		memset(res, 0, sizeof(struct frameserver_shmpage));
		res->vbufofs = sizeof(struct frameserver_shmpage);
		res->vsyncc = res->vsyncp = CreateSemaphore(&sa, 0, 1, NULL); /* start locked, child will unlock when video is set-up */
		res->asyncc = res->asyncp = CreateSemaphore(&sa, 1, 1, NULL);
		return res;
	}

error:
	fprintf(stderr, "arcan_frameserver_spawn_server(), could't allocate shared memory.\n");
	return NULL;
}

arcan_frameserver* arcan_frameserver_spawn_server(char* fname, bool extcc, bool loop, arcan_frameserver* res)
{
	/* if res is non-null, we have a server context already set up,
	 * just need to reset the frame-server */
	bool restart = res != NULL;
	char* key;

	HANDLE shmh;
	struct frameserver_shmpage* shmpage = setupshmipc(&shmh, &key);

	if  (!shmpage)
		goto error;

	SDL_SysWMinfo wmi;
	SDL_VERSION(&wmi.version);
	SDL_GetWMInfo(&wmi);
	HWND handle = wmi.window;

	/* b: spawn the child process */
	char cmdline[512];
	snprintf(cmdline, sizeof(cmdline) - 1, "\"%s\" %i", fname, shmh);
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

		/* timed- wait for the semaphore */
		while (arcan_sem_timedwait( shmpage->vsyncp, 2000 ) != 0);
		if(1)
		{
			/* the child has successfully launched and provided the relevant video information */
			img_cons cons = { .w = shmpage->w, .h = shmpage->h, .bpp = shmpage->bpp};
			vfunc_state state = {.tag = ARCAN_TAG_MOVIE, .ptr = 0};
			arcan_errc err;

			if (res == NULL) {
				res = (arcan_frameserver*) calloc(sizeof(arcan_frameserver), 1);
				state.ptr = res;
				res->vid = arcan_video_addfobject((arcan_vfunc_cb) arcan_frameserver_videoframe, state, cons, 0);
				res->aid = arcan_audio_feed((void*)arcan_frameserver_audioframe, res, &err);
				res->source = strdup(fname);
			}

			res->child = pi.hProcess;
			res->child_alive = true;
			res->loop = loop;
			res->desc.width = cons.w;
			res->desc.height = cons.h;
			res->desc.bpp = cons.bpp;
			res->shm.ptr = (void*) shmpage;
			res->shm.handle = shmh;
			res->shm.shmsize = MAX_SHMSIZE;

			/* colour conversion currently ignored */
			res->desc.sformat = 0;
			res->desc.dformat = 0;

			/* vfthresh    : tolerance (ms) in deviation from current time and PTS,
			 * vskipthresh : tolerance (ms) before dropping a frame */
			res->desc.vfthresh    = ARCAN_FRAMESERVER_DEFAULT_VTHRESH_WAIT;
			res->desc.vskipthresh = ARCAN_FRAMESERVER_DEFAULT_VTHRESH_SKIP / 2;
			res->desc.samplerate = shmpage->frequency;
			res->desc.channels = shmpage->channels;
			res->desc.format = 0;
			res->desc.ready = true;
		
			unsigned short acachelim;
			unsigned short vcachelim;
			unsigned short abufsize;
			
			arcan_frameserver_queueopts(&vcachelim, &acachelim, &abufsize);
			
			arcan_framequeue_alloc(&res->afq, res->vid, acachelim, abufsize, arcan_frameserver_shmaudcb);
			arcan_framequeue_alloc(&res->vfq, res->vid, vcachelim, 4 + cons.w * cons.h * cons.bpp, arcan_frameserver_shmvidcb);
			return res;
		}
		else {
			fprintf(stderr, "arcan_frameserver_spawn_server(), couldn't spawn frameserver.\n");
		}
	}

error:
	return NULL;
}

