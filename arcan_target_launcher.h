/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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

/* launch the target as an internal process,
 * meaning that a ffunc will be hooked up to aid/vids,
 * and a callback can be added that translates events into the space of the child */
arcan_frameserver* arcan_target_launch_internal(const char* fname, char** argv);

#endif
