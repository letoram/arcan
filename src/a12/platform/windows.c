#include "../a12_platform.h"
#include <arcan_shmif.h>
#include <io.h>
//#include <fcntl.h>
#include <errno.h>
#include <windows.h>

void* mmap(void* addr, size_t len, int prot, int flags, int fildes, off_t off)
{
	DWORD win_flags = 0;
	if (prot != PROT_NONE) {
		win_flags |= ((prot & PROT_READ) > 0) * FILE_MAP_READ;
		win_flags |= ((prot & PROT_WRITE) > 0) * FILE_MAP_WRITE;
		win_flags |= ((prot & PROT_EXEC) > 0) * FILE_MAP_EXECUTE;
	}
	win_flags |= ((flags & MAP_PRIVATE) > 0) * FILE_MAP_COPY;

	HANDLE handle = (HANDLE)_get_osfhandle(fildes);
	return MapViewOfFile(
		handle,
		win_flags,
		0,
		off,
		len
	);
}

int munmap(void* addr, size_t len)
{
	if (UnmapViewOfFile(addr)) return 0;
	errno = EINVAL;
	return -1;
}

int a12int_dupfd(int fd)
{
	int rfd = -1;
	if (-1 == fd)
		return -1;

	HANDLE proc = GetCurrentProcess();
	HANDLE handle = (HANDLE)_get_osfhandle(fd);
	HANDLE new_handle;
	BOOL success = DuplicateHandle(
		proc,
		handle,
		proc,
		&new_handle,
		0,
		FALSE,
		DUPLICATE_SAME_ACCESS
	);

	if (!success)
		return -1;

	rfd = _open_osfhandle((intptr_t)new_handle, 0);

	return rfd;
}

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

bool arcan_shmif_resize_ext(struct arcan_shmif_cont* cont, unsigned width, unsigned height, struct shmif_resize_ext ext)
{
	return 0;
}

bool arcan_shmif_resize(struct arcan_shmif_cont* cont, unsigned width, unsigned height)
{
	return 0;
}

unsigned arcan_shmif_signal(struct arcan_shmif_cont* cont, int x)
{
	return 0;
}
