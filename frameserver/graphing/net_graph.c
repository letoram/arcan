/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3 
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/types.h>
#include <assert.h>

#include "net_graph.h"
#include "../../arcan_math.h"
#include "../../arcan_general.h"
#include "../arcan_frameserver.h"

/* 
 * allocate context -> depending on type, different buckets are set up. Each bucket maintain separate data-tracking,
 * can have different rendering modes etc. Buckets are populated indirectly through calling the exported higher-abstraction
 * functions ("connected", "sending tlv", ...) and the rendering mode of the context define how the buckets are setup,
 * scaling, refreshes etc. 
 */

/* can be created by taking a TTF font,
 * convert -resize 8x8\! -font Name-Family-Style -pointsize num label:CodePoint outp.xbm
 * sweep through the desired codepoints and build the outer array, dump to header and replace */
#include "font_8x8.h"
#define PXFONT font8x8_basic
#define PXFONT_WIDTH 8
#define PXFONT_HEIGHT 8

static const int pxfont_width = PXFONT_WIDTH;
static const int pxfont_height = PXFONT_HEIGHT;

#define GRAPH_SERVER(X) ( (X) >= GRAPH_NET_SERVER && (X) < GRAPH_NET_CLIENT )

enum plot_mode {
	PLOT_XY_POINT,
	PLOT_XY_LERP,
	PLOT_XY_ROW
};

struct datapoint {
	long long int timestamp; 
	const char* label; /* optional */
	bool continuous;   /* part of the regular dataflow or should be treated as an alarm */

	char type_id;      /* union selector */
	union {
		int ival;
		float fval;
	} value;
};

struct event_bucket {
	bool labels;   /* render possibly attached labels */
	bool absolute; /* should basev/maxv/minv be relative to window or accumulate */
	enum plot_mode mode; 
	
/* data model -- ring-buffer of datapoints, these and scales are
 * modified dynamically based on the domain- specific events further below */
	int ringbuf_sz, buf_front, buf_back;
	struct datapoint* ringbuf;

/* x scale */
	const char* suffix_x;
	long long int last_updated;
	long long int window_beg;

/* y scale */
	const char* suffix_y;
	int maxv, minv, basev;
};

struct graph_context {
/* graphing storage */
	int width, height;
	uint32_t* vidp;

	struct {
		uint32_t bg;
		uint32_t border;
		uint32_t grid;
		uint32_t gridalign;
		uint32_t data;
		uint32_t alert;
		uint32_t notice;
	} colors;

/* data storage */
	int n_buckets;
	struct event_bucket* buckets;
	
/* mode is determined on context creation, and determines how logged entries
 * will be stored and presented */
	enum graphing_mode mode;
};

static inline void draw_hline(struct graph_context* ctx, int x, int y, int width, uint32_t col)
{
/* clip */
	if (y < 0 || y >= ctx->height)
		return;

	if (x + width > ctx->width)
		width = ctx->width - x;
	
	uint32_t* buf = &ctx->vidp[y * ctx->width + x];

	while (--width > 0)
		*(buf++) = col;
}

static inline void draw_vline(struct graph_context* ctx, int x, int y, int height, uint32_t col)
{
	if (x < 0 || x >= ctx->width)
		return;

	if (y + height > ctx->height)
		height = ctx->height - y;
	
	uint32_t* buf = &ctx->vidp[y * ctx->width + x];
	
	while (--height > 0){
		*buf = col;
		buf += ctx->width;
	}
}

static inline void clear_tocol(struct graph_context* ctx, uint32_t col)
{
	int ntc = ctx->width * ctx->height;
	for (int i = 0; i < ntc; i++)
		ctx->vidp[i] = col;
}

static inline void draw_square(struct graph_context* ctx, int x, int y, int side, uint32_t col)
{
	int lx = x - side >= 0 ? x - side : 0;
	int ly = y - side >= 0 ? y - side : 0;
	int ux = x + side >= ctx->width ? ctx->width - 1 : x + side;
	int uy = y + side >= ctx->height ? ctx->height - 1 : y + side;

	for (int cy = ly; cy != uy; cy++)
		for (int cx = lx; cx != ux; cx++)
			ctx->vidp[ cy * ctx->width + cx ] = col;
}

/* use the included 8x8 bitmap font to draw simple 7-bit ASCII messages */
static void draw_text(struct graph_context* ctx, const char* msg, int x, int y, uint32_t txcol)
{
	if (y + pxfont_height >= ctx->height)
		return;

	while (*msg && x+pxfont_width < ctx->width){
/* font only has that many entry points */
		if (*msg <= 127)
			for (int row = 0; row < pxfont_height; row++)
				for (int col = 0; col < pxfont_width; col++)
/* no AA, no blending, no filtering */
					if (PXFONT[*msg][row] & 1 << col)
						ctx->vidp[ctx->width * (row + y) + col + x] = txcol;

			x += pxfont_width;
			msg++;
	}
}

