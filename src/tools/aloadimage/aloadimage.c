/*
 * Copyright 2017-2019, Björn Ståhl
 * Description: CLI image file viewer
 * License: 3-Clause BSD, see COPYING file in arcan source repository
 * Reference: http://arcan-fe.com, README.MD
 */
#include <arcan_shmif.h>
#include <arcan_tuisym.h>
#include <unistd.h>
#include <inttypes.h>
#include <poll.h>
#include <getopt.h>
#include <stdarg.h>
#include "imgload.h"

static void progress_report(float progress);

#define AR_EPSILON 0.001
#define STBIR_PROGRESS_REPORT(val) progress_report(val)
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"

/*
 * shared global state with imgloader in liu of a config- call for now
 */
int image_size_limit_mb = 64;
bool disable_syscall_flt = false;

/*
 * all the context needed for one window, could theoretically be used for
 * multiple windows with different playlists etc. stereo mode is a bit
 * special as the state contains two target outputs
 */
struct draw_state {
	struct arcan_shmif_cont* con;

/*
 * stereoscopic rendering may need an extra context and synch signalling
 * so that updates are synched to updates on the right eye.
 */
	struct arcan_shmif_cont* con_right;
	bool stereo;

/* blitting controls */
	shmif_pixel pad_col;
	int out_w, out_h;
	bool aspect_ratio;
	bool source_size;
	int blit_ind;
	float dpi;

/* loading/ resource management state */
	int wnd_lim, wnd_fwd, wnd_pending, wnd_act;
	int wnd_prev, wnd_next;
	int timeout;
	bool stdin_pending, loaded, animated, vector;

/* playlist related state */
	struct img_state* playlist;
	int pl_ind, pl_size;
	int step_timer, init_timer;
	bool step_block;
	bool handover_exec;

/* user- navigation related states */
	bool block_input;
	bool loop;

/* dirty requested as triggered from input handlers */
	bool dirty;
};

static struct draw_state* last_ds;
static bool set_playlist_pos(struct draw_state* ds, int new_i);

void debug_message(const char* msg, ...)
{
#ifdef DEBUG
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
#endif
}

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

/* resize to match? try and find the largest permitted fit - this will be
 * SHMPAGE_MAXW * SHMPAGE_MAXH (in bytes) but can theoretically be larger in
 * certain circumstances and practically be smaller depending on what the
 * server end says */
	if (state->source_size){
		size_t dw = src->w;
		size_t dh = src->h;

		int attempts = 0;
		while (dw && dh && !arcan_shmif_resize(dst, dw, dh)){
			debug_message("resize to %zu*%zu rejected, trying %zu*%zu\n");
			if (!attempts){
				if (dw > dh){
					float ratio = (float)dh / (float)dw;
					dw = PP_SHMPAGE_MAXW;
					dh = dw * ratio;
					attempts++;
				}
				else {
					float ratio = (float)dw / (float)dh;
					dh = PP_SHMPAGE_MAXH;
					dw = dh * ratio;
					attempts++;
				}
				continue;
			}
			dw >>= 1;
			dh >>= 1;
			attempts++;
		}
	}
/* safe: shmif_resize on <= 0 and <= 0 would fail without changing dst->w,h */
	int dw = dst->w;
	int dh = dst->h;

/* scale to fit or something more complex? */
	float ar = (float)src->w / (float)src->h;
	if (state->out_w && state->out_h &&
		state->out_w <= dw && state->out_h <= dh){
		dw = state->out_w;
		dh = state->out_h;
	}

/* reduce to fit aspect? */
	float new_ar = (float)dw / (float)dh;
	if (state->aspect_ratio && fabs(new_ar - ar) > AR_EPSILON){
/* bias against the dominant axis */
		debug_message("blit[adjust %f] %d*%d -> ", ar, dw, dh);
		float wr = src->w / dst->w;
		float hr = src->h / dst->h;
		dw = hr > wr ? dst->h * ar : dst->w;
		dh = hr < wr ? dst->w / ar : dst->h;
		debug_message("%d*%d\n", dw, dh);
	}

