/*
 * No copyright claimed, Public Domain
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
	if (winnolog)
		return;

/* redirection needed for win (SDL etc. also tries to, but we need
 * to handle things) differently, especially for Win/UAC and permissions,
 * thus we can assume resource/theme
 * folder is r/w but nothing else ..
 */
	if (!stdout_redirected){
		char* dst = arcan_expand_resource("arcan_warning.txt", RESOURCE_SYS_DEBUG);
		if (dst){
			winnolog = freopen(dst, "a", stdout) == NULL;
			arcan_mem_free(dst);
		}
		else
			winnolog = true;
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
	va_list args;
	va_start(args, msg );
	size_t len = vsnprintf(NULL, 0, msg, args);
	va_end(args);

	char dbuf[len];
	va_start(args, msg );
	vsnprintf(dbuf, len, msg, args);
	va_end(args);

	char* dst = arcan_expand_resource("arcan_warning.txt", RESOURCE_SYS_DEBUG);
	if (dst){
		vfprintf(stderr, "%s\n", (char*)dbuf);
		fflush(stderr);
		arcan_mem_free(dst);
	}

	MessageBox(NULL, dbuf, NULL, MB_OK | MB_ICONERROR | MB_APPLMODAL );
	exit(1);
}

