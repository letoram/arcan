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

/* Structure for keeping track of the context */
typedef struct {
	arcan_frameserver source;
} arcan_launchtarget;

/* kill the process, free resources associated with the
 * launchtarget, vid however will be kept (destroy the video object manually) */
int arcan_target_clean_internal(arcan_launchtarget* tgt);

/* upkeep, check if child is still alive etc. */
void arcan_target_tick_control(arcan_launchtarget* tgt);

/* launch the target as an external process,
 * and wait for the process to finish. */
int arcan_target_launch_external(const char* fname, char** argv);

/* try and pause/unpause the launchtarget,
 * the actual way this is done depends on the hijack lib (just sends
 * a command packet with a request), but resume assume it can be woken up with a 
 * SIGUSR2. Biggest problem might be the time dialation that occurs */
void arcan_target_suspend_internal(arcan_launchtarget* tgt);
void arcan_target_resume_internal(arcan_launchtarget* tgt);


/* launch the target as an internal process,
 * meaning that a ffunc will be hooked up to aid/vids,
 * and a callback can be added that translates events into the space of the child */
arcan_frameserver* arcan_target_launch_internal(const char* fname, char** argv);

#endif
