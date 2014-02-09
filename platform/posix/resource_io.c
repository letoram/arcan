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
	    char playbuf[4096];
  	  playbuf[4095] = '\0';

			snprintf(playbuf, sizeof(playbuf) - 1, "broken_fd(%d:%s)", 
				sptr->fd, sptr->source);

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

	if (url){
		res.fd = open(url, O_RDONLY);
		if (res.fd != -1){
			res.start  = 0;
			res.source = strdup(url);
			res.len    = 0; /* map resource can figure it out */ 
		}
	}
	else 
		res.fd = BADFD;

	return res;
}