static void draw_bucket(struct graph_context* ctx, struct event_bucket* src, int x, int y, int w, int h)
{
/* with labels toggled, the issue is if labels should be placed closed to the datapoint,
 * or if separate space should be allocated beneath the grid and use colors to map */
	draw_vline(ctx, x, y, h, ctx->colors.border);
	draw_hline(ctx, x, y, w, ctx->colors.border);

	int step_sz = (src->maxv - src->minv) / y;
	int i = src->buf_back;
/* we use the bucket midpoint as 0 for y axis, it should be <= minv */

	switch (src->mode){
		case PLOT_XY_POINT:
			while (i != src->buf_front){
				int xv, yv;
				uint32_t col;
				draw_square(ctx, xv, yv, 4, col);
				i = (i + 1) % src->ringbuf_sz;
			}
		break;
		case PLOT_XY_LERP:  break;
		case PLOT_XY_ROW:   break;
		default:
			LOG("net_graph(draw_bucket) -- unknown mode specified (%d)\n", src->mode);
			abort();
	}
}

/* These two functions traverses the history buffer, drops the elements that are outside the current time-window,
 * and converts the others to draw-calls, layout is different for server (1:n) and client (1:1). */
static bool graph_refresh_server(struct graph_context* ctx)
{
	switch (ctx->mode){
/* just draw discover- server and one client, similar to client mode */
		case GRAPH_NET_SERVER_SINGLE:

		break;

		case GRAPH_NET_SERVER:

		break;
	}
	
	return true;
}

/* divide Y- res based on number of event- buckets in time-window (client should really just have one or two)
 * render each event-bucket based on the graph- profile of the bucket */
static bool graph_refresh_client(struct graph_context* ctx)
{
	long long int ts = frameserver_timemillis();
	int bucketh = (ctx->height - 10) / 3;

/* two buckets, one (height / 3) for discovery domain data, one for main domain */
	clear_tocol(ctx, ctx->colors.bg);
	
	switch (ctx->n_buckets){
		case 1: draw_bucket(ctx, &ctx->buckets[0], 0, 0, ctx->width, ctx->height); break;
		case 2: 
			draw_bucket(ctx, &ctx->buckets[0], 0, 0, ctx->width, bucketh);
			draw_bucket(ctx, &ctx->buckets[1], 0, 10 + bucketh, ctx->width, bucketh * 2);
		break;
		default:
			LOG("graphing(graph_refresh_client) : draw failed, unhandled number of buckets (%d)\n", ctx->n_buckets);
			abort();
	}

	return true;
}

bool graph_refresh(struct graph_context* ctx)
{
	if (ctx->mode != GRAPH_NET_CLIENT)
		return graph_refresh_server(ctx);
	else 
		return graph_refresh_client(ctx); 
}

/* setup basic context (history buffer etc.)
 * along with colours etc. to some defaults. */
struct graph_context* graphing_new(enum graphing_mode mode, int width, int height, uint32_t* vidp)
{
	if (width * height == 0)
		return NULL;

	struct graph_context* rctx = malloc( sizeof(struct graph_context) );
	
	if (rctx){
		struct graph_context rv = { .mode = mode, .width = width, .height = height, .vidp = vidp,
			.colors.bg = 0xffffffff, .colors.border = 0xff000000, .colors.grid = 0xffaaaaaa, .colors.gridalign = 0xffff4444,
			.colors.data = 0xff00ff00, .colors.alert = 0xffff0000, .colors.notice = 0xff0000ff };
			*rctx = rv;
	}
	return rctx;
}

void graph_tick(struct graph_context* ctx, long long int timestamp)
{
	assert(ctx);

	/* rescale time-window for all buckets and throw away those that fall outside */
}

/* all these events are simply translated to a data-point and inserted into the related bucket */
void graph_log_connected(struct graph_context* ctx, char* label)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	} else {
	}
	
}

void graph_log_connecting(struct graph_context* ctx, char* label)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}

}

void graph_log_connection(struct graph_context* ctx, unsigned id, const char* label)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}
}

void graph_log_disconnect(struct graph_context* ctx, unsigned id, const char* label)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}
}

void graph_log_discover_req(struct graph_context* ctx, unsigned id, const char* label)
{
	assert(ctx);
	
	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}
}

void graph_log_discover_rep(struct graph_context* ctx, unsigned id, const char* label)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}
}

void graph_log_tlv_in(struct graph_context* ctx, unsigned id, const char* label, unsigned tag, unsigned len)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}
}

void graph_log_tlv_out(struct graph_context* ctx, unsigned id, const char* label, unsigned tag, unsigned len)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}
}

void graph_log_conn_error(struct graph_context* ctx, unsigned id, const char* label)
{
	assert(ctx);

	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}
}

void graph_log_message(struct graph_context* ctx, unsigned long timestamp, size_t pkg_sz, int stateid, bool oob)
{
	assert(ctx);
	
	if (GRAPH_SERVER(ctx->mode)){
	}
	else {
	}	
}
