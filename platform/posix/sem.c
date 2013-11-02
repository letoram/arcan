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
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <sys/types.h>
#include <unistd.h>

#include "../../arcan_math.h"
#include "../../arcan_general.h"

int arcan_sem_post(sem_handle sem)
{
	return sem_post(sem);
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return sem_unlink(key);
}

static int sem_timedwaithack(sem_handle semaphore, int msecs)
{
	if (msecs == 0)
		return sem_trywait( semaphore );

	if (msecs == -1){
		int rv;
		while ( -1 == (rv = sem_wait( semaphore )) && errno == EINTR);
		return rv;
	}

	int rc = -1;
	while ( (rc = sem_trywait(semaphore) != 0) && msecs && errno != EINVAL);

	return rc;
}

int arcan_sem_timedwait(sem_handle semaphore, int msecs)
{
    return sem_timedwaithack(semaphore, msecs);
}
