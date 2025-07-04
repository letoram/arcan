/* public domain, no copyright claimed */
#include <arcan_shmif.h>
#include "shmif_platform.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

/* yet another sigh for Mac OSX */
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

int shmif_platform_mem_from_socket(int fd)
{
	int dfd;
	shmif_platform_fetchfds(fd, &dfd, 1, true, NULL, NULL);
	return dfd;
}

int shmif_platform_dupfd_to(int fd, int dstnum, int fflags, int fdopt)
{
	int rfd = -1;
	if (-1 == fd)
		return -1;

	if (dstnum >= 0)
		while (-1 == (rfd = dup2(fd, dstnum)) && errno == EINTR){}

	if (-1 == rfd)
		while (-1 == (rfd = dup(fd)) && errno == EINTR){}

	if (-1 == rfd)
		return -1;

/* unless F_SETLKW, EINTR is not an issue */
	int flags;
	flags = fcntl(rfd, F_GETFL);
	if (-1 != flags && fflags)
		fcntl(rfd, F_SETFL, flags | fflags);

	flags = fcntl(rfd, F_GETFD);
	if (-1 != flags && fdopt)
		fcntl(rfd, F_SETFD, flags | fdopt);

	return rfd;
}

bool shmif_platform_pushfd(int fd, int sockout)
{
	char empty = '!';

	struct cmsgbuf {
		union {
			struct cmsghdr hdr;
			char buf[CMSG_SPACE(sizeof(int))];
		};
	} msgbuf;

	struct iovec nothing_ptr = {
		.iov_base = &empty,
		.iov_len = 1
	};

	struct msghdr msg = {
		.msg_name = NULL,
		.msg_namelen = 0,
		.msg_iov = &nothing_ptr,
		.msg_iovlen = 1,
		.msg_flags = 0,
	};

	if (-1 == fd){
	}
	else {
		msg.msg_control = &msgbuf.buf;
		msg.msg_controllen = sizeof(msgbuf.buf);
		struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
		cmsg->cmsg_len = CMSG_LEN(sizeof(int));
		cmsg->cmsg_level = SOL_SOCKET;
		cmsg->cmsg_type  = SCM_RIGHTS;
		*(int*)CMSG_DATA(cmsg) = fd;
		fcntl(fd, F_SETFD, FD_CLOEXEC);
	}

	int rv = sendmsg(sockout, &msg, MSG_DONTWAIT | MSG_NOSIGNAL);
	return rv >= 0;
}

int shmif_platform_fetchfds(
	int sockin_fd, int* dfd, size_t nfd,
	bool blocking, bool (*alive_check)(void*), void* tag)
{
	for (size_t i = 0; i < nfd; i++)
		dfd[i] = BADFD;

	if (sockin_fd == BADFD)
		return BADFD;

/* nfd here will be, at most, 4 * 3 * sizeof(int) for transfer of 4-plane image
 * + release and acquire fenceses */

	struct cmsgbuf {
		union {
			struct cmsghdr hdr;
			char buf[CMSG_SPACE(48)];
		};
	} msgbuf;

/* pinged with single character because OSX breaking on 0- iov_len */
	char empty;
	struct iovec nothing_ptr = {
		.iov_base = &empty,
		.iov_len = 1
	};

	struct msghdr msg = {
		.msg_iov = &nothing_ptr,
		.msg_iovlen = 1,
		.msg_control = &msgbuf.buf,
		.msg_controllen = sizeof(msgbuf.buf)
	};

/* spin until we get something over the socket or the aliveness check fails */
	if (blocking){
		for (;;){
			if (-1 != recvmsg(sockin_fd, &msg, MSG_NOSIGNAL | MSG_DONTWAIT))
				break;

/* since the parent can crash / migrate / handover / other operations that
 * would pull the DMS into trigger recovery we can't simply block on recvmsg
 * so resort to a long-ish poll */
			struct pollfd pfd = {.fd = sockin_fd, .events = POLLIN | POLLHUP};
			poll(&pfd, 1, 1000);

			if (alive_check && !alive_check(tag))
				return -1;
		}
	}
	else if (-1 == recvmsg(sockin_fd, &msg, MSG_DONTWAIT | MSG_NOSIGNAL))
		return -1;

	int nd = 0;
	struct cmsghdr* cmsg;
	for (cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL; cmsg = CMSG_NXTHDR(&msg, cmsg)){
		if (cmsg->cmsg_len % sizeof(int) != 0 || cmsg->cmsg_len <= CMSG_LEN(0)){
			debug_print(FATAL, NULL,
				"fetchfds(%zu) - bad cmsg length: %zu\n", nfd, (size_t) cmsg->cmsg_len);
			return -1;
		}

		for (size_t i = 0; i < (cmsg->cmsg_len - CMSG_LEN(0)) / sizeof(int); i++){
			dfd[nd] = ((int*)CMSG_DATA(cmsg))[i];
			fcntl(dfd[nd], F_SETFD, FD_CLOEXEC);
			nd++;
		}
	}

	return nd;
}
