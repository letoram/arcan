/*
 * [x] announce supported extensions (universal open)
 * [x] on enter, announce to save (universal save)
 * [ ] on mouse-click + motion (drag) announce bchunk-out on clipboard
 * [ ] on mouse-motion + drag gesture without button, visual signal drop
 *     square, on bchunk-in on clipboard, treat as drop
 */

#include <arcan_shmif.h>
#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include "../../../src/shmif/arcan_tuisym.h"

/* reuse TUI code for monospace text rendering */
#include "pixelfont.h"
#include "draw.h"

static struct tui_pixelfont* font;

static shmif_pixel palette[] = {
	SHMIF_RGBA(0xef, 0xd4, 0x69, 0xff),
	SHMIF_RGBA(0x43, 0xab, 0xc9, 0xff),
	SHMIF_RGBA(0xcd, 0x59, 0x4a, 0xff),
	SHMIF_RGBA(0xb5, 0xc6, 0x89, 0xff),
	SHMIF_RGBA(0xf5, 0x8b, 0x4c, 0xff),
	SHMIF_RGBA(0xed, 0x67, 0x85, 0xff),
	SHMIF_RGBA(0xd0, 0xd0, 0xd0, 0xff)
};

struct region {
	size_t x1, y1, x2, y2;
	int fd;
/* only color for now, should be able to get raw pixel region as well
 * from parent, but arcan lacks the API to make that possible */
	shmif_pixel color;
	char* label;
	bool active;
};
static struct region* focus_item;
static uint8_t mstate[ASHMIF_MSTATE_SZ];
static int mouse_x, mouse_y;
static bool mouse_drag;

struct region regions[32];
static size_t font_w, font_h;

/*
 * mouse picking
 */
static struct region* region_at(size_t x, size_t y)
{
	if (focus_item){
		if (x >= focus_item->x1 && y >= focus_item->y1 &&
			x <= focus_item->x2 && y <= focus_item->y2)
			return focus_item;
	}

	for (size_t i = 0; i < 32; i++){
		if (regions[i].active &&
			x >= regions[i].x1 && x <= regions[i].x2 &&
			y >= regions[i].y1 && y <= regions[i].y2)
			return &regions[i];
	}

	return NULL;
}

static void draw_item(
	struct arcan_shmif_cont* dst, struct region* R, bool sel)
{
	const char* label = (R->label && R->label[0]) ? R->label : "unknown";
	size_t pxw = font_w * strlen(label);
	shmif_pixel fg, bg;
	if (sel){
		bg = R->color;
		fg = SHMIF_RGBA(0x00, 0x00, 0x00, 0xff);
	}
	else {
		fg = R->color;
		bg = SHMIF_RGBA(0x00, 0x00, 0x00, 0xff);
	}

	size_t i = 0;
	do {
		tui_pixelfont_draw(font, dst->vidp, dst->pitch, label[i],
			R->x1 + i * font_w, R->y1, fg, bg, dst->w, dst->h, false);
	} while(label[++i]);

	R->y2 = R->y1 + font_h;
	R->x2 = R->x1 + i * font_w;
}

static void draw(struct arcan_shmif_cont* dst)
{
	shmif_pixel bgcol = SHMIF_RGBA(0x10, 0x10, 0x10, 0xff);

/* just a test-app, be inefficient */
	draw_box(dst, 0, 0, dst->w, dst->h, bgcol);

	for (size_t i = 0; i < 32; i++){
		if (!regions[i].active || &regions[i] == focus_item)
			continue;
		draw_item(dst, &regions[i], false);
	}

/* always draw focus item last */
	if (focus_item)
		draw_item(dst, focus_item, true);

	arcan_shmif_signal(dst, SHMIF_SIGVID);
}

static void add_region(
	size_t x1, size_t y1, size_t x2, size_t y2, char* desc, int fd)
{
	size_t i;
	for (i = 0; i < sizeof(regions)/sizeof(regions[0]); i++){
		if (!regions[i].active)
			break;
	}
	if (i >= sizeof(regions)/sizeof(regions[0])){
		close(fd);
		return;
	}

	regions[i] = (struct region){
		.x1 = 0, .y1 = 0,
		.x2 = 0, .y2 = 0, // invisible until drawn
		.label = desc,
		.active = true,
		.fd = fd,
		.color = palette[i % (sizeof(palette)/sizeof(palette[0]))]
	};
}

