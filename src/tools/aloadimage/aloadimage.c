/*
 * Copyright 2017, Björn Ståhl
 * Description: CLI image file viewer
 * License: 3-Clause BSD, see COPYING file in arcan source repository
 * Reference: http://arcan-fe.com, README.MD
 */
#include <arcan_shmif.h>
#include <arcan_shmif_tuisym.h>
#include <unistd.h>
#include "imgload.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"

struct draw_state {
	shmif_pixel pad_col;
	bool source_size, loop, stdin_pending, loaded;
	struct img_state* playlist;
	struct img_state* cur;
	int pl_ind, pl_size;
	int wnd_lim, wnd_pending;
	int step_timer, init_timer;
	int out_w, out_h;
};

/*
 * caller guarantee:
 * h-y > 0 && w-x > 0
 * state->w <= out_w && state->h <= out_h
 */
static void blit(struct arcan_shmif_cont* dst,
	const struct img_data* const src, const struct draw_state* const state)
{
/* draw pad color if the active image is incorrect */
	if (!src || !src->ready){
		for (int row = 0; row < dst->h; row++)
			for (int col = 0; col < dst->h; col++)
				dst->vidp[row * dst->pitch + col] = state->pad_col;
		arcan_shmif_signal(dst, SHMIF_SIGVID);
		return;
	}

/* scale to fit or something more complex? */
	int dw = dst->w ?
		(dst->w > dst->w ? dst->w : dst->w) : dst->w;
	int dh = state->out_h ?
		(dst->h > state->out_h ? state->out_h : dst->h) : dst->h;

/* sanity check */
	if (src->buf_sz != src->w * src->h * 4)
		return;

	int pad_w = dst->w - dw;
	int pad_h = dst->h - dh;
	int src_stride = src->w * 4;

/* stretch-blit for zoom in/out or pan */
	stbir_resize_uint8(
		&src->buf[src->y * src_stride + src->x],
		src->w - src->x, src->h - src->y,
		src_stride, dst->vidb, dw, dh, dst->stride, 4
	);

/* pad with color */
	for (int y = 0; y < dh; y++){
		shmif_pixel* vidp = dst->vidp + y * dst->pitch;
		for (int x = dw; x < dst->w; x++)
			vidp[x] = 0;
	}

/* pad last few rows */
	for (int y = dh; y < dst->h; y++){
		shmif_pixel* vidp = dst->vidp + y * dst->pitch;
		for (int x = 0; x < dst->w; x++)
			*vidp++ = state->pad_col;
	}

	arcan_shmif_signal(dst, SHMIF_SIGVID);
}

static void set_ident(struct arcan_shmif_cont* out,
	const char* prefix, const char* str)
{
	struct arcan_event ev = {.ext.kind = ARCAN_EVENT(IDENT)};
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	size_t len = strlen(str);

	if (len > lim)
		str += len - lim - 1;

	snprintf((char*)ev.ext.message.data, lim, "%s%s", prefix, str);
	arcan_shmif_enqueue(out, &ev);
}

/* sweep O(n) slots for pending loads as we want to reel them in immediately
 * to keep the active number of zombies down and shrink our own memory alloc */
static void poll_pl(struct draw_state* ds)
{
	for (size_t i = 0; i < ds->pl_size && ds->wnd_pending; i++)
	{
		if (ds->playlist[i].out && ds->playlist[i].proc)
			if (imgload_poll(&ds->playlist[i])){
				ds->wnd_pending--;
				if (ds->playlist[i].is_stdin)
					ds->stdin_pending = false;
			}
	}
}

/* spawn a new worker if:
 *  1. one isn't active on the slot
 *  2. slot isn't stdin or slot is stdin but there's no stdin- working
 */