/* sanity check */
	if (src->buf_sz != src->w * src->h * 4)
		return;

	int pad_w = dst->w - dw;
	int pad_h = dst->h - dh;
	int src_stride = src->w * 4;

/* early out, no transform */
	if (dw == dst->w && dh == dst->h &&
		src->w == dst->w && src->h == dst->h){
		debug_message("full-blit[%d*%d]\n", (int)dst->w, (int)dst->h);
		for (size_t row = 0; row < dst->h; row++)
			memcpy(&dst->vidp[row*dst->pitch],
				&src->buf[row*src_stride], src_stride);
		goto done;
	}

	int pad_pre_x = pad_w >> 1;
	int pad_pre_y = pad_h >> 1;

/* FIXME: stretch-blit/transform for zoom in/out or pan */
	debug_message("blit[%d+%d*%d+%d] -> [%d,%d]:pad(%d,%d)\n",
		(int)src->w, (int)src->x, (int)src->h, (int)src->y,
		(int)dw, (int)dh, pad_w, pad_h);
	stbir_resize_uint8(
		&src->buf[src->y * src_stride + src->x],
		src->w - src->x, src->h - src->y,
		src_stride,
		(uint8_t*) &dst->vidp[pad_pre_y * dst->pitch + pad_pre_x],
		dw, dh, dst->stride, sizeof(shmif_pixel)
	);

/* pad beginning / end rows */
	for (int y = 0; y < pad_pre_y; y++){
		shmif_pixel* vidp = dst->vidp + y * dst->pitch;
		for (int x = 0; x < dst->w; x++)
			vidp[x] = state->pad_col;
	}

	for (int y = pad_pre_y + dh; y < dst->h; y++){
		shmif_pixel* vidp = dst->vidp + y * dst->pitch;
		for (int x = 0; x < dst->w; x++)
			vidp[x] = state->pad_col;
	}

/* pad with color */
	for (int y = pad_pre_y; y < pad_pre_y + dh; y++){
		shmif_pixel* vidp = dst->vidp + y * dst->pitch;
		for (int x = 0; x < pad_pre_x; x++)
			vidp[x] = state->pad_col;

		for (int x = pad_pre_x + dw; x < dst->w; x++)
			vidp[x] = state->pad_col;
	}

done:
	arcan_shmif_signal(dst, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
}

static void set_ident(struct arcan_shmif_cont* out,
	const char* prefix, const char* str)
{
	struct arcan_event ev = {.ext.kind = ARCAN_EVENT(IDENT)};
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	size_t len = strlen(str);

/* strip away overflowing prefix, assume suffix is more important */
	if (len > lim)
		str += len - lim - 1;

	snprintf((char*)ev.ext.message.data, lim, "%s%s", prefix, str);
	debug_message("new ident: %s%s\n", prefix, str);
	arcan_shmif_enqueue(out, &ev);
}

/*
 * last_ds state is needed as this is mapped into the STB- code that
 * provides no other interface, just callback with value, no ctx.
 */
static void progress_report(float state)
{
	static float last_state;
	if (state < 1.0){
		char msgbuf[16];
		if (state - last_state > 0.1){
			last_state = state;
			snprintf(msgbuf, 16, "scale(%.2d%%) ", (int)(state*100));
			set_ident(last_ds->con, msgbuf, last_ds->playlist[last_ds->pl_ind].fname);
		}
	}
	else{
		set_ident(last_ds->con, "", last_ds->playlist[last_ds->pl_ind].fname);
		last_state = 0.0;
	}
}

static bool update_item(struct draw_state* ds, struct img_state* i, int step)
{
	if (imgload_poll(i)){
		if (i->is_stdin)
			ds->stdin_pending = false;

		i->life = 0;
		ds->wnd_pending--;

/* OK poll result is just that it's finished, not that it succeeded */
		if (!i->broken){
			debug_message("worker (%s) finished\n", i->fname);
			ds->wnd_act++;
			return true;
		}
		else {
			debug_message("worker (%s) broken: %s\n", i->fname, i->msg);
			if (&ds->playlist[ds->pl_ind] == i){
/* item broken, just jump to next */
				if (!set_playlist_pos(ds, ds->pl_ind + 1))
					return false;
			}
		}
	}
	else if (step && i->life > 0){
//		i->life--;
		if (!i->life){
			debug_message("worker (%s) timed out\n", i->fname);
			imgload_reset(i);
			ds->wnd_pending--;
			i->life = -1;
		}
	}
	return false;
}

