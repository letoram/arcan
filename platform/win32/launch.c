#include <stdlib.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <signal.h>
#include <limits.h>
#include <pthread.h>
#include <semaphore.h>

#include <sys/types.h>

#include <SDL.h>
#include <SDL_opengl.h>

#undef SDL_VIDEO_DRIVER_DDRAW
#define SDL_VIDEO_DRIVER_DDRAW
#include <SDL_syswm.h>

#include <assert.h>
#include <errno.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"

#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_frameserver_backend.h"

int arcan_target_launch_external(const char* fname,
	char** argv, char** envv, char** libs)
{
	PROCESS_INFORMATION pi;
	STARTUPINFO si = {0};
	DWORD exitcode;
	unsigned long int start = arcan_frametime();
	if (fname == NULL || argv == NULL) {
		arcan_warning("arcan_target_launch_external(win32) :"
			" invalid arguments to launch\n\t (empty fname or empty argv)"
			", check the database.\n");
		return -1;
	}

	argv++; /* skip the first fname, UNIX convention and all that */

	arcan_video_prepare_external();

	char** base = argv;
	size_t total = strlen(fname) + 1;
	while (base && *base) {
		size_t res = strlen(*base++);
		if (res == -1) {
			arcan_warning("arcan_target_launch_external(), "
				"error parsing string argument.\n");
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
	if (CreateProcess(0, cmdline, 0, 0, FALSE,
		CREATE_NO_WINDOW, 0, 0, &si, &pi)) {
		while (1) {
			MSG msg;
			if (!GetExitCodeProcess(pi.hProcess, &exitcode)
				|| exitcode != STILL_ACTIVE)
				break;

			WaitForSingleObject(pi.hProcess, INFINITE);
		}
	}

	CloseHandle(pi.hProcess);
	free(cmdline);
	ShowWindow(wmi.window, SW_SHOW);
	arcan_video_restore_external();

	return arcan_frametime() - start;
}

arcan_frameserver* arcan_target_launch_internal(
	const char* fname, char** argv, char** envv, char** libs)
{
	return NULL;
}
