#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <pthread.h>
#include <errno.h>
#include "../platform.h"

struct thread_data {
	int fd;
	int pipeout;
	size_t block_sz;
	void* tag;
	uint8_t* buf;
	bool allow_short;
	bool (*callback)(int, uint8_t*, size_t, void*);
};

static void* iothread(void* tag)
{
	struct thread_data* thd = tag;
	size_t ofs = 0;

	for(;;){

/* with short read, just pass whatever comes through */
		if (thd->allow_short){
			ssize_t nr = read(thd->fd, thd->buf, thd->block_sz);
			if (-1 == nr){
				if (errno != EAGAIN && errno != EINTR){
					thd->callback(-1, NULL, 0, thd->tag);
					break;
				}
			}
			if (nr > 0){
				if (!thd->callback(thd->pipeout, thd->buf, nr, thd->tag)){
					break;
				}
			}
			continue;
		}

/* otherwise we need to buffer and emit when we reach the size */
		size_t ntr = thd->block_sz - ofs;
		ssize_t nr = read(thd->fd, &thd->buf[ofs], ntr);
		if (-1 == nr){
			if (errno != EAGAIN && errno != EINTR){
			}
		}
		ofs += nr;
		if (ofs == thd->block_sz){
			if (!thd->callback(thd->pipeout, thd->buf, thd->block_sz, thd->tag))
				break;
			ofs = 0;
		}
	}

	close(thd->fd);
	close(thd->pipeout);
	free(thd->buf);
	return NULL;
}

int platform_producer_thread(int infd,
	size_t block_sz, bool(*callback)(int, uint8_t*, size_t, void*), void* tag)
{
	struct thread_data* thd = malloc(sizeof(struct thread_data));
	if (!thd)
		return -1;

	int pp[2];
	if (pipe(pp) == -1){
		free(thd);
		return -1;
	}

/* make all non-blocking, but the read end should also be nonblock */
	int flags = fcntl(pp[0], F_GETFD);
	if (-1 != flags)
		fcntl(pp[0], F_SETFD, flags | FD_CLOEXEC);

	flags = fcntl(pp[1], F_GETFD);
	if (-1 != flags)
		fcntl(pp[1], F_SETFD, flags | FD_CLOEXEC);

	flags = fcntl(pp[0], F_GETFL);
	if (-1 != flags)
		fcntl(pp[0], F_SETFL, flags | O_NONBLOCK);

/* if the caller wants a fixed block size, provide that, otherwise we will just
 * match against a small buffer size and let the callback do the buffering */
	size_t buf_sz = 4096;
	bool allow_short = true;

	if (block_sz){
		buf_sz = block_sz;
		allow_short = false;
	}

	thd->buf = malloc(buf_sz);
	if (!thd->buf){
		free(thd);
		close(pp[0]);
		close(pp[1]);
		return -1;
	}

	*thd = (struct thread_data){
		.fd = infd,
		.block_sz = buf_sz,
		.allow_short = allow_short,
		.tag = tag,
		.pipeout = pp[1],
		.callback = callback
	};

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

	if (-1 == pthread_create(&pth, &pthattr, iothread, thd)){
		free(thd);
		close(pp[0]);
		close(pp[1]);
		return -1;
	}

	return pp[0];
}
