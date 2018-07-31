#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <signal.h>

#include <arcan_shmif.h>

static void send_frame(struct arcan_shmif_cont* cont, shmif_pixel color)
{
	for (size_t row = 0; row < cont->h; row++)
		for (size_t col = 0; col < cont->w; col++)
			cont->vidp[ row * cont->addr->w + col ] = color;

	arcan_shmif_signal(cont, SHMIF_SIGVID);
}

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	bool stress = argc > 1 && strcmp(argv[1], "-stress") == 0;

/* for stress, we just spin the same case and request */
	if (getenv("ARCAN_HANDOVER")){
		if (!stress){
			printf("in handover, waiting 10s for gdb-attach on pid: %d\n", getpid());
			sleep(10);
		}
	}

	char* testenv[] = {"test=1", "test2=2", NULL};
	arcan_shmif_resize(&cont, 64, 64);

	signal(SIGCHLD, SIG_IGN);

/* different color in parent and child */
	shmif_pixel color = stress || getenv("ARCAN_HANDOVER")?
		SHMIF_RGBA(0x00, 0xff, 0x00, 0xff):
		SHMIF_RGBA(0xff, 0x00, 0x00, 0xff);

	send_frame(&cont, color);

/* stress chains infinitely */
	if (!getenv("ARCAN_HANDOVER") || stress)
		arcan_shmif_enqueue(&cont, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_HANDOVER
		});
/* else just sleep and die */
	else{
		send_frame(&cont, color);
		sleep(10);
		arcan_shmif_drop(&cont);
		return EXIT_SUCCESS;
	}

	struct arcan_event ev;
	while (arcan_shmif_wait(&cont, &ev)){
			if (ev.category == EVENT_TARGET)
			switch (ev.tgt.kind){
			case TARGET_COMMAND_PAUSE:
				printf("suspended\n");
			break;
			case TARGET_COMMAND_NEWSEGMENT:
				arcan_shmif_handover_exec(
					&cont, ev, argv[0], &argv[1], testenv, false);
			break;
			case TARGET_COMMAND_UNPAUSE:
				printf("resumed\n");
			break;
			case TARGET_COMMAND_EXIT:
				arcan_shmif_drop(&cont);
				return EXIT_SUCCESS;
			break;
			default:
			break;
		}
	}

#ifndef ENABLE_FSRV_AVFEED
	return EXIT_SUCCESS;
#endif
}
