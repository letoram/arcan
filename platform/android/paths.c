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
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <android/log.h>

#include "../../arcan_math.h"
#include "../../arcan_general.h"

static char* tag_resleak = "resource_leak";
static data_source* alloc_datasource()
{
	data_source* res = malloc(sizeof(data_source));
	res->fd     = -1;
	res->start  =  0;
	res->len    =  0;

/* trace for this value to track down leaks */
	res->source = tag_resleak;
	
	return res;
}

/* just map to wrapping implementations in arcan_androidmain.c.
 * the "full" lookup scope is;
 * [RESOURCES] -> APK -> common-searchpaths
 * [THEME]     -> APK -> Application-specific store with themename as subdir */
extern int android_aman_scanraw(const char* const, off_t* outofs, 
	off_t* outlen);

/* no advanced scanning in use currently,
 * just open explicitly and if it succeeds, close fd again and return the match */
char* arcan_find_resource_path(const char* name, const char* path,
	int searchmask)
{
	off_t ofs, len;
	int fd = android_aman_scanraw(name, &ofs, &len); 

	if (-1 != fd){
		close(fd);
		return strdup(name); 
	}
	else
		return NULL;
}

char* arcan_find_resource(const char* name, int searchmask)
{
	return arcan_find_resource_path(name, NULL, searchmask);
}

data_source* aarcan_find_resource(const char* const key)
{
	arcan_warning("arcan_find_resource(%s)\n", key);
	data_source* res = alloc_datasource();
	res->source = strdup(key);
	res->fd = android_aman_scanraw(key, &res->start, &res->len);
	
	if (-1 == res->fd)
		arcan_release_resource(res);

	return res;	
}

bool check_theme(const char* theme)
{
	return false;
}

char* arcan_expand_resource(const char* label, bool global)
{
	return NULL;
}

char* arcan_themepath    = "./";
char* arcan_resourcepath = "./";
char* arcan_libpath      = NULL;
char* arcan_binpath      = "./ale_frameserver";
char* arcan_fontpath     = "/system/fonts";
char* arcan_themename    = "default";

const char* internal_launch_support()
{
	return "NO SUPPORT";
}

unsigned arcan_glob(char* basename, int searchmask,
	void (*cb)(char*, void*), void* tag)
{
		return 0;
}

bool arcan_setpaths()
{
	return true; /* all other checks can be done at the APK level */
}

