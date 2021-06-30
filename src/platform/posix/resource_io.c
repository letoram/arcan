/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
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

#include "platform_types.h"
#include "platform.h"

static char* tag_resleak = "resource_leak";

void arcan_release_resource(data_source* sptr)
{
	if (-1 != sptr->fd)
/* trying to recover other issues are futile and race-prone */
		while (-1 == close(sptr->fd) && errno == EINTR);

/* don't want this one free:d */
	if ( sptr->source == tag_resleak )
		sptr->source = NULL;

	free(sptr->source);
	sptr->source = NULL;
	sptr->fd = -1;
	sptr->start = -1;
	sptr->len = -1;
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
