/*
 * Simple shmif- proxy, as a skeleton for more advanced forms and for testing.
 *
 * missing:
 *  multiple subsegments
 *  multiprocessing
 *  accelerated handles
 *  output segments
 *  subprotocols
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <poll.h>

/*
 * Semi-informed proxying, gets access to buffer copies etc.
 */
static void proxy_client(struct shmifsrv_client* a)
{
/* special connection settings to fit no-activation */
	struct arcan_shmif_cont b =
		arcan_shmif_open(SEGID_UNKNOWN, SHMIF_NOACTIVATE, NULL);

	if (!b.addr){
		fprintf(stderr, "couldn't open upstream connection\n");
		shmifsrv_free(a);
		return;
	}

	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[2] = {
		{
			.fd = shmifsrv_client_handle(a),
			.events = pollev
		},
		{
			.fd = b.epipe,
			.events = pollev
		}
	};

	bool alive = true;
/* last, check if there's anything new with the buffers */

	while (alive){
		int sv = poll(fds, 2, 1000 / 15);

		if (sv < 0){
			if (sv == -1 && errno != EAGAIN && errno != EINTR)
				alive = false;
			continue;
		}

/* event from child, we need to reflect resize, and treat timers locally so
 * they have better accuracy */
		if (sv && fds[0].revents){
			struct arcan_event newev;
			if (fds[0].revents != POLLIN){
				alive = false;
				continue;
			}
			while (shmifsrv_dequeue_events(a, &newev, 1)){
				arcan_shmif_enqueue(&b, &newev);
			}
		}

/* events from parent, nothing special - unless the carry a descriptor */
		if (sv && fds[1].revents){
			struct arcan_event newev;
			int sc;
			while (( sc = arcan_shmif_poll(&b, &newev)) > 0){
				shmifsrv_enqueue_event(a, &newev, -1);
			}
			if (-1 == sc){
				alive = false;
			}
		}

		switch(shmifsrv_poll(a)){
		case CLIENT_DEAD:
		break;
		case CLIENT_NOT_READY:
/* do nothing */
		break;
		case CLIENT_VBUFFER_READY:
			fprintf(stderr, "client got vbuffer\n");
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

	fprintf(stderr, "cleanup up\n");
	shmifsrv_free(a);
	arcan_shmif_drop(&b);
}

int main(int argc, char** argv)
{
	int fd = -1;
	int sc = 0;

	while(true){
/* setup listening point */
		struct shmifsrv_client* cl =
			shmifsrv_allocate_connpoint("proxycon", NULL, S_IRWXU, &fd, &sc, 0);

		if (!cl){
			fprintf(stderr, "couldn't allocate connection point\n");
			return EXIT_FAILURE;
		}

/* wait until something happens */
		struct pollfd pfd = {
			.fd = shmifsrv_client_handle(cl),
			.events = POLLIN | POLLERR | POLLHUP
		};
		if (poll(&pfd, 1, -1) == 1){
/* go through the accept step, now we can hand the connection over
 * and repeat the listening stage in some other execution context,
 * here's the point to thread or multiprocess */
			if (pfd.revents == POLLIN){
				shmifsrv_poll(cl);
				proxy_client(cl);
			}
			else
				shmifsrv_free(cl);
		}
/* SIGINTR */
		else
			break;

		proxy_client(cl);
	}

	return EXIT_FAILURE;
}
