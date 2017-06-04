#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <signal.h>

#include <arcan_shmif.h>

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
	if (getenv("ARCAN_HANDOVER")){
		printf("in handover, stress? %s", stress ? "yes" : "no");
	}

	signal(SIGCHLD, SIG_IGN);

	shmif_pixel color = stress || getenv("ARCAN_HANDOVER")?
		SHMIF_RGBA(0xaa, 0xff, 0xaa, 0xff):
		SHMIF_RGBA(0xaa, 0xaa, 0xaa, 0xff);

	for (size_t row = 0; row < cont.h; row++)
		for (size_t col = 0; col < cont.w; col++)
			cont.vidp[ row * cont.addr->w + col ] = color;
	arcan_shmif_signal(&cont, SHMIF_SIGVID);

/* stress chains infinitely */
	if (!getenv("ARCAN_HANDOVER") || stress)
		arcan_shmif_enqueue(&cont, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_HANDOVER
		});
/* else just sleep and die */
	else{
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
			case TARGET_COMMAND_NEWSEGMENT:{
				printf("received subsegment to hand over\n");

/* this uses the setup approach from normal frameservers, unlink only happens
 * during acquire or when the server-side decides to, so that's covered. */
				if ( fork()  == 0){
					close(3);
					setenv("ARCAN_SHMKEY", ev.tgt.message, 1);
					dup2(ev.tgt.ioevs[0].iv, 3);
					setenv("ARCAN_SOCKIN_FD", "3", 1);
					setenv("ARCAN_HANDOVER", "1", 1);
					execv(argv[0], &argv[1]);
					exit(EXIT_FAILURE);
				}
			}
/*
 * fork(),
 * dup descriptor,
 * set environment (both FD and HANDOVER)
 * exec self with same arguments
 */
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
