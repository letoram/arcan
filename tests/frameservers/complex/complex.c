/*
 * this frameserver represents a complex and partly mischevious client
 *
 * testing:
 *  [ ] client- supplied borders
 *  [ ] client supplied mouse cursor
 *      [ ] with conflicting cursorhints
 *  [ ] clipboard
 *      [ ] cut
 *          [ ] spamming text
 *          [ ] images
 *          [ ] audio
 *          [ ] bchunk
 *      [ ] paste
 *          [ ] text
 *          [ ] images
 *          [ ] audio
 *          [ ] bchunk
 *  [ ] accessibility
 *  [ ] debug
 *  [ ] titlebar
 *  [ ] popup
 *  [ ] accelerated subsurface
 *  [ ] event-driven subwindow
 *  [ ] subwindow- spawn spam
 *  [ ] multiple windows on one buffer
 *  [ ] state load/store on main.
 *  [ ] scrollbar / content feedback support
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <pthread.h>
#include <arcan_shmif.h>

#include "font.h"

static void got_icon(struct arcan_shmif_cont cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(&cont, &ev)){
		printf("icon event(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(&cont);
}

static void got_status(struct arcan_shmif_cont cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(&cont, &ev)){
		printf("status event(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(&cont);
}

static void got_clipboard(struct arcan_shmif_cont cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(&cont, &ev)){
		printf("clipboard(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(&cont);
}

static void got_clipboard_paste(struct arcan_shmif_cont cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(&cont, &ev)){
		printf("clipboard(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(&cont);
}

static void got_accessibility(struct arcan_shmif_cont cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(&cont, &ev)){
		printf("accessib.(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(&cont);
}

static void got_cursor(struct arcan_shmif_cont cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(&cont, &ev)){
		printf("cursor.(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(&cont);
}

static void got_debug(struct arcan_shmif_cont cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(&cont, &ev)){
		printf("debug.(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(&cont);
}

/*
 * mapped:
 * knowned and fixed, reactive = don't request,
 * threaded = spawn handler in its own thread
 */
struct {
	bool mapped, reactive, threaded;
	uint32_t kind;
	uint32_t id;
	struct arcan_shmif_cont cont;
	void (*handler)(struct arcan_shmif_cont cont);
}
segtbl[] = {
	{
		.kind = SEGID_ICON,
		.id = 0xfeedface,
		.handler = got_icon,
		.threaded = true
	},
	{
		.kind = SEGID_TITLEBAR,
		.id = 0xbacabaca,
		.handler = got_status,
		.threaded = true
	},
	{
		.kind = SEGID_CLIPBOARD,
		.id = 0x12121212,
		.handler = got_clipboard,
		.threaded = true
	},
	{
		.kind = SEGID_CLIPBOARD_PASTE,
		.id = 0x21212121,
		.handler = got_clipboard_paste,
		.reactive = true
	},
	{
		.kind = SEGID_DEBUG,
		.id = 0xacacacac,
		.handler = got_debug,
		.reactive = true
	},
	{
		.kind = SEGID_ACCESSIBILITY,
		.id = 0xcacecace,
		.reactive = true,
		.handler = got_accessibility
	}
};

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	arcan_shmif_resize(&cont, 640, 480);

/* request all 'special types' */
	for (size_t i = 0; i < sizeof(segtbl)/sizeof(segtbl[0]); i++){
		arcan_event req = {
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = segtbl[i].kind,
			.ext.segreq.id = segtbl[i].id
		};
		if (!segtbl[i].reactive)
			arcan_shmif_enqueue(&cont, &req);
	}

/* draw border and hint that it is used */
	arcan_event ev;
	while(arcan_shmif_wait(&cont, &ev) != 0){
		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
		case TARGET_COMMAND_NEWSEGMENT:{
			for (size_t i = 0; i < sizeof(segtbl)/sizeof(segtbl[0]); i++){
/* FIXME: match against segtbl and ID */
				if (ev.tgt.ioev[1].iv == segtbl[i].id){
					printf("matched handler\n");
				}
			}
		}
		break;
		default:
		break;
		}
		else if (ev.category == EVENT_IO){
		}
		else
			;
/* if we receive the proper segment request, forward to the tbl */
	}
	arcan_shmif_drop(&cont);
	return EXIT_SUCCESS;
}
