/* public domain, no copyright claimed */

#include <stdlib.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
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
		int fd[1];
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
		.msg_control = &msgbuf,
		.msg_controllen = CMSG_LEN(sizeof(int))
	};

	struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
	cmsg->cmsg_len = msg.msg_controllen;
	cmsg->cmsg_level = SOL_SOCKET;
	cmsg->cmsg_type  = SCM_RIGHTS;
	int* dptr = (int*) CMSG_DATA(cmsg);
	*dptr = source;

	return sendmsg(channel, &msg, MSG_DONTWAIT | MSG_NOSIGNAL) >= 0;
}

file_handle arcan_fetchhandle(int sockin_fd)
{
	int rv = -1;

/* some would call this black magic. They'd be right. */
	if (sockin_fd != -1){
		char empty;

		struct cmsgbuf {
			struct cmsghdr hdr;
			int fd[1];
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
			.msg_control = &msgbuf,
			.msg_controllen = sizeof(struct cmsghdr) + sizeof(int)
		};

		struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
		cmsg->cmsg_len = msg.msg_controllen;
		cmsg->cmsg_level = SOL_SOCKET;
		cmsg->cmsg_type  = SCM_RIGHTS;
		int* dfd = (int*) CMSG_DATA(cmsg);
		*dfd = -1;

		if (recvmsg(sockin_fd, &msg, MSG_DONTWAIT | MSG_NOSIGNAL) >= 0)
			rv = msgbuf.fd[0];
	}

	return rv;
}
