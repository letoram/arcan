#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"
#include "../screen/libtsm.h"
#include "../../arcan_tui_copywnd.h"
#include <math.h>
#include <pthread.h>

static void display_hint(struct tui_context* tui, arcan_tgtevent* ev)
{
/* first, are other dimensions than our current ones requested? */
	int w = ev->ioevs[0].iv ? ev->ioevs[0].iv : tui->acon.w;
	int h = ev->ioevs[1].iv ? ev->ioevs[1].iv : tui->acon.h;
	bool cell_changed = false;

/* did we get an updated cell-state and we are in server-side rendering? */
	int hcw = ev->ioevs[5].iv;
	int hch = ev->ioevs[6].iv;
	if (tui->rbuf_fwd && hcw > 0 && tui->cell_w != hcw){
		cell_changed = true;
		tui->cell_w = hcw;
	}
	if (tui->rbuf_fwd && hch > 0 && tui->cell_h != hch){
		cell_changed = true;
		tui->cell_h = hch;
	}

/* anything that would case relayout, resize, renegotiation */
	if (cell_changed ||
		(abs((int)w - (int)tui->acon.w) > 0) ||
		(abs((int)h - (int)tui->acon.h) > 0))
	{
/* realign against grid and clamp */
		size_t rows = h / tui->cell_h;
		size_t cols = w / tui->cell_w;
		if (!rows)
			rows++;
		if (!cols)
			cols++;

		LOG("cell-change: %zu*%zu @ %d:%d\n", rows, cols, tui->cell_w, tui->cell_h);

/* and communicate our cell dimensions back as well as the resolved size */
		if (arcan_shmif_resize_ext(&tui->acon,
			cols * tui->cell_w, rows * tui->cell_h,
			(struct shmif_resize_ext){
				.vbuf_cnt = -1,
				.abuf_cnt = -1,
				.rows = rows,
				.cols = cols
			}))
			tui_screen_resized(tui);
	}

/* Then we have visibility states, there is a handler for it so some
 * interactive clients won't draw when they are not visibile, forward
 * to those. Otherwise just say that the cursor state has changed */
	bool update = false;

	if ((ev->ioevs[2].iv & 2) ^ tui->inactive){
		tui->inactive = (ev->ioevs[2].iv & 2);
		tui->dirty |= DIRTY_CURSOR;
		if (tui->handlers.visibility)
			tui->handlers.visibility(tui, !tui->inactive, !tui->defocus, tui->handlers.tag);
	}

	if ((ev->ioevs[2].iv & 4) ^ tui->defocus){
		tui->defocus = ev->ioevs[2].iv & 4;
		tui->dirty |= DIRTY_CURSOR;
		tui->modifiers = 0;
	}

/* did we get an update indicating that the screen density changed? that
 * will affect the font manager, which in turn may try and resize the screen */
	if (ev->ioevs[4].fv > 0 && fabs(ev->ioevs[4].fv - tui->ppcm) > 0.01){
		float sf = tui->ppcm / ev->ioevs[4].fv;
		tui->ppcm = ev->ioevs[4].fv;
		tui_fontmgmt_invalidate(tui);
	}
}

static int segid_to_tuiid(int segid)
{
	switch(segid){
	case SEGID_TUI:
	return TUI_WND_TUI;
	case SEGID_POPUP:
	return TUI_WND_POPUP;
	case SEGID_DEBUG:
	return TUI_WND_DEBUG;
	case SEGID_HANDOVER:
	return TUI_WND_HANDOVER;
	}
	return SEGID_UNKNOWN;
}

/* cursor blinking is thus far implemented here, should be moved server-side
 * as an idle-cursor state */
static void tick_cursor(struct tui_context* tui)
{
	if (!tui->cursor_period)
		return;

	if (!tui->defocus){
		tui->inact_timer++;
		if (tui->sbofs != 0){
			tui->cursor_off = true;
		}
		else
			tui->cursor_off = tui->inact_timer > 1 ? !tui->cursor_off : false;
	}

	tui->cursor_upd = true;
	tui->dirty |= DIRTY_CURSOR;
}

