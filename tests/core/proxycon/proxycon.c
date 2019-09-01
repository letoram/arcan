/*
 * Simple shmif- proxy, as a skeleton for more advanced forms and for testing.
 *
 * missing:
 *  multiple subsegments (descrevents)
 *  accelerated handles (just send fail atm.)
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
		shmifsrv_free(a, true);
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
		int left = 0;
		int tick = shmifsrv_monotonic_tick(&left);
		int sv = poll(fds, 2, 16);

		if (sv < 0){
			if (sv == -1 && errno != EAGAIN && errno != EINTR)
				alive = false;
			continue;
		}

		while(tick-- > 0){
/*			alive = shmifsrv_tick(a); */
		}

/* event from child, we need to reflect resize, and treat timers locally so
 * they have better accuracy */
		struct arcan_event newev;
		while (shmifsrv_dequeue_events(a, &newev, 1)){
			if (arcan_shmif_descrevent(&newev)){
				printf("ignored descrevent: %s\n", arcan_shmif_eventstr(&newev, NULL, 0));
			}
			else {
				printf("dequeue (in) -> %s\n", arcan_shmif_eventstr(&newev, NULL, 0));
				arcan_shmif_enqueue(&b, &newev);
			}
		}

		int sc;
		while (( sc = arcan_shmif_poll(&b, &newev)) > 0){
			if (arcan_shmif_descrevent(&newev)){
				printf("event parent rejected (%s)\n", arcan_shmif_eventstr(&newev, NULL, 0));
				}
			else {
				printf("event parent -> child (%s)\n", arcan_shmif_eventstr(&newev, NULL, 0));
				shmifsrv_enqueue_event(a, &newev, -1);
			}
		}
		if (-1 == sc){
			alive = false;
		}

		switch(shmifsrv_poll(a)){
		case CLIENT_DEAD:
			alive = false;
		break;
		case CLIENT_NOT_READY:
/* do nothing */
		break;
		case CLIENT_VBUFFER_READY:{
			printf("vbuffer\n");
			struct shmifsrv_vbuffer vbuf = shmifsrv_video(a);
			if (!shmifsrv_enter(a))
				goto out;


			if (vbuf.w != b.w || vbuf.h != b.h){
				if (!arcan_shmif_resize(&b, vbuf.w, vbuf.h)){
					fprintf(stderr, "couldn't match src-sz with dst-sz\n");
					goto out;
				}
			}

/* assume the same stride/packing rules being applied (same version of shmif
 * so not a particularly dangerous assumption) */
			memcpy(b.vidb, vbuf.buffer, vbuf.stride * vbuf.h);

/* should really interleave and run with audio in our muxing */
			arcan_shmif_signal(&b, SHMIF_SIGVID);

/* details:
 * buffer [raw pixels or others
 * flags: origo_ll, ignore_alpha, subregion, srgb, hwhandles,
 *        and hwhandles determine the passing strategy and
 *        buffers communicate modifiers
 */

			shmifsrv_video_step(a);
			shmifsrv_leave();
		}
		break;
		case CLIENT_ABUFFER_READY:
/* copy + release if possible */
			shmifsrv_audio(a, NULL, 0);
		break;
/* do nothing */
		break;
		}
	}

out:
	shmifsrv_free(a, true);
	arcan_shmif_drop(&b);
}

int main(int argc, char** argv)
{
	int fd = -1;
	shmifsrv_monotonic_rebase();

	while(true){
/* setup listening point */
		struct shmifsrv_client* cl =
			shmifsrv_allocate_connpoint("proxycon", NULL, S_IRWXU, fd);

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
				shmifsrv_free(cl, true);
		}
/* SIGINTR */
		else
			break;

		proxy_client(cl);
	}

	return EXIT_FAILURE;
}
