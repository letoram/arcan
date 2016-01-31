#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <inttypes.h>
#include <unistd.h>
#include <stdbool.h>
#include <arcan_shmif.h>

#ifdef ENABLE_FSRV_AVFEED
int afsrv_avfeed(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	struct arcan_shmif_cont cont = *con;
#else
int main(int argc, char** argv){
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);
#endif

	arcan_event ev;
	struct {shmif_pixel* vp; shmif_pixel col;} ca[3] = {0};

	arcan_shmif_resize_ext(&cont, 640, 480, (struct shmif_resize_ext){
		.abuf_sz = 0, .abuf_cnt = 0, .vbuf_cnt = 3
	});

/* We pair vidp pointer value with slot in array, so that each possible video
 * buffer slot gets a known color. If every frame is red, the cycling is
 * entirely ignored. If every frame is blue, only the latest is shown and we
 * are maintaing a clock that match the display. */
	ca[0].col = SHMIF_RGBA(255, 0, 0, 255);
	ca[1].col = SHMIF_RGBA(0, 255, 0, 255);
	ca[2].col = SHMIF_RGBA(0, 0, 255, 255);
	int i = 0;
	int fc = 500;

	while(cont.addr->dms && fc--){
		shmif_pixel color;
/* grab matching color, we don't know the other vidps so have to log */
		for (i=0; i < 3; i++){
			if (ca[i].vp == cont.vidp){
				color = ca[i].col;
				break;
			}
		}

/* not found, register */
		if (i==3){
			for (i=0; i < 3; i++){
				if(ca[i].vp == NULL){
					ca[i].vp = cont.vidp;
					color = ca[i].col;
					printf("buffer: %"PRIxPTR" associated with %i\n",
						(uintptr_t)cont.vidp, i);
					break;
				}
			}
		}

		if (i==3){
			printf("buffer - slot mismatch\n");
			return EXIT_FAILURE;
		}

	for (size_t row = 0; row < cont.addr->h; row++)
		for (size_t col = 0; col < cont.addr->w; col++)
			cont.vidp[ row * cont.addr->w + col ] = color;

		long long time = arcan_timemillis();
		arcan_shmif_signal(&cont, SHMIF_SIGVID);
		long long endt = arcan_timemillis();

		printf("synch took: %lld, mask: %d\n", endt - time, cont.addr->vpending);

		while (arcan_shmif_poll(&cont, &ev) == 1)
			;
	}

	FILE* outf = fopen("counter.dump", "w+");
	fwrite(cont.addr, 1, cont.shmsize, outf);
	fclose(outf);

	return EXIT_SUCCESS;
}
