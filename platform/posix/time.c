/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */
#include <stdlib.h>
#include <errno.h>
#include <assert.h>
#include <time.h>
#include <math.h>

#include <stdint.h>
#include <stdbool.h>

long long int arcan_timemillis()
{
	struct timespec tp;
#ifdef CLOCK_SOURCE_RAW
	clock_gettime(CLOCK_MONOTONIC_RAW, &tp);
#else
	clock_gettime(CLOCK_MONOTONIC, &tp);
#endif
/*
	deprecated:
	struct timeval tv;
	gettimeofday(&tv, NULL);
	tp.tv_sec = tp.tv_sec;
	tp.tv_nsec = tv.tv_usec * 1000;
*/

	return (tp.tv_sec * 1000) + (tp.tv_nsec / 1000000);
}

void arcan_timesleep(unsigned long val)
{
	struct timespec req, rem;
	req.tv_sec = floor(val / 1000);
	val -= req.tv_sec * 1000;
	req.tv_nsec = val * 1000000;

	while( nanosleep(&req, &rem) == -1 ){
		assert(errno != EINVAL);
		if (errno == EFAULT)
			break;

/* sweeping EINTR introduces an error rate that can grow large,
 * check if the remaining time is less than a threshold */
		if (errno == EINTR) {
			req = rem;
			if (rem.tv_sec * 1000 + (1 + req.tv_nsec) / 1000000 < 4)
				break;
		}
	}
}
