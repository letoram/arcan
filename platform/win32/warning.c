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
#include <stdarg.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>

#include <arcan_math.h>
#include <arcan_general.h>

extern bool stderr_redirected;
extern bool stdout_redirected;

static bool winnolog;

void arcan_warning(const char* msg, ...)
{
	char playbuf[4096];
	playbuf[4095] = '\0';

	if (winnolog)
		return;

/* redirection needed for win (SDL etc. also tries to, but we need 
 * to handle things) differently, especially for Win/UAC and permissions,
 * thus we can assume resource/theme
 * folder is r/w but nothing else .. 
 */
	if (!stdout_redirected && arcan_resourcepath != NULL){
		snprintf(playbuf, sizeof(playbuf) - 1,
			"%s/logs/arcan_warning.txt", arcan_resourcepath);
	/* even if this fail, we will not try again */
		winnolog = freopen(playbuf, "a", stdout) == NULL;
		stdout_redirected = true;
	}

	va_list args;
	va_start( args, msg );
	vfprintf(stdout,  msg, args );
	va_end(args);
	fflush(stdout);
}

void arcan_fatal(const char* msg, ...)
{
	char buf[4096];
	buf[4095] = '\0';

	if (!stderr_redirected && arcan_resourcepath != NULL){
		snprintf(buf, 4095, "%s/logs/arcan_fatal.txt", arcan_resourcepath);
		winnolog = freopen(buf, "a", stderr) == NULL;
		stderr_redirected = true;
	}

	va_list args;
	va_start(args, msg );
	vsnprintf(buf, 4095, msg, args);
	va_end(args);

	fprintf(stderr, "%s\n", buf);
	fflush(stderr);
	MessageBox(NULL, buf, NULL, MB_OK | MB_ICONERROR | MB_APPLMODAL );
	exit(1);
}

