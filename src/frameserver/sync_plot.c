/*
 * Arcan Frameserver Quick'n'Dirty timing graphing
 * Copyright 2012-2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

#include "arcan_shmif.h"
#include "sync_plot.h"

#include "graphing/net_graph.h"

#ifndef GRAPH_BUFFER_SIZE
#define GRAPH_BUFFER_SIZE 160
#endif

struct graph_int {
	struct graph_context* graphing;
	struct arcan_shmif_cont* cont;

	timestamp_t frametimes[GRAPH_BUFFER_SIZE];
	timestamp_t framedrops[GRAPH_BUFFER_SIZE];
	timestamp_t framexfer[GRAPH_BUFFER_SIZE];

	unsigned xfercosts[GRAPH_BUFFER_SIZE];
	unsigned abufsizes[GRAPH_BUFFER_SIZE];

	size_t ofs_time, ofs_drop, ofs_xfer, ofs_cost, ofs_abufsz;
};

#define stepmsg(ctx, x, yv) \
	draw_box(ctx, 0, yv, PXFONT_WIDTH * strlen(x),\
		PXFONT_HEIGHT, 0xff000000);\
	draw_text(ctx, x, 0, yv, 0xffffffff);\
	yv += PXFONT_HEIGHT;

static void f_update(struct synch_graphing* ctx, float period, const char* msg)
{
	size_t yv = 0;
	struct graph_int* priv = ctx->priv;
	char* work = strdup(msg);
	char* ctxp;
	char* cp = strtok_r(work, "\n", &ctxp);

	if (priv->cont->addr->vready)
		return;

	draw_box(priv->graphing, 0, 0, priv->cont->addr->w,
		priv->cont->addr->h, 0xffffffff);

	while(cp){
		stepmsg(priv->graphing, cp, yv);
		cp = strtok_r(NULL, "\n", &ctxp);
	}

	free(work);

/* color-coded frame timing / alignment, starting at the far right
 * with the next intended frame, horizontal resolution is 2 px / ms */
	int dw = priv->cont->addr->w;

	draw_box(priv->graphing, 0, yv, dw, PXFONT_HEIGHT * 2, 0xff000000);
	draw_hline(priv->graphing, 0, yv + PXFONT_HEIGHT, dw, 0xff999999);

/* first, ideal deadlines, now() is at the end of the X scale */
	int stepc = 0;
	double current = arcan_timemillis();
	double minp    = current - dw;
	double mspf    = period;
	double startp  = (double) current - modf(current, &mspf);

	while ( startp - (stepc * period) >= minp ){
		draw_vline(priv->graphing, startp -
			(stepc * period) - minp, yv + PXFONT_HEIGHT - 1,
				-(PXFONT_HEIGHT-1), 0xff00ff00);
		stepc++;
	}

/*
 * second, actual frames, plot against ideal,
 * step back etc. until we land outside range
 */
	size_t cellsz = sizeof(priv->frametimes) / sizeof(priv->frametimes[0]);

#define STEPBACK(X) ( (X) > 0 ? (X) - 1 : cellsz - 1)
	int ofs = STEPBACK(priv->ofs_time);

	while (true){
		if (priv->frametimes[ofs] >= minp)
			draw_vline(priv->graphing, current -
				priv->frametimes[ofs], yv + PXFONT_HEIGHT + 1,
				PXFONT_HEIGHT - 1, 0xff00ffff);
		else
			break;

		ofs = STEPBACK(ofs);
		if (priv->frametimes[ofs] >= minp)
			draw_vline(priv->graphing, current -
				priv->frametimes[ofs], yv + PXFONT_HEIGHT + 1,
				PXFONT_HEIGHT - 1, 0xff00aaaa);
		else
			break;

		ofs = STEPBACK(ofs);
	}

	cellsz = sizeof(priv->framedrops) / sizeof(priv->framedrops[0]);
	ofs = STEPBACK(priv->ofs_drop);

	while (priv->framedrops[ofs] >= minp){
		draw_vline(priv->graphing, current -
			priv->framedrops[ofs], yv + PXFONT_HEIGHT + 1,
				PXFONT_HEIGHT - 1, 0xff0000ff);
		ofs = STEPBACK(ofs);
	}

