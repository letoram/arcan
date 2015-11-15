#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <string.h>

#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = 2,
		.ext.clock.dynamic = (argc > 1 && strcmp(argv[1], "dynamic") == 0)
	};
	arcan_shmif_enqueue(&cont, &ev);

	ev.ext.clock.dynamic = false;
	int tbl[] = {20, 40, 42, 44, 60, 80, 86, 88, 100, 120};
	int step = 0;

	for (size_t i=0; i < sizeof(tbl)/sizeof(tbl[0]); i++){
		ev.ext.clock.once = true;
		ev.ext.clock.rate = tbl[i];
		ev.ext.clock.id = i + 2; /* 0 index and 1 is reserved */
		arcan_shmif_enqueue(&cont, &ev);
	}

	while(arcan_shmif_wait(&cont, &ev) != 0){
		if (ev.category == EVENT_TARGET)
			switch(ev.tgt.kind){
				case TARGET_COMMAND_STEPFRAME:
					printf("step: %d, source: %d\n",
						ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
					if (ev.tgt.ioevs[1].iv > 1){
						if (step == ev.tgt.ioevs[1].iv-2)
							printf("custom timer %d OK\n", step);
						else
							printf("timer out of synch, expected %d got %d\n",
							step, ev.tgt.ioevs[1].iv-2);
						step++;
					}
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
