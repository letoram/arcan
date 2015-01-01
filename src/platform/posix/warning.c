/* public domain, no copyright claimed */

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

void (*arcan_fatal_hook)(void) = NULL;

void arcan_warning(const char* msg, ...)
{
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
}

void arcan_fatal(const char* msg, ...)
{
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);

	if (arcan_fatal_hook)
		arcan_fatal_hook();

#ifdef _DEBUG
	abort();
#else
	exit(1);
#endif
}
