#ifndef HAVE_A12_PLATFORM
#define HAVE_A12_PLATFORM

#include <sys/types.h>
#include <stdbool.h>

#define PROT_READ 0x1
#define PROT_WRITE 0x2
#define PROT_EXEC 0x4
#define PROT_NONE 0x0

#define MAP_SHARED 0x01
#define MAP_PRIVATE 0x02

#define MAP_FILE 0

void* mmap(void* addr, size_t len, int prot, int flags, int fildes, off_t off);

int munmap(void* addr, size_t len);

int a12int_dupfd(int fd);

#endif
