#ifndef HAVE_A12_PLATFORM
#define HAVE_A12_PLATFORM

#include <sys/types.h>
#include <stdbool.h>

#define A12INT_PROT_READ 0x1
#define A12INT_PROT_WRITE 0x2
#define A12INT_PROT_EXEC 0x4
#define A12INT_PROT_NONE 0x0

#define A12INT_MAP_SHARED 0x01
#define A12INT_MAP_PRIVATE 0x02

void* a12int_mmap(void* addr, size_t len, int prot, int flags, int fildes, off_t off);

int a12int_munmap(void* addr, size_t len);

int a12int_dupfd(int fd);

#endif
