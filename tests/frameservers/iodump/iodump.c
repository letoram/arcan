#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>
#include <inttypes.h>

static uint8_t mstate[ASHMIF_MSTATE_SZ];

const char* msub_to_lbl(int ind)
{
	switch(ind){
	case MBTN_LEFT_IND: return "left";
	case MBTN_RIGHT_IND: return "right";
	case MBTN_MIDDLE_IND: return "middle";
	case MBTN_WHEEL_UP_IND: return "wheel-up";
	case MBTN_WHEEL_DOWN_IND: return "wheel-down";
	default:
		return "unknown";
	}
}

static void dump_event(struct arcan_event ev)
{
	printf("%s\n", arcan_shmif_eventstr(&ev, NULL, 0));
}

static bool draw_box_px(
shmif_pixel* px, size_t pitch, size_t max_w, size_t max_h,
size_t x, size_t y, size_t w, size_t h, shmif_pixel col)
{
	if (x >= max_w || y >= max_h || x + w > max_w || y + h > max_h)
		return false;

	if (x + w > max_w - 1)
		w = max_w - x - 1;

	if (y + h > max_h - 1)
		h = max_h - y - 1;

	int ux = x + w > max_w ? max_w : x + w;
	int uy = y + h > max_h ? max_h : y + h;

	for (int cy = y; cy < uy; cy++)
		for (int cx = x; cx < ux; cx++)
			px[ cy * pitch + cx ] = col;

	return true;
}

static bool process_io(struct arcan_shmif_cont* c, struct arcan_event e)
{
	static uint8_t i_touch = 127;
	static uint8_t i_mouse = 127;

	if (e.category != EVENT_IO){
		if (e.category == EVENT_TARGET && e.tgt.kind == TARGET_COMMAND_DISPLAYHINT){
			if (e.tgt.ioevs[0].uiv && e.tgt.ioevs[1].uiv){
				return arcan_shmif_resize(c, e.tgt.ioevs[0].uiv, e.tgt.ioevs[1].uiv);
			}
		}
		return false;
	}

	int x = 0;
	int y = 0;
	shmif_pixel rgb = SHMIF_RGBA(0, 0, 0, 255);

	switch(e.io.datatype){
	case EVENT_IDATATYPE_ANALOG:
		if (e.io.devkind == EVENT_IDEVKIND_MOUSE){
			if (!arcan_shmif_mousestate(c, mstate, &e, &x, &y))
				return false;
			i_mouse++;
			rgb = SHMIF_RGBA(i_mouse, 0, 0, 255);
		}
		else
			return false;
	break;
	case EVENT_IDATATYPE_EYES:
	break;
	case EVENT_IDATATYPE_TOUCH:
		i_touch++;
		rgb = SHMIF_RGBA(0, 0, i_touch, 255);
		x = e.io.input.touch.x;
		y = e.io.input.touch.y;
	break;
	default:
		return false;
	}

	draw_box_px(c->vidp, c->pitch, c->w, c->h, x, y, 4, 4, rgb);
	return true;
}

int main(int argc, char** argv)
{
	int id = SEGID_APPLICATION;
	struct arg_arr* aarr;
	if (argc > 1){
		if (strcmp(argv[1], "-game") == 0)
			id = SEGID_GAME;
		else if (strcmp(argv[1], "-terminal") == 0)
			id = SEGID_TERMINAL;
		else if (strcmp(argv[1], "-vm") == 0)
			id = SEGID_VM;
		else{
			printf("usage: \n\tiodump to identify as normal application"
				"\n\tiodump -game to identify as game"
				"\n\tiodump -terminal to identify as terminal"
				"\n\tiodump -vm to identify as vm\n"
			);
				return EXIT_FAILURE;
			}
		}

	struct arcan_shmif_cont cont = arcan_shmif_open(
		id, SHMIF_ACQUIRE_FATALFAIL, &aarr);
	printf("open\n");

	arcan_shmif_mousestate_setup(&cont, false, mstate);
	arcan_event ev;

/* just send garbage so the correct events are being propagated */
	arcan_shmif_signal(&cont, SHMIF_SIGVID);
	printf("loop\n");
	while (arcan_shmif_wait(&cont, &ev)){
		dump_event(ev);
		bool dirty = process_io(&cont, ev);
		while (arcan_shmif_poll(&cont, &ev) > 0){
			dump_event(ev);
			dirty |= process_io(&cont, ev);
		}
		if (dirty)
			arcan_shmif_signal(&cont, SHMIF_SIGVID);
	}

	return EXIT_SUCCESS;
}