/* sweep O(n) slots for pending loads as we want to reel them in immediately
 * to keep the active number of zombies down and shrink our own memory alloc */
static bool poll_pl(struct draw_state* ds, int step)
{
	bool update = false;
	for (size_t i = 0; i < ds->pl_size && ds->wnd_pending; i++){
		struct img_state* is = &ds->playlist[i];
		if (is->proc)
			update |= update_item(ds, is, step);
	}

/* special treatment for the currently selected index, have a retry timer
 * on failure, update ident with current load status */
	struct img_state* cur = &ds->playlist[ds->pl_ind];
	if (!ds->loaded && (cur->broken || (cur->out && cur->out->ready))){
		set_ident(ds->con, (char*) cur->msg, cur->fname);
		ds->loaded = update = true;
	}
	else {
/* progress ident is updated in callback, scheduling is done in set_pl_pos,
 * but we can set the steam status to match our playlist position vs. playlist
 * size */
	}

	return update;
}

/* used to spawn a new worker process */
static bool try_dispatch(struct draw_state* ds, int ind, int prio_d)
{
/* already loaded and acknowledged? */
	if (ds->playlist[ind].out && ds->playlist[ind].life >= 0)
		return false;

/* or stdin- slot one is already being loaded from standard input */
	if (ds->playlist[ind].is_stdin && ds->stdin_pending)
		return false;

/* NOTE: we don't care if the entry has previously been marked as broken,
 * the specified input may have appeared or permissions might have changed */

/* all done, spawn */
	if (imgload_spawn(ds->con, &ds->playlist[ind], prio_d)){
		if (ds->playlist[ind].is_stdin)
			ds->stdin_pending = true;
		ds->wnd_pending++;
		ds->playlist[ind].life = ds->timeout;
			debug_message("queued %s[%d], pending: %d\n",
			ds->playlist[ind].fname,  ind, ds->wnd_pending);
		return true;
	}
	else
		debug_message("imgload_spawn failed on [%d]\n", ind);

	return false;
}

static void reset_slot(struct draw_state* ds, int ind)
{
	if (ind >= 0 && ind < ds->pl_size && ds->playlist[ind].out){
		if (ds->playlist[ind].proc)
			ds->wnd_pending--;
		else if (!ds->playlist[ind].broken)
			ds->wnd_act--;
		imgload_reset(&ds->playlist[ind]);
		ds->playlist[ind].life = -1;
	}
}

static void clean_queue(struct draw_state* ds)
{
/* scan horizon to determine the number of entries to drop, assumptions from
 * caller is that we're in a state where entries actually need to be dropped */
	size_t fwd = ds->pl_ind;
	size_t ntr = ds->wnd_fwd;

/* A special case to consider: when we step backwards in playlist and exceeds
 * the window, that'll cause the window to grow outside bounds.  This is
 * accepted (for now) on the motivation that the forward direction is more
 * important and is the expected use-case. To change this, simply take
 * step- direction into account. */
	while (ntr){
		if (!ds->playlist[fwd].out)
			if (!ds->playlist[fwd].broken)
				break;
		ntr--;
		fwd = fwd + 1;
		if (fwd == ds->pl_size){
			if (ds->loop)
				fwd = 0;
			else {
				ntr = 0;
			}
		}
	}
	debug_message("clean_queue(%zu)\n", ntr);

	if (!ntr)
		return;

/* find oldest item */
	size_t back = ds->pl_ind > 0 ? ds->pl_ind - 1 : ds->pl_size - 1;
	while (ds->playlist[back].out || ds->playlist[back].broken)
		back = back > 0 ? back - 1 : ds->pl_size - 1;

/* and start the purge */
	while (ntr){
		if (ds->playlist[back].out){
			debug_message("unloading tail@%zu (%s), left: %zu\n",
				back, ds->playlist[back].fname, ntr);
			reset_slot(ds, back);
			ntr--;
		}
		back = (back + 1) % ds->pl_size;
	}
}

