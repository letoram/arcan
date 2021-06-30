/*
 * Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "platform_types.h"
#include "os_platform.h"

/*
 * some mapping mechanisms other than arcan_map_resource should be used for
 * dealing with single resources larger than this size.
 */
#ifndef MAX_RESMAP_SIZE
#define MAX_RESMAP_SIZE (1024 * 1024 * 40)
#endif

static inline bool read_safe(int fd, size_t ntr, int bs, char* dofs)
{
	char* dbuf = dofs;

	while (ntr > 0){
		int nr = read(fd, dbuf, bs > ntr ? ntr : bs);

		if (nr > 0)
			ntr -= nr;
		else
			if (errno == EINTR);
		else
			break;

		if (dofs)
			dbuf += nr;
	}

	return ntr == 0;
}

/*
 * flow cases:
 *  (1) too large region to map
 *  (2) mapping at an unaligned offset
 *  (3) mapping a pipe at offset
 */
map_region arcan_map_resource(data_source* source, bool allowwrite)
{
	map_region rv = {0};
	struct stat sbuf;

/*
 * if additional properties (size, ...) has not yet been resolved,
 * try and figure things out manually
 */
	if (0 == source->len && -1 != fstat(source->fd, &sbuf)){
		source->len = sbuf.st_size;
		source->start = 0;
	}

/* bad resource */
	if (!source->len)
		return rv;

/*
 * for unaligned reads (or in-place modifiable memory)
 * we manually read the file into a buffer
 */
	if (source->start % sysconf(_SC_PAGE_SIZE) != 0 || allowwrite){
		goto memread;
	}

/*
 * The use-cases for most resources mapped in this manner relies on
 * mapping reasonably small buffer lengths for decoding. Reasonably
 * is here defined by MAX_RESMAP_SIZE
 */
	if (0 < source->len && MAX_RESMAP_SIZE > source->len){
		rv.sz  = source->len;
		rv.ptr = mmap(NULL, rv.sz, PROT_READ,
			MAP_FILE | MAP_PRIVATE, source->fd, source->start);

		if (rv.ptr == MAP_FAILED){
			char errbuf[64];
			if (strerror_r(errno, errbuf, 64))
				;

			arcan_warning("arcan_map_resource() failed, reason(%d): %s\n\t"
				"(length)%d, (fd)%d, (offset)%d\n", errno, errbuf,
				rv.sz, source->fd, source->start);

			rv.ptr = NULL;
			rv.sz  = 0;
		}
		else{
			rv.mmap = true;
		}
	}
	return rv;

memread:
	rv.ptr  = malloc(source->len);
	rv.sz   = source->len;
	rv.mmap = false;
/*
 * there are several devices where we can assume that seeking is not possible,
 * then we automatically convert seeking to "skipping"
 */
		bool rstatus = true;
		if (source->start > 0 && -1 == lseek(source->fd, SEEK_SET, source->start)){
			rstatus = read_safe(source->fd, source->start, 8192, NULL);
		}

		if (rstatus){
			rstatus = read_safe(source->fd, source->len, 8192, rv.ptr);
		}

		if (!rstatus){
			free(rv.ptr);
			rv.ptr = NULL;
			rv.sz  = 0;
		}

	return rv;
}

bool arcan_release_map(map_region region)
{
	int rv = -1;

	if (region.sz > 0 && region.ptr)
		rv = region.mmap ? munmap(region.ptr, region.sz) : (free(region.ptr), 0);

	return rv != -1;
}
