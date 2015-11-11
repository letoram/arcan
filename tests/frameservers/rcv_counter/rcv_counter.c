#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

void verify_step(struct arcan_shmif_cont* cont)
{
	uint32_t cb = cont->vidp[0];

	static uint8_t step_r = 0;
	static uint8_t step_g = 0;
	static uint8_t step_b = 255;

	if (RGBA(step_r, step_g, step_b, 0xff) != cb){
		fprintf(stderr, "error in readback data, expected %d, got %d\n",
			(int) cb, (int) (RGBA(step_r, step_g, step_b, 0xff)));
		exit(EXIT_FAILURE);
	}

	step_r++;
	step_g += step_r == 255;
	step_b += step_g == 255;

	for (size_t row = 0; row < cont->addr->h; row++)
		for (size_t col = 0; col < cont->addr->w; col++)
			if (cont->vidp[ row * cont->addr->w + col ] != cb){
				fprintf(stderr, "error in readback data (%d vs %d)\n",
					(int) cb, (int) cont->vidp[ row * cont->addr->w + col ]);
				exit(EXIT_FAILURE);
			}

	cont->addr->vready = false;
}

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_ENCODER, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	arcan_event ev;
	bool running = true;

	while(running){
		while (arcan_shmif_wait(&cont, &ev)){
			if (ev.category == EVENT_TARGET)
			switch (ev.tgt.kind){
			case TARGET_COMMAND_STEPFRAME:
				verify_step(&cont);
			break;
			case TARGET_COMMAND_EXIT:
				running = false;
			break;
			default:
			break;
			}
		}
	}

#ifndef ENABLE_FSRV_AVFEED
	return EXIT_SUCCESS;
#endif
}