static bool set_playlist_pos(struct draw_state* ds, int new_i)
{
	size_t pos;

/* range-check, if we don't loop, return to start */
	if (new_i < 0)
		new_i = ds->pl_size-1;

	if (new_i >= ds->pl_size){
		if (ds->loop){
			debug_message("looping");
			new_i = 0;
		}
		else{
			debug_message("playlist out of bounds, shut down\n");
			arcan_shmif_drop(ds->con);
			return false;
		}
	}

/* if we land outside the previous window, full-reset everything */
	if (ds->wnd_lim && abs(new_i - ds->pl_ind) > ds->wnd_lim){
		for (size_t i = 0; i < ds->pl_size; i++)
			reset_slot(ds, i);
		ds->wnd_act = 0;
		ds->wnd_pending = 0;
	}

/* first dispatch the currently requested slot at normal priority */
	ds->pl_ind = new_i;
	struct img_state* cur = &ds->playlist[ds->pl_ind];
	if (!cur->out){
		debug_message("single load (%s)\n", cur->fname);
		try_dispatch(ds, ds->pl_ind, 0);
	}

/* if we overshoot or are at capacity, start flushing out */
	if (ds->wnd_lim && ds->pl_size > ds->wnd_lim &&
		ds->wnd_pending + ds->wnd_act >= ds->wnd_lim){
		clean_queue(ds);
	}

/* and then fill up with lesser priority, note that there is a slight degrade
 * if we step from the currently loaded into one that is pending as the
 * priority for that one, though the effect should be minimal enough to not
 * bothering with renicing */
	pos = (new_i + 1) % ds->pl_size;

	while (pos != new_i &&
		(ds->wnd_act + ds->wnd_pending < ds->wnd_lim || !ds->wnd_lim)){
		debug_message("attempt to queue (%s)\n", ds->playlist[pos].fname);
		try_dispatch(ds, pos, 1);
		pos = (pos + 1) % ds->pl_size;
	}

	debug_message("position set to (%d, act: %d/%d, pending: %d)\n",
		ds->pl_ind, ds->wnd_act, ds->wnd_lim, ds->wnd_pending);

	arcan_shmif_enqueue(ds->con, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(STREAMSTATUS),
		.ext.streamstat.completion = (float)ds->pl_ind / (float)ds->pl_size,
		.ext.streamstat.frameno = ds->pl_ind
	});

	for (size_t i = 0; i < ds->pl_size; i++)
		debug_message("%c ", i == ds->pl_ind ? '*' :
			(ds->playlist[i].out ? 'o' : 'x'));
	debug_message("\n");

	return true;
}

struct lent {
	const char* lbl;
	const char* descr;
	int defsym;
	bool(*ptr)(struct draw_state*);
};

static bool step_next(struct draw_state* state)
{
	set_playlist_pos(state, state->pl_ind + 1);
	return true;
}

static bool step_prev(struct draw_state* state)
{
	set_playlist_pos(state, state->pl_ind - 1);
	return true;
}

static bool source_size(struct draw_state* state)
{
	if (!state->source_size){
		state->source_size = true;
		state->blit_ind = -1;
	}
	return false;
}

static bool server_size(struct draw_state* state)
{
	if (state->source_size){
		state->source_size = false;
		state->blit_ind = -1;
		return arcan_shmif_resize(state->con, state->out_w, state->out_h);
	}
	else
		return false;
}

static bool pl_toggle(struct draw_state* state)
{
	state->step_block = !state->step_block;
	return false;
}

static bool aspect_ratio(struct draw_state* state)
{
	state->aspect_ratio = !state->aspect_ratio;
	return true;
}

