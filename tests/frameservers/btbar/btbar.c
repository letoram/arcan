#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

void redraw_cont(struct arcan_shmif_cont* c)
{
/* content is pratically broken for small windows */
	bool too_small = (c->h < 20 + 8 || c->w < 8);

	shmif_pixel clear = too_small ?
		SHMIF_RGBA(128, 128, 128, 255) : SHMIF_RGBA(0, 0, 0, 255);

	shmif_pixel tbar = SHMIF_RGBA(164, 164, 164, 255);
	shmif_pixel border = SHMIF_RGBA(64, 64, 64, 255);

/* clear */
	for (size_t y = 0; y < c->h; y++)
		for (size_t x = 0; x < c->w; x++){
			c->vidp[y * c->pitch + x] = clear;
	}

	if (too_small)
		return;

/* titlebar */
	for (size_t y = 0; y < 20 && y < c->h; y++)
		for (size_t x = 0; x < c->w; x++){
			c->vidp[y * c->pitch + x] = tbar;
		}

/* border */
	for (size_t y = 20; y < c->h - 4; y++){
		for (size_t x = 0; x < 4; x++){
			c->vidp[y * c->pitch + x] = border;
			c->vidp[y * c->pitch + c->w - x - 1] = border;
		}
	}
	for (size_t y = c->h - 5; y < c->h; y++){
		for (size_t x = 0; x < c->w; x++)
			c->vidp[y * c->pitch + x] = border;
	}
}

int dispatch_event(struct arcan_shmif_cont* c, arcan_event* ev)
{
	if (ev->category == EVENT_TARGET){
		switch (ev->tgt.kind){
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev->tgt.ioevs[0].iv && ev->tgt.ioevs[1].iv){
				arcan_shmif_resize(c, ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv);
				redraw_cont(c);
				return 1;
			}
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
			.title = "CSD test",
			.ident = ""
		}, sizeof(struct shmif_open_ext)
	);

/* populate the contents */
	arcan_event ev;
	redraw_cont(&cont);
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

	return EXIT_SUCCESS;
}
