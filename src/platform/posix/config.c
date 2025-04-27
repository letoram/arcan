#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>
#include <ctype.h>
#include "../platform.h"
#include "../../common/arcan_str.h"

#ifdef WITH_ARCAN_DB
#include "../../engine/arcan_db.h"
#endif

#ifndef MIN
#define MIN(a, b) a < b ? a : b
#endif

extern char **environ;

static uintptr_t token = 0xdeadbabe;

static bool lookup(const char* const pattern,
	unsigned short ind, char** val, uintptr_t tag)
{
	if (!pattern || tag != token){
		if (val)
			*val = NULL;
		return false;
	}

	char tmpbuf[strlen(pattern) + sizeof("ARCAN_") + sizeof("65536_")];
	snprintf(tmpbuf, sizeof(tmpbuf), "ARCAN_%s", pattern);

	bool is_glob = strchr(pattern, '%');
	if (is_glob){
		arcan_str pat = arcan_str_fromcstr(pattern);

		char** var = environ;
		while(*var){
			arcan_str envvar = arcan_str_fromcstr(*var);
			arcan_str envkey;
			arcan_strtok(envvar, &envkey, '=');
			if (!arcan_strvalid(envkey)) continue;
			if (!arcan_strglobmatch(envkey, pat, '%')) continue;

			arcan_str envval = envkey;
			arcan_strtok(envvar, &envval, '=');
			if (!arcan_strvalid(envval)) continue;

			*val = strdup(envval.ptr);
			return true;
		}
	}
	else{
		char* tmp = tmpbuf;
		while(*tmp){
			*tmp = toupper(*tmp);
			tmp++;
		}

		char* test = getenv(tmpbuf);
		if (test && val){
			*val = strdup(test);
			return true;
		}
	}

#ifdef WITH_ARCAN_DB
/* fallback to database- config in arcan appl- space */
	const char* appl;
	struct arcan_dbh* dbh = arcan_db_get_shared(&appl);
	if (ind > 0)
		snprintf(tmpbuf, sizeof(tmpbuf), "%s_%"PRIu16, pattern, ind);
	else
		snprintf(tmpbuf, sizeof(tmpbuf), "%s", pattern);
	char* test = arcan_db_appl_val(dbh, appl, tmpbuf);
	if (test && val){
		*val = test;
	}
	else
		arcan_mem_free(test);
#endif

	return NULL;
}

arcan_cfg_lookup_fun arcan_platform_config_lookup(uintptr_t* tag)
{
	if (!tag)
		return NULL;

	*tag = token;
	return lookup;
}
