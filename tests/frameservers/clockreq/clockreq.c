#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>

#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);
	bool resubmit = false;

	arcan_event ev = {
			.ext.kind = ARCAN_EVENT(CLOCKREQ),
			.ext.clock.rate = 50,
			.ext.clock.id = 10,
		};

	if (argc > 1 && strcmp(argv[1], "present") == 0){
		arcan_shmif_enqueue(&cont, &(struct arcan_event){
				.ext.kind = ARCAN_EVENT(CLOCKREQ),
				.ext.clock.dynamic = 1
		});
		printf("requesting feedback on submit-ack and present\n");
		arcan_shmif_signal(&cont, SHMIF_SIGVID);
		resubmit = true;
	}
	else if (argc > 1 && strcmp(argv[1], "vsignal") == 0){
		cont.hints = SHMIF_RHINT_VSIGNAL_EV;
		arcan_shmif_resize(&cont, cont.w, cont.h);
		arcan_shmif_signal(&cont, SHMIF_SIGVID);
		resubmit = true;
	}
	else if (argc > 1 && strcmp(argv[1], "vblank") == 0){
		arcan_shmif_enqueue(&cont, &(struct arcan_event){
				.ext.kind = ARCAN_EVENT(CLOCKREQ),
				.ext.clock.dynamic = 2
		});
		printf("requesting timer each blank\n");
		arcan_shmif_signal(&cont, SHMIF_SIGVID);
	}
	else {
		printf("running basic [n=50@25Hz -> 2s] custom timer with id 10\n");
		arcan_shmif_enqueue(&cont, &ev);
	}

	while(arcan_shmif_wait(&cont, &ev) != 0){
		if (ev.category == EVENT_TARGET)
			switch(ev.tgt.kind){
				case TARGET_COMMAND_STEPFRAME:
					printf("step: %d, source: %d cval: %"PRIu32"\n",
						ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].uiv);
					if (resubmit)
						arcan_shmif_signal(&cont, SHMIF_SIGVID);
				break;
				case TARGET_COMMAND_EXIT:
					goto done; /* break(1), please */
				default:
				break;
			}
	}

done:
	arcan_shmif_drop(&cont);
	return EXIT_SUCCESS;
}
