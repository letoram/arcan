#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <strings.h>

#include "../platform.h"

static uintptr_t token = 0xdeadbabe;

static bool lookup(const char* const key,
	unsigned short ind, char** val, uintptr_t tag)
{
	if (tag != token || ind > 0){
		if (val)
			*val = NULL;
		return false;
	}

/*
 * missing: map to arcan_db with some fallback to ARCAN_xxx env
 */
	return false;
}

cfg_lookup_fun platform_config_lookup(uintptr_t* tag)
{
	if (!tag)
		return NULL;

	*tag = token;
	return lookup;
}
