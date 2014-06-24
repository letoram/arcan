/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

/*
 * For POSIX We want a slightly different behavior from realpath et. al,
 * in that symlinks/bindmounts should be accepted, we don't protect against
 * things e.g. themes/a/symlink_to_themes/../aha but just want to discover
 * obvious breaks outside from themes or resources.
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
const char* strip_traverse(const char* input)
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
