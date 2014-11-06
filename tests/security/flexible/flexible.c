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

	while(1){
		size_t neww = rand() % PP_SHMPAGE_MAXW;
		size_t newh = rand() % PP_SHMPAGE_MAXH;

		arcan_shmif_resize(&cont, neww, newh);

	for (size_t row = 0; row < cont.addr->h; row++)
		for (size_t col = 0; col < cont.addr->w; col++)
			cont.vidp[ row * cont.addr->w + col ] = RGBA(255, 0, 0, 255);

/* truncate to mess with parent */
		ftruncate(cont.shmh, 1024);

/* make sure it'll try to copy */
		arcan_shmif_signal(&cont, SHMIF_SIGVID);
	}

	return EXIT_SUCCESS;
}
