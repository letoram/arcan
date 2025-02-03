#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <pthread.h>

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

static void* segthread(void* c)
{
	struct arcan_shmif_cont* C = c;
	struct arcan_shmif_cont* P = C->user;

	struct arcan_event ev;
	uint8_t rgb[3] = {32, 32, 32};
	run_frame(C, rgb);

	while (arcan_shmif_wait(C, &ev) > 0){
		if (ev.category == EVENT_IO &&
			ev.io.datatype == EVENT_IDATATYPE_DIGITAL &&
			ev.io.input.digital.active){
			printf("send exit\n");
			arcan_shmif_lock(P);
				arcan_shmif_enqueue(P, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_EXIT
				});
			arcan_shmif_unlock(P);
		}
		run_frame(C, rgb);
	}

	printf("segthread over\n");
	arcan_shmif_drop(C);
	return NULL;
}

static void block_grab(struct arcan_shmif_cont* c, struct arcan_shmif_cont* d)
{
	arcan_shmif_enqueue(c,
		&(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_SEGREQ,
		.ext.segreq.kind = SEGID_GAME
	});

	arcan_event ev;
	while (arcan_shmif_wait(c, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;
		if (ev.tgt.kind == TARGET_COMMAND_REQFAIL){
			fprintf(stderr, "request-failed on new segment request\n");
			break;
		}
/* spawn segthread */
		if (ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT){
			fprintf(stderr, "mapped new subsegment\n");
			*d = arcan_shmif_acquire(c, NULL, SEGID_APPLICATION, 0);
			d->user = c;
			arcan_shmif_resize(d, 320, 220);
			pthread_t pth;
			pthread_attr_t pthattr;
			pthread_attr_init(&pthattr);
			pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
			pthread_create(&pth, &pthattr, segthread, d);
			break;
		}
	}
}

int main(int argc, char** argv)
{
	bool running = true;

	struct {
		struct arcan_shmif_cont cont;
		uint8_t rgb[3];
	} cont[2];

	cont[0].cont = arcan_shmif_open(SEGID_GAME, SHMIF_ACQUIRE_FATALFAIL, NULL);
	cont[0].rgb[0] = cont[0].rgb[1] = cont[1].rgb[2] = 0;
	arcan_shmif_resize(&cont[0].cont, 640, 480);

	block_grab(&cont[0].cont, &cont[1].cont);

	struct arcan_event ev;
	while(running){
		run_frame(&cont[0].cont, cont->rgb);
		if (!arcan_shmif_wait(&cont[0].cont, &ev)){
			printf("segment dead\n");
			running = false;
			break;
		}
		if (ev.category == EVENT_TARGET)
		switch (ev.tgt.kind){
			case TARGET_COMMAND_EXIT:
				printf("exit received\n");
				running = false;
			break;
			default:
			break;
		}
	}
	return EXIT_SUCCESS;
}
