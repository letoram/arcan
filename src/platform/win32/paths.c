/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
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

static char* envvs[] = {
	"ARCAN_APPLPATH",
	"ARCAN_RESOURCEPATH",
	"ARCAN_APPLTEMPPATH",
	"ARCAN_STATEPATH", /* will be ignored */
	"ARCAN_APPLBASEPATH",
	"ARCAN_APPLSTOREPATH",
	"ARCAN_STATEBASEPATH",
	"ARCAN_FONTPATH",
	"ARCAN_BINPATH",
	"ARCAN_LIBPATH",
	"ARCAN_LOGPATH"
};

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

	arcan_softoverride_namespace(respath, RESOURCE_APPL_SHARED);
	arcan_softoverride_namespace(state_dir, RESOURCE_SYS_APPLSTATE);
	arcan_softoverride_namespace(debug_dir, RESOURCE_SYS_DEBUG);
	arcan_softoverride_namespace(font_dir, RESOURCE_SYS_FONT);
	arcan_softoverride_namespace("./", RESOURCE_SYS_BINS);
	arcan_softoverride_namespace("./", RESOURCE_SYS_LIBS);
}