static bool try_dispatch(struct draw_state* ds, int ind)
{
	if (!ds->playlist[ind].out ||
		(!ds->playlist[ind].out->ready && ds->playlist[ind].proc)){

		if (ds->playlist[ind].is_stdin && ds->stdin_pending)
		return false;

		if (imgload_spawn(arcan_shmif_primary(SHMIF_INPUT), &ds->playlist[ind])){
			if (ds->playlist[ind].is_stdin)
				ds->stdin_pending = true;
			ds->wnd_pending++;
			return true;
		}
	}

	return false;
}

static struct img_state* set_playlist_pos(struct draw_state* ds, int i)
{
	poll_pl(ds);

/* range-check, if we don't loop, return to start */
	if (i < 0)
		i = ds->pl_size-1;

	if (i >= ds->pl_size){
		if (ds->loop)
			i = 0;
		else
			return NULL;
	}

/* FIXME: we should drop 'n' outdated slots */

/* fill up new worker slots */
	ds->pl_ind = i;
	do {
		try_dispatch(ds, i);
		i = (i + 1) % ds->pl_size;
	} while (ds->wnd_pending < ds->wnd_lim && i != ds->pl_ind);

	return &ds->playlist[ds->pl_ind];
}

struct lent {
	const char* lbl;
	const char* descr;
	const char* def;
	int defsym;
	bool(*ptr)(struct draw_state*);
};

static void set_active(struct draw_state* ds)
{
	struct arcan_shmif_cont* cont = arcan_shmif_primary(SHMIF_INPUT);
	if (!ds || !ds->cur){
		set_ident(cont, "missing playlist item", "");
		return;
	}

	if (ds->cur->proc){
		ds->loaded = false;
		return;
	}

	ds->loaded = true;
	if (ds->cur->broken){
		set_ident(cont, "failed: ", ds->cur->fname);
	}
	else {
		if (ds->source_size)
			arcan_shmif_resize(cont, ds->cur->out->w, ds->cur->out->h);
			set_ident(cont, "", ds->cur->fname);
	}
	blit(cont, (struct img_data*) ds->cur->out, ds);
}

static bool step_next(struct draw_state* state)
{
	state->cur = set_playlist_pos(state, state->pl_ind + 1);
	set_active(state);
	return true;
}

static bool step_prev(struct draw_state* state)
{
	state->cur = set_playlist_pos(state, state->pl_ind - 1);
	set_active(state);
	return true;
}

static const struct lent labels[] = {
	{"PREV", "Step to previous entry in playlist", "LEFT", TUIK_LEFT, step_prev},
	{"NEXT", "Step to next entry in playlist", "RIGHT", TUIK_RIGHT, step_next},
	{NULL, NULL}
};

static const struct lent* find_label(const char* label)
{
	const struct lent* cur = labels;
	while(cur->ptr){
		if (strcmp(label, cur->lbl) == 0)
			return cur;
		cur++;
	}
	return NULL;
}

static const struct lent* find_sym(unsigned sym)
{
	const struct lent* cur = labels;
	if (sym == 0)
		return NULL;

	while(cur->ptr){
		if (cur->defsym == sym)
			return cur;
		cur++;
	}

	return NULL;
}

static bool dispatch_event(
	struct arcan_shmif_cont* con, struct arcan_event* ev, struct draw_state* ds)
{
	if (ev->category == EVENT_IO){
/* drag/zoom/pan/... */
		if (ev->io.devkind == EVENT_IDEVKIND_MOUSE){
			return false;
		}
		else if (ev->io.datatype == EVENT_IDATATYPE_DIGITAL){
			if (!ev->io.input.translated.active || !ev->io.label[0])
				return false;

			const struct lent* lent = find_label(ev->io.label);
			if (lent)
				return lent->ptr(ds);
		}
		else if (ev->io.datatype == EVENT_IDATATYPE_TRANSLATED){
			if (!ev->io.input.translated.active)
				return false;
			const struct lent* lent = ev->io.label[0] ?
				find_label(ev->io.label) : find_sym(ev->io.input.translated.keysym);
			if (lent)
				return lent->ptr(ds);
		}
	}
	else if (ev->category == EVENT_TARGET)
		switch(ev->tgt.kind){
		case TARGET_COMMAND_DISPLAYHINT:
			if (!ds->source_size && ev->tgt.ioevs[0].iv && ev->tgt.ioevs[1].iv &&
				arcan_shmif_resize(con, ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv))
				return true;
		break;
		case TARGET_COMMAND_STEPFRAME:
			if (ds->step_timer > 0){
				if (ds->step_timer == 0){
					ds->step_timer = ds->init_timer;
					ds->cur = set_playlist_pos(ds, ds->pl_ind + 1);
				}
			}
		break;
		case TARGET_COMMAND_EXIT:
			arcan_shmif_drop(con);
			return false;
		break;
		default:
		break;
		}
	return false;
}

