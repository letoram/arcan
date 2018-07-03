#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

static void fill(struct arcan_shmif_cont* c)
{
	shmif_pixel col = SHMIF_RGBA(127, random() % 255, random() % 255, 255);
	for (size_t y = 0; y < c->h; y++)
		for (size_t x = 0; x < c->w; x++)
			c->vidp[y * c->pitch + x] = col;

	arcan_shmif_signal(c, SHMIF_SIGVID);
}

static void clock_tick(struct arcan_shmif_cont* c)
{
	static int counter = 1000;
	counter = counter - 1;
	if (counter == 0){
		arcan_shmif_last_words(c, "I regret nothing!");
		exit(EXIT_FAILURE);
	}
	if (counter % 100 == 0){
		printf("sent notification (@%d)\n", counter);
		arcan_shmif_enqueue(c, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(ALERT),
			.ext.message = {"this is a notification"}
		});
	}
}

int dispatch_event(struct arcan_shmif_cont* c, arcan_event* ev)
{
	if (ev->category == EVENT_TARGET){
		switch (ev->tgt.kind){
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev->tgt.ioevs[0].iv && ev->tgt.ioevs[1].iv){
				arcan_shmif_resize(c, ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv);
				fill(c);
				return 1;
			}
		break;

		case TARGET_COMMAND_STEPFRAME:
			clock_tick(c);
		break;

		default:
		break;
		}
	}
/* just some effect to show that we get input */
	else if (ev->category == EVENT_IO){
		shmif_pixel col = SHMIF_RGBA(255, 255, 255, 255);
		c->vidp[(random() % c->h) * c->pitch + (random() % c->w)] = col;
		return 1;
	}
	return 0;
}

int main(int argc, char** argv)
{
	struct arcan_shmif_cont cont = arcan_shmif_open_ext(
		SHMIF_ACQUIRE_FATALFAIL, NULL, (struct shmif_open_ext){
			.type = SEGID_APPLICATION,
			.title = "Last Word",
			.ident = "bla"
		}, sizeof(struct shmif_open_ext)
	);

/* request a timer */
	arcan_shmif_enqueue(&cont, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = 1
	});

/* populate the contents */
	arcan_event ev;
	fill(&cont);
	arcan_shmif_signal(&cont, SHMIF_SIGVID);

/* simple block-flush-update loop */
	int dirty = 0;
	while (arcan_shmif_wait(&cont, &ev) != 0){
		dirty |= dispatch_event(&cont, &ev);
		while (arcan_shmif_poll(&cont, &ev) > 0)
			dirty |= dispatch_event(&cont, &ev);
		if (dirty){
			arcan_shmif_signal(&cont, SHMIF_SIGVID);
			dirty = 0;
		}
	}

	arcan_shmif_drop(&cont);
	return EXIT_SUCCESS;
}