static const struct lent labels[] = {
	{"PREV", "Step to previous entry in playlist", TUIK_H, step_prev},
	{"NEXT", "Step to next entry in playlist", TUIK_L, step_next},
	{"PL_TOGGLE", "Toggle playlist stepping on/off", TUIK_SPACE, pl_toggle},
	{"SOURCE_SIZE", "Resize the window to fit image size", TUIK_F5, source_size},
	{"SERVER_SIZE", "Use the recommended connection size", TUIK_F6, server_size},
	{"ASPECT_TOGGLE", "Maintain aspect ratio", TUIK_TAB, aspect_ratio},
/*
 * "ZOOM_IN", "Increment the scale factor (integer)", "F1", TUIK_F1, zoom_in},
	{"ZOOM_OUT", "Decrement the scale factor (integer)", "F2", TUIK_F2, zoom_out},
 */
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
		if (ds->block_input)
			return false;

/* drag/zoom/pan/... */
		if (ev->io.devkind == EVENT_IDEVKIND_MOUSE){
			return false;
		}
		else if (ev->io.datatype == EVENT_IDATATYPE_DIGITAL){
			if (!ev->io.input.translated.active || !ev->io.label[0])
				return false;

			const struct lent* lent = find_label(ev->io.label);
			if (lent){
				if (lent->ptr(ds)){
					debug_message("dirty from [digital] input\n");
					return true;
				}
			}
		}
		else if (ev->io.datatype == EVENT_IDATATYPE_TRANSLATED){
			if (!ev->io.input.translated.active)
				return false;
			const struct lent* lent = ev->io.label[0] ?
				find_label(ev->io.label) : find_sym(ev->io.input.translated.keysym);
			if (lent && lent->ptr(ds)){
				debug_message("dirty from [translated] input\n");
				return true;
			}
		}
	}
	else if (ev->category == EVENT_TARGET)
		switch(ev->tgt.kind){
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev->tgt.ioevs[0].iv && ev->tgt.ioevs[1].iv &&
				(ev->tgt.ioevs[0].iv != con->w || ev->tgt.ioevs[1].iv != con->h)){
				if (!ds->source_size && arcan_shmif_resize(
					con, ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv)){
						debug_message("server requested [%d*%d] vs. current [%d*%d]\n",
							ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv, con->w, con->h);
						return true;
				}
			}
		break;
		case TARGET_COMMAND_STEPFRAME:
			if (ev->tgt.ioevs[1].iv == 0xfeed)
				if (poll_pl(ds, 1))
					return true;

			if (ds->step_timer > 0 && !ds->step_block){
				if (ds->step_timer == 0){
					ds->step_timer = ds->init_timer;
					set_playlist_pos(ds, ds->pl_ind + 1);
					return true;
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
	printf("Usage: aloadimage [options] file1 .. filen\n"
"Basic Use:\n"
"-h     \t--help        \tThis text\n"
"-a     \t--aspect      \tMaintain aspect ratio when scaling\n"
"-S     \t--server-size \tScale to fit server- suggested window size\n"
"-l     \t--loop        \tStep back to [file1] after reaching [filen] in playlist\n"
"-t sec \t--step-time   \tSet playlist step time (~seconds)\n"
"-b     \t--block-input \tIgnore keyboard and mouse input\n"
"-d str \t--display     \tSet/override the display server connection path\n"
"-p rgba\t--padcol      \tSet the padding color, like -p 127,127,127,255\n"
"Tuning:\n"
"-m num \t--limit-mem   \tSet loader process memory limit to [num] MB\n"
"-r num \t--readahead   \tSet the playlist window queue size\n"
"-T sec \t--timeout     \tSet unresponsive worker kill- timeout\n"
"-H     \t--vr          \tSet stereoscopic mode, prefix files with l: or r:\n"
#ifdef ENABLE_SECCOMP
"-X    \t--no-sysflt   \tDisable seccomp- syscall filtering\n"
#endif
	);
	return EXIT_FAILURE;
}

static void expose_labels(struct arcan_shmif_cont* con)
{
	const struct lent* cur = labels;
	while(cur->lbl){
		arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(LABELHINT),
			.ext.labelhint.initial = cur->defsym,
			.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
		};
			snprintf(ev.ext.labelhint.label,
			sizeof(ev.ext.labelhint.label)/sizeof(ev.ext.labelhint.label[0]),
			"%s", cur->lbl
		);
		cur++;
		arcan_shmif_enqueue(con, &ev);
	}
}

