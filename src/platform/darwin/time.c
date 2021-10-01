/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <errno.h>
#include <assert.h>
#include <sys/time.h>
#include <time.h>
#include <stdbool.h>
#include <math.h>

#include "../platform_types.h"

#include <mach/mach_time.h>

#include <stdint.h>
#include <stdbool.h>

unsigned long long int arcan_timemillis()
{
	uint64_t time = mach_absolute_time();
	static double sf;

	if (!sf){
		mach_timebase_info_data_t info;
		kern_return_t ret = mach_timebase_info(&info);
		if (ret == 0)
			sf = (double)info.numer / (double)info.denom;
		else{
			sf = 1.0;
		}
	}
	return ( (double)time * sf) / 1000000;
}

unsigned long long int arcan_timemicros()
{
	uint64_t time = mach_absolute_time();
	static double sf;

	if (!sf){
		mach_timebase_info_data_t info;
		kern_return_t ret = mach_timebase_info(&info);
		if (ret == 0)
			sf = (double)info.numer / (double)info.denom;
		else{
			sf = 1.0;
		}
	}
	return ( (double)time * sf) / 1000;
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

struct platform_timing platform_hardware_clockcfg()
{
	return (struct platform_timing){
		.cost_us = 0,
		.tickless = true
	};
}
