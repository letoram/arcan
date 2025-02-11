#include "../a12_platform.h"
#include <io.h>
#include <errno.h>
#include <windows.h>

void* a12int_mmap(void* addr, size_t len, int prot, int flags, int fildes, off_t off)
{
	DWORD win_flags = 0;
	if (prot != A12INT_PROT_NONE) {
		win_flags |= ((prot & A12INT_PROT_READ) > 0) * FILE_MAP_READ;
		win_flags |= ((prot & A12INT_PROT_WRITE) > 0) * FILE_MAP_WRITE;
		win_flags |= ((prot & A12INT_PROT_EXEC) > 0) * FILE_MAP_EXECUTE;
	}
	win_flags |= ((flags & A12INT_MAP_PRIVATE) > 0) * FILE_MAP_COPY;

	HANDLE handle = (HANDLE)_get_osfhandle(fildes);
	return MapViewOfFile(
		handle,
		win_flags,
		0,
		off,
		len
	);
}

int a12int_munmap(void* addr, size_t len)
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
