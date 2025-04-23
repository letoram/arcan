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
	struct arcan_shmif_cont C;
	struct arcan_shmif_cont root;

	root = arcan_shmif_open(SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);
	block_grab(&root, &C);
	uint8_t col[3] = {120, 0, 0};

	run_frame(&C, col);
	arcan_event ev;

	while (arcan_shmif_wait(&C, &ev) > 0){
		if (ev.category == EVENT_TARGET)
			if (ev.tgt.kind == TARGET_COMMAND_STEPFRAME)
				run_frame(&C, col);
	}

out:
	return EXIT_SUCCESS;
}
