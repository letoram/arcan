#include "../a12_platform.h"

#include <stdlib.h>
#include <errno.h>
#include <assert.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>
#include <math.h>

void* a12int_mmap(void* addr, size_t len, int prot, int flags, int fildes, off_t off)
{
	return mmap(addr, len, prot, flags, fildes, off);
}

int a12int_munmap(void* addr, size_t len)
{
	return munmap(addr, len);
}

int a12int_dupfd(int fd)
{
	int fdopt = FD_CLOEXEC;

	int rfd = -1;
	if (-1 == fd)
		return -1;

	while (-1 == (rfd = dup(fd)) && errno == EINTR){}

	if (-1 == rfd)
		return -1;

	int flags = fcntl(rfd, F_GETFD);
	if (-1 != flags && fdopt)
		fcntl(rfd, F_SETFD, flags | fdopt);

	return rfd;
}
