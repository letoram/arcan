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

unsigned arcan_glob(char* basename, enum arcan_namespaces space,
	void (*cb)(char*, void*), void* tag)
{
	unsigned count = 0;

	if (!basename || verify_traverse(basename) == NULL)
		return 0;

	for (int i = 1; i <= RESOURCE_SYS_ENDM; i <<= 1){
		if ( (space & i) == 0 )
			continue;

		glob_t res = {0};
		char* path = arcan_expand_resource(basename, i);

		if ( glob(path, 0, NULL, &res) == 0 ){
			char** beg = res.gl_pathv;
			while(*beg){
				cb(strrchr(*beg, '/') ? strrchr(*beg, '/')+1 : *beg, tag);
				beg++;
				count++;
			}
		}

		globfree(&res);
		arcan_mem_free(path);
	}

	return count;
}

