#include <arcan_shmif.h>
#include <pthread.h>
#include "platform/shmif_platform.h"
#include <errno.h>
#include <sys/stat.h>

static bool write_buffer(int fd, char* inbuf, size_t inbuf_sz)
{
	while(inbuf_sz){
		ssize_t nr = write(fd, inbuf, inbuf_sz);
		if (-1 == nr){
			if (errno == EAGAIN || errno == EINTR)
				continue;
			return false;
		}
		inbuf += nr;
		inbuf_sz -= nr;
	}
	return true;
}

static void* copy_thread(void* inarg)
{
	int* fds = inarg;
	char inbuf[4096];
	int8_t sc = 0;

	size_t tot = 0;
	size_t acc = 0;
	size_t last_acc = 0;
	uint64_t time_last = arcan_timemillis();
	static const size_t report_mb = 10;

	struct stat fs;

/* might not remain accurate but fair to keep around, slightly more
 * diligent is re-stating on boundary invalidation (st_size < acc) */
	if (-1 != fstat(fds[0], &fs) && fs.st_size > 0){
		tot = fs.st_size;
	}

/* depending on type and OS, there are a number of options e.g. sendfile,
 * splice, sosplice, ... right now just use a slow/safe */
	for(;;){
		ssize_t nr = read(fds[0], inbuf, sizeof(inbuf));
		if (-1 == nr){
			if (errno == EAGAIN || errno == EINTR)
				continue;
			sc = -1;
			break;
		}
		if (0 == nr){
			break;
		}
		else if (!write_buffer(fds[1], inbuf, nr)){
			sc = -2;
			break;
		}

/* PIPE_BUF is required to be >= 512 on POSIX, only update every n megabytes or
 * every second or so as to not block unnecessarily on reporting while still
 * being responsive. */
		if (fds[3] & SHMIF_BGCOPY_PROGRESS){
			acc += nr;

			if (acc - last_acc > report_mb * 1024 * 1024 ||
				arcan_timemillis() - time_last > 1000){

				time_last = arcan_timemillis();
				int n = snprintf(inbuf,
					sizeof(inbuf), "%zu:%zu:%zu\n", (size_t) nr, acc, tot);
				write(fds[2], inbuf, n);
			}
		}
	}

	if (!(fds[3] & SHMIF_BGCOPY_KEEPIN))
		close(fds[0]);
	if (!(fds[3] & SHMIF_BGCOPY_KEEPOUT))
		close(fds[1]);

	if (-1 != fds[2]){
		if (fds[3] & SHMIF_BGCOPY_PROGRESS){
			int n = snprintf(inbuf, sizeof(inbuf), "%d:%zu:%zu\n", sc, acc, tot);
			while (-1 == write(fds[2], inbuf, n) &&
				(errno == EAGAIN || errno == EINTR)){}
		}
		else
			while (-1 == write(fds[2], &sc, 1) &&
				(errno == EAGAIN || errno == EINTR)){}

		close(fds[2]);
	}

	free(fds);
	return NULL;
}

void arcan_shmif_bgcopy(
	struct arcan_shmif_cont* c, int fdin, int fdout, int sigfd, int fl)
{
	int* fds = malloc(sizeof(int) * 4);
	if (!fds)
		return;

	fds[0] = fdin;
	fds[1] = fdout;
	fds[2] = sigfd;
	fds[3] = fl;

/* options, fork or thread */
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

	if (-1 == pthread_create(&pth, &pthattr, copy_thread, fds)){
		if (!(fl & SHMIF_BGCOPY_KEEPIN))
			close(fdin);
		if (!(fl & SHMIF_BGCOPY_KEEPOUT))
			close(fdout);
		if (-1 != sigfd){
			int8_t ch = -3;
			write(sigfd, &ch, 1);
		}
		free(fds);
	}
}

/*
 * Missing: special behavior for SHMIF_RHINT_SUBREGION_CHAIN, setup chain of
 * atomic [uint32_t, bitfl] and walk from first position to last free. Bitfl
 * marks both the server side "I know this" and client side "synch this or
 * wait".
 *
 * If there's not enough store left to walk on, signal video and wait (unless
 * noblock flag is set)
 */

#ifdef __LINUX
char* arcan_shmif_bchunk_resolve(
	struct arcan_shmif_cont* C, struct arcan_event* bev)
{
	char buf[24];
	if (bev->category != EVENT_TARGET ||
		(bev->tgt.kind != TARGET_COMMAND_BCHUNK_IN &&
		 bev->tgt.kind != TARGET_COMMAND_BCHUNK_OUT))
		return NULL;

	char* mbuf = malloc(PATH_MAX);
	if (!mbuf)
		return mbuf;

	snprintf(buf, sizeof(buf), "/proc/self/fd/%d", bev->tgt.ioevs[0].iv);
	ssize_t rv = readlink(buf, mbuf, PATH_MAX);

	if (-1 == rv || mbuf[0] != '/')
		return NULL;

	struct stat base, comp;
	if (-1 == fstat(bev->tgt.ioevs[0].iv, &base) ||
			-1 == stat(mbuf, &comp) || base.st_ino != comp.st_ino){
		free(mbuf);
		return NULL;
	}

	return mbuf;
}
/* OpenBSD has no solution, FreeBSD / OSX has a fcntl that can be used */
#else
char* arcan_shmif_bchunk_resolve(
	struct arcan_shmif_cont* C, struct arcan_event* bev)
{
	return NULL;
}
#endif
