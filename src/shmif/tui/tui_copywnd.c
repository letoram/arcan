#include <unistd.h>
#include <fcntl.h>

#include "../arcan_shmif.h"
#include "../arcan_tui.h"

#include "libtsm.h"
#include "libtsm_int.h"

#include <pthread.h>
#include <errno.h>

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

typedef void TTF_Font;
#include "tui_int.h"

struct copywnd_context {
	struct tui_context* tui;
	struct tsm_save_buf* buf;
	bool invalidated;
	int iopipes[2];
	bool edit_mode;
	uint8_t bgc[3];
	uint8_t color_index;

/* button that triggered the select state */
	int in_select;
	int last_x, last_y;
	int last_mx, last_my;
};

static uint8_t color_palette[][3] = {
	{   0,   0,   0 }, /* black */
	{ 205,   0,   0 }, /* red */
	{   0, 205,   0 }, /* green */
	{ 205, 205,   0 }, /* yellow */
	{   0,   0, 238 }, /* blue */
	{ 205,   0, 205 }, /* magenta */
	{   0, 205, 205 }, /* cyan */
	{ 229, 229, 229 }, /* light grey */
	{ 127, 127, 127 }, /* dark grey */
	{ 255,   0,   0 }, /* light red */
	{   0, 255,   0 }, /* light green */
	{ 255, 255,   0 }, /* light yellow */
	{  92,  92, 255 }, /* light blue */
	{ 255,   0, 255 }, /* light magenta */
	{   0, 255, 255 }, /* light cyan */
	{ 255, 255, 255 }, /* white */
	{ 229, 229, 229 }, /* light grey */
	{   0,   0,   0 }, /* black */
};

static inline void flag_cursor(struct tui_context* c)
{
	c->cursor_upd = true;
	c->dirty = DIRTY_PENDING;
	c->inact_timer = -4;
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

static void copywnd_resized(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	struct copywnd_context* ctx = t;
	if (!ctx->tui)
		return;

	tsm_screen_erase_screen(ctx->tui->screen, false);
	tsm_screen_load(ctx->tui->screen, ctx->buf, 0, 0, 0);
}

static void copywnd_set_labels(
	struct tui_context* c, struct copywnd_context* t)
{
	arcan_shmif_enqueue(&c->acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(LABELHINT),
		.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL,
		.ext.labelhint.label = "PASTE_SELECT",
		.ext.labelhint.descr = "Mark window as clipboard recipient",
		.ext.labelhint.initial = TUIK_RETURN,
		.ext.labelhint.modifiers = TUIM_LMETA
	});
	arcan_shmif_enqueue(&c->acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(LABELHINT),
		.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL,
		.ext.labelhint.label = "EDIT_TOGGLE",
		.ext.labelhint.descr = "Toggle highlight/edit mode",
		.ext.labelhint.initial = TUIK_ESCAPE,
		.ext.labelhint.modifiers = TUIM_LMETA
	});
}

static void copywnd_set_ident(
	struct tui_context *c, struct copywnd_context* tag)
{
	char buf[20];
	snprintf(buf, sizeof(buf), "Copy%s", tag->edit_mode ? ":Edit" : "");
	arcan_tui_ident(c, buf);
}

static bool copywnd_utf8(struct tui_context* c,
	const char* u8, size_t len, void* t)
{
	struct copywnd_context* ctx = t;
	if (!ctx->tui || !ctx->edit_mode)
		return false;

/* some collisions between text input and symbol input where we want
 * the symbol input to be dominant over the text input */
	if (u8[0] == 8 || u8[0] == '\r' || u8[0] == '\n'){
		return false;
	}
	else
	if (u8[0]){
		if (arcan_tui_writeu8(c, (const uint8_t*) u8, len, NULL)){
			return true;
		}
	}
/* edit at current cursor position, then move */
	return false;
}

static void copywnd_mark_cell(
	struct tui_context* c, struct copywnd_context* tag)
{
	tsm_symbol_t ch;
	struct tui_screen_attr attr =	tsm_attr_at_cursor(c->screen, &ch);
	attr.bc[0] = color_palette[tag->color_index][0];
	attr.bc[1] = color_palette[tag->color_index][1];
	attr.bc[2] = color_palette[tag->color_index][2];
	if (ch == 0){
		arcan_tui_writeu8(c, (uint8_t[]){' '}, 1, &attr);
	}
	else
		arcan_tui_write(c, ch, &attr);
	tag->invalidated = true;
}

