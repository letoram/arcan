/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#include <arcan_math.h>
#include <arcan_general.h>

/*
 * some mapping mechanisms other than arcan_map_resource
 * should be used for dealing with single resources larger
 * than this size.
 */
#ifndef MAX_RESMAP_SIZE
#define MAX_RESMAP_SIZE (1024 * 1024 * 10)
#endif

/* malloc() wrapper for now, entry point here
 * to easier switch to pooled storage */
static char* tag_resleak = "resource_leak";
static data_source* alloc_datasource()
{
	data_source* res = malloc(sizeof(data_source));
	res->fd     = BADFD;
	res->start  =  0;
	res->len    =  0;

/* trace for this value to track down leaks */
	res->source = tag_resleak;

	return res;
}

/* FIXME;
 * on failed mapping, try to read/buffer in accordance with
 * read_safe etc. from POSIX
 */

map_region arcan_map_resource(data_source* source, bool allowwrite)
{
	map_region rv = {0};

	HANDLE fmh = CreateFileMapping(source->fd, NULL, PAGE_READONLY,
		0, 0, NULL);

/* the caller is forced to clean up */
	if (fmh == INVALID_HANDLE_VALUE){
		return rv;
	}

	rv.ptr = (void*) MapViewOfFile(fmh, FILE_MAP_READ, 0, 0, 0);
	rv.sz  = GetFileSize(source->fd, NULL);
	rv.mmap= true;

	return rv;
}

bool arcan_release_map(map_region region)
{
	int rv = -1;

	if (region.sz > 0 && region.ptr)
		rv = region.mmap ?
			UnmapViewOfFile(region.ptr) :
			(free(region.ptr), 0);

	return rv != -1;
}
