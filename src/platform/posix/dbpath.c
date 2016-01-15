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

char* platform_dbstore_path()
{
	char* out = NULL;
	char* homedir = getenv("HOME");
	size_t len;

	if (homedir && (len = strlen(homedir))){
		char dirbuf[len + sizeof("/.arcan")];
		snprintf(dirbuf, sizeof(dirbuf), "%s/.arcan", homedir);

/* ensure it exists, ignore EEXIST */
		mkdir(dirbuf, S_IRWXU);
		char fbuf[sizeof(dirbuf) + sizeof("/arcan.sqlite")];
		snprintf(fbuf, sizeof(fbuf), "%s/.arcan/arcan.sqlite", homedir);
		return strdup(fbuf);
	}

	return NULL;
}