static int show_use(const char* msg)
{
	fprintf(stderr, "%s\nUse: aloadimage [opts] file1 .. filen \n", msg);
	return EXIT_FAILURE;
}

static void expose_labels(struct arcan_shmif_cont* con)
{
	const struct lent* cur = labels;
	while(cur->lbl){
		arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(LABELHINT),
			.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
		};
			snprintf(ev.ext.labelhint.label,
			sizeof(ev.ext.labelhint.label)/sizeof(ev.ext.labelhint.label[0]),
			"%s", cur->lbl
		);
		snprintf(ev.ext.labelhint.initial,
			sizeof(ev.ext.labelhint.initial)/sizeof(ev.ext.labelhint.initial[0]),
			"%s", cur->def
		);
		cur++;
		arcan_shmif_enqueue(con, &ev);
	}
}

int main(int argc, char** argv)
{
	if (argc <= 1)
		return show_use("invalid/missing arguments");

	struct img_state playlist[argc];
	struct draw_state ds = {
		.source_size = true,
		.wnd_lim = 2,
		.step_timer = 0,
		.init_timer = 0,
		.pad_col = SHMIF_RGBA(32, 32, 32, 255),
		.playlist = playlist
	};

/* parse opts and update ds accordingly */
	int i;
	for (i = 1; i < argc; i++){
/* FIXME: parse options and modify settings */
		if (argv[i][0] != '-')
			break;
	}

	for (; i < argc; i++){
		playlist[ds.pl_size] = (struct img_state){
			.fname = argv[i],
			.is_stdin = strcmp(argv[i], "-") == 0
		};
		ds.pl_size++;
	}
	if (ds.pl_size == 0)
		return show_use("no images found");

/* dispatch workers */
	ds.cur = set_playlist_pos(&ds, 0);

/* connect while the workers are busy */
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);
	arcan_shmif_setprimary(SHMIF_INPUT, &cont);
	blit(&cont, NULL, &ds);

/* 1s. timer for automatic stepping and load/poll */
	arcan_shmif_enqueue(&cont, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = 25
	});

	ds.out_w = cont.w;
	ds.out_h = cont.h;
	while (ds.cur){
		if (!ds.loaded){
			if (imgload_poll(ds.cur)){
				ds.wnd_pending--;
				ds.loaded = true;
				set_active(&ds);
			}
			else
				set_ident(&cont, "loading: ", ds.cur->fname);
		}
		poll_pl(&ds);

/* Block for one event, then flush out any burst. Blit on any change */
		arcan_event ev;
		if (!arcan_shmif_wait(&cont, &ev))
			break;
		bool dirty = dispatch_event(&cont, &ev, &ds);
		while(arcan_shmif_poll(&cont, &ev) > 0)
			dirty |= dispatch_event(&cont, &ev, &ds);
		poll_pl(&ds);

		if (dirty && ds.cur && ds.cur->out && ds.cur->out->ready){
			blit(&cont, (struct img_data*) ds.cur->out, &ds);
		}
	}
	return EXIT_SUCCESS;
}
