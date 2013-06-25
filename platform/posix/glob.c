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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
 *
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <glob.h>

#include <stdbool.h>
#include "../../arcan_math.h"
#include "../../arcan_general.h"

extern char* arcan_themepath;
extern char* arcan_themename;

unsigned arcan_glob(char* basename, int searchmask,
	void (*cb)(char*, void*), void* tag)
{
	unsigned count = 0;
	char* basepath;
	char playbuf[4096];
	playbuf[4095] = '\0';

	if ((searchmask & ARCAN_RESOURCE_THEME) > 0){
		snprintf(playbuf, sizeof(playbuf)-1, "%s/%s/%s", 
			arcan_themepath, arcan_themename, strip_traverse(basename));

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
		snprintf(playbuf, sizeof(playbuf)-1, "%s/%s", arcan_resourcepath, 
			strip_traverse(basename));
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
