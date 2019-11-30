#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL | SHMIF_NOREGISTER | SHMIF_NOACTIVATE, &aarr);

	arcan_event ev;
	bool running = true;

	arcan_shmif_resize(&cont, 640, 480);

	uint8_t step_r = 0;
	uint8_t step_g = 0;
	uint8_t step_b = 255;

	int frames = 0;
	while(running){
		if (frames++ > 200){
			printf("send resize\n");
			arcan_shmif_resize(&cont, 128 + (rand() % 1024), 128 + (rand() % 1024));
			printf("unlock resize\n");
			frames = 0;
		}

		printf("frame(%zu, %zu)\n", cont.w, cont.h);
		for (size_t row = 0; row < cont.h; row++)
			for (size_t col = 0; col < cont.w; col++){
				cont.vidp[ row * cont.addr->w + col ] = SHMIF_RGBA(step_r, step_g, step_b, 0xff);
				step_r++;
				step_g += step_r == 255;
				step_b += step_g == 255;
			}

		arcan_shmif_signal(&cont, SHMIF_SIGVID);

		int rv;
		while ( (rv = arcan_shmif_poll(&cont, &ev)) == 1){
			if (ev.category == EVENT_TARGET)
			switch (ev.tgt.kind){
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
