/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
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
		rv = S_ISREG(buf.st_mode) || S_ISFIFO(buf.st_mode);

	return rv;
}

static char* envvs[] = {
	"ARCAN_APPLPATH",
	"ARCAN_RESOURCEPATH",
	"ARCAN_APPLTEMPPATH",
	"ARCAN_STATEPATH",
	"ARCAN_FONTPATH",
	"ARCAN_BINPATH",
	"ARCAN_LIBPATH",
	"ARCAN_LOGPATH"
};

static char* binpath_unix()
{
	char* binpath = NULL;

	if (arcan_isfile( "./arcan_frameserver") )
		binpath = strdup("./arcan_frameserver" );
	else if (arcan_isfile( "/usr/local/bin/arcan_frameserver"))
		binpath = strdup("/usr/local/bin/arcan_frameserver");
	else if (arcan_isfile( "/usr/bin/arcan_frameserver" ))
		binpath = strdup("/usr/bin/arcan_frameserver");
	else ;

	return binpath;
}

static char* libpath_unix()
{
	char* libpath = NULL;

	if (arcan_isfile( getenv("ARCAN_HIJACK") ) )
		libpath = strdup( getenv("ARCAN_HIJACK") );
	else if (arcan_isfile( "./" LIBNAME ) )
		libpath = realpath( "./", NULL );
	else if (arcan_isfile( "/usr/local/lib/" LIBNAME) )
		libpath = strdup( "/usr/local/lib/");
	else if (arcan_isfile( "/usr/lib/" LIBNAME) )
		libpath = strdup( "/usr/lib/");

	return libpath;
}

static char* unix_find(const char* fname)
{
	char* res = NULL;
	char* pathtbl[] = {
		".",
		NULL, /* fill in with HOME */
		"/usr/local/share/arcan",
		"/usr/share/arcan",
		NULL /* NULL terminates */
	};

	if (getenv("HOME")){
		size_t len = strlen( getenv("HOME") ) + 9;
		pathtbl[1] = malloc(len);
		snprintf(pathtbl[1], len, "%s/.arcan", getenv("HOME") );
	}
	else
		pathtbl[1] = strdup("");

	size_t fn_l = strlen(fname);
	for (char** base = pathtbl; *base != NULL; base++){
		char buf[ fn_l + strlen(*base) + 2 ];
		snprintf(buf, sizeof(buf), "%s/%s", *base, fname);

		if (arcan_isdir(buf)){
			res = strdup(buf);
			break;
		}
	}

	free(pathtbl[1]);
	return res;
}

/*
 * This is set-up to mimic the behavior of previous arcan
 * version as much as possible. For other, more controlled settings,
 * this is a good function to replace.
 */
void arcan_set_namespace_defaults()
{
	arcan_override_namespace(binpath_unix(), RESOURCE_SYS_BINS);
	arcan_override_namespace(libpath_unix(), RESOURCE_SYS_LIBS);

	char* respath = unix_find("resources");
	if (!respath){
		arcan_warning("set_namespace_defaults(): "
			"Couldn't find a suitable 'resources' folder.\n");
	}
 	else {
		size_t len = strlen(respath);
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
	}

	char* scrpath = unix_find("appl");
	if (!scrpath)
		scrpath = unix_find("themes"); /* legacy */

	if (scrpath){
		arcan_override_namespace(scrpath, RESOURCE_APPL);
		arcan_override_namespace(scrpath, RESOURCE_APPL_TEMP);
	}

/*
 * NOTE: nice spot to add configuration file loading
 */

/*
 * use environment variables as overrides (then command-line args
 * can override those in turn)
 */
	for (int i = 0; i < sizeof( envvs ) / sizeof( envvs[0] ); i++){
		const char* tmp = getenv(envvs[i]);
		arcan_override_namespace(tmp, 1 << i);
	}
}