/* lastly, the transfer costs, sweep twice,
 * first for Y scale then for drawing */
	cellsz = sizeof(priv->xfercosts) / sizeof(priv->xfercosts[0]);
	ofs = STEPBACK(priv->ofs_xfer);
	int maxv = 0, count = 0;

	while( count < priv->cont->addr->w ){
		if (priv->xfercosts[ ofs ] > maxv)
			maxv = priv->xfercosts[ ofs ];

		count++;
		ofs = STEPBACK(ofs);
	}

	if (maxv > 0){
			yv += PXFONT_HEIGHT * 2;
		float yscale = (float)(PXFONT_HEIGHT * 2) / (float) maxv;
		ofs = STEPBACK(priv->ofs_xfer);
		count = 0;
		draw_box(priv->graphing, 0, yv, dw, PXFONT_HEIGHT * 2, 0xff000000);

		while (count < dw){
			int sample = priv->xfercosts[ofs];

			if (sample > -1)
				draw_vline(priv->graphing, dw - count - 1, yv +
					(PXFONT_HEIGHT * 2), -1 * yscale * sample, 0xff00ff00);
			else
				draw_vline(priv->graphing, dw - count - 1, yv +
					(PXFONT_HEIGHT * 2), -1 * PXFONT_HEIGHT * 2, 0xff0000ff);

			ofs = STEPBACK(ofs);
			count++;
		}
	}

	if (ctx->state == SYNCH_INDEPENDENT)
		priv->cont->addr->vready = true;
}

static void f_cont_switch(struct synch_graphing* ctx,
	struct arcan_shmif_cont* newcont)
{
	struct graph_int* g = ctx->priv;
	g->cont = newcont;
	graphing_destroy(g->graphing);
	g->graphing = graphing_new(newcont->addr->w,
		newcont->addr->h, (uint32_t*) newcont->vidp);
}

#define STEP_FIELD(ptr, ary, ofs, val) { \
		ptr->ary[ptr->ofs] = val; \
		ptr->ofs = (ptr->ofs + 1) % (sizeof(ptr->ary) / sizeof(ptr->ary[0]));\
	}

static void f_mark_input(struct synch_graphing* ctx, timestamp_t ts)
{
}

static void f_mark_drop(struct synch_graphing* ctx, timestamp_t ts)
{
	struct graph_int* g = ctx->priv;
	STEP_FIELD(g, framedrops, ofs_drop, ts);
}

static void f_mark_abuf_size(struct synch_graphing* ctx, unsigned size)
{
	struct graph_int* g = ctx->priv;
	STEP_FIELD(g, abufsizes, ofs_abufsz, size);
}

static void f_mark_video_sync(struct synch_graphing* ctx, timestamp_t val)
{
	struct graph_int* g = ctx->priv;
	STEP_FIELD(g, frametimes, ofs_time, val);
}

static void f_mark_video_transfer(
	struct synch_graphing* ctx, timestamp_t when, unsigned cost)
{
	struct graph_int* g = ctx->priv;
	STEP_FIELD(g, framexfer, ofs_xfer, cost);
	STEP_FIELD(g, frametimes, ofs_xfer, when);
}

static void f_free(struct synch_graphing** ctx)
{
	free((*ctx)->priv);
	memset(*ctx, '\0', sizeof(struct synch_graphing));
	free(*ctx);
	*ctx = NULL;
}

struct synch_graphing* setup_synch_graph(
	struct arcan_shmif_cont* cont, bool overlay)
{
	struct synch_graphing res = {
		.update = f_update,
		.mark_input = f_mark_input,
		.mark_drop = f_mark_drop,
		.mark_abuf_size = f_mark_abuf_size,
		.mark_start = f_mark_video_sync,
		.mark_stop = f_mark_video_sync,
		.mark_transfer = f_mark_video_transfer,
		.cont_switch = f_cont_switch,
		.free = f_free
	};

	if (overlay){
		res.state = SYNCH_OVERLAY;
	}
	else {
		res.state = SYNCH_INDEPENDENT;
	}

	struct synch_graphing* resp = malloc(sizeof(struct synch_graphing));
	struct graph_int* priv = malloc(sizeof(struct graph_int));
	memset(priv, '\0', sizeof(struct graph_int));

	res.priv = priv;
	priv->cont = cont;

	priv->graphing = graphing_new(cont->addr->w,
		cont->addr->h, (uint32_t*) cont->vidp);

	*resp = res;
	return resp;
}
