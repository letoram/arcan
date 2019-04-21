/*
 * Copyright: 2018, Bjorn Stahl
 * License: 3-Clause BSD
 * Description: Implements a support wrapper for the a12 function patterns used
 * to implement a single a12- server that translated to an a12- client
 * connection. This is the dispatch function that sets up a managed loop
 * handling one client. Thread or multiprocess it.
 */
#include <arcan_shmif.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>

#include "a12_int.h"
#include "a12.h"
#include "a12_helper.h"

struct cl_state {
	struct arcan_shmif_cont wnd[256];
	size_t n_segments;
};

static void on_cl_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	if (!cont){
		debug_print(1, "ignore incoming event on unknown context");
		return;
	}
	if (arcan_shmif_descrevent(ev)){
/*
 * Events needed to be handled here:
 * NEWSEGMENT, map it, add it to the context channel list.
 */
		debug_print(1, "incoming descr- event ignored");
	}
	else {
		debug_print(2, "client event: %s on ch %d",
			arcan_shmif_eventstr(ev, NULL, 0), chid);
		arcan_shmif_enqueue(cont, ev);
	}
}

int a12helper_a12srv_shmifcl(
	struct a12_state* S, const char* cp, int fd_in, int fd_out)
{
	if (!cp)
		cp = getenv("ARCAN_CONNPATH");
	else
		setenv("ARCAN_CONNPATH", cp, 1);

	if (!cp){
		debug_print(1, "No connection point was specified");
		return -ENOENT;
	}

/* Channel - connection mapping */
	struct cl_state cl_state = {};

/* Open / set the primary connection */
	cl_state.wnd[0] = arcan_shmif_open(SEGID_UNKNOWN, SHMIF_NOACTIVATE, NULL);
	if (!cl_state.wnd[0].addr){
		debug_print(1, "Couldn't connect to an arcan display server");
		return -ENOENT;
	}
	cl_state.n_segments = 1;
	debug_print(1, "Segment connected");

	a12_set_destination(S, &cl_state.wnd[0], 0);

/* set to non-blocking */
	int flags = fcntl(fd_in, F_GETFL);
	fcntl(fd_in, F_SETFL, flags | O_NONBLOCK);

	uint8_t* outbuf;
	size_t outbuf_sz = 0;
	debug_print(1, "got proxy connection, waiting for source");

	int status;
	while (-1 != (status = a12helper_poll_triple(
		cl_state.wnd[0].epipe, fd_in, outbuf_sz ? fd_out : -1, 4))){

		if (status & A12HELPER_WRITE_OUT){
			if (outbuf_sz || (outbuf_sz = a12_channel_flush(S, &outbuf))){
				ssize_t nw = write(fd_out, outbuf, outbuf_sz);
				if (nw > 0){
					outbuf += nw;
					outbuf_sz -= nw;
				}
			}
		}

		if (status & A12HELPER_DATA_IN){
			uint8_t inbuf[9000];
			ssize_t nr = read(fd_in, inbuf, 9000);
			if (-1 == nr && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
				debug_print(1, "failed to read from input: %d", errno);
				break;
			}

			debug_print(2, "unpack %zd bytes", nr);
			a12_channel_unpack(S, inbuf, nr, NULL, on_cl_event);
		}

/* 1 client can have multiple segments */
		for (size_t i = 0, count = cl_state.n_segments; i < 256 && count; i++){
			if (!cl_state.wnd[i].addr)
				continue;

			count--;
			struct arcan_event newev;
			int sc;
			while (( sc = arcan_shmif_poll(&cl_state.wnd[i], &newev)) > 0){
/* we got a descriptor passing event, some of these we could/should discard,
 * while others need to be forwarded as a binary- chunk stream and kept out-
 * of order on the other side */
				if (arcan_shmif_descrevent(&newev)){
					debug_print(1, "(cl:%zu) ign-descr-event: %s",
						i, arcan_shmif_eventstr(&newev, NULL, 0));
				}
				else {
					debug_print(2, "enqueue %s", arcan_shmif_eventstr(&newev, NULL, 0));
					a12_channel_enqueue(S, &newev);
				}
			}
		}

/* we might have gotten data to flush, so use that as feedback */
		if (!outbuf_sz){
			outbuf_sz = a12_channel_flush(S, &outbuf);
			if (outbuf_sz)
				debug_print(2, "output buffer size: %zu", outbuf_sz);
		}
	}

/* though a proper cleanup would cascade, it doesn't help being careful */
	for (size_t i = 0, count = cl_state.n_segments; i < 256 && count; i++){
		if (!cl_state.wnd[i].addr)
				continue;
		arcan_shmif_drop(&cl_state.wnd[i]);
		cl_state.wnd[i].addr = NULL;
	}

	return 0;
}
