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

static struct {
	union {
		struct {
			char* appl;
			char* shared;
			char* temp;
			char* state;
			char* appbase;
			char* appstore;
			char* statebase;
			char* font;
			char* bins;
			char* libs;
			char* debug;
		};
		char* paths[11];
	};

	int flags[11];
	int lenv[11];

} namespaces = {0};

static const char* lbls[] = {
	"application",
	"application-shared",
	"application-temporary",
	"application-state",
	"system-applbase",
	"system-applstore",
	"system-statebase",
	"system-font",
	"system-binaries",
	"system-libraries(hijack)",
	"system-debugoutput"
};

static unsigned i_log2(uint32_t n)
{
	unsigned res = 0;
	while (n >>= 1) res++;
	return res;
}

char* arcan_find_resource(const char* label,
	enum arcan_namespaces space, enum resource_type ares)
{
	if (label == NULL || verify_traverse(label) == NULL)
		return NULL;

	size_t label_len = strlen(label);

	for (int i = 1, j = 0; i <= RESOURCE_SYS_ENDM; i <<= 1, j++){
		if ((space & i) == 0 || !namespaces.paths[j])
			continue;

		char scratch[ namespaces.lenv[j] + label_len + 2 ];
		snprintf(scratch, sizeof(scratch),
			label[0] == '/' ? "%s%s" : "%s/%s",
			namespaces.paths[j], label
		);

		if (
			((ares & ARES_FILE) && arcan_isfile(scratch)) ||
			((ares & ARES_FOLDER) && arcan_isdir(scratch))
		)
			return strdup(scratch);
	}

	return NULL;
}

char* arcan_fetch_namespace(enum arcan_namespaces space)
{
	int space_ind = i_log2(space);
	assert(space > 0 && (space & (space - 1) ) == 0);
	if (space_ind > sizeof(namespaces.paths)/sizeof(namespaces.paths[0]))
		return NULL;
	return namespaces.paths[space_ind];
}

char* arcan_expand_resource(const char* label, enum arcan_namespaces space)
{
	assert( space > 0 && (space & (space - 1) ) == 0 );
	int space_ind =i_log2(space);
	if (space_ind > sizeof(namespaces.paths)/sizeof(namespaces.paths[0]) ||
		label == NULL || verify_traverse(label) == NULL ||
		!namespaces.paths[space_ind]
	)
		return NULL;

	size_t len_1 = strlen(label);
	size_t len_2 = namespaces.lenv[space_ind];

	if (len_1 == 0)
		return namespaces.paths[space_ind] ?
			strdup( namespaces.paths[space_ind] ) : NULL;

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
		return arcan_find_resource(label, space, ARES_FILE);

	if (len_2 == 0)
		return NULL;

/* append, re-use strlens and null terminate */
	char buf[ len_1 + len_2 + 2 ];
	memcpy(buf, path, len_1);
	buf[len_1] = '/';
	memcpy(&buf[len_1+1], label, len_2 + 1);

/* simply forward */
	char* res = arcan_find_resource(buf, space, ARES_FILE);
	return res;
}

static char* atypestr = NULL;
const char* arcan_frameserver_atypes()
{
	return atypestr ? atypestr : "";
}

bool arcan_verify_namespaces(bool report)
{
	bool working = true;

	if (report)
		arcan_warning("--- Verifying Namespaces: ---\n");

/* 1. check namespace mapping for holes */
	for (int i = 0; i < sizeof(
		namespaces.paths) / sizeof(namespaces.paths[0]); i++){
			if (namespaces.paths[i] == NULL){
				if (i != (int)log2(RESOURCE_SYS_LIBS)){
					working = false;
					if (report)
						arcan_warning("%s -- broken\n", lbls[i]);
					continue;
				}
			}

		if (report)
			arcan_warning("%s -- OK (%s)\n", lbls[i], namespaces.paths[i]);
	}

	if (report)
		arcan_warning("--- Namespace Verification Completed ---\n");

/* 2. missing; check permissions for each mounted space, i.e. we should be able
 * to write to state, we should be able to write to appl temporary etc.  also
 * check disk space for possible warning conditions (these should likely also
 * be emitted as system events)
 */

	if (working){
		char* toktmp = strdup(FRAMESERVER_MODESTRING);

/* modestring is static, atypestr can only be reduced in bytes used */
		if (!atypestr)
			atypestr = strdup(FRAMESERVER_MODESTRING);

		char* tokctx, (* tok) = strtok_r(toktmp, " ", &tokctx);
		if (tok && atypestr){
			char* base = arcan_expand_resource("", RESOURCE_SYS_BINS);
			size_t baselen = strlen(base);

/* fix for specialized "do we have default arcan_frameserver? then compact to
 * afsrv_ for archetype prefix" mode */
			size_t sfxlen = sizeof("arcan_frameserver") - 1;
			if (baselen >= sfxlen){
				if (strcmp(&base[baselen - sfxlen], "arcan_frameserver") == 0){
					const char* sfx = "afsrv";
					memcpy(&base[baselen - sfxlen], sfx, sizeof("afsrv"));
				}
			}

/* could / should do a more rigorous test of the corresponding afsrv, e.g.
 * executable, permission and linked shmif version */
			atypestr[0] = '\0';
			bool first = true;
			do{
				char* fn;
				char exp[2 + baselen + strlen(tok)];
				snprintf(exp, sizeof(exp), "%s_%s", base, tok);
				if (arcan_isfile(exp)){
					if (!first){
						strcat(atypestr, " ");
					}
					strcat(atypestr, tok);
					first = false;
				}
			} while ((tok = strtok_r(NULL, " ", &tokctx)));

			free(base);
		}
		free(toktmp);
	}

	return working;
}

void arcan_softoverride_namespace(const char* new, enum arcan_namespaces space)
{
	char* tmp = arcan_expand_resource("", space);
	if (!tmp)
		arcan_override_namespace(new, space);
	else
		free(tmp);
}

void arcan_pin_namespace(enum arcan_namespaces space)
{
	int ind = i_log2(space);
	namespaces.flags[ind] = 1;
}

void arcan_override_namespace(const char* path, enum arcan_namespaces space)
{
	if (path == NULL)
		return;

	assert( space > 0 && (space & (space - 1) ) == 0 );
	int space_ind =i_log2(space);

	if (namespaces.paths[space_ind] != NULL){
		if (namespaces.flags[space_ind])
			return;

		arcan_mem_free(namespaces.paths[space_ind]);
	}

	namespaces.paths[space_ind] = strdup(path);
	namespaces.lenv[space_ind] = strlen(namespaces.paths[space_ind]);
}

