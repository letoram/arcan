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
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "../../arcan_math.h"
#include "../../arcan_general.h"

char* arcan_themepath      = NULL;
char* arcan_resourcepath   = NULL;
char* arcan_themename      = "welcome";
char* arcan_binpath        = NULL;
char* arcan_libpath        = NULL;
char* arcan_fontpath       = "fonts/";

static inline bool is_dir(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL)
			return false;

	if (stat(fn, &buf) == 0)
		rv = S_ISDIR(buf.st_mode);

	return rv;
}

static inline bool file_exists(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL)
		return false;

	if (stat(fn, &buf) == 0)
		rv = S_ISREG(buf.st_mode);

	return rv;
}

char* arcan_find_resource(const char* label, int searchmask)
{
	if (label == NULL || strip_traverse(label) == NULL)
		return NULL;

	char playbuf[4096];
	playbuf[4095] = '\0';

	if (searchmask & ARCAN_RESOURCE_THEME) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s", arcan_themepath, 
			arcan_themename, label);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	if (searchmask & ARCAN_RESOURCE_SHARED) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s", arcan_resourcepath, label);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	return NULL;
}

static bool check_paths()
{
	/* binpath, libpath, resourcepath, themepath */
	if (!arcan_binpath){
		arcan_fatal("Fatal: check_paths(), frameserver not found.\n");
		return false;
	}

	if (!arcan_libpath){
		arcan_warning("Warning: check_paths(), libpath not found "
			"(internal support downgraded to partial).\n");
	}

	if (!arcan_resourcepath){
		arcan_fatal("Fatal: check_paths(), resourcepath not found.\n");
		return false;
	}

	if (!arcan_themepath){
		arcan_fatal("Fatal: check_paths(), themepath not found.\n");
	}

	return true;
}

bool check_theme(const char* theme)
{
	if (theme == NULL)
		return false;
	char playbuf[4096];
	playbuf[4095] = '\0';

	snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s", arcan_themepath, theme);

	if (!is_dir(playbuf)) {
		arcan_warning("Warning: theme check failed, directory %s not found.\n", 
			playbuf);
		return false;
	}

	snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s.lua", arcan_themepath,
		theme, theme);
	if (!file_exists(playbuf)) {
		arcan_warning("Warning: theme check failed, script %s not found.\n", 
			playbuf);
		return false;
	}

	return true;
}

char* arcan_expand_resource(const char* label, bool global)
{
	char playbuf[4096];
	playbuf[4095] = '\0';

	if (strip_traverse(label) == NULL)
		return NULL;

	if (global) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s", arcan_resourcepath, 
			label);
	}
	else {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s", arcan_themepath, 
			arcan_themename, label);
	}

	return strdup( playbuf );
}

char* arcan_find_resource_path(const char* label, const char* path, 
	int searchmask)
{
	if (label == NULL || 
		strip_traverse(path) == NULL || strip_traverse(label) == NULL)
			return NULL;

	char playbuf[4096];
	playbuf[4095] = '\0';

	if (searchmask & ARCAN_RESOURCE_THEME) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s/%s", arcan_themepath, 
			arcan_themename, path, label);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	if (searchmask & ARCAN_RESOURCE_SHARED) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s", 
			arcan_resourcepath, path, label);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	return NULL;
}

static char* unix_find(const char* fname){
	char* res = NULL;
	char* pathtbl[] = {
		".",
		NULL,
		"/usr/local/share/arcan",
		"/usr/share/arcan",
		NULL
	};

	if (getenv("HOME")){
		size_t len = strlen( getenv("HOME") ) + 9;
		pathtbl[1] = malloc(len);
		snprintf(pathtbl[1], len, "%s/.arcan", getenv("HOME") );
	}
	else
		pathtbl[1] = strdup("");

	char playbuf[4096];
	playbuf[4095] = '\0';

	for (char** base = pathtbl; *base != NULL; base++){
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s", *base, fname );

		if (is_dir(playbuf)){
			res = strdup(playbuf);
			break;
		}
	}

cleanup:
	free(pathtbl[1]);
	return res;
}

static void setpaths_unix()
{
	if (arcan_binpath == NULL){
		if (file_exists( getenv("ARCAN_FRAMESERVER") ) )
			arcan_binpath = strdup( getenv("ARCAN_FRAMESERVER") );
		else if (file_exists( "./arcan_frameserver") )
			arcan_binpath = strdup("./arcan_frameserver" );
		else if (file_exists( "/usr/local/bin/arcan_frameserver"))
			arcan_binpath = strdup("/usr/local/bin/arcan_frameserver");
		else if (file_exists( "/usr/bin/arcan_frameserver" ))
			arcan_binpath = strdup("/usr/bin/arcan_frameserver");
		else ;
	}

	/* thereafter, the hijack-  lib */
	if (arcan_libpath == NULL){
		if (file_exists( getenv("ARCAN_HIJACK") ) )
			arcan_libpath = strdup( getenv("ARCAN_HIJACK") );
		else if (file_exists( "./" LIBNAME ) )
			arcan_libpath = realpath( "./", NULL );
		else if (file_exists( "/usr/local/lib/" LIBNAME) )
			arcan_libpath = strdup( "/usr/local/lib/");
		else if (file_exists( "/usr/lib/" LIBNAME) )
			arcan_libpath = strdup( "/usr/lib/");
	}

	if (arcan_resourcepath == NULL){
		if ( file_exists(getenv("ARCAN_RESOURCEPATH")) )
			arcan_resourcepath = strdup( getenv("ARCAN_RESOURCEPATH") );
		else
			arcan_resourcepath = unix_find("resources");
	}

	if (arcan_themepath == NULL){
		if ( file_exists(getenv("ARCAN_THEMEPATH")) )
			arcan_themepath = strdup( getenv("ARCAN_THEMEPATH") );
		else
			arcan_themepath = unix_find("themes");
	}
}

bool arcan_setpaths()
{
	setpaths_unix();
	return check_paths();
}
