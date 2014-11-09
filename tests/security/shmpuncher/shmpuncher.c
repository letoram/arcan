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

	arcan_shmif_resize(&cont, 640, 480);

/* truncate to mess with parent */
	ftruncate(cont.shmh, 1024);

/* make sure it'll try to copy */
	arcan_shmif_signal(&cont, SHMIF_SIGVID);

	return EXIT_SUCCESS;
}
