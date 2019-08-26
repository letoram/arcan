#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"
#include "../screen/libtsm.h"
#include "../screen/libtsm_int.h"

#include <stdio.h>
#include <inttypes.h>
#include <math.h>

void tui_queue_requests(struct tui_context* tui, bool clipboard, bool ident)
{
/* immediately request a clipboard for cut operations (none received ==
 * running appl doesn't care about cut'n'paste/drag'n'drop support). */
/* and send a timer that will be used for cursor blinking when active */
	if (clipboard)
	arcan_shmif_enqueue(&tui->acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.width = 1,
		.ext.segreq.height = 1,
		.ext.segreq.kind = SEGID_CLIPBOARD,
		.ext.segreq.id = 0xfeedface
	});

/* always request a timer as the _tick callback may need it */
	arcan_shmif_enqueue(&tui->acon, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = tui->cursor_period,
		.ext.clock.id = 0xabcdef00,
	});

/* ident is only set on crash recovery */
	if (ident){
		if (tui->last_bchunk_in.ext.bchunk.extensions[0] != '\0')
			arcan_shmif_enqueue(&tui->acon, &tui->last_bchunk_in);

		if (tui->last_bchunk_out.ext.bchunk.extensions[0] != '\0')
			arcan_shmif_enqueue(&tui->acon, &tui->last_bchunk_out);

		if (tui->last_ident.ext.kind != 0)
			arcan_shmif_enqueue(&tui->acon, &tui->last_ident);

		arcan_shmif_enqueue(&tui->acon, &tui->last_state_sz);
	}

	tui_expose_labels(tui);
}

static int parse_color(const char* inv, uint8_t outv[4])
{
	return sscanf(inv, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
		&outv[0], &outv[1], &outv[2], &outv[3]);
}

static void apply_arg(struct tui_settings* cfg,
	struct arg_arr* args, struct tui_context* src)
{
/* FIXME: if src is set, copy settings from there (and dup descriptors) */
	if (!args)
		return;

	const char* val;
	uint8_t ccol[4] = {0x00, 0x00, 0x00, 0xff};
	long vbufv = 0;

