#include "../a12_platform.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

// Imported as-is from <sys/mman.h>
void* mmap(void* addr, size_t len, int prot, int flags, int fildes, off_t off);
int munmap(void* addr, size_t len);

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
