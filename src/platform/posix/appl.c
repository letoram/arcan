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

static size_t appl_len = 0;
static char* g_appl_id = "#app_not_initialized";
static char* appl_script = NULL;

/*
 * This is also planned as an entry point for implementing the
 * APF mapping, possibly with the chainloader setting envvars
 * for how the namespace is made, and if not (.apf extension in appl_id)
 * setup the context and functions required to do data lookups.
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
	char* base = strdup(appl_id);
	bool expand = true;

/*
 * absolute/relative path? don't define namespaces using SYS_*
 * will maintain STATE namespace set by paths. Absolute paths
 * should only be presented from a privileged state (command-line
 * or in-engine, not Lua->engine).
 */
	if (appl_id[0] == '/' || appl_id[0] == '\\' || appl_id[0] == '.'){
		char* work = strdup(base);
		char* dir = strdup( dirname( work ) );
		free(work);

		work = strdup(base);
		base = strdup( basename(work) );
		free(work);

		arcan_override_namespace(appl_id, RESOURCE_APPL);
		arcan_override_namespace(appl_id, RESOURCE_APPL_TEMP);

		arcan_softoverride_namespace(dir, RESOURCE_SYS_APPLBASE);
		arcan_softoverride_namespace(dir, RESOURCE_SYS_APPLSTORE);

		free(dir);
		expand = false;
	}

/*
 * with path stripped, we can make sure to see that we have a proper name
 */
	app_len = strlen(base);
	for (size_t i = 0; i < app_len; i++){
		if (!isalnum(base[i]) && base[i] != '_'){
			*errc = "invalid character in appl_id (only a..Z _ 0..9 allowed)\n";
			return false;
		}
	}

	if (expand){
		char* dir = arcan_expand_resource(base, RESOURCE_SYS_APPLBASE);
		if (!dir){
			*errc = "missing application base\n";
			free(base);
			return false;
		}
		arcan_override_namespace(dir, RESOURCE_APPL);
		arcan_mem_free(dir);

		dir = arcan_expand_resource(base, RESOURCE_SYS_APPLSTORE);
		if (!dir){
			*errc = "missing application temporary store\n";
			free(base);
			return false;
		}
		arcan_override_namespace(dir, RESOURCE_APPL_TEMP);
		arcan_mem_free(dir);
	}

/* state- storage has specific rules so it is always checked for expansion,
 * if STATE is a subpath of shared, we have global application state (i.e.
 * multiple scripts can use the same state storage for virtual machines),
 * otherwise we expand */
	char* p_a = arcan_expand_resource("", RESOURCE_APPL_SHARED);
	char* p_b = arcan_expand_resource("", RESOURCE_SYS_APPLSTATE);
	if (!p_b)
		arcan_override_namespace(p_a, RESOURCE_APPL_STATE);
	else if (strncmp(p_a, p_b, strlen(p_a)) == 0){
		arcan_override_namespace(p_b, RESOURCE_APPL_STATE);
	}
	else {
		arcan_mem_free(p_b);
		p_b = arcan_expand_resource(base, RESOURCE_SYS_APPLSTATE);
		arcan_override_namespace(p_b, RESOURCE_APPL_STATE);
	}
	arcan_mem_free(p_a);
	arcan_mem_free(p_b);

	char wbuf[ app_len + sizeof(".lua")];
	snprintf(wbuf, sizeof(wbuf), "%s.lua", base);

	char* script_path = arcan_expand_resource(wbuf, RESOURCE_APPL);
	if (!script_path || !arcan_isfile(script_path)){
		*errc = "missing script matching appl_id (see appname/appname.lua)";
		arcan_mem_free(script_path);
		return false;
	}

	g_appl_id = base;
	appl_len = app_len;
	appl_script = script_path;

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

