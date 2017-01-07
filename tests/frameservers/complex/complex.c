/*
 * this frameserver represents a complex and partly mischevious client
 *
 * testing:
 *  [x] client- supplied borders
 *  [x] client supplied mouse cursor
 *      [x] with conflicting cursorhints
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
 *  [x] titlebar
 *  [x] animated icon, with alert
 *  [ ] popup
 *  [ ] accelerated subsurface
 *  [ ] subwindow- spawn spam
 *  [ ] multiple windows on one buffer
 *  [ ] state load/store on main.
 *  [ ] scrollbar / content feedback support
 */

#include <arcan_shmif.h>
#include <pthread.h>

#include "font.h"

static void got_icon(struct arcan_shmif_cont* cont)
{
	char buf[256];
	arcan_shmif_enqueue(cont, &(arcan_event){
		.ext.kind = ARCAN_EVENT(CLOCKREQ), .ext.clock.rate = 20});

	uint8_t gv = 0;
	draw_box(cont, 0, 0, cont->w, cont->h, SHMIF_RGBA(0, 128, 0, 255));
	arcan_shmif_signal(cont, SHMIF_SIGVID);

	arcan_event ev;
	while (arcan_shmif_wait(cont, &ev)){
		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
/* synch icon dimensions with displayhint */
		case TARGET_COMMAND_DISPLAYHINT:
			arcan_shmif_resize(cont,
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
		break;
		case TARGET_COMMAND_STEPFRAME:
/* repeat "fire-once" event time with some pseudorandom */
			if (ev.tgt.ioevs[1].iv > 1){
				arcan_shmif_enqueue(cont, &(arcan_event){
						.ext.kind = ARCAN_EVENT(CLOCKREQ),
						.ext.clock.once = true,
						.ext.clock.rate = 32 + (random() % 100)
					}
				);
				arcan_shmif_enqueue(cont, &(arcan_event){
					.ext.kind = ARCAN_EVENT(MESSAGE),
					.ext.message.data = "alert"
				});
			}
/* for the periodic, just cycle a color */
			else{
				gv = (gv + 32) % 127;
				draw_box(cont,
					0, 0, cont->w, cont->h, SHMIF_RGBA(0, 128 + gv, 0, 255));
				arcan_shmif_signal(cont, SHMIF_SIGVID);
			}
		break;
		default:
			printf("icon event(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
		break;
		}
	}

	arcan_shmif_drop(cont);
	free(cont);
}

static void got_title(struct arcan_shmif_cont* cont)
{
	draw_box(cont, 0, 0, cont->w, cont->h, SHMIF_RGBA(69, 47, 47, 255));
	draw_text(cont, "Custom Titlebar", 2, 2, SHMIF_RGBA(255, 255, 255, 255));
	arcan_shmif_signal(cont, SHMIF_SIGVID);

/* request new segments inside the titlebar to test if the running appl
 * ignores more complex hiearchies */
	arcan_shmif_enqueue(cont, &(arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = SEGID_UNKNOWN
	});
	arcan_shmif_enqueue(cont, &(arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = SEGID_TITLEBAR
	});

	arcan_event ev;
	while (arcan_shmif_wait(cont, &ev)){
		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
/* synch icon dimensions with displayhint */
		case TARGET_COMMAND_DISPLAYHINT:
			arcan_shmif_resize(cont,
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
			draw_box(cont, 0, 0, cont->w, cont->h, SHMIF_RGBA(69, 47, 47, 255));

/* instead of drawing text, update IDENT so the user- set font can be used */
			arcan_shmif_enqueue(cont, &(arcan_event){
				.ext.kind = ARCAN_EVENT(IDENT),
				.ext.message.data = "titlebar- test"
			});
			arcan_shmif_signal(cont, SHMIF_SIGVID);
		break;
		default:
		break;
		}
	}
	arcan_shmif_drop(cont);
	free(cont);
}

static void got_clipboard(struct arcan_shmif_cont* cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(cont, &ev)){
		printf("clipboard(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(cont);
	free(cont);
}

static void got_clipboard_paste(struct arcan_shmif_cont* cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(cont, &ev)){
		printf("clipboard(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(cont);
	free(cont);
}

static void got_accessibility(struct arcan_shmif_cont* cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(cont, &ev)){
		printf("accessib.(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(cont);
	free(cont);
}

static void got_cursor(struct arcan_shmif_cont* cont)
{
	arcan_event ev;
	char buf[256];

	draw_box(cont, 0, 0, cont->w, cont->h, SHMIF_RGBA(255, 255, 0, 255));
	arcan_shmif_signal(cont, SHMIF_SIGVID);

	while (arcan_shmif_wait(cont, &ev)){
		printf("cursor.(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(cont);
	free(cont);
}

static void got_debug(struct arcan_shmif_cont* cont)
{
	arcan_event ev;
	char buf[256];

	while (arcan_shmif_wait(cont, &ev)){
		printf("debug.(%s)\n", arcan_shmif_eventstr(&ev, buf, sizeof(buf)));
	}
	arcan_shmif_drop(cont);
	free(cont);
}

static void update_surf(struct arcan_shmif_cont* cont, size_t border)
{
	if (border)
		draw_box(cont, 0,0, cont->w, cont->h, SHMIF_RGBA(0x00, 0xff, 0x00, 0xff));

	shmif_pixel* vidp = cont->vidp;
	for (size_t y = border; y < cont->h - border; y++){
		float lf_y = (float)y / (cont->h - border - border);

		for (size_t x = border; x < cont->w - border; x++){
			float lf_x = (float)x / (cont->w - border - border);
			vidp[y * cont->pitch + x] = SHMIF_RGBA(
				x*255.0, y*255.0, 0, lf_x * lf_y * 255.0);
		}
	}

	arcan_shmif_signal(cont, SHMIF_SIGVID);
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
	uint16_t width, height;
	struct arcan_shmif_cont cont;
	void (*handler)(struct arcan_shmif_cont* cont);
}
segtbl[] = {
	{
		.kind = SEGID_ICON,
		.id = 0xfeedface,
		.handler = got_icon,
		.width = 64,
		.height = 64,
		.threaded = true
	},
	{
		.kind = SEGID_TITLEBAR,
		.id = 0xbacabaca,
		.handler = got_title,
		.threaded = true
	},
	{
		.kind = SEGID_CLIPBOARD,
		.id = 0x12121212,
		.handler = got_clipboard,
		.threaded = true
	},
	{
		.kind = SEGID_CURSOR,
		.id = 0xdadadada,
		.handler = got_cursor,
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

static const char* cursors[] = {
	"normal", "wait", "select-inv", "select", "up", "down",
	"left-right", "drag-up-down", "drag-up", "drag-down", "drag-left",
	"drag-right", "drag-left-right", "rotate-cw", "rotate-ccw", "normal-tag",
	"diag-ur", "diag-ll", "drag-diag", "datafield", "move", "typefield",
	"forbiden", "help", "vertical-datafield", "drag-drop", "drag-reject"
};
static size_t cursor_ind;

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	size_t border_sz = 0;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	arcan_shmif_enqueue(&cont, &(arcan_event){
		.ext.kind = ARCAN_EVENT(CLOCKREQ), .ext.clock.rate = 40});

/* default static properties to send on connection */
	struct arcan_event etbl[] = {
		{
			.ext.kind = ARCAN_EVENT(IDENT),
			.ext.message.data = "complex-test"
		},
		{
			.ext.kind = ARCAN_EVENT(COREOPT),
			.ext.message.data = "0:key:testopt"
		},
		{
			.ext.kind = ARCAN_EVENT(COREOPT),
			.ext.message.data = "0:descr:some kv option"
		},
		{
			.ext.kind = ARCAN_EVENT(COREOPT),
			.ext.message.data = "0:arg:val_1|val_2|val_3"
		},
		{
			.ext.kind = ARCAN_EVENT(STATESIZE),
			.ext.stateinf.size = 4096,
			.ext.stateinf.type = 0xff
		},
		{
			.ext.kind = ARCAN_EVENT(LABELHINT),
			.ext.labelhint.label = "SCROLL_UP",
			.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
		},
		{
			.ext.kind = ARCAN_EVENT(LABELHINT),
			.ext.labelhint.label = "SCROLL_DOWN",
			.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
		},
	};

	arcan_shmif_resize(&cont, 640, 480);

/* request all 'special types' */
	for (size_t i = 0; i < sizeof(segtbl)/sizeof(segtbl[0]); i++){
		if (!segtbl[i].reactive)
			arcan_shmif_enqueue(&cont, &(arcan_event) {
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = segtbl[i].kind,
			.ext.segreq.id = segtbl[i].id,
			.ext.segreq.width = segtbl[i].width,
			.ext.segreq.height = segtbl[i].height
		});
	}

/* define viewport that takes border into account */
	arcan_shmif_enqueue(&cont, &(arcan_event){
		.ext.kind = ARCAN_EVENT(VIEWPORT),
		.ext.viewport = {.w = 640, .h = 480, .border = 5}
	});

	for (size_t i = 0; i < sizeof(etbl)/sizeof(etbl[0]); i++)
		arcan_shmif_enqueue(&cont, &etbl[i]);

/* draw border and hint that it is used */
	arcan_event ev;
	while(arcan_shmif_wait(&cont, &ev) != 0){
		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
		case TARGET_COMMAND_NEWSEGMENT:
			for (size_t i = 0; i < sizeof(segtbl)/sizeof(segtbl[0]); i++){
/* map if req-id matches or (type+reactive) */
				if (segtbl[i].id == ev.tgt.ioevs[0].iv ||
					(segtbl[i].reactive && ev.tgt.ioevs[2].iv == segtbl[i].kind)){
					struct arcan_shmif_cont* tc = malloc(sizeof(struct arcan_shmif_cont));
					*tc = arcan_shmif_acquire(&cont,
						NULL, segtbl[i].kind, SHMIF_DISABLE_GUARD);
					if (!tc->vidp)
						free(tc);
					else {
						pthread_t pth;
						pthread_create(&pth, NULL, (void*) segtbl[i].handler, tc);
						pthread_detach(pth);
					}
				}
			}
		break;
		case TARGET_COMMAND_STEPFRAME:
/* on timer, rotate custom mouse cursor and change border area */
			if (ev.tgt.ioevs[1].iv > 1){
				static bool cflip;
				arcan_event ev = {.ext.kind = ARCAN_EVENT(CURSORHINT)};
				cflip = !cflip;
				if (cflip)
					memcpy(ev.ext.message.data, "custom", 6);
				else{
					memcpy(ev.ext.message.data,
						cursors[cursor_ind], strlen(cursors[cursor_ind]));
					cursor_ind = (cursor_ind+1) % (sizeof(cursors)/sizeof(cursors[0]));
				}
			}
			border_sz = (border_sz + 2) % 10;
			arcan_shmif_enqueue(&cont, &ev);
			arcan_shmif_enqueue(&cont, &(arcan_event){
				.ext.kind = ARCAN_EVENT(VIEWPORT),
				.ext.viewport.w = cont.w,
				.ext.viewport.h = cont.h,
				.ext.viewport.border = border_sz
			});
			update_surf(&cont, border_sz);
		break;

		default:
		break;
		}
		else if (ev.category == EVENT_IO){
/* mouse cursor implementation, use position to send update to cursor
 * subsegment (if present), right click in one quanta to set popup.. these are
 * expensive on purpose . Scroll UP ->update content hint, Scroll Down ->
 * update content hint */
		}
		else
			;
/* if we receive the proper segment request, forward to the tbl */
/* send CURSORHINT with cycle from the list */
	}
	arcan_shmif_drop(&cont);
	return EXIT_SUCCESS;
}