static void copywnd_color(
	struct tui_context* c, struct copywnd_context* ctx)
{
	ctx->bgc[0] = color_palette[ctx->color_index][0];
	ctx->bgc[1] = color_palette[ctx->color_index][1];
	ctx->bgc[2] = color_palette[ctx->color_index][2];
	c->colors[TUI_COL_CURSOR].rgb[0] = ctx->bgc[0];
	c->colors[TUI_COL_CURSOR].rgb[1] = ctx->bgc[1];
	c->colors[TUI_COL_CURSOR].rgb[2] = ctx->bgc[2];
	flag_cursor(c);
}

static void copywnd_step_mouse(
	struct tui_context* c, struct copywnd_context* tag)
{
	switch (tag->in_select){
/* trigger mark */
	case 1:{
		copywnd_mark_cell(c, tag);
	}
	break;
	case 2:
		arcan_tui_erase_chars(c, 1);
		tag->invalidated = true;
	break;
/* erase */
	case 3:
	break;
/* switch color */
	default:
		return;
	break;
	}
}

static void copywnd_key(struct tui_context* c,
	uint32_t keysym, uint8_t scancode, uint8_t mods, uint16_t subid, void* tag)
{
	struct copywnd_context* ctx = tag;
	if (keysym == TUIK_UP){
		if (mods & (TUIM_LSHIFT | TUIM_RSHIFT))
			copywnd_mark_cell(c, ctx);
		else
			arcan_tui_move_up(c, 1, false);
	}
	else if (keysym == TUIK_DOWN){
		if (mods & (TUIM_LSHIFT | TUIM_RSHIFT))
			copywnd_mark_cell(c, ctx);
		else
			arcan_tui_move_down(c, 1, false);
	}
	else if (keysym == TUIK_LEFT){
		if (mods & (TUIM_LSHIFT | TUIM_RSHIFT))
			copywnd_mark_cell(c, ctx);
		else
			arcan_tui_move_left(c, 1);
	}
	else if (keysym == TUIK_RIGHT){
		if (mods & (TUIM_LSHIFT | TUIM_RSHIFT))
			copywnd_mark_cell(c, ctx);
		else
			arcan_tui_move_right(c, 1);
	}
	else if (keysym == TUIK_RETURN){
		ctx->last_my++;
		arcan_tui_move_to(c, ctx->last_mx, ctx->last_my);
		flag_cursor(c);
	}
	else if (keysym == TUIK_BACKSPACE || keysym == TUIK_CLEAR){
		arcan_tui_erase_chars(c, 1);
		arcan_tui_move_left(c, 1);
		ctx->invalidated = true;
	}
/* copy color at cursor (maybe switch style as well since it will get
 * hard to see where the cursor is, so using a contrast border + hollow
 * will help with the marking */
	else if (keysym == TUIK_ESCAPE){
		tsm_symbol_t ch;
		struct tui_screen_attr attr =	tsm_attr_at_cursor(c->screen, &ch);
		c->colors[TUI_COL_CURSOR].rgb[0] = attr.bc[0];
		c->colors[TUI_COL_CURSOR].rgb[0] = attr.bc[1];
		c->colors[TUI_COL_CURSOR].rgb[0] = attr.bc[2];
		ctx->bgc[0] = attr.bc[0];
		ctx->bgc[1] = attr.bc[1];
		ctx->bgc[2] = attr.bc[2];
		flag_cursor(c);
	}
	else if (keysym >= TUIK_F1 && keysym <= TUIK_F10){
		ctx->color_index = keysym - TUIK_F1;
		copywnd_color(c, ctx);
	}
}

