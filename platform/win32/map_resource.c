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
