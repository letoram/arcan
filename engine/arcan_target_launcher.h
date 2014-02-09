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

#ifndef _HAVE_ARCAN_TARGET_LAUNCHER
#define _HAVE_ARCAN_TARGET_LAUNCHER

/* launch the target as an external process,
 * and wait for the process to finish. */
int arcan_target_launch_external(const char* fname, char** argv);

/* fork and exec 'fname' "internally" (with a preloaded library, mapped to a frameserver)
 * hijack points to the hijack-lib to use, default is arcan_libpath, but some targets may override this)
 * argv is a NULL terminated array of strings to the arguments of the program
 */
arcan_frameserver* arcan_target_launch_internal(const char* fname, char* hijack, char** argv);

#endif