static void copywnd_mouse_motion(struct tui_context* c,
	bool relative, int x, int y, int modifiers, void* t)
{
/* update cursor x, y to match mouse if in edit mode */
	struct copywnd_context* ctx = t;
	if (!ctx->tui || !ctx->edit_mode)
		return;

	int dx = x - ctx->last_x;
	int dy = y - ctx->last_y;

	if (ctx->in_select && (dx || dy)){
/* fill in the blanks as bursts and sample merging might create holes */
		if (dx > 1){
			while (dx--){
				arcan_tui_move_to(c, x-dx, y);
				copywnd_step_mouse(c, ctx);
			}
		}
		if (dx < -1){
			while (dx++){
				arcan_tui_move_to(c, x+dx, y);
				copywnd_step_mouse(c, ctx);
			}
		}
		if (dy > 1){
			while (dy--){
				arcan_tui_move_to(c, x, y-dy);
				copywnd_step_mouse(c, ctx);
			}
		}
		if (dy < -1){
			while (dy++){
				arcan_tui_move_to(c, x, y+dy);
				copywnd_step_mouse(c, ctx);
			}
		}

		ctx->last_x = x;
		ctx->last_y = y;

		arcan_tui_move_to(c, x, y);
		copywnd_step_mouse(c, ctx);
	}
	arcan_tui_move_to(c, x, y);

	ctx->last_mx = x;
	ctx->last_my = y;
}

static void copywnd_mouse_button(struct tui_context* c,
	int last_x, int last_y, int button, bool active, int modifiers,
	void *t)
{
	struct copywnd_context* ctx = t;
	if (!ctx->tui || !ctx->edit_mode)
		return;

	if (ctx->in_select == button){
		if (active){
			return; /* nop, contact bounce or repeat */
		}
/* stop with mouse- mode */
		else {
			ctx->in_select = -1;
			return;
		}
	}

	if (!active)
		return;

/* only step if it is the normal buttons */
	if (button <= 3){
		ctx->in_select = button;
		ctx->last_x = last_x;
		ctx->last_y = last_y;
		copywnd_step_mouse(c, ctx);
	}
/* wheel is mapped to color */
	else {
		if (button == 4){
			ctx->color_index = ctx->color_index > 0 ?
				ctx->color_index - 1 : COUNT_OF(color_palette) - 1;
			copywnd_color(c, ctx);
		}
		else if (button == 5){
			ctx->color_index = ctx->color_index > 0 ?
				ctx->color_index - 1 : COUNT_OF(color_palette) - 1;
			copywnd_color(c, ctx);
		}
	}
}

static bool copywnd_label(struct tui_context* c,
	const char* label, bool active, void* t)
{
	struct copywnd_context* ctx = t;
	if (!ctx->tui)
		return false;

/* atomically grab the only 'paste' target slot */
	if (strcmp(label, "PASTE_SELECT") == 0){
		if (active){
			atomic_store(&paste_destination, ctx->iopipes[1]);
		}
		copywnd_set_ident(c, ctx);
		return true;
	}
	else if (strcmp(label, "EDIT_TOGGLE") == 0){
		if (!active)
			return true;

		if (ctx->edit_mode){
			c->mouse_forward = ctx->edit_mode = false;
			arcan_tui_set_flags(c, TUI_HIDE_CURSOR);
		}
		else {
			c->mouse_forward = ctx->edit_mode = true;
			arcan_tui_set_flags(c, 0);
		}
		copywnd_set_ident(c, ctx);
		return true;
	}
	return false;
}

static void copywnd_reset(struct tui_context* c, int level, void* tag)
{
	copywnd_set_labels(c, (struct copywnd_context*) tag);
	copywnd_set_ident(c, (struct copywnd_context*) tag);
}

