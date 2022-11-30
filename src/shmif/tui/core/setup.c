#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"
#include "arcan_ttf.h"
#include "../raster/raster.h"

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
		.ext.clock.rate = 1,
		.ext.clock.id = 0xabcdef00,
	});

/* ident is only set on crash recovery */
	if (ident){
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

/* possible command line overrides */
static void apply_arg(struct tui_context* src, struct arg_arr* args)
{
	if (!args)
		return;

	const char* val = NULL;
	if (arg_lookup(args, "bgalpha", 0, &val) && val)
		src->alpha = strtoul(val, NULL, 10);
}

arcan_tui_conn* arcan_tui_open_display(const char* title, const char* ident)
{
	struct arcan_shmif_cont* res = malloc(sizeof(struct arcan_shmif_cont));
	if (!res)
		return NULL;

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

	res->user = (void*) 0xdeadbeef;
	return res;
}

void arcan_tui_destroy(struct tui_context* tui, const char* message)
{
	if (!tui)
		return;

	if (tui->parent){
		for (size_t i = 0; i < COUNT_OF(tui->parent->children); i++){
			if (tui->parent->children[i] == tui){
				tui->parent->children[i] = NULL;
				break;
			}
		}
		tui->parent = NULL;
	}

	for (size_t i = 0; i < COUNT_OF(tui->children); i++){
		if (tui->children[i] && tui->children[i]->parent == tui)
			tui->children[i]->parent = NULL;
	}

	if (tui->clip_in.vidp)
		arcan_shmif_drop(&tui->clip_in);

	if (tui->clip_out.vidp)
		arcan_shmif_drop(&tui->clip_out);

	if (tui->acon.addr){
		if (message)
			arcan_shmif_last_words(&tui->acon, message);

		arcan_shmif_drop(&tui->acon);
	}

	free(tui->base);

	memset(tui, '\0', sizeof(struct tui_context));
	free(tui);
}

/*
 * though we are supposed to be prerolled the colors from our display server
 * connection, it's best to have something that gets activated initially
 * regardless..
 */
static void set_builtin_palette(struct tui_context* ctx)
{
	arcan_tui_set_color(ctx, TUI_COL_CURSOR, (uint8_t[]){0x00, 0xff, 0x00});
	arcan_tui_set_bgcolor(ctx, TUI_COL_CURSOR, (uint8_t[]){0x00, 0xff, 0x00});

	arcan_tui_set_color(ctx, TUI_COL_ALTCURSOR, (uint8_t[]){0xff, 0xff, 0x00});
	arcan_tui_set_bgcolor(ctx, TUI_COL_ALTCURSOR, (uint8_t[]){0xff, 0xff, 0x00});

	arcan_tui_set_color(ctx, TUI_COL_PRIMARY, (uint8_t[]){0xff, 0xff, 0xff});
	arcan_tui_set_color(ctx, TUI_COL_SECONDARY, (uint8_t[]){0xaa, 0xaa, 0xaa});

	arcan_tui_set_bgcolor(ctx, TUI_COL_BG, (uint8_t[]){0x10, 0x10, 0x10});

	arcan_tui_set_color(ctx, TUI_COL_TEXT, (uint8_t[]){0xaa, 0xaa, 0xaa});
	arcan_tui_set_bgcolor(ctx, TUI_COL_TEXT, (uint8_t[]){0x10, 0x10, 0x10});

	arcan_tui_set_color(ctx, TUI_COL_HIGHLIGHT, (uint8_t[]){246, 84, 0});
	arcan_tui_set_bgcolor(ctx, TUI_COL_HIGHLIGHT, (uint8_t[]){0x10, 0x10, 0x10});

	arcan_tui_set_color(ctx, TUI_COL_LABEL, (uint8_t[]){0xff, 0xff, 0xff});
	arcan_tui_set_bgcolor(ctx, TUI_COL_LABEL, (uint8_t[]){0x00, 0x00, 0x00});

	arcan_tui_set_color(ctx, TUI_COL_WARNING, (uint8_t[]){255, 255, 255});
	arcan_tui_set_bgcolor(ctx, TUI_COL_WARNING, (uint8_t[]){246, 84, 0});

	arcan_tui_set_color(ctx, TUI_COL_ERROR, (uint8_t[]){255, 255, 255});
	arcan_tui_set_bgcolor(ctx, TUI_COL_ERROR, (uint8_t[]){190, 0, 0});

	arcan_tui_set_color(ctx, TUI_COL_ALERT, (uint8_t[]){190, 0, 0});
	arcan_tui_set_bgcolor(ctx, TUI_COL_ALERT, (uint8_t[]){0x10, 0x10, 0x10});

	arcan_tui_set_color(ctx, TUI_COL_REFERENCE, (uint8_t[]){31, 104, 230});
	arcan_tui_set_bgcolor(ctx, TUI_COL_REFERENCE, (uint8_t[]){0x10, 0x10, 0x10});

	arcan_tui_set_color(ctx, TUI_COL_INACTIVE, (uint8_t[]){0x80, 0x80, 0x80});
	arcan_tui_set_bgcolor(ctx, TUI_COL_INACTIVE, (uint8_t[]){0x00, 0x00, 0x00});

	arcan_tui_set_color(ctx, TUI_COL_UI, (uint8_t[]){255, 255, 255});
	arcan_tui_set_bgcolor(ctx, TUI_COL_UI, (uint8_t[]){31, 104, 230});

/* legacy terminal color-set */
	arcan_tui_set_color(ctx, TUI_COL_TBASE+0, (uint8_t[]){0, 0, 0});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+1, (uint8_t[]){205, 0, 0});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+2, (uint8_t[]){0, 205, 0});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+3, (uint8_t[]){205, 205, 0});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+4, (uint8_t[]){0, 0, 238});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+5, (uint8_t[]){205, 0, 205});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+6, (uint8_t[]){0, 205, 205});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+7, (uint8_t[]){229, 229, 229});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+8, (uint8_t[]){127, 127, 127});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+9, (uint8_t[]){255, 0, 0});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+10, (uint8_t[]){0, 255, 0});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+11, (uint8_t[]){255, 255, 0});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+12, (uint8_t[]){0, 0, 255});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+13, (uint8_t[]){255, 0, 255});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+14, (uint8_t[]){0, 255, 255});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+15, (uint8_t[]){255, 255, 255});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+16, (uint8_t[]){229, 229, 229});
	arcan_tui_set_color(ctx, TUI_COL_TBASE+17, (uint8_t[]){0, 0, 0});
}

