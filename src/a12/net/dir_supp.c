#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <ftw.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <inttypes.h>
#include <stdint.h>
#include <signal.h>

#include "../a12.h"
#include "../a12_int.h"
#include "anet_helper.h"
#include "directory.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>

bool g_shutdown;

void anet_directory_ioloop
	(struct a12_state* S, void* tag,
	int fdin, int fdout,
	int usrfd,
	void (*on_event)(struct arcan_shmif_cont* cont, int chid, struct arcan_event*, void*),
	bool (*on_directory)(struct a12_state* S, struct appl_meta* dir, void*),
	void (*on_userfd)(struct a12_state* S, void*))
{
	int errmask = POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[3] =
	{
		{.fd = usrfd, .events = POLLIN | errmask},
		{.fd = fdin, .events = POLLIN | errmask},
		{.fd = -fdout, .events = POLLOUT | errmask}
	};

	uint8_t inbuf[9000];
	uint8_t* outbuf = NULL;
	uint64_t ts = 0;

	fcntl(fdin, F_SETFD, FD_CLOEXEC);
	fcntl(fdout, F_SETFD, FD_CLOEXEC);

	size_t outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);

	if (outbuf_sz)
		fds[2].fd = fdout;

/* regular simple processing loop, wait for DIRECTORY-LIST command */
	while (a12_ok(S) && -1 != poll(fds, 3, -1)){
		if ((fds[0].revents | fds[1].revents | fds[2].revents) & errmask)
			break;

		if (fds[0].revents & POLLIN){
			on_userfd(S, tag);
		}

		if ((fds[2].revents & POLLOUT) && outbuf_sz){
			ssize_t nw = write(fdout, outbuf, outbuf_sz);
			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}
		}

		if (fds[1].revents & POLLIN){
			ssize_t nr = recv(fdin, inbuf, 9000, 0);
			if (-1 == nr && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
				a12int_trace(A12_TRACE_DIRECTORY, "shutdown:reason=rw_error");
				break;
			}
			else if (0 == nr){
				a12int_trace(A12_TRACE_DIRECTORY, "shutdown:reason=closed");
				break;
			}
			a12_unpack(S, inbuf, nr, tag, on_event);

/* check if there has been a change to the directory state after each unpack */
			uint64_t new_ts;
			if (on_directory){
				struct appl_meta* dir = a12int_get_directory(S, &new_ts);
				if (new_ts != ts){
					ts = new_ts;
					if (!on_directory(S, dir, tag))
						return;
				}
			}
		}

		if (!outbuf_sz){
			outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);
			if (!outbuf_sz && g_shutdown){
				break;
			}
		}

		fds[0].revents = fds[1].revents = fds[2].revents = 0;
		fds[2].fd = outbuf_sz ? fdout : -1;
	}
}