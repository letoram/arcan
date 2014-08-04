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
#include <stdio.h>
#include <libgen.h>
#include <string.h>
#include <math.h>
#include <assert.h>
#include <ctype.h>

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <arcan_math.h>
#include <arcan_general.h>

static bool appl_ready = false;
static size_t appl_len = 0;
static char* g_appl_id = "#app_not_initialized";
static char* appl_script = NULL;

bool arcan_isdir(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL)
			return false;

	if (stat(fn, &buf) == 0)
		rv = S_ISDIR(buf.st_mode);

	return rv;
}

bool arcan_isfile(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL)
		return false;

	if (stat(fn, &buf) == 0)
		rv = S_ISREG(buf.st_mode);

	return rv;
}

void arcan_set_namespace_defaults()
{
/* when CWD is correctly set to the installation path */
	char* respath = "./resources";
	size_t len = strlen(respath);

/* typically inside build-directory */	
	if (!arcan_isdir(respath)){
		respath = "../resources";
	}

	char debug_dir[ len + sizeof("/logs") ];
	char state_dir[ len + sizeof("/savestates") ];
	char font_dir[ len + sizeof("/fonts") ];

	snprintf(debug_dir, sizeof(debug_dir), "%s/logs", respath);
	snprintf(state_dir, sizeof(state_dir), "%s/savestates", respath);
	snprintf(font_dir, sizeof(font_dir), "%s/fonts", respath);

	arcan_override_namespace(respath, RESOURCE_APPL_SHARED);
	arcan_override_namespace(debug_dir, RESOURCE_SYS_DEBUG);
	arcan_override_namespace(state_dir, RESOURCE_APPL_STATE);
	arcan_override_namespace(font_dir, RESOURCE_SYS_FONT);

/* makes no sense on windows currently */
	arcan_override_namespace("./", RESOURCE_SYS_BINS);
	arcan_override_namespace("./", RESOURCE_SYS_LIBS);
}

