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

	arcan_event ev;
	bool running = true;

	arcan_shmif_resize(&cont, 320, 200);

/* fill with red and transfer */
	for (size_t row = 0; row < cont.addr->h; row++)
		for (size_t col = 0; col < cont.addr->w; col++)
			cont.vidp[ row * cont.addr->w + col ] = RGBA(255, 0, 0, 255);

	arcan_shmif_signal(&cont, SHMIF_SIGVID);

	while (running && arcan_event_wait(&cont.inev, &ev)){
		if (ev.category == EVENT_TARGET)
		switch (ev.kind){
		case TARGET_COMMAND_EXIT:
			running = false;
		break;
		}
	}

	return EXIT_SUCCESS;
}

