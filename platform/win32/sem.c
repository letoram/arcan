/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#include <arcan_math.h>
#include <arcan_general.h>

int arcan_sem_post(sem_handle sem)
{
	return ReleaseSemaphore(sem, 1, 0) == 0 ? -1 : 1;
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return CloseHandle(sem);
}

int arcan_sem_trywait(sem_handle sem)
{
	DWORD rc = WaitForSingleObject(sem, 0);
	int rv = 0;

	switch (rc){
		case WAIT_ABANDONED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_TIMEOUT:
			rv = -1;
			errno = EAGAIN;
		break;

		case WAIT_FAILED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_OBJECT_0:
		break; /* default returnpath */

	default:
		arcan_warning("Warning: arcan_sem_timedwait(win32) "
			"-- unknown result on WaitForSingleObject (%i)\n", rc);
	}

	return rv;
}

int arcan_sem_wait(sem_handle sem)
{
	DWORD rc = WaitForSingleObject(sem, INFINITE);
	int rv = 0;

	switch (rc){
		case WAIT_ABANDONED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_TIMEOUT:
			rv = -1;
			errno = EAGAIN;
		break;

		case WAIT_FAILED:
			rv = -1;
			errno = EINVAL;
		break;

		case WAIT_OBJECT_0:
		break; /* default returnpath */

	default:
		arcan_warning("Warning: arcan_sem_timedwait(win32) "
			"-- unknown result on WaitForSingleObject (%i)\n", rc);
	}

	return rv;
}