static bool late_bind(
	arcan_tui_conn* con, struct tui_context* res, bool setup)
{
/*
 * if the connection comes from _open_display, free the intermediate
 * context store here and move it to our tui context
 */
	bool managed = false;

/* unbind from current? */
	if (!con){
		res->acon = (struct arcan_shmif_cont){0};
		return true;
	}

/* or attach new */
	res->acon = *con;
	if( (uintptr_t)con->user == 0xdeadbeef){
		if (managed)
			free(con);
		managed = true;
	}

/*
 * only in a managed context can we retrieve the initial state truthfully, as
 * it only takes a NEWSEGMENT event, not a context activation like for the
 * primary. Thus derive from the primary in that case, inherit from the parent
 * and then let any dynamic overrides appear as normal.
 */
	struct arcan_shmif_initial* init = NULL;
	if (sizeof(struct arcan_shmif_initial) !=
		arcan_shmif_initial(&res->acon, &init) && managed){
		LOG("initial structure size mismatch, out-of-synch header/shmif lib\n");
		arcan_shmif_drop(&res->acon);
		free(res);
		return false;
	}

/* this could have been set already by deriving from a parent */
	if (!res->ppcm){
		if (init){
			res->ppcm = init->density;
			res->cell_w = init->cell_w;
			res->cell_h = init->cell_h;
		}
		else
			res->ppcm = ARCAN_SHMPAGE_DEFAULT_PPCM;
	}

	if (!res->cell_w)
		res->cell_w = 8;

	if (!res->cell_h)
		res->cell_h = 8;

	tui_fontmgmt_setup(res, init);

	arcan_shmif_mousestate_setup(&res->acon, false, res->mouse_state);
	res->acon.hints = SHMIF_RHINT_TPACK | SHMIF_RHINT_VSIGNAL_EV;

/* clipboard, timer callbacks, no IDENT */
	tui_queue_requests(res, true, false);

	arcan_shmif_resize_ext(&res->acon,
		res->acon.w, res->acon.h,
		(struct shmif_resize_ext){
			.vbuf_cnt = -1,
			.abuf_cnt = -1,
			.rows = res->acon.h / res->cell_h,
			.cols = res->acon.w / res->cell_w
		}
	);

	for (size_t i = 0; init && i <
			COUNT_OF(init->colors) && i < COUNT_OF(res->colors); i++){
		if (init->colors[i].fg_set)
			memcpy(res->colors[i].rgb, init->colors[i].fg, 3);

		if (init->colors[i].bg_set){
			memcpy(res->colors[i].bg, init->colors[i].bg, 3);
			res->colors[i].bgset = true;
		}
	}

	tui_screen_resized(res);

	if (res->handlers.resized)
		res->handlers.resized(res, res->acon.w, res->acon.h,
			res->cols, res->rows, res->handlers.tag);

	return true;
}

