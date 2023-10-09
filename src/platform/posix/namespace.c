/*
 * Copyright: Björn Ståhl
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
#include <fcntl.h>

#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_db.h>

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
			char* sysscr;
		};
		char* paths[12];
	};

	int flags[12];
	int lenv[12];

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
	"system-libraries",
	"system-debugoutput",
	"system-scripts"
};
bool arcan_lookup_namespace(const char* id, struct arcan_userns* dst, bool dfd);

static unsigned i_log2(uint32_t n)
{
	unsigned res = 0;
	while (n >>= 1) res++;
	return res;
}

static char* find_ns_user(const char* str, struct arcan_userns* dns)
{
	size_t i = 0;
	bool found = false;

	for (;str[i] && isalnum(str[i]); i++);
	if (str[i] != ':' || str[i+1] != '/'){
		return NULL;
	}

	struct arcan_userns ns = {0};
	if (i > sizeof(ns.name) - 1)
		return NULL;

	memcpy(ns.name, str, i);
	if (!arcan_lookup_namespace(ns.name, &ns, false))
		return NULL;

	size_t path_sz = strlen(&str[i+2]) + sizeof("/") + strlen(ns.path);
	char* res = malloc(path_sz);

	if (!res)
		return NULL;

	if (dns)
		*dns = ns;

	snprintf(res, path_sz, "%s/%s", ns.path, &str[i+2]);
	return res;
}

static char* handle_dynfile(char* base, enum resource_type ares, int* dfd)
{
/* only want to resolve */
	if (!dfd)
		return base;

	int fl = O_CLOEXEC;
	if (ares & ARES_FOLDER)
		fl |= O_DIRECTORY;

	if (ares & ARES_CREATE){
		*dfd = open(base, fl | O_CREAT | O_RDWR | O_EXCL, S_IRWXU);
	}
	else {
		int fl = O_RDWR;
		if (ares & ARES_RDONLY)
			fl = O_RDONLY;
		*dfd = open(base, fl);
	}

	if (-1 == *dfd){
		free(base);
		return NULL;
	}

	return base;
}

char* arcan_find_resource(const char* label,
	enum arcan_namespaces space, enum resource_type ares, int* dfd)
{
	if (dfd)
		*dfd = -1;

	if (label == NULL || verify_traverse(label) == NULL)
		return NULL;

/* user-ns aware applications shouldn't really need this but in order
 * to not miss compat. well it is better to at least provide something */
	if (space & RESOURCE_NS_USER){
		struct arcan_userns ns;
		char* res = find_ns_user(label, &ns);

/* write implies read, but if read-only is set the fs does not have
 * to have write permissions */
		if (res){
			if (ares & ARES_FILE){
				bool read = ares & ARES_RDONLY;

				if ((ns.read && read) || ns.write)
					return handle_dynfile(res, ares, dfd);
			}
			if ((ares & ARES_FOLDER) && arcan_isdir(res))
				return handle_dynfile(res, ares, dfd);

/* other options like sockets, ... are ignored now (the ipc perm) */
			free(res);
			return NULL;
		}
	}

	space &= ~RESOURCE_NS_USER;
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
		){
			return handle_dynfile(strdup(scratch), ares, dfd);
		}
/* this assumes that the write- permission is enforced by the layer making the
 * request, e.g. the matching arcan-lua call as well as by the env. itself (os
 * mount / path setup and permissions) */
		else if (ares & ARES_CREATE){
			return handle_dynfile(strdup(scratch), ares, dfd);
		}
	}

	return NULL;
}

char* arcan_fetch_namespace(enum arcan_namespaces space)
{
	space &= ~RESOURCE_NS_USER;
	int space_ind = i_log2(space);
	assert(space > 0 && (space & (space - 1) ) == 0);
	if (space_ind > sizeof(namespaces.paths)/sizeof(namespaces.paths[0]))
		return NULL;
	return namespaces.paths[space_ind];
}

