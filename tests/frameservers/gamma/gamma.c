#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	printf("trying to switch to gamma control mode\n");
	arcan_shmif_resize_ext(&cont, cont.w, cont.h, (struct shmif_resize_ext){
		.meta = SHMIF_META_CM
	});

	struct arcan_shmif_ramp* gamma =
		arcan_shmif_substruct(&cont, SHMIF_META_HMD).cramp;

	if (!gamma){
		printf("color management request was not accepted\n");
#ifndef ENABLE_FSRV_AVFEED
		return EXIT_FAILURE;
#else
		return;
#endif
	}

#ifndef ENABLE_FSRV_AVFEED
	return EXIT_SUCCESS;
#endif
}