bool arcan_tui_bind(arcan_tui_conn* con, struct tui_context* orphan)
{
	return late_bind(con, orphan, false);
}

struct tui_context* arcan_tui_setup(
	arcan_tui_conn* con,
	struct tui_context* parent,
	const struct tui_cbcfg* cbs,
	size_t cbs_sz, ...)
{
/* empty- con is permitted in order to allow 'late binding' of an orphaned
 * context, a way to pre-manage tui contexts without waiting for a matching
 * subwindow request */
	if (!cbs)
		return NULL;

	struct tui_context* res = malloc(sizeof(struct tui_context));
	if (!res)
		return NULL;
	*res = (struct tui_context){
		.alpha = 0xff,
		.font_sz = 0.0416,
		.flags = TUI_ALTERNATE,
		.cell_w = 8,
		.cell_h = 8
	};

	res->defattr = (struct tui_screen_attr){
		.bc = TUI_COL_TEXT,
		.fc = TUI_COL_TEXT,
		.aflags = TUI_ATTR_COLOR_INDEXED
	};

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

	set_builtin_palette(res);

/* con can be bad (NULL) or reserved (-1) and in those cases we should not
 * try to extract the default set of arguments because there aren't any. */
	if (con && (uintptr_t)-1 != (uintptr_t) con)
		apply_arg(res, arcan_shmif_args(con));

/* tui_fontmgmt is also responsible for building the raster context */
/* if we have a parent, we should derive settings etc. from there.
 *
 * There is a special state parent can be in if there is a handover subsegment
 * pending. This is used to be able to embed a handover segment into ourselves
 * and to make the API for that work like everything else, the tactic is to
 * create an non-bound context where we track the cookie for handover. See the
 * newsegment in dispatch.c
 *
 * This also allows us to have a way of forwarding events to the handover
 * context (say by implementing a shmif-server inherited connection), unpack
 * into the proxy- window and blit into ourselves if our connection rejects
 * additional subwindows. */
	if (parent){
		res->alpha = parent->alpha;
		res->cursor = parent->cursor;
		res->ppcm = parent->ppcm;

		tui_fontmgmt_setup(res, &(struct arcan_shmif_initial){
			.fonts = {
				{
					.size_mm = parent->font_sz,
					.fd = arcan_shmif_dupfd(parent->font[0]->fd, -1, true)
				},
				{
					.size_mm = parent->font_sz,
					.fd = arcan_shmif_dupfd(parent->font[1]->fd, -1, true)
				}
		}});

		if (parent->pending_handover){
			res->viewport_proxy = parent->pending_handover;
			parent->pending_handover = 0;
/* track hierarchical relationship,
 * used for embedding to work when there is a handover */
			res->parent = parent;
			for (size_t i = 0; i < COUNT_OF(parent->children); i++){
				if (!parent->children[i]){
					parent->children[i] = res;
					break;
				}
			}
		}
	}

	if (con && (uintptr_t)-1 != (uintptr_t) con)
		late_bind(con, res, true);

	if (parent){
		memcpy(res->colors, parent->colors, sizeof(res->colors));
		res->defattr = parent->defattr;
	}

/* allow our own formats to be exposed */
	arcan_tui_announce_io(res, false, NULL, "tui-raw");

	return res;
}
