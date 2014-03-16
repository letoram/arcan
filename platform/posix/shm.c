/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
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

/*
 * try to allocate a shared memory page and three semaphores (vid / aud / ev)
 * return a pointer to the shared key (this will keep the resources allocated) 
 * or NULL on fail. For semalloc == false, it means that semaphores will be
 * allocated / set / used in some other way (win32 ex. pass handles on cmdline)
 */
#include <sys/mman.h>
char* arcan_findshmkey(int* dfd, bool semalloc){
	int fd = -1;
	pid_t selfpid = getpid();
	int retrycount = 10;
	size_t pb_ofs = 0;

	const char* pattern = "/arcan_%i_%im";
	char playbuf[sizeof(pattern) + 8];

	while (1){
		snprintf(playbuf, sizeof(playbuf), pattern, selfpid % 1000, rand() % 1000);
		pb_ofs = strlen(playbuf) - 1;
		fd = shm_open(playbuf, O_CREAT | O_RDWR | O_EXCL, 0700);

	/* 
	 * with EEXIST, we happened to have a name collision, 
	 * it is unlikely, but may happen. for the others however, 
	 * there is something else going on and there's no point retrying 
	 */
		if (-1 == fd && errno != EEXIST){
			arcan_warning("arcan_findshmkey(), allocating "
				"shared memory, reason: %d\n", errno);
			return NULL;
		}

		if (fd > 0){
			if (!semalloc)
				break;

			playbuf[pb_ofs] = 'v';
			sem_t* vid = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 0);

			if (SEM_FAILED != vid){
				playbuf[pb_ofs] = 'a';

				sem_t* aud = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 0);
				if (SEM_FAILED != aud){

/* note the initial state of the semaphore here: */
					playbuf[pb_ofs] = 'e';
					sem_t* ev = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 1);

					if (SEM_FAILED != ev)
						break;

					playbuf[pb_ofs] = 'a';
					sem_unlink(playbuf);
				}

				playbuf[pb_ofs] = 'v';
				sem_unlink(playbuf);
			}

		/* semaphores couldn't be created, retry */
			shm_unlink(playbuf);
			fd = -1;

			if (retrycount-- == 0){
				arcan_warning("arcan_findshmkey(), allocating named "
				"semaphores failed, reason: %d, aborting.\n", errno);
				return NULL;
			}
		}
	}

	if (dfd)
		*dfd = fd;

	playbuf[pb_ofs] = 'm';
	return strdup(playbuf);
}

