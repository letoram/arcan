#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	uint8_t r = 255;
	uint8_t g = 0;
	uint8_t b = 0;

	while(1){
		size_t neww = 32 + (rand() % PP_SHMPAGE_MAXW);
		size_t newh = 32 + (rand() % PP_SHMPAGE_MAXH);

		if (!arcan_shmif_resize(&cont, neww, newh)){
			fprintf(stderr, "Resize (%zu * %zu) failed, giving up.\n", neww, newh);
			break;
		}

		r = ~r;
		g = ~g;
		b = ~b;

		arcan_event ev;
		while (arcan_shmif_poll(&cont, &ev) == 1){}

		for (size_t row = 0; row < cont.addr->h; row++)
			for (size_t col = 0; col < cont.addr->w; col++)
				cont.vidp[ row * cont.addr->w + col ] = SHMIF_RGBA(r, g, b, 255);

		arcan_shmif_signal(&cont, SHMIF_SIGVID);
	}

	return EXIT_SUCCESS;
}
