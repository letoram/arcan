/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
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

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <stdio.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <time.h>

#include "arcan_math.h"
#include "arcan_general.h"

/* sigh, we don't know where we come from so we have to have a separate buffer here */
extern bool stdout_redirected;
static char winplaybuf[64 * 1024] = {0};
static bool winnolog = false;

void arcan_warning(const char* msg, ...)
{
	if (winnolog)
		return;

/* redirection needed for win (SDL etc. also tries to, but we need to handle things)
 * differently, especially for Win/UAC and permissions, thus we can assume resource/theme
 * folder is r/w but nothing else .. */
	if (!stdout_redirected && arcan_resourcepath != NULL){
		sprintf(winplaybuf, "%s/logs/arcan_warning.txt", arcan_resourcepath);
	/* even if this fail, we will not try again */
		winnolog = freopen(winplaybuf, "a", stdout) == NULL;
		stdout_redirected = true;
	}

	va_list args;
	va_start( args, msg );
	vfprintf(stdout,  msg, args );
	va_end(args);
	fflush(stdout);
}

#include "win32/realpath.c"

extern bool stderr_redirected;
void arcan_fatal(const char* msg, ...)
{
	char buf[256] = {0};
	if (!stderr_redirected && arcan_resourcepath != NULL){
		sprintf(winplaybuf, "%s/logs/arcan_fatal.txt", arcan_resourcepath);
		winnolog = freopen(winplaybuf, "a", stderr) == NULL;
		stderr_redirected = true;
	}

	va_list args;
	va_start(args, msg );
	vsnprintf(buf, 255, msg, args);
	va_end(args);

	fprintf(stderr, "%s\n", buf);
	fflush(stderr);
	MessageBox(NULL, buf, NULL, MB_OK | MB_ICONERROR | MB_APPLMODAL );
	exit(1);
}

double round(double x)
{
	return floor(x + 0.5);
}

bool arcan_setpaths()
{
/* could add a check of the users path cleanup (that turned out to be a worse mess than before)
 * with AppData etc. from Vista and friends */

	if (!arcan_resourcepath)
		arcan_resourcepath = strdup("./resources");

	arcan_libpath = NULL;

	if (!arcan_themepath)
		arcan_themepath = strdup("./themes");

	if (!arcan_binpath)
		arcan_binpath = strdup("./arcan_frameserver");

	return true;
}

int arcan_sem_post(sem_handle sem)
{
	return ReleaseSemaphore(sem, 1, 0);
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return CloseHandle(sem);
}

int arcan_sem_timedwait(sem_handle sem, int msecs)
{
	if (msecs == -1)
		msecs = INFINITE;

	DWORD rc = WaitForSingleObject(sem, msecs);
	int rv = 0;

	switch (rc){
		case WAIT_ABANDONED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_TIMEOUT:
			rv = -1;
			errno = EAGAIN;
		break;

		case WAIT_FAILED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_OBJECT_0:
		break; /* default returnpath */

	default:
		arcan_warning("Warning: arcan_sem_timedwait(win32) -- unknown result on WaitForSingleObject (%i)\n", rc);
	}

	return rv;
}

unsigned arcan_glob(char* basename, int searchmask, void (*cb)(char*, void*), void* tag){
	HANDLE findh;
	WIN32_FIND_DATA finddata;

	unsigned count = 0;
	char* basepath;

	if ((searchmask & ARCAN_RESOURCE_THEME) > 0){
		snprintf(playbuf, playbufsize, "%s/%s/%s", arcan_themepath, arcan_themename, strip_traverse(basename));

		findh = FindFirstFile(playbuf, &finddata);
		if (findh != INVALID_HANDLE_VALUE)
			do{
				snprintf(playbuf, playbufsize, "%s", finddata.cFileName);
				if (strcmp(playbuf, ".") == 0 || strcmp(playbuf, "..") == 0)
					continue;

				cb(playbuf, tag);
				count++;
			} while (FindNextFile(findh, &finddata));

		FindClose(findh);
	}

	if ((searchmask & ARCAN_RESOURCE_SHARED) > 0){
		snprintf(playbuf, playbufsize, "%s/%s", arcan_resourcepath, strip_traverse(basename));

		findh = FindFirstFile(playbuf, &finddata);
		if (findh != INVALID_HANDLE_VALUE)
		do{
			snprintf(playbuf, playbufsize, "%s", finddata.cFileName);
			if (strcmp(playbuf, ".") == 0 || strcmp(playbuf, "..") == 0)
					continue;

			cb(playbuf, tag);
			count++;
		} while (FindNextFile(findh, &finddata));

		FindClose(findh);
	}

	return count;
}

char* arcan_findshmkey(int* dfd, bool semalloc)
{
	return NULL;
}
