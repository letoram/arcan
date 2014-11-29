#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

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

#ifdef _DEBUG
	abort();
#else
	exit(1);
#endif
}
