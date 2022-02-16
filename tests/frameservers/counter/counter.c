#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

bool run_frame(struct arcan_shmif_cont* c, uint8_t rgb[3])
{
	rgb[0]++;
	rgb[1] += rgb[0] == 255;
	rgb[2] += rgb[1] == 255;

	for (size_t row = 0; row < c->h; row++)
		for (size_t col = 0; col < c->w; col++){
		c->vidp[ row * c->pitch + col ] = SHMIF_RGBA(rgb[0], rgb[1], rgb[2], 0xff);
	}

	arcan_shmif_signal(c, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
	return true;
}

static void block_grab(struct arcan_shmif_cont* c, struct arcan_shmif_cont* d)
{
	arcan_shmif_enqueue(c,
		&(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_SEGREQ,
		.ext.segreq.kind = SEGID_APPLICATION
	});

	arcan_event ev;
	while (arcan_shmif_wait(c, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;
		if (ev.tgt.kind == TARGET_COMMAND_REQFAIL){
			fprintf(stderr, "request-failed on new segment request\n");
			break;
		}
		if (ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT){
			fprintf(stderr, "mapped new subsegment\n");
			*d = arcan_shmif_acquire(c, NULL, SEGID_GAME, 0);
			d->hints = SHMIF_RHINT_VSIGNAL_EV;
			arcan_shmif_resize(d, 320, 220);
			break;
		}
	}
}

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	bool running = true;

	size_t n_cont = 1;
	size_t cont_ofs = 1;

	if (argc > 1)
		n_cont = strtoul(argv[1], NULL, 10);

	if (n_cont == 0)
		return EXIT_FAILURE;

	struct {
		struct arcan_shmif_cont cont;
		uint8_t rgb[3];
	} cont[n_cont];

	cont[0].cont = arcan_shmif_open(SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);
	cont[0].rgb[0] = cont[0].rgb[1] = cont[1].rgb[2] = 0;
	cont[0].cont.hints = SHMIF_RHINT_VSIGNAL_EV;
	arcan_shmif_resize(&cont[0].cont, 640, 480);

	unsigned long long last = arcan_timemillis();
	while(running){
		size_t pending = cont_ofs;
		arcan_event ev;

/* throw out the requests, but delay! */
		if (n_cont > 1 && arcan_timemillis() - last > 1000){
			block_grab(&cont[0].cont, &cont[cont_ofs].cont);
			cont_ofs++;
			n_cont--;
			last = arcan_timemillis();
		}

/* this will trigger N vsignal events */
		for (size_t i = 0; i < cont_ofs; i++)
			run_frame(&cont[i].cont, cont->rgb);

/* then we collect them and continue when we have all */
		while (pending){
			for (size_t i = 0; i < cont_ofs && pending; i++){
				if(!arcan_shmif_wait(&cont[i].cont, &ev))
					goto out;

				if (ev.category != EVENT_TARGET)
					continue;

				switch (ev.tgt.kind){
				case TARGET_COMMAND_EXIT:
					goto out;
				break;
				case TARGET_COMMAND_STEPFRAME:
					if (pending)
						pending = pending - 1;
				break;
				default:
				break;
				}
			}
		}
	}
out:
	return EXIT_SUCCESS;
}
