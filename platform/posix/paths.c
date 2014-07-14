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

static struct {
	union {
		struct {
			char* appl;
			char* shared;
			char* temp;
			char* state;
			char* font;
			char* bins;
			char* libs;
			char* debug;
		};
		char* paths[8];
	};

	int lenv[8];

} namespaces = {0};

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

const char* lbls[] = {
		"application",
		"application-shared",
		"application-temporary",
		"application-state",
		"system-font",
		"system-binaries",
		"system-libraries(hijack)",
		"system-debugoutput"
};

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

char* arcan_find_resource(const char* label, enum arcan_namespaces space)
{
	if (label == NULL || verify_traverse(label) == NULL)
		return NULL;

	size_t label_len = strlen(label);

	for (int i = 1, j = 0; i <= RESOURCE_SYS_ENDM; i <<= 1, j++){
		if ((space & i) == 0)
			continue;

		char scratch[ namespaces.lenv[j] + label_len + 2 ];
		snprintf(scratch, sizeof(scratch),
			label[0] == '/' ? "%s%s" : "%s/%s",
			namespaces.paths[j], label
		);

		if (file_exists(scratch))
			return strdup(scratch);
	}

	return NULL;
}

char* arcan_expand_resource(const char* label, enum arcan_namespaces space)
{
	assert( space > 0 && (space & (space - 1) ) == 0 );

	if (label == NULL || verify_traverse(label) == NULL)
		return NULL;

	int space_ind = log2(space);

	size_t len_1 = strlen(label);
	size_t len_2 = namespaces.lenv[space_ind];

	if (len_1 == 0)
		return strdup( namespaces.paths[space_ind] );

	char cbuf[ len_1 + len_2 + 2 ];
	memcpy(cbuf, namespaces.paths[space_ind], len_2);
 	cbuf[len_2] = '/';
	memcpy(&cbuf[len_2 + (label[0] == '/' ? 0 : 1)], label, len_1+1);

	return strdup(cbuf);
}

char* arcan_find_resource_path(const char* label, const char* path,
	enum arcan_namespaces space)
{
	if (label == NULL || path == NULL ||
		verify_traverse(path) == NULL || verify_traverse(label) == NULL)
			return NULL;

/* combine the two strings, add / delimiter if necessary and forward */
	size_t len_1 = strlen(path);
	size_t len_2 = strlen(label);

	if (len_1 == 0)
		return arcan_find_resource(label, space);

	if (len_2 == 0)
		return NULL;

/* append, re-use strlens and null terminate */
	char buf[ len_1 + len_2 + 2 ];
	memcpy(buf, path, len_1);
	buf[len_1] = '/';
	memcpy(&buf[len_1+1], label, len_2 + 1);

/* simply forward */
	char* res = arcan_find_resource(buf, space);
	return res;
}

bool arcan_verify_namespaces(bool report)
{
	bool working = true;

#ifdef _DEBUG
	arcan_warning("--- Verifying Namespaces: ---\n");
#endif

/* 1. check namespace mapping for holes */
	for (int i = 0; i < sizeof(
		namespaces.paths) / sizeof(namespaces.paths[0]); i++){
			if (namespaces.paths[i] == NULL){
				if (working && report){
					arcan_warning("--- Broken Namespaces detected: ---\n");
				}
				if (report)
					arcan_warning("%s missing (env-var: %s).\n", lbls[i], envvs[i]);
				working = false;
		}
		else{
#ifdef _DEBUG
			arcan_warning("%s OK (%s)\n", lbls[i], namespaces.paths[i]);
#endif
		}
	}

#ifdef _DEBUG
	arcan_warning("--- Namespace Verification Completed ---\n");
#endif
/* 2. missing; check permissions for each mounted space */

	return working;
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
	if (appl_id[0] == '/' || appl_id[0] == '.'){
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
			arcan_warning("switch app, invalid character in %s\n", appl_id);
			return false;
		}
	}

	char* subpath = arcan_expand_resource(appl_id, RESOURCE_APPL);
	size_t s_ofs = strlen(subpath);
	char wbuf[ s_ofs + sizeof("/.lua") + app_len + 1];

	snprintf(wbuf, sizeof(wbuf), "%s/%s.lua", subpath, appl_id);
	if (!file_exists(wbuf)){
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

void arcan_override_namespace(const char* path, enum arcan_namespaces space)
{
	if (path == NULL)
		return;

	assert( space > 0 && (space & (space - 1) ) == 0 );
	int space_ind = log2(space);

	if (namespaces.paths[space_ind] != NULL){
		arcan_mem_free(namespaces.paths[space_ind]);
	}

	namespaces.paths[space_ind] = strdup(path);
	namespaces.lenv[space_ind] = strlen(namespaces.paths[space_ind]);
}

static char* binpath_unix()
{
	char* binpath = NULL;

	if (file_exists( "./arcan_frameserver") )
		binpath = strdup("./arcan_frameserver" );
	else if (file_exists( "/usr/local/bin/arcan_frameserver"))
		binpath = strdup("/usr/local/bin/arcan_frameserver");
	else if (file_exists( "/usr/bin/arcan_frameserver" ))
		binpath = strdup("/usr/bin/arcan_frameserver");
	else ;

	return binpath;
}

static char* libpath_unix()
{
	char* libpath = NULL;

	if (file_exists( getenv("ARCAN_HIJACK") ) )
		libpath = strdup( getenv("ARCAN_HIJACK") );
	else if (file_exists( "./" LIBNAME ) )
		libpath = realpath( "./", NULL );
	else if (file_exists( "/usr/local/lib/" LIBNAME) )
		libpath = strdup( "/usr/local/lib/");
	else if (file_exists( "/usr/lib/" LIBNAME) )
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

		if (is_dir(buf)){
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
		const char* tmp = getenv(lbls[i]);
		arcan_override_namespace(tmp, 1 << i);
	}
}

size_t arcan_appl_id_len()
{
	return appl_len;
}

