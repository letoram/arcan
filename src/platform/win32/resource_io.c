/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#include <arcan_math.h>
#include <arcan_general.h>

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

