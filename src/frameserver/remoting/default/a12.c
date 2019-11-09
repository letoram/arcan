#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include "a12.h"

#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>
#include <poll.h>
#include <errno.h>

#include "anet_helper.h"

static void on_cl_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
/*
 * the events here are what a remote 'window' would provide you with,
 * which would basically be data transfers (you requested to copy something)
 * as the videos are handled by the a12 state machine itself
 * printf("got client event: %s\n", arcan_shmif_eventstr(ev, NULL, 0));
 */
}

static void main_loop(
	struct arcan_shmif_cont* C, struct a12_state* S, int fd)
{
/* slightly more naive than the version we have been using in the other
 * tools, but basically a - flushing incoming data, flush event loop,
 * flush outgoing data with a poll as trigger */
	uint8_t inbuf[9000];
	uint8_t* outbuf = NULL;
	size_t outbuf_sz = 0;

	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[2] = {
		{.fd = fd, .events = POLLIN | errmask},
		{.fd = C->epipe, .events = POLLIN | errmask}
	};

/* just map incoming A/V buffers to the segment */
	a12_set_destination(S, C, 0);

	while(-1 != poll(fds, 2, -1)){
		if (fds[0].revents & errmask || fds[1].revents & errmask){
			break;
		}

/* incoming data into state machine */
		if (fds[0].revents & POLLIN){
			ssize_t nr = read(fds[0].fd, inbuf, 9000);
			if (nr > 0){
				a12_unpack(S, inbuf, nr, C, on_cl_event);
			}
		}

/* flush any events, the ones that we should take particular note of, as they
 * require us to allocate resources on both sides is the data- transfers and
 * clipboard requests */
		struct arcan_event ev;

		while (arcan_shmif_poll(C, &ev) > 0){
/* forward IO, shutdown on EXIT */
			if (ev.category == EVENT_IO){
				a12_channel_enqueue(S, &ev);
				continue;
			}

			if (ev.category != EVENT_TARGET)
				continue;

			switch(ev.tgt.kind){
			case TARGET_COMMAND_EXIT:
				a12_channel_shutdown(S, NULL);
			break;
			default:
			break;
			}
		}

		outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);
		while(outbuf_sz){
			ssize_t nw = write(fd, outbuf, outbuf_sz);
			if (-1 == nw){
				if (errno != EINTR && errno != EAGAIN)
					goto out;
				continue;
			}
			outbuf += nw;
			outbuf_sz -= nw;
		}
	}

out:
	arcan_shmif_drop(C);
	a12_free(S);
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" password\t val       \t use this (7-bit ascii) password for auth\n"
	  " host    \t hostname  \t connect to the specified host\n"
		" port    \t portnum   \t use the specified port for connecting\n"
		"---------\t-----------\t----------------\n"
	);
}

int run_a12(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	struct addrinfo hints = {
		.ai_family = AF_UNSPEC,
		.ai_socktype = SOCK_STREAM
	};
	struct addrinfo* addr = NULL;
	const char* host = NULL;
	const char* port = "6680";

	struct a12_context_options* opts =
		a12_sensitive_alloc(sizeof(struct a12_context_options));
	a12_plain_kdf(NULL, opts);

	if (!arg_lookup(args, "host", 0, &host)){
		arcan_shmif_last_words(cont, "missing host argument");
		fprintf(stderr, "missing host argument\n");
		dump_help();
		return EXIT_FAILURE;
	}

	const char* tmp;
	if (arg_lookup(args, "port", 0, &tmp)){
		port = tmp;
	}

	int ec = getaddrinfo(host, port, &hints, &addr);
	if (ec){
		char buf[64];
		snprintf(buf, sizeof(buf), "couldn't resolve: %s", gai_strerror(ec));
		arcan_shmif_last_words(cont, buf);
		fprintf(stderr, "%s", buf);
		return EXIT_FAILURE;
	}

	int fd = anet_clfd(addr);
	if (-1 == fd){
		char buf[64];
		snprintf(buf, sizeof(buf), "couldn't connect to %s:%s", host, port);
		arcan_shmif_last_words(cont, buf);
		fprintf(stderr, "%s\n", buf);
		freeaddrinfo(addr);
		return EXIT_FAILURE;
	}

/* at this stage we have a valid connection, time to build the state machine */
	struct a12_state* state = a12_open(opts);
	if (!state){
		const char* err = "Failed to build a12 state machine (invalid arguments)";
		arcan_shmif_last_words(cont, err);
		fprintf(stderr, "%s\n", err);
		freeaddrinfo(addr);
		close(fd);
		return EXIT_FAILURE;
	}

	main_loop(cont, state, fd);

	return EXIT_SUCCESS;
}
