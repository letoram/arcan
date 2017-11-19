/*
 * Pipe-based implementation of the A12 protocol,
 * relying on pre-established secure channels and low
 * bandwidth demands.
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include "a12.h"

static const short c_pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;

static void server_mode(struct shmifsrv_client* a, struct a12_state* ast)
{
/* 1. setup a12 in connect mode, _open */
	struct pollfd fds[3] = {
		{ .fd = shmifsrv_client_handle(a), .events = c_pollev },
		{	.fd = STDIN_FILENO, .events = c_pollev },
		{ .fd = STDOUT_FILENO, .events = POLLOUT }
	};

	bool alive = true;

	uint8_t* outbuf;
	size_t outbuf_sz = 0;

	while (alive){
/* first, flush current outgoing and/or swap buffers */
		int np = 2;
		if (outbuf_sz || (outbuf_sz = a12_channel_flush(ast, &outbuf))){
			ssize_t nw = write(STDOUT_FILENO, outbuf, outbuf_sz);
			if (nw > 0)
				outbuf_sz -= nw;
			if (outbuf_sz)
				np = 3;
		}

/* pollset is extended to cover STDOUT if we have an ongoing buffer */
		int sv = poll(fds, np, 1000 / 15);
		if (sv < 0){
			if (sv == -1 && errno != EAGAIN && errno != EINTR)
				alive = false;
			continue;
		}

/* STDIN - update a12 state machine */
		if (sv && fds[1].revents){
		}

/* SHMIF-client - poll event queue, check/dispatch buffers */
		if (sv && fds[0].revents){
			struct arcan_event newev;
			if (fds[0].revents != POLLIN){
				alive = false;
				continue;
			}
			while (shmifsrv_dequeue_events(a, &newev, 1)){
				a12_channel_enqueue(ast, &newev);
			}
		}

		switch(shmifsrv_poll(a)){
			case CLIENT_DEAD:
/* the descriptor will be gone so next poll will fail */
			break;
			case CLIENT_NOT_READY:
/* do nothing */
			break;
			case CLIENT_VBUFFER_READY:
				fprintf(stderr, "client got vbuffer, flush to state\n");
/* copy + release if possible */
				shmifsrv_video(a, true);
			break;
			case CLIENT_ABUFFER_READY:
				fprintf(stderr, "client got abuffer\n");
/* copy + release if possible */
				shmifsrv_audio(a, NULL, 0);
			break;
/* do nothing */
			break;
			}
		}
	shmifsrv_free(a);
}

static int run_shmif_server(uint8_t* authk, size_t auth_sz, const char* cp)
{
	int fd = -1, sc = 0;

/* repeatedly open the same connection point */
	while(true){
		struct shmifsrv_client* cl =
			shmifsrv_allocate_connpoint(cp, NULL, S_IRWXU, &fd, &sc, 0);

		if (!cl){
			fprintf(stderr, "couldn't allocate connection point\n");
			return EXIT_FAILURE;
		}

		struct pollfd pfd = { .fd = fd, .events = POLLIN | POLLERR | POLLHUP };
		if (poll(&pfd, 1, -1) == 1){
/* go through the accept step, now we can hand the connection over
 * and repeat the listening stage in some other execution context,
 * here's the point to thread or multiprocess */
			if (pfd.revents == POLLIN){
				shmifsrv_poll(cl);

/* build the a12 state and hand it over to the main loop */
				server_mode(cl, a12_channel_open(authk, auth_sz));
			}
			else
				shmifsrv_free(cl);
		}
/* SIGINTR */
		else
			break;

/* wait until something happens */
	}
	return EXIT_SUCCESS;
}

static int run_shmif_client(uint8_t* authk, size_t authk_sz)
{
	struct arcan_shmif_cont wnd =
		arcan_shmif_open(SEGID_UNKNOWN, SHMIF_NOACTIVATE, NULL);

	struct a12_state* ast = a12_channel_build(authk, authk_sz);

	struct pollfd fds[] = {
		{ .fd = wnd.epipe, .events = c_pollev },
		{	.fd = STDIN_FILENO, .events = c_pollev },
		{ .fd = STDOUT_FILENO, .events = POLLOUT }
	};

	uint8_t* outbuf;
	size_t outbuf_sz = 0;

	bool alive;
	while (alive){
/* first, flush current outgoing and/or swap buffers */
		int np = 2;
		if (outbuf_sz || (outbuf_sz = a12_channel_flush(ast, &outbuf))){
			ssize_t nw = write(STDOUT_FILENO, outbuf, outbuf_sz);
			if (nw > 0)
				outbuf_sz -= nw;
			if (outbuf_sz)
				np = 3;
		}

/* events from parent, nothing special - unless the carry a descriptor */
		int sv = poll(fds, np, 1000 / 15);

		if (sv < 0){
			if (sv == -1 && errno != EAGAIN && errno != EINTR)
				alive = false;
			continue;
		}

		if (sv && fds[1].revents){
			struct arcan_event newev;
			int sc;
			while (( sc = arcan_shmif_poll(&wnd, &newev)) > 0){
			}
			if (-1 == sc){
				alive = false;
			}
		}
	}

	return EXIT_SUCCESS;
}

static int show_usage(const char* n, const char* msg)
{
	fprintf(stderr, "%s\nUsage:\n\t%s shmif-client [-k authkfile(0<n<64b)] -c"
	"\n\t%s shmif-server [-k authfile(0<n<64b)] -s connpoint\n", msg, n, n);
	return EXIT_FAILURE;
}

int main(int argc, char** argv)
{
	if (isatty(STDIN_FILENO) || isatty(STDOUT_FILENO))
		return show_usage(argv[0], "[stdin] / [stdout] should not be TTYs\n");

	uint8_t authk[64] = {0};
	size_t authk_sz = 0;

	const char* cp = NULL;
	int mode = 0;

	for (size_t i = 1; i < argc; i++){
		if (strcmp(argv[i], "-k") == 0){
			i++;
			if (i == argc)
				return show_usage(argv[i], "missing keyfile argument");
			else {
				FILE* fpek = fopen(argv[i], "r");
				if (!fpek)
					return show_usage(argv[i], "keyfile couldn't be read");
				authk_sz = fread(authk, 1, 64, fpek);
				fclose(fpek);
			}
		}
		else if (strcmp(argv[i], "-s") == 0){
			i++;
			if (i == argc)
				return show_usage(argv[i], "missing connection point argument");
			mode = 1;
			cp = argv[i];
			break;
		}
		else if (strcmp(argv[i], "-c") == 0){
			mode = 2;
			break;
		}
	}

/* both stdin and stdout in non-blocking mode */
	int flags = fcntl(STDOUT_FILENO, F_GETFL);
	fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK);
	flags = fcntl(STDIN_FILENO, F_GETFL);
	fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);

	if (mode == 0)
		return show_usage(argv[0], "missing connection mode (-c or -s)");

	if (mode == 1)
		return run_shmif_server(authk, authk_sz, cp);

	if (mode == 2)
		return run_shmif_client(authk, authk_sz);

	return EXIT_SUCCESS;
}
