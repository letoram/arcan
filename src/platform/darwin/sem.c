/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <sys/types.h>
#include <unistd.h>

#include PLATFORM_HEADER

int arcan_sem_post(sem_handle sem)
{
	return sem_post(sem);
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return sem_unlink(key);
}

int arcan_sem_trywait(sem_handle sem)
{
	return sem_trywait(sem);
}

int arcan_sem_wait(sem_handle sem)
{
	return sem_wait(sem);
}

/*
 * In its infinite wisdom, darwin only supports
 * named semaphores (seriously). We are forced to
 * either rewrite some parts for this, or simulate
 * named through unnamed.
 */
int arcan_sem_init(sem_handle* sem, unsigned val)
{
	char tmpbuf[32];
	int retryc = 10;


	while(retryc--){
		snprintf(tmpbuf, 32, "/arc_dwn_sem_%d", rand());
		*sem = sem_open(tmpbuf, O_CREAT | O_EXCL, 0700, val);

/* note: sem_unlink is distinct from sem_close ;-) */
		sem_unlink(tmpbuf);

		if (SEM_FAILED != *sem){
			return 0;
		}
	}

	return -1;
}

int arcan_sem_destroy(sem_handle sem)
{
	if (!sem)
		return -1;

	int rv = sem_close(sem);
	return rv;
}
