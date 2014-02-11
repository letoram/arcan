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
#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <arcan_math.h>
#include <arcan_general.h>

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
	if (label == NULL)
		return NULL;

	char playbuf[4096];
	playbuf[4095] = '\0';

	if (searchmask & ARCAN_RESOURCE_THEME) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s", arcan_themepath, 
			arcan_themename, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	if (searchmask & ARCAN_RESOURCE_SHARED) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s", 
			arcan_resourcepath, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	return NULL;
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

	if (global) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s", arcan_resourcepath, 
			label);
	}
	else {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s", arcan_themepath, 
			arcan_themename, label);
	}

	return strdup( strip_traverse(playbuf) );
}

char* arcan_find_resource_path(const char* label, const char* path, 
	int searchmask)
{
	if (label == NULL)
		return NULL;

	char playbuf[4096];
	playbuf[4095] = '\0';

	if (searchmask & ARCAN_RESOURCE_THEME) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s/%s", arcan_themepath, 
			arcan_themename, path, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);
	}

	if (searchmask & ARCAN_RESOURCE_SHARED) {
		snprintf(playbuf, sizeof(playbuf) - 1, "%s/%s/%s", 
			arcan_resourcepath, path, label);
		strip_traverse(playbuf);

		if (file_exists(playbuf))
			return strdup(playbuf);

	}

	return NULL;
}

const char* internal_launch_support()
{
	return "PARTIAL SUPPORT";
}

bool arcan_setpaths()
{
/* could add a check of the users path cleanup 
(that turned out to be a worse mess than before)
 * with AppData etc. from Vista and friends */
	if (!arcan_resourcepath)
		arcan_resourcepath = strdup("./resources");

	arcan_libpath = NULL;

	if (!arcan_themepath)
		arcan_themepath = strdup("./themes");

	if (!arcan_binpath)
		arcan_binpath = strdup("./arcan_frameserver");

	return true;
}


