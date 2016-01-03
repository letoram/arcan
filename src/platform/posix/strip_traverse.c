/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * For POSIX We want a slightly different behavior from realpath et. al,
 * in that symlinks/bindmounts should be accepted, we don't protect against
 * things e.g. appl/a/symlink_to_appl/../aha but just want to discover
 * obvious breaks outside from appl or resources.
 *
 *
 * we do this just by sweeping the string, calculate the current "level"
 * a/, /a/ increment
 * ../     decrement
 * ./      retain
 * and return NULL as soon as level goes below 0
 */
#include <stdlib.h>
extern void arcan_warning(const char* msg, ...);
const char* verify_traverse(const char* input)
{
	int level = 0;
	int gotch = 0;
	int dc    = 0;

	if (!input)
		return NULL;

	while (*input){
		if (*input == '.'){
			dc++;
		}
		else if (*input == '/'){
			if (dc == 2 && gotch == 0){
				level--;
				if (level < 0)
					goto error;
			}
			else if (gotch > 0){
				level++;
			}

			gotch = dc = 0;
		}
		else
			gotch++;

		input++;
	}

	if (dc == 2 && gotch == 0 && level == 0){
error:
		arcan_warning("resource (%s) blocked, traversal outside root\n", input);
		return NULL;
	}

	return input;
}
