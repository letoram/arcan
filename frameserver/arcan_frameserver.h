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

#ifndef _HAVE_ARCAN_FRAMESERVER
#define _HAVE_ARCAN_FRAMESERVER

#define LOG(...) ( fprintf(logdev, __VA_ARGS__))

extern FILE* logdev;
extern sem_handle video_sync;
extern sem_handle audio_sync;
extern sem_handle event_sync;

/* clean up any namespace entries used for semaphores / shared memory */
bool frameserver_semcheck(sem_handle semaphore, unsigned mstimeout);
struct frameserver_shmpage* frameserver_getshm(const char* shmkey, unsigned width, unsigned height, unsigned bpp, unsigned nchan, unsigned freq);

#endif
