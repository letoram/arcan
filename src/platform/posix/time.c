/* public domain, no copyright claimed */

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
	clock_gettime(CLOCK_MONOTONIC, &tp);
	return (tp.tv_sec * 1000) + (tp.tv_nsec / 1000000);
}

long long int arcan_timemicros()
{
	struct timespec tp;
	clock_gettime(CLOCK_MONOTONIC, &tp);
	return (tp.tv_sec * 1000000) + (tp.tv_nsec / 1000);
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
