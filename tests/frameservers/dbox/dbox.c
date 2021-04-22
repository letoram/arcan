/*
 * A wandering box test that deals with dirty rectangles
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

static size_t box_x;
static size_t box_y;
static bool reset = true;

static shmif_pixel bgcol = SHMIF_RGBA(32, 32, 32, 255);
static shmif_pixel boxcol = SHMIF_RGBA(64, 128, 64, 255);

static bool draw_box_px(
shmif_pixel* px, size_t pitch, size_t max_w, size_t max_h,
size_t x, size_t y, size_t w, size_t h, shmif_pixel col)
{
	if (x >= max_w || y >= max_h)
		return false;

	int ux = x + w > max_w ? max_w : x + w;
	int uy = y + h > max_h ? max_h : y + h;

	for (int cy = y; cy < uy; cy++)
		for (int cx = x; cx < ux; cx++)
			px[ cy * pitch + cx ] = col;

	return true;
}

static bool draw_box(struct arcan_shmif_cont* c,
	size_t x, size_t y, int w, int h, shmif_pixel col)
{
	return draw_box_px(c->vidp, c->pitch, c->w, c->h, x, y, w, h, col);
}

void run_frame(struct arcan_shmif_cont* c)
{
	draw_box(c, box_x, box_y, 32, 32, bgcol);
	c->dirty.x1 = box_x;
	c->dirty.y1 = box_y;
	c->dirty.x2 = box_x + 32 + 8;
	c->dirty.y2 = box_y + 32 + 8;

	box_x += 8;
	box_y += 8;

	if (box_x >= c->w){
		box_x = random() % (c->w - 32);
		reset = true;
	}

	if (box_y >= c->h){
		box_y = random() % (c->h - 32);
		reset = true;
	}

	if (reset){
		c->dirty.x1 = 0;
		c->dirty.y1 = 0;
		c->dirty.x2 = c->w;
		c->dirty.y2 = c->h;
		bgcol = SHMIF_RGBA(32 + random() % 224, 64 + random() % 196, 32 + random() % 224, 0xff);
		draw_box(c, 0, 0, c->w, c->h, bgcol);
		reset = false;
	}

	draw_box(c, box_x, box_y, 32, 32, boxcol);

	arcan_shmif_signal(c, SHMIF_SIGVID);
}

int main(int argc, char** argv)
{
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);

/* event- frame clock + dirty updates */
	cont.hints = SHMIF_RHINT_SUBREGION | SHMIF_RHINT_IGNORE_ALPHA | SHMIF_RHINT_VSIGNAL_EV;
	draw_box(&cont, cont.w, cont.h, 32, 32, boxcol);

/* enable the hints and send contents */
	arcan_shmif_resize(&cont, cont.w, cont.h);
	arcan_shmif_signal(&cont, SHMIF_SIGVID);

	struct arcan_event ev;
	while (arcan_shmif_wait(&cont, &ev)){
		switch (ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			goto out;
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev.tgt.ioevs[0].iv > 32 && ev.tgt.ioevs[1].iv > 32){
				arcan_shmif_resize(&cont, ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
				reset = true;
				run_frame(&cont);
			}
		break;
		case TARGET_COMMAND_RESET:
			reset = true;
			run_frame(&cont);
		break;
		case TARGET_COMMAND_STEPFRAME:
			run_frame(&cont);
		break;

		default:
		break;
		}
	}
out:
	return EXIT_SUCCESS;
}
