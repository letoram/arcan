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

#include <arcan_math.h>
#include <arcan_general.h>

static char* tag_resleak = "resource_leak";

void arcan_release_resource(data_source* sptr)
{
/* relying on a working close() is bad form,
 * unfortunately recovery options are few
 * this could be a race instead, however main
 * app shouldn't be multithreaded. */
	if (-1 != sptr->fd){
		int trycount = 10;
		while (trycount--){
			if (close(sptr->fd) == 0)
				break;
		}

/* don't want this one free:d */
		if ( sptr->source == tag_resleak )
			sptr->source = NULL;

/* something broken with the file-descriptor,
 * not many recovery options but purposefully leak
 * the memory so that it can be found in core dumps etc. */
		if (trycount && sptr->source){
			const char fmt[] = "broken_fd(%.4d:%s)";
	    char playbuf[sizeof(fmt) + 4 + strlen(sptr->source)];
			snprintf(playbuf, sizeof(playbuf)/sizeof(playbuf[0]),
				fmt, sptr->fd, sptr->source);

			free( sptr->source );
			sptr->source = strdup(playbuf);
			return;
		}
		else {
/* make the released memory distinguishable from a broken
 * descriptor from a memory analysis perspective */
			free( sptr->source );
			sptr->fd     = -1;
			sptr->start  = -1;
			sptr->len    = -1;
		}
	}
}

/*
 * Somewhat rugged at the moment,
 * Mostly designed the way it is to account for the "zip is a container"
 * approach used in android and elsewhere, or (with some additional work)
 * actual URI references
 */
data_source arcan_open_resource(const char* url)
{
	data_source res = {.fd = BADFD};
	if (!url)
		return res;

	res.fd = open(url, O_RDONLY);
	if (res.fd != -1){
		res.start  = 0;
		res.source = strdup(url);
		res.len    = 0; /* map resource can figure it out */
		fcntl(res.fd, F_SETFD, FD_CLOEXEC);
	}

	return res;
}