static void drop_pending(struct tsm_save_buf** tui)
{
	if (!*tui)
		return;

	free((*tui)->metadata);
	free((*tui)->scrollback);
	free((*tui)->screen);
	free(*tui);
	*tui = NULL;
}

/* this is raw without formatting */
struct dump_thread_data {
	FILE* fpek;
	char* outb;
	size_t sz;
};

static void* copy_thread(void* in)
{
	struct dump_thread_data* din = in;
	fwrite(din->outb, din->sz, 1, din->fpek);
	fclose(din->fpek);
	free(din->outb);
	free(din);
	return NULL;
}

static void dump_to_fd(struct tui_context* tui, int fd)
{
	if (-1 == fd)
		return;

	FILE* fpek = fdopen(fd, "w");
	if (!fpek){
		close(fd);
		return;
	}

	char* outb = malloc(tui->rows * tui->cols * 4 + tui->rows);
	if (!outb){
		fclose(fpek);
		return;
	}
	size_t ofs = 0;

	struct tui_cell* front = tui->front;
	for (size_t row = 0; row < tui->rows; row++){
		for (size_t col = 0; col < tui->cols; col++){
			char out[4];
			size_t nb = arcan_tui_ucs4utf8(front->ch, out);
			if (out[0]){
				memcpy(&outb[ofs], out, nb);
				ofs += nb;
			}
			else
				outb[ofs++] = ' ';
			front++;
		}
		outb[ofs++] = '\n';
	}

/* go with writer thread */
	struct dump_thread_data* data = malloc(sizeof(struct dump_thread_data));
	if (!data)
		goto block_dump;

	*data = (struct dump_thread_data){
		.outb = outb,
		.fpek = fpek,
		.sz = ofs
	};

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
/* if it worked, it is up to the thread now */
	if (-1 != pthread_create(&pth, &pthattr, copy_thread, data)){
		return;
	}

/* fallback to a block write */
block_dump:
	free(data);
	fwrite(outb, ofs, 1, fpek);
	fclose(fpek);
	free(outb);
}

