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

	arcan_shmif_signal(&cont, SHMIF_SIGVID);

	while (1){
	arcan_shmif_resize_ext(&cont, cont.w, cont.h, (struct shmif_resize_ext){
		.meta = SHMIF_META_CM
	});

		if (arcan_shmif_substruct(&cont, SHMIF_META_CM).cramp)
			break;

		printf("no gamma, retrying in 1s\n");
		sleep(1);
	}

	printf("got gamma ramps, enter sleep/get/increment loop\n");
	while (1){
		struct arcan_shmif_ramp* hdr =
				arcan_shmif_substruct(&cont, SHMIF_META_CM).cramp;
		uint8_t din = hdr->dirty_in;
		if (!din){
			printf("no ramp updates, sleeping.\n");
			sleep(1);
			continue;
		}

/* for each changed display,
 *  for each color plane
 *  increment with 0.1 and wrap around at 1.0 */
		for (size_t i=0; i<8; i++){
			if (!((1 << i) & din))
				continue;

			struct ramp_block block;
			if (arcan_shmifsub_getramp(&cont, i, &block)){
				printf("retrieved ramp [%zu], (%f, %f, %f)  updating:\n", i,
					block.planes[0], block.planes[1], block.planes[2]);
				size_t plane_pos = 0;
				for (size_t j=0; j < SHMIF_CMRAMP_PLIM; j++){
					printf("\t plane[%zu] - %zu samples\n", j, block.plane_sizes[j]);
					for (size_t k=0; k < block.plane_sizes[j]; k++){
						block.planes[plane_pos + k] += 0.1;
						if (block.planes[plane_pos + k] > 1.0)
							block.planes[plane_pos + k] -= 1.0;
					}

					plane_pos += block.plane_sizes[j];
				}

				arcan_shmifsub_setramp(&cont, i, &block);
			}
		}
	}

#ifndef ENABLE_FSRV_AVFEED
	return EXIT_SUCCESS;
#endif
}