	if (arg_lookup(args, "fgc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->fgc[0] = ccol[0]; cfg->fgc[1] = ccol[1]; cfg->fgc[2] = ccol[2];
		}

	if (arg_lookup(args, "bgc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->bgc[0] = ccol[0]; cfg->bgc[1] = ccol[1]; cfg->bgc[2] = ccol[2];
		}

	if (arg_lookup(args, "cc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->cc[0] = ccol[0]; cfg->cc[1] = ccol[1]; cfg->cc[2] = ccol[2];
		}

	if (arg_lookup(args, "clc", 0, &val) && val)
		if (parse_color(val, ccol) >= 3){
			cfg->clc[0] = ccol[0]; cfg->clc[1] = ccol[1]; cfg->clc[2] = ccol[2];
		}

	if (arg_lookup(args, "blink", 0, &val) && val){
		cfg->cursor_period = strtol(val, NULL, 10);
	}

	if (arg_lookup(args, "bgalpha", 0, &val) && val)
		cfg->alpha = strtoul(val, NULL, 10);

	if (arg_lookup(args, "force_bitmap", 0, &val))
		cfg->render_flags |= TUI_RENDER_BITMAP;
}

struct tui_settings arcan_tui_defaults(
	arcan_tui_conn* conn, struct tui_context* ref)
{
	struct tui_settings res = {
		.cell_w = 8,
		.cell_h = 8,
		.alpha = 0xff,
		.bgc = {0x00, 0x00, 0x00},
		.fgc = {0xff, 0xff, 0xff},
		.cc = {0x00, 0xaa, 0x00},
		.clc = {0xaa, 0xaa, 0x00},
		.ppcm = ARCAN_SHMPAGE_DEFAULT_PPCM,
		.hint = 0,
		.mouse_fwd = true,
		.cursor_period = 0,
		.font_sz = 0.0416
	};

	apply_arg(&res, arcan_shmif_args(conn), ref);

	if (ref){
		res.cell_w = ref->cell_w;
		res.cell_h = ref->cell_h;
		res.alpha = ref->alpha;
		res.font_sz = ref->font_sz;
		res.hint = ref->hint;
		res.cursor_period = ref->cursor_period;
		res.render_flags = ref->render_flags;
		res.ppcm = ref->ppcm;
	}
	return res;
}

arcan_tui_conn* arcan_tui_open_display(const char* title, const char* ident)
{
	struct arcan_shmif_cont* res = malloc(sizeof(struct arcan_shmif_cont));
	if (!res)
		return NULL;

	struct shmif_open_ext args = {.type = SEGID_TUI };

	*res = arcan_shmif_open_ext(
		SHMIF_ACQUIRE_FATALFAIL, NULL, (struct shmif_open_ext){
			.type = SEGID_TUI,
			.title = title,
			.ident = ident,
		}, sizeof(struct shmif_open_ext)
	);

	if (!res->addr){
		free(res);
		return NULL;
	}

/* to separate a tui_open_display call from a shmif-context that is
 * retrieved from another setting, we tag the user field to know it is
 * safe to free */
	res->user = (void*) 0xfeedface;
	return res;
}

void arcan_tui_destroy(struct tui_context* tui, const char* message)
{
	if (!tui)
		return;

	if (tui->clip_in.vidp)
		arcan_shmif_drop(&tui->clip_in);

	if (tui->clip_out.vidp)
		arcan_shmif_drop(&tui->clip_out);

	if (message)
		arcan_shmif_last_words(&tui->acon, message);

	arcan_shmif_drop(&tui->acon);
	tsm_utf8_mach_free(tui->ucsconv);

	free(tui->base);

	memset(tui, '\0', sizeof(struct tui_context));
	free(tui);
}

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
}

/*
 * though we are supposed to be prerolled the colors from our display
 * server connection, it's best to have something that gets activated
 * initially regardless..
 */
static void set_builtin_palette(struct tui_context* ctx)
{
	ctx->colors[TUI_COL_CURSOR] = (struct color){0x00, 0xff, 0x00};
	ctx->colors[TUI_COL_ALTCURSOR] = (struct color){0x00, 0xff, 0x00};
	ctx->colors[TUI_COL_HIGHLIGHT] = (struct color){0x26, 0x8b, 0xd2};
	ctx->colors[TUI_COL_BG] = (struct color){0x2b, 0x2b, 0x2b};
	ctx->colors[TUI_COL_PRIMARY] = (struct color){0x13, 0x13, 0x13};
	ctx->colors[TUI_COL_SECONDARY] = (struct color){0x42, 0x40, 0x3b};
	ctx->colors[TUI_COL_TEXT] = (struct color){0xff, 0xff, 0xff};
	ctx->colors[TUI_COL_LABEL] = (struct color){0xff, 0xff, 0x00};
	ctx->colors[TUI_COL_WARNING] = (struct color){0xaa, 0xaa, 0x00};
	ctx->colors[TUI_COL_ERROR] = (struct color){0xaa, 0x00, 0x00};
	ctx->colors[TUI_COL_ALERT] = (struct color){0xaa, 0x00, 0xaa};
	ctx->colors[TUI_COL_REFERENCE] = (struct color){0x20, 0x30, 0x20};
	ctx->colors[TUI_COL_INACTIVE] = (struct color){0x20, 0x20, 0x20};
}

struct tui_context* arcan_tui_setup(struct arcan_shmif_cont* con,
	const struct tui_settings* set, const struct tui_cbcfg* cbs,
	size_t cbs_sz, ...)
{
	if (!set || !con || !cbs)
		return NULL;

	struct tui_context* res = malloc(sizeof(struct tui_context));
	if (!res)
		return NULL;
	*res = (struct tui_context){};

/*
 * if the connection comes from _open_display, free the intermediate
 * context store here and move it to our tui context
 */
	bool managed = (uintptr_t)con->user == 0xfeedface;
	res->acon = *con;
	if (managed)
		free(con);

/*
 * only in a managed context can we retrieve the initial state truthfully,
 * for subsegments the values are derived from parent via the defaults stage.
 */
	struct arcan_shmif_initial* init = NULL;
	if (sizeof(struct arcan_shmif_initial) != arcan_shmif_initial(con, &init)
		&& managed){
		LOG("initial structure size mismatch, out-of-synch header/shmif lib\n");
		arcan_shmif_drop(&res->acon);
		free(res);
		return NULL;
	}

	if (tsm_screen_new(&res->screen, tsm_log, res) < 0){
		LOG("failed to build screen structure\n");
		if (managed)
			arcan_shmif_drop(&res->acon);
		free(res);
		return NULL;
	}

/*
 * due to handlers being default NULL, all fields are void* / fptr*
 * (and we assume sizeof(void*) == sizeof(fptr*) which is somewhat
 * sketchy, but if that's a concern, subtract the offset of tag),
 * and we force the caller to provide its perceived size of the
 * struct we can expand the interface without breaking old clients
 */
	if (cbs_sz > sizeof(struct tui_cbcfg) || cbs_sz % sizeof(void*) != 0){
		LOG("arcan_tui(), caller provided bad size field\n");
		return NULL;
	}
	memcpy(&res->handlers, cbs, cbs_sz);

	if (init){
		res->ppcm = init->density;
	}
	else
		res->ppcm = set->ppcm;

	res->alpha = set->alpha;
	res->cell_w = set->cell_w;
	res->cell_h = set->cell_h;
	set_builtin_palette(res);
	memcpy(res->colors[TUI_COL_CURSOR].rgb, set->cc, 3);
	memcpy(res->colors[TUI_COL_ALTCURSOR].rgb, set->clc, 3);
	memcpy(res->colors[TUI_COL_BG].rgb, set->bgc, 3);
	memcpy(res->colors[TUI_COL_TEXT].rgb, set->fgc, 3);
	res->hint = set->hint;
	res->mouse_forward = set->mouse_fwd;
	res->cursor_period = set->cursor_period;
	res->cursor = set->cursor;
	res->render_flags = set->render_flags;
	res->font_sz = set->font_sz;

/* TEMPORARY: while moving to server-side rasterization */
	res->rbuf_fwd = getenv("TUI_RPACK");
	if (res->rbuf_fwd)
		res->acon.hints = SHMIF_RHINT_TPACK;
	else
		res->acon.hints = SHMIF_RHINT_SUBREGION;

/* tui_fontmgmt is also responsible for building the raster context */
	tui_fontmgmt_setup(res, init);
	if (0 != tsm_utf8_mach_new(&res->ucsconv)){
		free(res);
		return NULL;
	}

	tsm_screen_set_def_attr(res->screen,
		&(struct tui_screen_attr){
			.fr = res->colors[TUI_COL_TEXT].rgb[0],
			.fg = res->colors[TUI_COL_TEXT].rgb[1],
			.fb = res->colors[TUI_COL_TEXT].rgb[2],
			.br = res->colors[TUI_COL_BG].rgb[0],
			.bg = res->colors[TUI_COL_BG].rgb[1],
			.bb = res->colors[TUI_COL_BG].rgb[2]
		}
	);
	tsm_screen_set_max_sb(res->screen, 1000);

/* clipboard, timer callbacks, no IDENT */
	tui_queue_requests(res, true, false);

/* show the current cell dimensions to help limit resize requests */
	arcan_shmif_enqueue(&res->acon,
		&(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(CONTENT),
			.ext.content.cell_w = res->cell_w,
			.ext.content.cell_h = res->cell_h
		}
	);

	tui_screen_resized(res);

	if (res->handlers.resized)
		res->handlers.resized(res, res->acon.w, res->acon.h,
			res->cols, res->rows, res->handlers.tag);

	return res;
}
