/* stdlib */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <strings.h>
#include <unistd.h>
#include <time.h>

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
#include "../arcan_frameserver_shmpage.h"
#include "../frameserver/arcan_frameserver_libretro.h"
#include "../frameserver/arcan_frameserver_decode.h"

/* APR won't be an explicit requirement until 0.2.3 */
#ifdef HAVE_APR
#include "../frameserver/arcan_frameserver_net.h"
#endif

#define DST_SAMPLERATE 44100
#define DST_AUDIOCHAN  2
#define DST_VIDEOCHAN  4

const int audio_samplerate = DST_SAMPLERATE;
const int audio_channels   = DST_AUDIOCHAN;
const int video_channels   = DST_VIDEOCHAN; /* RGBA */

FILE* logdev = NULL;
HWND parent = 0;
sem_handle async, vsync, esync;

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

void* frameserver_getrawfile_handle(file_handle fh, ssize_t* ressize)
{
	void* retb = NULL;

	*ressize = GetFileSize(fh, NULL);

	if (*ressize > 0 /* && sz < THRESHOLD */ )
	{
		retb = malloc(*ressize);
		if (!retb)
			return retb;

		memset(retb, 0, *ressize);
		OVERLAPPED ov = {0};
		DWORD retc;
		ov.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);

		if (!ReadFile(fh, retb, *ressize, &retc, &ov) && GetLastError() == ERROR_IO_PENDING){
			if (!GetOverlappedResult(fh, &ov, &retc, TRUE)){
				free(retb);
				retb = NULL;
				*ressize = -1;
			}
		}

		CloseHandle(ov.hEvent);
	}

	CloseHandle(fh);

	return retb;
}

/* always close handle */
bool frameserver_dumprawfile_handle(const void* const buf, size_t bufs, file_handle fh, bool finalize)
{
	bool rv = false;

/* facepalm awarded for this function .. */
	OVERLAPPED ov = {0};
	DWORD retc;

	if (INVALID_HANDLE_VALUE != fh){
		ov.Offset = 0xFFFFFFFF;
		ov.OffsetHigh = 0xFFFFFFFF;
		ov.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);

		if (!WriteFile(fh, buf, bufs, &retc, &ov) && GetLastError() == ERROR_IO_PENDING){
			if (!GetOverlappedResult(fh, &ov, &retc, TRUE)){
				LOG("frameserver(win32)_dumprawfile : failed, %ld\n", GetLastError());
			}
		}

		CloseHandle(ov.hEvent);
		if (finalize)
			CloseHandle(fh);
	}

	return rv;
}

/* assumed to live as long as the frameserver is alive, and killed / closed alongside process */
void* frameserver_getrawfile(const char* resource, ssize_t* ressize)
{
	HANDLE fh = CreateFile( resource, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL );
	if (fh == INVALID_HANDLE_VALUE)
		return NULL;

	HANDLE fmh = CreateFileMapping(fh, NULL, PAGE_READONLY, 0, 0, NULL);
	if (fmh == INVALID_HANDLE_VALUE)
		return NULL;

	void* res = (void*) MapViewOfFile(fmh, FILE_MAP_READ, 0, 0, 0);
	if (ressize)
		*ressize = (ssize_t) GetFileSize(fh, NULL);

	return res;
}

static LARGE_INTEGER ticks_pers;
static LARGE_INTEGER start_ticks;

long long int frameserver_timemillis()
{
	LARGE_INTEGER ticksnow;
	QueryPerformanceCounter(&ticksnow);

	ticksnow.QuadPart -= start_ticks.QuadPart;
	ticksnow.QuadPart *= 1000;
	ticksnow.QuadPart /= ticks_pers.QuadPart;

	return ticksnow.QuadPart;
}

file_handle frameserver_readhandle(arcan_event* src)
{
	return src->data.target.fh;
}

static HMODULE lastlib = NULL;
bool frameserver_loadlib(const char* const name)
{
    lastlib = LoadLibrary(name);
    return lastlib != NULL;
}

