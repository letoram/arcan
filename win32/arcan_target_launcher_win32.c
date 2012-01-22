#include <stdlib.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <limits.h>

#include <SDL.h>
#include <SDL_opengl.h>
#include <SDL_syswm.h>

#include <assert.h>
#include <errno.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_video.h"
#include "../arcan_audio.h"
#include "../arcan_event.h"
#include "../arcan_framequeue.h"
#include "../arcan_frameserver_backend.h"
#include "../arcan_target_const.h"
#include "../arcan_target_launcher.h"

extern bool fullscreen;

int arcan_target_launch_external(const char* fname, char** argv)
{
	PROCESS_INFORMATION pi;
	STARTUPINFO si = {0};
	DWORD exitcode;
	unsigned long int start = SDL_GetTicks();
	if (fname == NULL || argv == NULL) {
		arcan_warning("arcan_target_launch_external(win32) : invalid arguments to launch\n\t (empty fname or empty argv), check the database.\n");
		return -1;
	}

	argv++; /* skip the first fname, UNIX convention and all that */
		
	arcan_video_prepare_external();

	char** base = argv;
	size_t total = strlen(fname) + 1;
	while (base && *base) {
		size_t res = strlen(*base++);
		if (res == -1) {
			arcan_warning("arcan_target_launch_external(), error parsing string argument.\n");
			continue;
		}

		total += res + 1;
	}

	char* cmdline;
	cmdline = (char*) calloc(total + 2, sizeof(char));
	base = argv;
	sprintf(cmdline, "%s ", fname);

	while (base && *base) {
		strcat(cmdline, *base++);
		strcat(cmdline, " ");
	}

	/* grab HWND */
	SDL_SysWMinfo wmi;
	SDL_VERSION(&wmi.version);
	SDL_GetWMInfo(&wmi);
	ShowWindow(wmi.window, SW_HIDE);

	/* merge argv */
	si.cb = sizeof(si);
	if (CreateProcess(0, cmdline, 0, 0, FALSE, CREATE_NO_WINDOW, 0, 0, &si, &pi)) {
		while (1) {
			MSG msg;
			if (!GetExitCodeProcess(pi.hProcess, &exitcode) || exitcode != STILL_ACTIVE)
				break;

			WaitForSingleObject(pi.hProcess, INFINITE);
		}
	}

	CloseHandle(pi.hProcess);
	free(cmdline);
	ShowWindow(wmi.window, SW_SHOW);
	arcan_video_restore_external();

	return SDL_GetTicks() - start;
}

/* Internal support missing completely,
 * See arcan_target_launcher_unix for the structure 
 * (most of the rendering code etc. should be usable still)
 * Port arcan_target.c and make a .dll- generating front-end.
 * Lastly, integrate one of the nasty ways of doing dll- injection */

int arcan_target_clean_internal(arcan_launchtarget* tgt)
{
	if (!tgt)
		return -1;

	/* kill process handle */
	/* close descriptors / shared memory pages, ... */

	return 0;
}

static arcan_errc again_feed(float gain, void* tag)
{
	arcan_launchtarget* tgt = (arcan_launchtarget*) tag;
	arcan_errc rv = ARCAN_OK;

	/* 1 char tag (2 : audio gain)
	 * 1 float (4 bytes) gain value */

	return rv;
}

void arcan_target_suspend_internal(arcan_launchtarget* tgt)
{
}

void arcan_target_resume_internal(arcan_launchtarget* tgt)
{
}

arcan_errc arcan_target_inject_event(arcan_launchtarget* tgt, arcan_event ev)
{
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

arcan_launchtarget* arcan_target_launch_internal(const char* fname, char** argv,
        enum intercept_mechanism mechanism,
        enum intercept_mode intercept,
        enum communication_mode comm)
{
	return NULL;
}
