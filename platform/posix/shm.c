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

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdbool.h>
#include <errno.h>
#include <string.h>

#include <arcan_math.h>
#include <arcan_general.h>

/* try to allocate a shared memory page and two semaphores (vid / aud) is specififed,
 * return a pointer to the shared key (this will keep the resources allocated) or NULL on fail */
#include <sys/mman.h>
char* arcan_findshmkey(int* dfd, bool semalloc){
	int fd = -1;
	pid_t selfpid = getpid();
	int retrycount = 10;

	char playbuf[4096];
	playbuf[4095] = '\0';

	while (1){
		snprintf(playbuf, sizeof(playbuf) - 1, "/arcan_%i_%im", selfpid, rand());
		fd = shm_open(playbuf, O_CREAT | O_RDWR | O_EXCL, 0700);

	/* with EEXIST, we happened to have a name collision, it is unlikely, but may happen.
	 * for the others however, there is something else going on and there's no point retrying */
		if (-1 == fd && errno != EEXIST){
			arcan_warning("arcan_findshmkey(), allocating shared memory, reason: %d\n", errno);
			return NULL;
		}

		if (fd > 0){
			if (!semalloc)
				break;

			char* work = strdup(playbuf);
			work[strlen(work) - 1] = 'v';
			sem_t* vid = sem_open(work, O_CREAT | O_EXCL, 0700, 1);

			if (SEM_FAILED != vid){
				work[strlen(work) - 1] = 'a';

				sem_t* aud = sem_open(work, O_CREAT | O_EXCL, 0700, 1);
				if (SEM_FAILED != aud){

					work[strlen(work) -1] = 'e';
					sem_t* ev = sem_open(work, O_CREAT | O_EXCL, 0700, 1);

					if (SEM_FAILED != ev){
						free(work);
						break;
					}

					work[strlen(work) -1] = 'a';
					sem_unlink(work);
				}

				work[strlen(work) - 1] = 'v';
				sem_unlink(work);
			}

		/* semaphores couldn't be created, retry */
			shm_unlink(playbuf);
			fd = -1;
			free(work);

			if (retrycount-- == 0){
				arcan_warning("arcan_findshmkey(), allocating named semaphores failed, reason: %d, aborting.\n", errno);
				return NULL;
			}
		}
	}

	if (dfd)
		*dfd = fd;

	return strdup(playbuf);
}

