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

int platform_device_open(const char* const identifier, int flags, mode_t mode)
{
	return open(identifier, flags, mode);
}
