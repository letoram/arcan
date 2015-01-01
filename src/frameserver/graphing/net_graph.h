/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef HAVE_NET_GRAPH
#define HAVE_NET_GRAPH

#define PXFONT font8x8_basic
#define PXFONT_WIDTH 8
#define PXFONT_HEIGHT 8

struct graph_context;

enum graphing_mode {
	GRAPH_MANUAL = 0,
	GRAPH_NET_SERVER,
	GRAPH_NET_SERVER_SPLIT,
	GRAPH_NET_SERVER_SINGLE,
	GRAPH_NET_CLIENT
};

/* allocate and populate a context structure based on the desired
 * graphing mode, note that these graphs are streaming, any history buffer
 * etc. is left as an exercise for whatever frontend is using these.
 * If the resolution etc. should be changed, then a new context will need
 * to be allocated */
struct graph_context* graphing_new(int width, int height, uint32_t* vidp);
void graphing_destroy(struct graph_context*);
void graphing_switch_mode(struct graph_context*, enum graphing_mode);

/* ALL context references below this point are silently assumed to
 * be from a valid graphing_new call. */


/* -------------------------------------------
 *      Higher Level control functions
 * -------------------------------------------*/

/* update context video buffer,
 * true if there's data to push to parent, invoke frequently */
bool graph_refresh(struct graph_context*);

/* --------------------------------------------------
 *         Domain Specific Mapping
 * --------------------------------------------------*/
/* client session events */
void graph_log_connecting(struct graph_context*, char* label);
void graph_log_connected(struct graph_context*, char* label);

/* server session events */
void graph_log_connection(struct graph_context*,
	unsigned id, const char* label);

/* shared events */
void graph_log_discover_req(struct graph_context*,
	unsigned id, const char* label);
void graph_log_discover_rep(struct graph_context*,
	unsigned id, const char* label);
void graph_log_disconnect(struct graph_context*,
	unsigned id, const char* label);
void graph_log_tlv_in(struct graph_context*,
	unsigned id, const char* label, unsigned tag, unsigned len);
void graph_log_tlv_out(struct graph_context*,
	unsigned id, const char* label, unsigned tag, unsigned len);
void graph_log_conn_error(struct graph_context*,
	unsigned id, const char* label);


/* ----------------------------------------------
 *       Lower Level drawing functions
 * ----------------------------------------------*/
/* assumed sanitized inputs, those that return bool
 * will return false if the primitive couldn't fit inside
 * the current context dimensions */

void clear_tocol(struct graph_context* ctx, uint32_t col);

void draw_hline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col);

void draw_vline(struct graph_context* ctx, int x, int y,
	int height,uint32_t col);

void  draw_aaline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col);

void  draw_square(struct graph_context* ctx, int x, int y,
	int side,  uint32_t col);

bool draw_box(struct graph_context* ctx, int x, int y,
	int width, int height, uint32_t col);

void blend_square(struct graph_context* ctx, int x, int y,
	int side,  uint32_t col, float fact);

void blend_vline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col, float fact);

void blend_hline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col, float fact);

bool draw_text(struct graph_context* ctx, const char* msg,
	int x, int y, uint32_t col);

void text_dimensions(struct graph_context* ctx, const char* msg,
	int* dw, int* dh);

void blend_text(struct graph_context* ctx, const char* msg,
	int x, int y, uint32_t col, float fact);
#endif
