/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
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