static const struct option longopts[] = {
	{"help", no_argument, NULL, 'h'},
	{"loop", no_argument, NULL, 'l'},
	{"step-time", required_argument, NULL, 't'},
	{"block-input", no_argument, NULL, 'b'},
	{"timeout", required_argument, NULL, 'T'},
	{"limit-mem", required_argument, NULL, 'm'},
	{"readahead", required_argument, NULL, 'r'},
	{"padcol", required_argument, NULL, 'p'},
	{"no-sysflt", no_argument, NULL, 'X'},
	{"server-size", no_argument, NULL, 'S'},
	{"display", no_argument, NULL, 'd'},
	{"aspect", no_argument, NULL, 'a'},
	{"vr180", no_argument, NULL, 'H'},
	{ NULL, no_argument, NULL, 0 }
};

/* wait but using the epipe and multiplex with current playlist item */
static void wait_for_event(struct draw_state* ds)
{
	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[2] = {
	{
		.events = pollev,
		.fd = ds->con->epipe
	},
	{
		.events = pollev,
		.fd = -1
	},
	};
	size_t pollsz = 1;
	int plfd = ds->playlist[ds->pl_ind].sigfd;
	if (plfd > 0){
		fds[1].fd = plfd;
		pollsz++;
	}

/* don't care about the result, only used for sleep / wake */
	poll(fds, pollsz, -1);
}

int main(int argc, char** argv)
{
	if (argc <= 1)
		return show_use("invalid/missing arguments");

	struct img_state playlist[argc];
	struct draw_state ds = {
		.source_size = true,
		.wnd_lim = 5,
		.init_timer = 0,
		.pad_col = SHMIF_RGBA(32, 32, 32, 255),
		.playlist = playlist,
		.blit_ind = -1
	};
	last_ds = &ds;

	int ch;
	int segid = SEGID_MEDIA;

	while((ch = getopt_long(argc, argv,
		"p:ihlt:bd:T:m:r:XSHd:a", longopts, NULL)) >= 0)
		switch(ch){
		case 'h' : return show_use(""); break;
		case 't' : ds.init_timer = strtoul(optarg, NULL, 10) * 5; break;
		case 'b' : ds.block_input = true; break;
		case 'd' : setenv("ARCAN_CONNPATH", optarg, 1); break;
		case 'T' : ds.timeout = strtoul(optarg, NULL, 10) * 5; break;
		case 'l' : ds.loop = true; break;
		case 'f' : ds.wnd_fwd = strtoul(optarg, NULL, 10); break;
		case 'p' : {
			uint8_t outv[4] = {0, 0, 0, 255};
			if (sscanf(optarg, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
				&outv[0], &outv[1], &outv[2], &outv[3])){
					ds.pad_col = SHMIF_RGBA(outv[0], outv[1], outv[2], outv[3]);
			}
		} break;
		case 'a' : ds.aspect_ratio = true; break;
		case 'm' : image_size_limit_mb = strtoul(optarg, NULL, 10); break;
		case 'r' : ds.wnd_lim = strtoul(optarg, NULL, 10); break;
		case 'X' : disable_syscall_flt = true; break;
		case 'N' : ds.handover_exec = true; break;
		case 'H' :
			ds.stereo = true;
			segid = SEGID_HMD_L;
		break;
		case 'S' :
			ds.source_size = false;
			segid = SEGID_APPLICATION;
		break;
		default:
			fprintf(stderr, "unknown/ignored option: %c\n", ch);
		break;
		}
	ds.step_timer = ds.init_timer;

/* there are more considerations here -
 *
 * some image formats will be packed l/r and in those cases we'd want to split (possibly use lr:)
 * along the dominant axis.
 *
 * other image formats are actually n images in one packed, something we don't support right now,
 * there also needs to be some way to specify the server-side projection geometry
 */
	if (ds.stereo){
		int rc = 0, lc = 0;
		bool last_l = false;

		for (int i = optind; i < argc; i++){
			if ((argv[i][0] != 'l' && argv[i][0] != 'r') || argv[i][1] != ':'){
				fprintf(stderr, "malformed entry (%d): %s\n"
					"vr mode (-H,--vr) requires l: and r: prefix for each entry\n", i - optind + 1, argv[i]);
				return EXIT_FAILURE;
			}

			if (argv[i][0] == 'l'){
				if (last_l){
					fprintf(stderr, "malformed l-entry (%d): %s\n"
						"vr mode (-H,--vr) requires l: and r: to interleave\n", i - optind + 1, &argv[i][2]);
				}
				last_l = true;
				lc++;
			}
			else{
				if (!last_l){
					fprintf(stderr, "malformed r-entry (%d): %s\n"
						"vr mode (-H,--vr) requires l: and r: to interleave\n", i - optind + 1, &argv[i][2]);
					return EXIT_FAILURE;
				}
				last_l = false;
				rc++;
			}

			playlist[ds.pl_size++] = (struct img_state){
				.fd = -1,
				.stereo_right = argv[i][0] == 'r',
				.fname = &argv[i][2],
				.is_stdin = false
			};
		}
		if (rc != lc){
			fprintf(stderr, "malformed number of arguments (l=%d, r=%d)\n"
				"vr mode (-X,--vr) requires an even number of l: and r: prefixed entries\n", lc, rc);
			return EXIT_FAILURE;
		}
	}
	else {
		for (int i = optind; i < argc; i++){
			playlist[ds.pl_size] = (struct img_state){
				.fd = -1,
				.fname = argv[i],
				.is_stdin = strcmp(argv[i], "-") == 0
			};
			ds.pl_size++;
		}
	}

/* sanity- clamp, always preload something*/
	if (ds.wnd_lim)
		ds.wnd_fwd = ds.wnd_lim > 2 ? ds.wnd_lim - 2 : 2;

	struct arcan_shmif_cont cont = arcan_shmif_open_ext(
		SHMIF_ACQUIRE_FATALFAIL, NULL, (struct shmif_open_ext){
			.type = segid,
			.title = "aloadimage",
			.ident = ""
		}, sizeof(struct shmif_open_ext)
	);

	if (ds.pl_size == 0){
		arcan_shmif_last_words(&cont, "empty playlist");
		arcan_shmif_drop(&cont);
		return EXIT_FAILURE;
	}

	struct arcan_shmif_initial* init;
	arcan_shmif_initial(&cont, &init);
	if (init && init->density > 0){
		ds.dpi = init->density / 2.5;
	}

	ds.con = &cont;

/* request the right segment, deal with it if it arrives */
 if (ds.stereo){
	 arcan_shmif_enqueue(&cont, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_HMD_R,
			.ext.segreq.id = 0x6502
		});
 }

