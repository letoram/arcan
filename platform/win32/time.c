/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

#include <Windows.h>

long long int arcan_timemillis()
{
	static LARGE_INTEGER ticks_pers;
	static LARGE_INTEGER start_ticks;
	static bool seeded = false;

	if (!seeded){
/* seed monotonic timing */
		QueryPerformanceFrequency(&ticks_pers);
		QueryPerformanceCounter(&start_ticks);
        seeded = true;
	}

	LARGE_INTEGER ticksnow;
	QueryPerformanceCounter(&ticksnow);

	ticksnow.QuadPart -= start_ticks.QuadPart;
	ticksnow.QuadPart *= 1000;
	ticksnow.QuadPart /= ticks_pers.QuadPart;

	return ticksnow.QuadPart;
}

void arcan_timesleep(unsigned long val)
{
	static bool sleepSeed = false;
	static bool spinLock = false;

/* try to force sleep timer resolution to 1 ms, should possible
 * be reset upon exit, doubt windows still enforces that though */
	if (sleepSeed == false){
		spinLock = !(timeBeginPeriod(1) == TIMERR_NOERROR);
		sleepSeed = true;
	}

	unsigned long int start = arcan_timemillis();

	while (val > (arcan_timemillis() - start)){
        Sleep( spinLock ? 0 : val );
	}
}
