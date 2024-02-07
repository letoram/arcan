#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <poll.h>
#include <inttypes.h>

void arcan_random(uint8_t*, size_t);

static void on_tick(struct shmifsrv_client* cl)
{
	if (!getenv("ANET_RUNNER_TICK"))
		return;

	struct arcan_event ev = (struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_MESSAGE
	};

	static int counter = 0;

	snprintf(ev.tgt.message, sizeof(ev.tgt.message), "tick=%d", counter);
	counter++;
	shmifsrv_enqueue_event(cl, &ev, -1);
}

int main(int argc, char** argv)
{
	FILE* ctrl_out = NULL;

	const char* errarg = "-O LOGFD:fd expected, "
		"use ANET_RUNNER=/path/to/bin arcan-net host app\n";

/* find -O to get the descriptor number */
	for (size_t i = 1; i < argc; i++){
		if (strcmp(argv[i], "-O") == 0){
			if (i == argc - 1){
				fputs(errarg, stderr);
				return EXIT_FAILURE;
			}

			i++;
			if (strncmp(argv[i], "LOGFD:", 6)){
				fputs(errarg, stderr);
				return EXIT_FAILURE;
			}

			int fdin = (int) strtoul(&argv[i][6], NULL, 10);
			if (fdin <= 0){
				fprintf(stderr, "LOGFD:fdnum - parse fdnum\n");
				return EXIT_FAILURE;
			}

			ctrl_out = fdopen(fdin, "w");
			break;
		}
	}

	if (!ctrl_out){
		fputs(errarg, stderr);
		return EXIT_FAILURE;
	}

	char buf[PATH_MAX];

	struct {
		uint32_t rnd;
		uint8_t buf[4];
	} rval;

	arcan_random(rval.buf, 4);
	snprintf(buf, sizeof(buf), "%s/anetrun%"PRIu32, getenv("XDG_RUNTIME_DIR"), rval.rnd);

/* setup listening point */
	int fd = -1;
	struct shmifsrv_client* cl =
		shmifsrv_allocate_connpoint(buf, NULL, S_IRWXU, fd);

/* setup our clock */
	shmifsrv_monotonic_rebase();

	if (!cl){
		fprintf(stderr, "couldn't allocate connection point\n");
		return EXIT_FAILURE;
	}

	fprintf(ctrl_out, "join %s\n", buf);
	fflush(ctrl_out);

/* control commands on stdin:
 *  - continue
 *  - dumpkeys
 *  - loadkey
 *  - dumpstate
 *  - commit
 *  - reload
 *  - lock
 */

/* sending replies:
 * #FINISH, #FAIL, #BEGINKV, #ENDKV,  #ERROR, #LASTSOURCE
 */

	int pv = -1;
	while (true){
		struct pollfd pfd = {
			.fd = shmifsrv_client_handle(cl, NULL),
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
		while ((sv = shmifsrv_poll(cl)) != CLIENT_IDLE){
			if (sv == CLIENT_DEAD){
				fprintf(stderr, "client died\n");
				break;
			}
		}

/* flush out events */
		struct arcan_event ev;
		while (1 == shmifsrv_dequeue_events(cl, &ev, 1)){
			fprintf(stderr, "in-event=%s\n", arcan_shmif_eventstr(&ev, NULL, 0));
			continue;
		}

/* let the monotonic clock drive timers etc. */
		int ticks = shmifsrv_monotonic_tick(NULL);
		while(ticks--){
			shmifsrv_tick(cl);
			on_tick(cl);
		}
	}

	shmifsrv_free(cl, true);
	return EXIT_SUCCESS;
}