/* dispatch workers */
	set_playlist_pos(&ds, 0);

/* 200ms timer for automatic stepping and load/poll, if this value is
 * changed, do trhe same for the multipliers to init_timer and timeout */
	arcan_shmif_enqueue(&cont, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = 5,
		.ext.clock.id = 0xfeed
	});

/* Block for events - timer should wake us up often enough, otherwise we need
 * a signal descriptor from the playlist processing and multiplex on both evdesc
 * and on the playlist */
	struct arcan_event ev;
	while (cont.addr && (wait_for_event(&ds), 1)){
		int pv;
		int dirty = 0;

		while((pv = arcan_shmif_poll(&cont, &ev)) > 0)
			dirty |= dispatch_event(&cont, &ev, &ds);

		if (pv == -1)
			break;

/* If we are waiting for the currently selected item to finish processing */
		dirty |= poll_pl(&ds, 0);

/* blit and update title as playlist position might have changed, or some other
 * metadata we present as part of the ident/title - if we are in stereo mode we
 * simply skip ahead one (l/r interleaved) and then send the second to the
 * other context, can do on a secondary thread */
		struct img_state* cur = &ds.playlist[ds.pl_ind];

		if (dirty && !cur->broken && cur->out && cur->out->ready){
			set_ident(ds.con, "", cur->fname);

			if (ds.pl_ind != ds.blit_ind){
				ds.blit_ind = ds.pl_ind;
				blit(&cont, (struct img_data*) cur->out, &ds);
			}
		}
	}

/* reset the entire playlist so leak detection is useful */
	for (size_t i = 0; i < ds.pl_size; i++)
		imgload_reset(&ds.playlist[i]);

	arcan_shmif_drop(&cont);
	if (ds.con_right)
		arcan_shmif_drop(ds.con_right);

	return EXIT_SUCCESS;
}
