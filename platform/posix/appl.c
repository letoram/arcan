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

static bool appl_ready = false;
static size_t appl_len = 0;
static char* g_appl_id = "#app_not_initialized";
static char* appl_script = NULL;

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
	if (!subpath)
		return false;

	size_t s_ofs = strlen(subpath);
	char wbuf[ s_ofs + sizeof("/.lua") + app_len + 1];

	snprintf(wbuf, sizeof(wbuf), "%s/%s.lua", subpath, appl_id);
	if (!arcan_isfile(wbuf)){
		*errc = "missing script matching appl_id (see appname/appname.lua)";
		free(subpath);
		return false;
	}

	if (getenv("ARCAN_APPLTEMPPATH")){
		arcan_override_namespace(getenv("ARCAN_APPLTEMPPATH"), RESOURCE_APPL_TEMP);
		if (appl_ready)
			arcan_warning("switching applications with an env- "
				"appl_temp path override in place forces two "
				"applications to share temporary namespace ");
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

size_t arcan_appl_id_len()
{
	return appl_len;
}

