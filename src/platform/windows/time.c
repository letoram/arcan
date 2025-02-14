#include <windows.h>

long long int arcan_timemillis()
{
    return GetTickCount64();
}

long long int arcan_timemicros()
{
	return arcan_timemillis() * 1000;
}

void arcan_timesleep(unsigned long val)
{
	timeBeginPeriod(1);
	Sleep(val);
	timeEndPeriod(1);
}
