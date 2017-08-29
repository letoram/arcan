/* public domain, no copyright claimed */

#include <stdlib.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stdbool.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <fcntl.h>
#include "../platform.h"

/* yet another sigh for Mac OSX */
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

bool arcan_pushhandle(file_handle source, int channel)
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

	if (-1 == source){
	}
	else {
		msg.msg_control = &msgbuf.buf;
		msg.msg_controllen = sizeof(msgbuf.buf);
		struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
		cmsg->cmsg_len = CMSG_LEN(sizeof(int));
		cmsg->cmsg_level = SOL_SOCKET;
		cmsg->cmsg_type  = SCM_RIGHTS;
		*(int*)CMSG_DATA(cmsg) = source;
		fcntl(source, F_SETFD, FD_CLOEXEC);
	}

	int rv = sendmsg(channel, &msg, MSG_DONTWAIT | MSG_NOSIGNAL);
	return rv >= 0;
}

file_handle arcan_fetchhandle(int sockin_fd, bool block)
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

	if (-1 == recvmsg(sockin_fd, &msg,
		(!block ? MSG_DONTWAIT : 0)| MSG_NOSIGNAL)){
		return -1;
	}

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
