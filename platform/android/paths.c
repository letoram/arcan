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
#include <stdio.h>
#include <math.h>
#include <stdio.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <time.h>

#include <android/log.h>

#include "arcan_general.h"

/* just map to wrapping implementations in arcan_androidmain.c.
 * the "full" lookup scope is;
 * [RESOURCES] -> APK -> common-searchpaths
 * [THEME]     -> APK -> Application-specific store with themename as subdir */
extern int android_aman_scanraw(const char* const, off_t* outofs, off_t* outlen);

/* no advanced scanning in use currently,
 * just open explicitly and if it succeeds, close fd again and return the match */
char* arcan_resolve_resource(const char* name, const char* const path, int searchmask)
{
	arcan_warning("arcan_resolve_resource(%s)\n", name);
	off_t ofs;
	off_t len;
	int fd = android_aman_scanraw(name, &ofs, &len); 

	arcan_warning("arcan_resolve_resource() fd from lookup: %d\n", fd);
	
	if (-1 != fd){
		close(fd);
		return strdup(name); 
	}
	else
		return NULL;
}

data_source* arcan_find_resource(const char* const key)
{
	arcan_warning("arcan_find_resource(%s)\n", key);
	data_source* res = alloc_datasource();
	res->source = strdup(key);
	res->fd = android_aman_scanraw(key, &res->start, &res->len);
	
	if (-1 == res->fd)
		arcan_release_resource(&res);

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

char* arcan_find_resource_path(const char* label, const char* path, int searchmask, off_t* ofs)
{
	return NULL;
}

bool arcan_setpaths()
{
	arcan_themepath    = "./";
	arcan_resourcepath = "./";
	arcan_binpath      = "./ale_frameserver";
	arcan_fontpath     = "/system/fonts";
	arcan_themename    = "default";

	return true; /* all other checks can be done at the APK level */
}
