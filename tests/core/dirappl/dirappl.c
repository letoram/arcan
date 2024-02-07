#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>
#include <pthread.h>

void* worker(void* arg)
{
	struct arg_arr* args;
	struct arcan_shmif_cont C =
		arcan_shmif_open(
			SEGID_NETWORK_SERVER,
			SHMIF_ACQUIRE_FATALFAIL |
			SHMIF_NOACTIVATE        |
			SHMIF_DISABLE_GUARD     |
			SHMIF_NOREGISTER,
			&args
		);

	arcan_shmif_enqueue(&C,
		&(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_NETSTATE,
			.ext.netstate = {
				.name = {1, 2, 3, 4, 5, 6, 7, 8}
			}
		});
	arcan_pushhandle(-1, C.epipe);

	struct arcan_event ev;
	while (arcan_shmif_wait(&C, &ev)){
		const char* evstr = arcan_shmif_eventstr(&ev, NULL, 0);
		fprintf(stdout, "worker_in=%s\n", evstr);
	}

	fprintf(stdout, "worker_over\n");
	arcan_shmif_drop(&C);
	return NULL;
}

static void spawn_worker(struct shmifsrv_client* cl, char* name, int dfd)
{
/* send the appl dirhandle,
 * can be re-used to send store access as well as database handle */
	struct arcan_event outev =
		(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
		};
	snprintf(outev.tgt.message, sizeof(outev.tgt.message), "%s", name);
	shmifsrv_enqueue_event(cl, &outev, dfd);

/* Setup 'fake' shmif client representing the worker, do this by a socketpair
 * that turns into shmifsrv_inherit_connection in the runner, and sneak it in
 * here with ARCAN_SOCKIN_FD + shmif_open into a separate process thread.
 * For the proper process, the worker gets a NEWSEGMENT with their end.
 */
	int sv[2];
	socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
	shmifsrv_enqueue_event(cl, &(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
			.tgt.message = ".worker=test",
		}, sv[0]);
	close(sv[0]);

	char buf[8];
	snprintf(buf, 8, "%d", sv[1]);
	setenv("ARCAN_SOCKIN_FD", buf, 1);

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pth, &pthattr, worker, NULL);
}

int main(int argc, char** argv)
{
	if (argc != 2){
		fprintf(stderr, "Use: dirappl /path/to/appldir; ARCAN_CONNPATH=dirappl arcan-net dirappl\n");
		return EXIT_FAILURE;
	}

/* connpath is evaluated before sockin_fd */
	unsetenv("ARCAN_CONNPATH");

	int dfd = open(argv[1], O_RDONLY | O_DIRECTORY);
	if (-1 == dfd){
		fprintf(stderr, "Couldn't open appl basedir (%s)\n", argv[1]);
		return EXIT_FAILURE;
	}

	char* split = strrchr(argv[1], '/');
	if (!split)
		split = argv[1];
	else
		split++;

	if (!strlen(split)){
		fprintf(stderr, "Couldn't get applname from basedir (%s)\n", argv[1]);
		return EXIT_FAILURE;
	}

/* setup listening point */
	struct shmifsrv_client* cl =
		shmifsrv_allocate_connpoint("dirappl", NULL, S_IRWXU, -1);

/* setup our clock that is used for time-keeping */
	shmifsrv_monotonic_rebase();

	if (!cl){
		fprintf(stderr, "couldn't allocate connection point\n");
		return EXIT_FAILURE;
	}

	bool cl_init = false;
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
				pv = 25;
			}
		}

/* flush or acknowledge buffer transfers */
		int sv;
		sv = shmifsrv_poll(cl);
		if (sv == CLIENT_DEAD){
			fprintf(stderr, "client died\n");
			break;
		}

/* flush out events - we don't really need anything here */
		struct arcan_event ev;
		while (1 == shmifsrv_dequeue_events(cl, &ev, 1)){
			shmifsrv_process_event(cl, &ev);
		}

/* let the monotonic clock drive timers etc. */
		int ticks = shmifsrv_monotonic_tick(NULL);
		while(ticks--)
			shmifsrv_tick(cl);

		if (!cl_init){
			cl_init = true;
			spawn_worker(cl, split, dfd);
		}
	}

	shmifsrv_free(cl, true);
	return EXIT_SUCCESS;
}
