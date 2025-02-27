/* public domain, no copyright claimed */
#include <arcan_shmif.h>
#include "shmif_platform.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

/* yet another sigh for Mac OSX */
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

int shmif_platform_mem_from_socket(int fd)
{
	return shmif_platform_fetchfd(fd, true, NULL, NULL);
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
		struct cmsghdr hdr;
		union {
			int fd[1];
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

int shmif_platform_fetchfd(
	int sockin_fd, bool blocking, bool (*alive_check)(void*), void* tag)
{
	if (sockin_fd == -1)
		return -1;

	char empty;

	struct cmsgbuf {
		struct cmsghdr hdr;
		union {
			char buf[CMSG_SPACE(sizeof(int))];
			int fd[1];
		};
	} msgbuf = {.fd[0] = -1};

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
		while (!alive_check || alive_check(tag)){
			if (-1 != recvmsg(sockin_fd, &msg, MSG_NOSIGNAL))
				break;
		}
	}
	else if (-1 == recvmsg(sockin_fd, &msg, MSG_DONTWAIT | MSG_NOSIGNAL))
		return -1;

	int nd = -1;
	struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
	if (cmsg &&
		cmsg->cmsg_len == CMSG_LEN(sizeof(int)) &&
		cmsg->cmsg_level == SOL_SOCKET &&
		cmsg->cmsg_type == SCM_RIGHTS){
		nd = *(int*)CMSG_DATA(cmsg);
		if (-1 != nd)
			fcntl(nd, F_SETFD, FD_CLOEXEC);
	}

	return nd;
}
