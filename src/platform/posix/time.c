/* public domain, no copyright claimed */

#include <stdlib.h>
#include <errno.h>
#include <assert.h>
#include <time.h>
#include <math.h>
#include <unistd.h>

#include <stdint.h>
#include <stdbool.h>

#ifdef __OpenBSD__
#include <sys/types.h>
#include <sys/sysctl.h>
#endif

#include "../platform_types.h"

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

struct platform_timing platform_hardware_clockcfg()
{
#ifdef __OpenBSD__
	int mib[2] = {CTL_KERN, KERN_CLOCKRATE};
	struct clockinfo cinf;
	size_t len = sizeof(struct clockinfo);
	if (sysctl(mib, 2, &cinf, &len, NULL, 0) != -1){
		return (struct platform_timing){
			.cost_us = cinf.tick,
			.tickless = false
		};
	}
	else {
		return (struct platform_timing){
			.cost_us = 10 * 1000,
			.tickless = false
		};
	}
#else
	return (struct platform_timing){
		.cost_us = 0,
		.tickless = true
	};
#endif
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
