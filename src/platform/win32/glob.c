/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include <arcan_math.h>
#include <arcan_general.h>

extern char* arcan_themename;
extern char* arcan_themepath;

unsigned arcan_glob(char* basename, enum arcan_namespaces space,
	void (*cb)(char*, void*), void* tag)
{
	unsigned count = 0;
	if (!basename || verify_traverse(basename) == NULL)
		return 0;

	for (int i = 1; i <= RESOURCE_SYS_ENDM; i <<= 1){
		if ((space & i) == 0)
			continue;

		char* path = arcan_expand_resource(basename, i);
		WIN32_FIND_DATA finddata;
		HANDLE findh = FindFirstFile(path, &finddata);
		if (findh != INVALID_HANDLE_VALUE)
			do{
				if (!finddata.cFileName || strcmp(finddata.cFileName, "..") == 0 ||
					strcmp(finddata.cFileName, ".") == 0)
					continue;

				cb(finddata.cFileName, tag);

				count++;
			} while (FindNextFile(findh, &finddata));

		FindClose(findh);
		arcan_mem_free(path);
	}

	return count;
}