static void* copywnd_thread_proc(void* in)
{
	struct copywnd_context* ctx = in;

	tsm_screen_load(ctx->tui->screen, ctx->buf, 0, 0, TSM_LOAD_RESIZE);
	copywnd_reset(ctx->tui, 1, ctx);
	ctx->tui->cursor_hard_off = true;
	int exp = -1;

	while (true){
/* take the paste-slot if no-one has it */
		while(!atomic_compare_exchange_weak(
			&paste_destination, &exp, ctx->iopipes[1]));

		struct tui_process_res res =
			arcan_tui_process(&ctx->tui, 1, &ctx->iopipes[0], 1, -1);

		if (res.errc < TUI_ERRC_OK || res.bad)
			break;

/* paste into */
		uint32_t ch;
		while (4 == read(ctx->iopipes[0], &ch, 4)){
			if (ch == '\n')
				tsm_screen_newline(ctx->tui->screen);
			else
				arcan_tui_write(ctx->tui, ch, NULL);
			ctx->invalidated = true;
		}

		if (-1 == arcan_tui_refresh(ctx->tui) && errno == EINVAL)
			break;
	}

/* remove the paste destination if it happens to be us */
	if (-1 != ctx->iopipes[0]){
		while(!atomic_compare_exchange_weak(
			&paste_destination, &ctx->iopipes[1], -1));
		close(ctx->iopipes[0]);
		close(ctx->iopipes[1]);
	}

	arcan_tui_destroy(ctx->tui, NULL);
	drop_pending(&ctx->buf);
	free(ctx);

	return NULL;
}


/* synch the buffer copy before so we don't lose pasted contents */
static void copywnd_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	struct copywnd_context* ctx = t;
	if (!ctx->tui)
		return;

	struct tsm_save_buf* newbuf;
	if (ctx->invalidated && tsm_screen_save(ctx->tui->screen, true, &newbuf)){
		drop_pending(&ctx->buf);
		ctx->invalidated = false;
		ctx->buf = newbuf;
	}
}

void arcan_tui_copywnd(struct tui_context* src, struct arcan_shmif_cont con)
{
	struct copywnd_context* ctx = malloc(sizeof(struct copywnd_context));
	*ctx = (struct copywnd_context){
		.buf = src->pending_copy_window,
		.iopipes = {-1, -1}
	};

	if (!ctx || -1 == pipe(ctx->iopipes)){
		free(ctx);
		arcan_shmif_drop(&con);
		drop_pending(&src->pending_copy_window);
		return;
	}

/* pipes used to communicate local clipboard data */
	fcntl(ctx->iopipes[0], F_SETFD, O_CLOEXEC);
	fcntl(ctx->iopipes[0], F_SETFL, O_NONBLOCK);
	fcntl(ctx->iopipes[1], F_SETFD, O_CLOEXEC);
	fcntl(ctx->iopipes[1], F_SETFL, O_NONBLOCK);

/* bind the context to a new tui session */
	struct tui_cbcfg cbs = {
		.tag = ctx,
		.resize = copywnd_resize,
		.resized = copywnd_resized,
		.input_label = copywnd_label,
		.input_mouse_motion = copywnd_mouse_motion,
		.input_mouse_button = copywnd_mouse_button,
		.input_utf8 = copywnd_utf8,
		.input_key = copywnd_key,
		.reset = copywnd_reset
	};

	struct tui_settings cfg = arcan_tui_defaults(&con, src);
	ctx->tui = arcan_tui_setup(&con, &cfg, &cbs, sizeof(cbs));
	if (!ctx->tui){
		arcan_shmif_drop(&con);
		close(ctx->iopipes[0]);
		close(ctx->iopipes[1]);
		free(ctx);
		drop_pending(&src->pending_copy_window);
		return;
	}

	ctx->tui->force_bitmap = src->force_bitmap;

/* make the erase color match the cursor */
	ctx->bgc[0] = ctx->tui->colors[TUI_COL_CURSOR].rgb[0];
	ctx->bgc[1] = ctx->tui->colors[TUI_COL_CURSOR].rgb[1];
	ctx->bgc[2] = ctx->tui->colors[TUI_COL_CURSOR].rgb[2];

/* send the session to a new background thread that we detach and ignore */
	pthread_attr_t bgattr;
	pthread_attr_init(&bgattr);
	pthread_attr_setdetachstate(&bgattr, PTHREAD_CREATE_DETACHED);

	pthread_t bgthr;
	if (0 != pthread_create(&bgthr, &bgattr, copywnd_thread_proc, ctx)){
		arcan_shmif_drop(&con);
		close(ctx->iopipes[0]);
		close(ctx->iopipes[1]);
		free(ctx);
		drop_pending(&src->pending_copy_window);
		return;
	}

/* responsibility handed over to thread */
	src->pending_copy_window = NULL;
}