char* arcan_expand_resource(const char* label, enum arcan_namespaces space)
{
	assert( space > 0 && (space & (space - 1) ) == 0 );
	if (space & RESOURCE_NS_USER){
		return find_ns_user(label, NULL);
	}

	space &= ~RESOURCE_NS_USER;

	int space_ind = i_log2(space);
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
				snprintf(exp, sizeof(exp), "AFSRV_BLOCK_%s", tok);
				if (getenv(exp))
					continue;

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
	space &= ~RESOURCE_NS_USER;
	char* tmp = arcan_expand_resource("", space);
	if (!tmp)
		arcan_override_namespace(new, space);
	else
		free(tmp);
}

void arcan_pin_namespace(enum arcan_namespaces space)
{
	space &= ~RESOURCE_NS_USER;
	int ind = i_log2(space);
	namespaces.flags[ind] = 1;
}

void arcan_override_namespace(const char* path, enum arcan_namespaces space)
{
	if (path == NULL)
		return;

	space &= ~RESOURCE_NS_USER;
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

/* take a properly formatted namespace string (ns_key=label:perm:path)
 * and split up into the arcan_userns structure */
static bool decompose(char* ns, struct arcan_userns* dst)
{
	*dst = (struct arcan_userns){0};
	char* tmp = ns;
	size_t pos = 0;

/* ns_key= comes hard coded from the arcan_db lookup and without it we
 * won't be here so it is safe to assume it exists */
	while (*tmp != '=')
		tmp++;
	*tmp++ = '\0';
	snprintf(dst->name, COUNT_OF(dst->name), "%s", &ns[3]);

	while (tmp){
		char* cur = strsep(&tmp, ":");
		switch(pos){
			case 0:
				snprintf(dst->label, 64, "%s", cur); break;
			case 1:
				if (strchr(cur, 'r'))
					dst->read = true;
				if (strchr(cur, 'w'))
					dst->write = true;
				if (strchr(cur, 'p'))
					dst->ipc = true;
			break;
			case 2:
				snprintf(dst->path, COUNT_OF(dst->path), "%s", cur);
				return true;
			break;
		}
		pos++;
	}

	return false;
}

struct arcan_strarr arcan_user_namespaces()
{
	struct arcan_strarr res = {0};
	struct arcan_strarr ids =
		arcan_db_applkeys(arcan_db_get_shared(NULL), "arcan", "ns_%");

	if (!ids.count){
		arcan_mem_freearr(&ids);
		return res;
	}

	int iind = 0;
	while (ids.data[iind]){
/* make sure that we fit or cancel out */
		if (res.count == res.limit){
			arcan_mem_growarr(&res);
			if (res.count == res.limit)
				break;
		}

/* parse and store in results */
		struct arcan_userns tmp;
		if (decompose(ids.data[iind], &tmp)){
			res.cdata[res.count] =
				arcan_alloc_mem(
					sizeof(struct arcan_userns), ARCAN_MEM_EXTSTRUCT,
					ARCAN_MEM_BZERO | ARCAN_MEM_NONFATAL,
					ARCAN_MEMALIGN_NATURAL
				);
			if (!res.cdata[res.count])
				break;
			*(struct arcan_userns*)(res.cdata[res.count]) = tmp;
			res.count++;
		}
		else
			arcan_warning("bad user-namespace format: %s (label:perm:path)", ids.data[iind]);
		iind++;
	}

	arcan_mem_freearr(&ids);
	return res;
}

bool arcan_lookup_namespace(const char* id, struct arcan_userns* dst, bool dfd)
{
	size_t len = strlen(id) + sizeof("ns_");
	char* buf = malloc(len);
	snprintf(buf, len, "ns_%s", id);

	struct arcan_strarr tbl =
		arcan_db_applkeys(arcan_db_get_shared(NULL), "arcan", buf);
	free(buf);
	bool res = false;

	if (tbl.count == 1){
		res = decompose(tbl.data[0], dst);
	}

	if (dfd && dst->path[0]){
		int dirfd = open(dst->path, O_RDWR, O_DIRECTORY);
		if (-1 == dirfd){
			arcan_mem_freearr(&tbl);
			*dst = (struct arcan_userns){0};
		}
	}

	arcan_mem_freearr(&tbl);
	return res;
}

