/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include <arcan_math.h>
#include <arcan_general.h>

extern char* arcan_themename;
extern char* arcan_themepath;

unsigned arcan_glob(char* basename, int searchmask, 
	void (*cb)(char*, void*), void* tag){
	HANDLE findh;
	WIN32_FIND_DATA finddata;
	char playbuf[4096];
	playbuf[4095] = '\0';

	unsigned count = 0;
	char* basepath;

	if ((searchmask & ARCAN_RESOURCE_THEME) > 0){
		snprintf(playbuf, sizeof(playbuf)-1, "%s/%s/%s", 
			arcan_themepath, arcan_themename, strip_traverse(basename));

		findh = FindFirstFile(playbuf, &finddata);
		if (findh != INVALID_HANDLE_VALUE)
			do{
				snprintf(playbuf, sizeof(playbuf)-1, "%s", finddata.cFileName);
				if (strcmp(playbuf, ".") == 0 || strcmp(playbuf, "..") == 0)
					continue;

				cb(playbuf, tag);
				count++;
			} while (FindNextFile(findh, &finddata));

		FindClose(findh);
	}

	if ((searchmask & ARCAN_RESOURCE_SHARED) > 0){
		snprintf(playbuf, sizeof(playbuf)-1, "%s/%s", arcan_resourcepath, 
			strip_traverse(basename));

		findh = FindFirstFile(playbuf, &finddata);
		if (findh != INVALID_HANDLE_VALUE)
		do{
			snprintf(playbuf, sizeof(playbuf)-1, "%s", finddata.cFileName);
			if (strcmp(playbuf, ".") == 0 || strcmp(playbuf, "..") == 0)
					continue;

			cb(playbuf, tag);
			count++;
		} while (FindNextFile(findh, &finddata));

		FindClose(findh);
	}

	return count;
}

