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
#include <stdbool.h>

#include "../../arcan_math.h"
#include "../../arcan_general.h"

/* malloc() wrapper for now, entry point here
 * to easier switch to pooled storage */
static char* tag_resleak = "resource_leak";
static data_source* alloc_datasource()
{
	data_source* res = malloc(sizeof(data_source));
	res->fd     =  BADFD;
	res->start  =  0;
	res->len    =  0;

/* trace for this value to track down leaks */
	res->source = tag_resleak; 
	
	return res;	
}

void arcan_release_resource(data_source* sptr)
{
	char playbuf[4096];
	playbuf[4095] = '\0';

	CloseHandle(sptr->fd);
	sptr->fd = BADFD;

	if (sptr->source){
		free(sptr->source);
		sptr->source = NULL;
	}
}

data_source arcan_open_resource(const char* url)
{
	data_source res = {.fd = BADFD};

	if (url){
		res.fd = CreateFile(url, GENERIC_READ, FILE_SHARE_READ, NULL,
			OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL );

		if (res.fd != INVALID_HANDLE_VALUE){
			res.start  = 0;
			res.source = strdup(url);
			res.len    = 0; /* map resource can figure it out */ 
		}
	}
	else 
		res.fd = BADFD;

	return res;
}

