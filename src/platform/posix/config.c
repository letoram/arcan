#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>
#include <strings.h>
#include <ctype.h>
#include "../platform.h"
#include "../../engine/arcan_math.h"
#include "../../engine/arcan_general.h"
#include "../../engine/arcan_db.h"

static uintptr_t token = 0xdeadbabe;

static bool lookup(const char* const key,
	unsigned short ind, char** val, uintptr_t tag)
{
	if (!key || tag != token || ind > 0){
		if (val)
			*val = NULL;
		return false;
	}

	char tmpbuf[strlen(key) + sizeof("ARCAN_") + sizeof("65536_")];

	if (ind > 0)
		snprintf(tmpbuf, sizeof(tmpbuf), "ARCAN_%s_%"PRIu16, key, ind);
	else
		snprintf(tmpbuf, sizeof(tmpbuf), "ARCAN_%s", key);
	char* tmp = tmpbuf;
	while(*tmp){
		*tmp = toupper(*tmp);
		tmp++;
	}

	char* test = getenv(tmpbuf);
	if (test && val){
		*val = strdup(test);
	}

/* fallback to database- config in arcan appl- space */
	if (!test){
		const char* appl;
		struct arcan_dbh* dbh = arcan_db_get_shared(&appl);
		if (ind > 0)
			snprintf(tmpbuf, sizeof(tmpbuf), "%s_%"PRIu16, key, ind);
		else
			snprintf(tmpbuf, sizeof(tmpbuf), "%s", key);
		test = arcan_db_appl_val(dbh, appl, tmpbuf);
		if (test && val){
			*val = test;
		}
		else
			arcan_mem_free(test);
	}

	return test != NULL;
}

cfg_lookup_fun platform_config_lookup(uintptr_t* tag)
{
	if (!tag)
		return NULL;

	*tag = token;
	return lookup;
}
