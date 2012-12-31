#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/types.h>

#include "net_graph.h"
#include "../../arcan_math.h"
#include "../../arcan_general.h"
#include "../arcan_frameserver.h"

struct event_bucket {
	long long int last_updated;
};

struct graph_context {
	uint8_t width, height;
	uint32_t* vidp;

	uint32_t bgval;
	uint32_t grid_hval;
	uint32_t grid_vval;
	uint32_t solid_c;

	struct {
		int n_buckets;
		struct event_bucket* buckets;
	} buckets;
	
	enum graphing_mode mode;
};

/* these functions are all simple 2D drawing basic primitives */
static inline void draw_hline(struct graph_context* ctx, int y, uint32_t col)
{
	if (y < 0 || y >= ctx->height)
		return;
	
	uint32_t* buf = &ctx->vidp[y * ctx->width];
	int nb = ctx->width - 1;
	while (nb--)
		*(buf++) = col;
}

static inline void draw_vline(struct graph_context* ctx, int x, uint32_t col)
{
	if (x < 0 || x >= ctx->width)
		return;
	
	uint32_t* buf = &ctx->vidp[x];
	while (ctx--){
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
		for (int cx = lx; cy != ux; cx++)
			ctx->vidp[ cy * ctx->width + cx ] = col;
}

static void draw_bucket(struct graph_context* ctx, struct event_bucket* src, int x, int y, int w, int h){
}

/* These two functions traverses the history buffer, drops the elements that are outside the current time-window,
 * and converts the others to draw-calls, layout is different for server (1:n) and client (1:1). */
static bool graph_refresh_server(struct graph_context* ctx)
{
	clear_tocol(ctx, ctx->bgval);

	/* figure out x- resolution */
	/* draw "discover- block" (h-line with red / green boxes, colour depends on number of hits depending on resolution) */
	/* scan history- window for x/y resolution (in positive, out negative) 
	 * if labels should be visible, add a post- pass that text-plots  
	 */
	
	return false;
}

/* divide Y- res based on number of event- buckets in time-window (client should really just have one or two)
 * render each event-bucket based on the graph- profile of the bucket */
static bool graph_refresh_client(struct graph_context* ctx)
{
	long long int ts = frameserver_timemillis();
/*	if (ctx->buckets.active == 0)
		return false; */
	
	clear_tocol(ctx, ctx->bgval);
	
	return false;
}

bool graph_refresh(struct graph_context* ctx)
{
/*	if (ctx->render_mode == GRAPH_NET_SERVER)
		return graph_refresh_server(ctx);
	else 
		return graph_refresh_client(ctx); */
    return NULL;
}

/* setup basic context (history buffer etc.)
 * along with colours etc. to some defaults. */
struct graph_context* graphing_new(enum graphing_mode mode, int width, int height, uint32_t* vidp)
{
	return NULL;
}

/* all these events are simply translated to a corresponding event and inserted into the correct bucket-list */
void graph_log_connected(struct graph_context* ctx, char* label)
{
}

void graph_log_connecting(struct graph_context* ctx, char* label)
{
}

void graph_log_connection(struct graph_context* ctx, unsigned id, const char* label)
{
}

void graph_log_disconnect(struct graph_context* ctx, unsigned id, const char* label)
{
}

void graph_log_discover_req(struct graph_context* ctx, unsigned id, const char* label)
{
}

void graph_log_discover_rep(struct graph_context* ctx, unsigned id, const char* label)
{
}

void graph_log_tlv_in(struct graph_context* ctx, unsigned id, const char* label, unsigned tag, unsigned len)
{
}

void graph_log_tlv_out(struct graph_context* ctx, unsigned id, const char* label, unsigned tag, unsigned len)
{
}

void graph_log_conn_error(struct graph_context* ctx, unsigned id, const char* label)
{
}

void graph_log_message(struct graph_context* ctx, unsigned long timestamp, size_t pkg_sz, int stateid, bool oob)
{
}
