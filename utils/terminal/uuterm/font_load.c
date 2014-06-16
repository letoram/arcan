#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

#include "ucf.h"

int ucf_load(struct ucf *f, const char *filename)
{
	int fd = open(filename, O_RDONLY);
	unsigned char *map;
	size_t l;
	
	if (fd < 0) return -1;
	map = mmap(0, l=lseek(fd, 0, SEEK_END), PROT_READ, MAP_SHARED, fd, 0);
	close(fd);
	if (map == MAP_FAILED) return -1;
	return ucf_init(f, map, l);
}