void* frameserver_requirefun(const char* const name)
{
    GetProcAddress(lastlib, name);
}

void frameserver_delay(unsigned long val)
{
/* since sleep precision sucks, timers won't help and it's typically a short amount we need to waste (3-7ish miliseconds)
 * just busyloop and count .. */

	unsigned long int start = frameserver_timemillis();

	while (val > (frameserver_timemillis() - start))
		Sleep(0); /* yield */
}

/* by default, we only do this for libretro where it might help
 * with external troubleshooting */
static void toggle_logdev(const char* prefix)
{
	const char* logdir = getenv("ARCAN_FRAMESERVER_LOGDIR");
/* win32 .. :'( */
	if (!logdir)
		logdir = "./resources/logs";

	if (logdir){
		char timeb[16];
		time_t t = time(NULL);
		struct tm* basetime = localtime(&t);
		strftime(timeb, sizeof(timeb)-1, "%y%m%d_%H%M", basetime);

		size_t logbuf_sz = strlen(logdir) + sizeof("/fsrv__yymmddhhss.txt") + strlen(prefix);
		char* logbuf = malloc(logbuf_sz + 1);

		snprintf(logbuf, logbuf_sz+1, "%s/fsrv_%s_%s.txt", logdir, prefix, timeb);
		logdev = freopen(logbuf, "a", stderr);
	}
}

int main(int argc, char* argv[])
{
	logdev = NULL;

#ifndef _DEBUG
/*	_set_invalid_parameter_handler(inval_param_handler) */
	DWORD dwMode = SetErrorMode(SEM_NOGPFAULTERRORBOX);
	SetErrorMode(dwMode | SEM_NOGPFAULTERRORBOX);

#else
/* set this env whenever you want to step through the frameserver as launched from the parent */
	LOG("arcan_frameserver(win32) -- launched with %d args.\n", argc);
#endif

	if (getenv("ARCAN_FRAMESERVER_DEBUGSTALL")){
		LOG("frameserver_debugstall, waiting 10s to continue. pid: %d\n", (int) getpid());
		Sleep(10);
	}

/* the convention on windows doesn't include the program name as first argument,
 * but some execution contexts may use it, e.g. ruby / cygwin / ... so skew the arguments */
    if (7 == argc){
        argv++;
        argc--;
    }

/* map cmdline arguments (resource, shmkey, vsem, asem, esem, mode),
 * parent is retrieved from shmpage */
	if (6 != argc){
	    LOG("arcan_frameserver(win32, parsecmd) -- unexpected number of arguments, giving up.\n");
        return 1;
    }

	vsync = (HANDLE) strtoul(argv[2], NULL, 10);
	async = (HANDLE) strtoul(argv[3], NULL, 10);
	esync = (HANDLE) strtoul(argv[4], NULL, 10);

	char* resource = argv[0];
	char* fsrvmode = argv[5];
	char* keyfile   = argv[1];

/* seed monotonic timing */
	QueryPerformanceFrequency(&ticks_pers);
	QueryPerformanceCounter(&start_ticks);

	if (strcmp(fsrvmode, "movie") == 0 || strcmp(fsrvmode, "audio") == 0)
		arcan_frameserver_ffmpeg_run(resource, keyfile);
#ifdef HAVE_APR
	else if (strcmp(fsrvmode, "net-cl") == 0 || strcmp(fsrvmode, "net-srv") == 0){
		toggle_logdev("net");
		arcan_frameserver_net_run(resource, keyfile);
	}
#endif
	else if (strcmp(fsrvmode, "libretro") == 0){
		toggle_logdev("retro");
		arcan_frameserver_libretro_run(resource, keyfile);
	}
	else if (strcmp(fsrvmode, "record") == 0){
		toggle_logdev("record");
		arcan_frameserver_ffmpeg_encode(resource, keyfile);
	}

	else;

	return 0;
}
