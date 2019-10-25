/*
 * This is an interesting hybrid / use case in its own right. Expose the encode
 * session as a 'remote desktop' kind of scenario where the client is allowed to
 * provide input, but at the same time is receiving A/V/E data.
 */

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include "a12.h"

#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <signal.h>
#include <netdb.h>
#include <poll.h>

#include "anet_helper.h"
#include <pthread.h>

static void on_client_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	if (!cont){
		return;
	}

/* the client isn't normal as such in that many of the shmif events do
 * not make direct sense to just forward verbatim. The input model match
 * 1:1, however, so forward those. */

	if (ev->category == EVENT_IO){
		arcan_shmif_enqueue(cont, ev);
	}
}

struct dispatch_data {
	struct arcan_shmif_cont* C;
	struct anet_options opts;
};
static void process_shmif(struct a12_state* S, struct dispatch_data* data)
{
	arcan_event ev;
	while(arcan_shmif_poll(data->C, &ev) > 0){
		if (ev.category != EVENT_TARGET)
			continue;
		switch(ev.tgt.kind){

/* this is a good testing basis for adaptive heavy preview- frame delivery
 * that gets sent in advanced, and forwarded unless the main frame arrives
 * in time. Then the SNR can be adjusted to match the quality of the link
 * for the time being. */
		case TARGET_COMMAND_STEPFRAME:{
			arcan_shmif_signal(data->C, SHMIF_SIGVID | SHMIF_SIGAUD);
		}
		default:
		break;
		}
	}
}
static void dispatch_single(struct a12_state* S, int fd, void* tag)
{
	struct arcan_event ev;
	struct dispatch_data* data = tag;

	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	size_t n_fd = 2;
	struct pollfd fds[3] = {
		{.fd = data->C->epipe, POLLIN | errmask},
		{.fd = fd, POLLIN | errmask},
		{.fd = fd, POLLOUT | errmask}
	};

	a12_set_destination(S, data->C, 0);

	uint8_t* outbuf = NULL;
	size_t outbuf_sz = 0;
	uint8_t inbuf[9000];

	for(;;){
/* break out and clean-up on pollset error */
		if (
				((-1 == poll(fds, 2, -1) && (errno != EAGAIN || errno != EINTR))) ||
				(fds[0].revents & errmask) || (fds[1].revents & errmask)
		){
				break;
		}

/* shmif takes priority */
		if (fds[0].revents){
			process_shmif(S, data);
		}

/* incoming data? update a12 state machine */
		if (fds[1].revents){
			ssize_t nr = recv(fd, inbuf, 9000, 0);

/* half-open client closed? or other error? give up */
			if ((-1 == nr && errno != EAGAIN &&
				errno != EWOULDBLOCK && errno != EINTR) || 0 == nr){
				break;
			}

/* populate state buffer, refill if needed */
			a12_unpack(S, inbuf, nr, NULL, on_client_event);
			if (!outbuf_sz)
				outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);
		}

/* flush output buffer */
		if (n_fd == 3 && (fds[2].revents & POLLOUT) && outbuf_sz){
			ssize_t nw = write(fd, outbuf, outbuf_sz);
			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}
		}

/* update pollset if there is something to write, this will cause the next
 * poll to bring us into the flush stage */
		n_fd = outbuf_sz > 0 ? 3 : 2;
	}

/* always clean-up the client socket */
	shutdown(fd, SHUT_RDWR);
	close(fd);
}

static void decode_args(struct arg_arr* arg, struct anet_options* dst)
{
}

void a12_serv_run(struct arg_arr* arg, struct arcan_shmif_cont cont)
{
	struct dispatch_data data = {
		.C = &cont
	};

	decode_args(arg, &data.opts);
/*
 * For the sake of oversimplification, use a single active client mode for
 * the time being. The other option is the complex (multiple active clients)
 * and the expensive (one active client, multiple observers).
 */
	while(cont.addr && anet_listen(&data.opts, dispatch_single, &data)){}

	arcan_shmif_drop(&cont);
	exit(EXIT_SUCCESS);
}
