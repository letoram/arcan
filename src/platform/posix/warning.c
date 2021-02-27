/* public domain, no copyright claimed */

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

void (*arcan_fatal_hook)(void) = NULL;

static _Thread_local FILE* log_dst;
static _Thread_local int log_level;

#ifdef ARCAN_LWA
#include <arcan_shmif.h>
#endif

void arcan_log_destination(FILE* outf, int level)
{
	log_dst = outf;
	log_level = level;
}

void arcan_warning(const char* msg, ...)
{
	va_list args;
	va_start( args, msg );
		if (log_dst)
			vfprintf(stderr,  msg, args );
	va_end( args);
}

void arcan_fatal(const char* msg, ...)
{
	va_list args;
	ssize_t cc; /* some bad versions/libcs return -1 or error and not 0 */

	va_start(args, msg);
		cc = vsnprintf(NULL, 0, msg, args);
	va_end(args);

	char* out = NULL;
	if (cc > 0 && (out = (char*) malloc(cc + 1)) ){
		va_start(args, msg);
			vsnprintf(out, cc+1, msg, args);
		va_end(args);
	}

/* for lwa we build a dynamic string and set that as the 'last words' for the
 * shmif segment in order to forward the error message to the other end */
#ifdef ARCAN_LWA
	if (out){
		arcan_shmif_last_words(arcan_shmif_primary(SHMIF_INPUT), out);
	}
#endif

	if (out){
		fputs(out, stderr);
		fflush(stderr);
		free(out);
	}

	if (arcan_fatal_hook)
		arcan_fatal_hook();

#ifdef _DEBUG
	abort();
#else
	exit(1);
#endif
}
