#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

/*
 * used with certain session managers
 */
void platform_device_init()
{
}

int platform_device_poll(char** identifier)
{
	return 0;
}

void platform_device_release(const char* const identifier, int ind)
{
}

int platform_device_pollfd()
{
	return -1;
}

int platform_device_open(const char* const identifier, int flags, mode_t mode)
{
	return open(identifier, flags, mode);
}