static void reposition_regions(size_t w, size_t h)
{
	for (size_t i = 0; i < sizeof(regions)/sizeof(regions[0]); i++){
		if (regions[i].x2 > w){
		}
		if (regions[i].y2 > h){
		}
	}
}

static bool request_out(struct arcan_shmif_cont* cont, struct arcan_event* ev)
{
	if (!focus_item)
		return false;

	int fd_out = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
	if (fd_out == -1){
		return false;
	}

	int fd_in = arcan_shmif_dupfd(focus_item->fd, -1, true);
	arcan_shmif_bgcopy(cont, fd_in, fd_out, -1, 0);
	return true;
}

bool run_event(struct arcan_shmif_cont* cont, struct arcan_event* ev)
{
	if (ev->category == EVENT_IO){
		if (ev->io.devkind == EVENT_IDEVKIND_MOUSE){
			if (ev->io.datatype == EVENT_IDATATYPE_ANALOG){
				arcan_shmif_mousestate(cont, mstate, ev, &mouse_x, &mouse_y);
				if (focus_item && mouse_drag){
					focus_item->x1 = mouse_x;
					focus_item->y1 = mouse_y;
					return true;
				}
			}
			else if (ev->io.subid == MBTN_LEFT_IND){
				mouse_drag = ev->io.input.digital.active;
				struct region* reg = region_at(mouse_x, mouse_y);
				if (!reg){
					if (focus_item){
						focus_item = NULL;
						return true;
					}
				}
/* enter drag- state, if we right- drag we indicate that it is a drag-
 * action, otherwise we just move it around */
				else if (mouse_drag && reg != focus_item){
					focus_item = reg;
					return true;
				}
			}
		}
/* on keyboard- enter, request another universal "pick" */
		else if (ev->io.datatype == EVENT_IDATATYPE_TRANSLATED){
			if (ev->io.input.translated.keysym == TUIK_RETURN && ev->io.input.translated.active){
				arcan_shmif_enqueue(cont, &(struct arcan_event){
					.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
					.category = EVENT_EXTERNAL,
					.ext.bchunk = {
						.extensions = "*",
						.input = false
					}
				});
			}
		}
	}
	if (ev->category == EVENT_TARGET){
		switch (ev->tgt.kind){
/* got a load operation */
			case TARGET_COMMAND_BCHUNK_IN:
				add_region(0, 0, 128, 200, "test", arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true));
				return true;
			break;
			case TARGET_COMMAND_DISPLAYHINT:
				if (ev->tgt.ioevs[0].iv && ev->tgt.ioevs[1].iv){
					arcan_shmif_resize(cont, ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv);
					reposition_regions(cont->w, cont->h);
					return true;
				}
			break;
/* got a store operation, dispatch to copy thread */
			case TARGET_COMMAND_BCHUNK_OUT:
				request_out(cont, ev);
			break;
			case TARGET_COMMAND_EXIT:
			break;
/* got ourselves a copyboard or a pasteboard */
			case TARGET_COMMAND_NEWSEGMENT:
			break;
			default:
			break;
		}
	}
	return false;
}

int main(int argc, char** argv)
{
	struct arcan_shmif_cont cont = arcan_shmif_open_ext(
		SHMIF_ACQUIRE_FATALFAIL, NULL, (struct shmif_open_ext )
		{.type = SEGID_APPLICATION}, sizeof(struct shmif_open_ext)
	);

	arcan_shmif_mousestate_setup(&cont, false, mstate);

/* need something to draw */
	struct arcan_shmif_initial* init;
	arcan_shmif_initial(&cont, &init);
	font = tui_pixelfont_open(64);
	size_t px_sz = ceilf(init->fonts[0].size_mm * 0.03527778 * init->density);
	tui_pixelfont_setsz(font, px_sz, &font_w, &font_h);

	draw(&cont);

	printf("announce in 3\n");
	sleep(3);

/* announce bchunk request, immediate, for open */
	arcan_shmif_enqueue(&cont, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.category = EVENT_EXTERNAL,
		.ext.bchunk = {
			.extensions = "*",
			.input = true
		}
	});

/* request a clipboard as a means of dealing with drop */

	arcan_event ev;
	while (arcan_shmif_wait(&cont, &ev)){
		bool dirty = run_event(&cont, &ev);

		while (arcan_shmif_poll(&cont, &ev) > 0)
			dirty = run_event(&cont, &ev);

		if (dirty)
			draw(&cont);
	}

	arcan_shmif_drop(&cont);
	return 0;
}
