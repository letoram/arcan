#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include "a12.h"

#include <sys/stat.h>
#include <poll.h>
#include <errno.h>

#include <sys/socket.h>
#include <netdb.h>
#include "anet_helper.h"

static void on_cl_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct a12_state* S = tag;

	if (ev->category == EVENT_EXTERNAL){
		switch (ev->ext.kind){
		case EVENT_EXTERNAL_REGISTER:
			a12_channel_enqueue(S, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_ACTIVATE
			});
		break;

		default:
		break;
		}
	}

/*
 * first off, REGISTER here need to provide an ACTIVATE after we send any
 * known initials. Those initials can be extracted (somewhat) from the cont
 * above.
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
				a12_unpack(S, inbuf, nr, S, on_cl_event);
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

static void dump_help(const char* reason)
{
	fprintf(stdout,
		"Error: %s\n"
		"Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" pass    \t val       \t use this (7-bit ascii) password for auth\n"
	  " host    \t hostname  \t connect to the specified host\n"
		" port    \t portnum   \t use the specified port for connecting\n"
		" tag     \t keyid     \t specify keystore identifier (can set host)\n"
		" trace   \t level     \t set trace mask (see arcan-net for values) for debug\n"
		" store   \t path      \t path to keystore base\n"
		" cache   \t path      \t path to binary file cache\n"
		"---------\t-----------\t----------------\n", reason
	);
}

int run_a12(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	const char* host = NULL;
	const char* port = "6680";
	const char* keyid = NULL;

	struct a12_context_options* opts =
		a12_sensitive_alloc(sizeof(struct a12_context_options));

	arg_lookup(args, "host", 0, &host);
	arg_lookup(args, "tag", 0, &keyid);

	if (!host && !keyid){
		arcan_shmif_last_words(cont, "missing host or key argument");
		dump_help("missing host or key argument");
		return EXIT_FAILURE;
	}

	const char* tmp;
	if (arg_lookup(args, "port", 0, &tmp)){
		if (!tmp || !strlen(tmp)){
			arcan_shmif_last_words(cont, "missing or invalid port value");
			dump_help("missing or invalid port value");
			return EXIT_FAILURE;
		}
		port = tmp;
	}

	if (arg_lookup(args, "trace", 0, &tmp) && tmp){
		long arg = strtol(tmp, NULL, 10);
		a12_set_trace_level(arg, stderr);
	}

/* after this point access to the keystore can be revoked, ideally we would be
 * able to get this information from arcan as well, something to consider with
 * afsrv_net is updated */
	struct anet_options netarg = {
		.host = host,
		.port = port,
		.key = keyid,
		.opts = opts
	};

	struct anet_cl_connection con = anet_cl_setup(&netarg);

	if (!con.state){
		arcan_shmif_last_words(cont, con.errmsg);
		fprintf(stderr, "%s\n", con.errmsg);
		return EXIT_FAILURE;
	}

	main_loop(cont, con.state, con.fd);

	return EXIT_SUCCESS;
}