static void target_event(struct tui_context* tui, struct arcan_event* aev)
{
	arcan_tgtevent* ev = &aev->tgt;

	switch (ev->kind){
/* GRAPHMODE is here used to signify a buffered update of the colors */
	case TARGET_COMMAND_GRAPHMODE:
		if (ev->ioevs[0].iv == 0){
			if (tui->handlers.recolor)
				tui->handlers.recolor(tui, tui->handlers.tag);
		}
		else if (ev->ioevs[0].iv == 1){
			tui->alpha = ev->ioevs[1].fv;
			tui->dirty = DIRTY_FULL;
		}
		else if (ev->ioevs[0].iv <= TUI_COL_INACTIVE){
			tui->colors[ev->ioevs[0].iv].rgb[0] = ev->ioevs[1].iv;
			tui->colors[ev->ioevs[0].iv].rgb[1] = ev->ioevs[2].iv;
			tui->colors[ev->ioevs[0].iv].rgb[2] = ev->ioevs[3].iv;
		}
	break;

/* sigsuspend to group */
	case TARGET_COMMAND_PAUSE:
		if (tui->handlers.exec_state)
			tui->handlers.exec_state(tui, 1, tui->handlers.tag);
	break;

/* sigresume to session */
	case TARGET_COMMAND_UNPAUSE:
		if (tui->handlers.exec_state)
			tui->handlers.exec_state(tui, 0, tui->handlers.tag);
	break;

	case TARGET_COMMAND_RESET:
		tui->modifiers = 0;
		switch(ev->ioevs[0].iv){
		case 0:
		case 1:
			if (tui->handlers.reset)
				tui->handlers.reset(tui, ev->ioevs[0].iv, tui->handlers.tag);
		break;

/* hard reset / crash recovery (server-side state lost) */
		case 2:
		case 3:
			if (tui->handlers.reset)
				tui->handlers.reset(tui, ev->ioevs[0].iv, tui->handlers.tag);
			arcan_shmif_drop(&tui->clip_in);
			arcan_shmif_drop(&tui->clip_out);
			tui_queue_requests(tui, true, true);
		break;
		}
		tui->dirty = DIRTY_FULL;
	break;

/* 'drag-and-drop' style data transfer requests */
	case TARGET_COMMAND_BCHUNK_IN:
		if (tui->handlers.bchunk)
			tui->handlers.bchunk(tui, true,
				ev->ioevs[1].iv | (ev->ioevs[2].iv << 31),
				ev->ioevs[0].iv,
				ev->message,
				tui->handlers.tag
			);
		break;
	case TARGET_COMMAND_BCHUNK_OUT:
/* overload custom bchunk handler */
		if (strcmp(ev->message, "tuiraw") == 0){
			dump_to_fd(tui, arcan_shmif_dupfd(ev->ioevs[0].iv, -1, false));
		}
		if (tui->handlers.bchunk)
			tui->handlers.bchunk(tui, false,
				ev->ioevs[1].iv | (ev->ioevs[2].iv << 31),
				ev->ioevs[0].iv,
				ev->message,
				tui->handlers.tag
			);
	break;

/* scrolling- command */
	case TARGET_COMMAND_SEEKCONTENT:
		if (ev->ioevs[0].iv){ /* relative */
			if (ev->ioevs[1].iv < 0){
				arcan_tui_scroll_up(tui, -1 * ev->ioevs[1].iv);
				tui->sbofs -= ev->ioevs[1].iv;
			}
			else{
				arcan_tui_scroll_down(tui, ev->ioevs[1].iv);
				tui->sbofs += ev->ioevs[1].iv;
			}
		}
	break;

/* font-properties has changed, forward to the font manager. this
 * may in turn lead to a screen resize (new cell dimensions) */
	case TARGET_COMMAND_FONTHINT:{
		tui_fontmgmt_fonthint(tui, ev);
	}
	break;

	case TARGET_COMMAND_DISPLAYHINT:
		display_hint(tui, ev);
	break;

/* if the highest bit is set in the request, it's an external request
 * and it should be forwarded to the event handler */
	case TARGET_COMMAND_REQFAIL:
		if ( ((uint32_t)ev->ioevs[0].iv & (1 << 31)) ){
			if (tui->handlers.subwindow){
				tui->handlers.subwindow(tui, NULL,
					(uint32_t)ev->ioevs[0].iv & 0xffff, TUI_WND_TUI, tui->handlers.tag);
			}
		}
		else if ((uint32_t)ev->ioevs[0].iv == REQID_COPYWINDOW){
			drop_pending(&tui->pending_copy_window);
		}
	break;

/*
 * map the two clipboards needed for both cut and for paste operations
 */
	case TARGET_COMMAND_NEWSEGMENT:
		if (ev->ioevs[2].iv != SEGID_TUI && ev->ioevs[2].iv != SEGID_POPUP &&
			ev->ioevs[2].iv != SEGID_HANDOVER && ev->ioevs[2].iv != SEGID_DEBUG &&
			ev->ioevs[2].iv != SEGID_ACCESSIBILITY &&
			ev->ioevs[2].iv != SEGID_CLIPBOARD_PASTE &&
			ev->ioevs[2].iv != SEGID_CLIPBOARD
		)
			return;

		if (ev->ioevs[2].iv == SEGID_CLIPBOARD_PASTE){
			if (!tui->clip_in.vidp){
				tui->clip_in = arcan_shmif_acquire(
					&tui->acon, NULL, SEGID_CLIPBOARD_PASTE, 0);
			}
			else
				LOG("multiple paste- clipboards received, likely appl. error\n");
		}
/*
 * the requested clipboard has arrived
 */
		else if (ev->ioevs[1].iv == 0 && ev->ioevs[3].iv == 0xfeedface){
			if (!tui->clip_out.vidp){
				tui->clip_out = arcan_shmif_acquire(
					&tui->acon, NULL, SEGID_CLIPBOARD, 0);
			}
			else
				LOG("multiple clipboards received, likely appl. error\n");
		}
/*
 * special handling for our pasteboard window
 */
		else if (ev->ioevs[3].iv == REQID_COPYWINDOW && tui->pending_copy_window){
			struct arcan_shmif_cont acon =
				arcan_shmif_acquire(&tui->acon, NULL, ev->ioevs[2].iv, 0);
			if (acon.addr)
				arcan_tui_copywnd(tui, acon);
			else
				drop_pending(&tui->pending_copy_window);
		}
/*
 * new caller requested segment, even though acon is auto- scope allocated
 * here, the API states that the normal setup procedure should be respected,
 * which means that there will be an explicit copy of acon rather than an
 * alias.
 */
		else{
			bool can_push = ev->ioevs[2].iv == SEGID_DEBUG;
			can_push |= ev->ioevs[2].iv == SEGID_ACCESSIBILITY;
			bool user_defined = (uint32_t)ev->ioevs[3].iv & (1 << 31);

			if ((can_push || user_defined) && tui->handlers.subwindow){
				uint32_t id = (uint32_t) ev->ioevs[3].uiv & 0xffff;
				int kind = segid_to_tuiid(ev->ioevs[2].iv);

/* for 'HANDOVER' and the handover exec, pass the original acon rather than
 * setting up the subsegment or the shmif_handover_exec implementation will
 * fail */
				if (ev->ioevs[2].iv == SEGID_HANDOVER){
					tui->got_pending = true;
					tui->pending_wnd = *aev;
					tui->handlers.subwindow(
						tui, (void*)(uintptr_t)-1, id, kind, tui->handlers.tag);
					tui->got_pending = false;
					return;
				}

				struct arcan_shmif_cont acon =
					arcan_shmif_acquire(&tui->acon, NULL, ev->ioevs[2].iv, 0);

/* defimpl will clean up, so no leak here */
				if (!tui->handlers.subwindow(tui, &acon, id, kind, tui->handlers.tag))
					arcan_shmif_defimpl(&acon, ev->ioevs[2].iv, tui);
			}
		}
	break;

/* only flag DIRTY_PENDING and let the normal screen-update actually bundle
 * things together so that we don't risk burning an update/ synch just because
 * the cursor started blinking. */
	case TARGET_COMMAND_STEPFRAME:
		if (ev->ioevs[1].iv == 1){
			tick_cursor(tui);

			if (tui->handlers.tick)
				tui->handlers.tick(tui, tui->handlers.tag);

			if (tui->in_select && tui->scrollback != 0){
				if (tui->scrollback < 0)
					arcan_tui_scroll_up(tui, abs(tui->scrollback));
				else
					arcan_tui_scroll_down(tui, tui->scrollback);
				tui->dirty |= DIRTY_FULL;
			}
		}
	break;

/* if the client supports other languages, this will result in a number
 * of drawcalls, so we don't have to do anything special here */
	case TARGET_COMMAND_GEOHINT:
		if (tui->handlers.geohint)
			tui->handlers.geohint(tui, ev->ioevs[0].fv, ev->ioevs[1].fv,
				ev->ioevs[2].fv, (char*) ev->ioevs[3].cv,
				(char*) ev->ioevs[4].cv, tui->handlers.tag
			);
	break;

/* state management is entirely up to the client/API user */
	case TARGET_COMMAND_STORE:
	case TARGET_COMMAND_RESTORE:
		if (tui->handlers.state)
			tui->handlers.state(tui, ev->kind == TARGET_COMMAND_RESTORE,
				ev->ioevs[0].iv, tui->handlers.tag);
	break;

/* immediately say we are shutting down, then kill the upstream
 * connection - the context is still alive but _process / _refresh
 * calls will now fail. */
	case TARGET_COMMAND_EXIT:
		if (tui->handlers.exec_state)
			tui->handlers.exec_state(tui, 2, tui->handlers.tag);
		arcan_shmif_drop(&tui->acon);
	break;

	default:
	break;
	}
}

void tui_event_poll(struct tui_context* tui)
{
	arcan_event ev;
	int pv;

	while ((pv = arcan_shmif_poll(&tui->acon, &ev)) > 0){
		switch (ev.category){
		case EVENT_IO:
			tui_input_event(tui, &(ev.io), ev.io.label);
		break;

		case EVENT_TARGET:
			target_event(tui, &ev);
		break;

		default:
		break;
		}
	}

	if (pv == -1)
		arcan_shmif_drop(&tui->acon);
}
