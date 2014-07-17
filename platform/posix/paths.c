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

static char* envvs[] = {
	"ARCAN_APPLPATH",
	"ARCAN_RESOURCEPATH",
	"ARCAN_APPLPATH",
	"ARCAN_STATEPATH",
	"ARCAN_BINPATH",
	"ARCAN_LIBPATH",
	"ARCAN_FONTPATH",
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

/*
 * This is also planned as an entry point for implementing the
 * APF mapping, possibly with the chainloader setting envvars
 * for how the namespace is made, and if not (.apf extension in appl_id)
 * setup the context and functions required to do data lookups
 */
bool arcan_verifyload_appl(const char* appl_id, const char** errc)
{
	size_t app_len;

	if (!appl_id || (app_len = strlen(appl_id)) == 0){
		*errc = "no application specified";
		return false;
	}

/*
 * NOTE: here is the place to check for .apf extension,
 * and if found, take a separate route for setting up.
 */

/* if we're switching apps, move back to the base directory,
 * then verifyload again */
	if (appl_ready){
		char* dir = arcan_expand_resource("", RESOURCE_APPL);
		size_t len = strlen(dir);
		if (dir[len] == '/')
			dir[len] = '\0';

		char* base = dirname(dir);
		arcan_override_namespace(base, RESOURCE_APPL);
		free(dir);

		appl_ready = false;
		return arcan_verifyload_appl(appl_id, errc);
	}

/* if the user specifies an absolute or relative path,
 * we override the default namespace setting */
	if (appl_id[0] == '/' || appl_id[0] == '.' || strchr(appl_id, '/')){
		char* work = strdup(appl_id);
		char* dir = strdup( dirname(work) );
		free(work);

		work = strdup(appl_id);
		char* base = strdup( basename(work) );
		free(work);

		arcan_override_namespace(dir, RESOURCE_APPL);
		arcan_override_namespace(dir, RESOURCE_APPL_TEMP);
		free(dir);

		bool res = arcan_verifyload_appl(base, errc);
		free(base);

		return res;
	}

	for (int i = 0; i < app_len; i++){
		if (!isalpha(appl_id[i]) && appl_id[i] != '_'){
			*errc = "invalid character in appl_id (only aZ_ allowed)\n";
			return false;
		}
	}

	char* subpath = arcan_expand_resource(appl_id, RESOURCE_APPL);
	size_t s_ofs = strlen(subpath);
	char wbuf[ s_ofs + sizeof("/.lua") + app_len + 1];

	snprintf(wbuf, sizeof(wbuf), "%s/%s.lua", subpath, appl_id);
	if (!arcan_isfile(wbuf)){
		*errc = "missing script matching appl_id (see appname/appname.lua)";
		free(subpath);
		return false;
	}

	arcan_override_namespace(subpath, RESOURCE_APPL);
	free(subpath);

	g_appl_id = strdup(appl_id);
	appl_ready = true;
	appl_len = app_len;
	appl_script = strdup(wbuf);

	return true;
}

const char* arcan_appl_basesource(bool* file)
{
	*file = true;
	return appl_script;
}

const char* arcan_appl_id()
{
	return g_appl_id;
}

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

size_t arcan_appl_id_len()
{
	return appl_len;
}

