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

/* try and acquire a lock on the semaphore before mstimeout runs out */
bool frameserver_semcheck(sem_handle semaphore, signed mstimeout);

/* setup a named memory / semaphore mapping with the server */
struct frameserver_shmcont{
	struct frameserver_shmpage* addr;
	sem_handle vsem;
	sem_handle asem;
	sem_handle esem;
};

/* to get rid of a few POSIX calls in libretro implementation */
void* frameserver_getrawfile(const char* resource, size_t* ressize);
struct frameserver_shmcont frameserver_getshm(const char* shmkey, unsigned width, unsigned height, unsigned bpp, unsigned nchan, unsigned freq);

#endif
