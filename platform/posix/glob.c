/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <glob.h>

#include <stdbool.h>
#include <sys/types.h>
#include <arcan_math.h>
#include <arcan_general.h>

extern char* arcan_themepath;
extern char* arcan_themename;

unsigned arcan_glob(char* basename, int searchmask,
	void (*cb)(char*, void*), void* tag)
{
	unsigned count = 0;

	if (!basename || strip_traverse(basename) == NULL)
		return 0;

	char playbuf[4096];
	playbuf[4095] = '\0';

	if ((searchmask & ARCAN_RESOURCE_THEME) > 0){
		snprintf(playbuf, sizeof(playbuf)-1, "%s/%s/%s", 
			arcan_themepath, arcan_themename, basename);

		glob_t res = {0};
		if ( glob(playbuf, 0, NULL, &res) == 0 ){
			char** beg = res.gl_pathv;
			while(*beg){
				cb(strrchr(*beg, '/') ? strrchr(*beg, '/')+1 : *beg, tag);
				beg++;
				count++;
			}
		}
		globfree(&res);
	}

	if ((searchmask & ARCAN_RESOURCE_SHARED) > 0){
		snprintf(playbuf, sizeof(playbuf)-1, "%s/%s",arcan_resourcepath,basename);
		glob_t res = {0};

		if ( glob(playbuf, 0, NULL, &res) == 0 ){
			char** beg = res.gl_pathv;
			while(*beg){
				cb(strrchr(*beg, '/') ? strrchr(*beg, '/')+1 : *beg, tag);
				beg++;
				count++;
			}
		}
		globfree(&res);
	}

	return count;
}
