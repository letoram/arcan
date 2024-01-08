#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

void run_frame(struct arcan_shmif_cont* c, uint64_t pos)
{
	uint8_t rgb[3] = {0};
	if (pos > 256){
		if (pos > 512){
			rgb[2] = pos - 512;
		}
		else
			rgb[1] = pos - 256;
	}
	else
		rgb[0] = pos;

	for (size_t row = 0; row < c->h; row++)
		for (size_t col = 0; col < c->w; col++){
		c->vidp[ row * c->pitch + col ] = SHMIF_RGBA(rgb[0], rgb[1], rgb[2], 0xff);
	}

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(STREAMSTATUS),
		.ext.streamstat.completion = (float)(pos+1.0) / 768.0
	};
	arcan_shmif_enqueue(c, &ev);

	arcan_shmif_signal(c, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
}

int main(int argc, char** argv)
{
	struct arcan_shmif_cont cont;
	uint8_t rgb[3];

	cont = arcan_shmif_open(SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);
	rgb[0] = rgb[1] = rgb[2] = 0;

	cont.hints = SHMIF_RHINT_VSIGNAL_EV | SHMIF_RHINT_IGNORE_ALPHA;
	arcan_shmif_resize(&cont, 640, 480);

	bool dirty = true;
	uint64_t position = 0;

	while(position < 768){
		if (dirty)
			dirty = (run_frame(&cont, ++position), 0);

		arcan_event ev;
		if(!arcan_shmif_wait(&cont, &ev))
			goto out;

		if (ev.category != EVENT_TARGET)
			continue;

		switch (ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			goto out;
		break;
		case TARGET_COMMAND_SEEKCONTENT:
			if (ev.tgt.ioevs[0].iv == 1){ /* absolute */
				if (ev.tgt.ioevs[1].fv >= 0 && ev.tgt.ioevs[1].fv <= 1.0){
					position = 768.0 * ev.tgt.ioevs[1].fv;
					dirty = true;
				}
				else if (ev.tgt.ioevs[0].iv == 0){ /* relative */
				}
			}
			else {
			}
		break;
		case TARGET_COMMAND_STEPFRAME:
			dirty = true;
		break;
		default:
		break;
		}
	}
out:
	return EXIT_SUCCESS;
}
