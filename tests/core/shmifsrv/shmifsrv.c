#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <poll.h>

static void on_abuffer(shmif_asample* buf,
	size_t n_samples, unsigned channels, unsigned rate, void* tag)
{
	fprintf(stderr,
		"abuffer, %zu samples, %u channels, %u rate\n",
		n_samples, channels, rate
	);
}

int main(int argc, char** argv)
{
	int fd = -1;

/* setup listening point */
	struct shmifsrv_client* cl =
		shmifsrv_allocate_connpoint("shmifsrv", NULL, S_IRWXU, fd);

/* setup our clock */
	shmifsrv_monotonic_rebase();

	if (!cl){
		fprintf(stderr, "couldn't allocate connection point\n");
		return EXIT_FAILURE;
	}

/* wait until something happens */

	int pv = -1;
	while (true){
		struct pollfd pfd = {
			.fd = shmifsrv_client_handle(cl),
			.events = POLLIN | POLLERR | POLLHUP
		};

		if (poll(&pfd, 1, pv) > 0){
			if (pfd.revents){
				if (pfd.revents != POLLIN)
					break;
				pv = 16;
			}
		}

/* flush or acknowledge buffer transfers */
		int sv;
		while ((sv = shmifsrv_poll(cl)) != CLIENT_NOT_READY){
			if (sv == CLIENT_DEAD){
				fprintf(stderr, "client died\n");
				break;
			}
			else if (sv == CLIENT_VBUFFER_READY){
				struct shmifsrv_vbuffer buf = shmifsrv_video(cl);
				shmifsrv_video_step(cl);
				fprintf(stderr, "[video] : %zu*%zu\n", buf.w, buf.h);
			}
			else if (sv == CLIENT_ABUFFER_READY){
				shmifsrv_audio(cl, on_abuffer, NULL);
			}
		}

/* flush out events */
		struct arcan_event ev;
		while (1 == shmifsrv_dequeue_events(cl, &ev, 1)){
/* PREROLL stage, need to send ACTIVATE */
			if (ev.ext.kind == EVENT_EXTERNAL_REGISTER){
				shmifsrv_enqueue_event(cl, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_ACTIVATE
				}, -1);
			}
/* always reject requests for additional segments */
			else if (ev.ext.kind == EVENT_EXTERNAL_SEGREQ){
				shmifsrv_enqueue_event(cl, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_REQFAIL,
					.tgt.ioevs[0].iv = ev.ext.segreq.id
				}, -1);
			}
			else if (shmifsrv_process_event(cl, &ev))
				continue;
		}

/* let the monotonic clock drive timers etc. */
		int ticks = shmifsrv_monotonic_tick(NULL);
		while(ticks--)
			shmifsrv_tick(cl);
	}

	shmifsrv_free(cl, true);
	return EXIT_SUCCESS;
}
