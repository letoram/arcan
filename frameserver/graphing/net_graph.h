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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,MA 02110-1301,USA.
 *
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
struct graph_context* graphing_new(enum graphing_mode, int width, 
	int height, uint32_t* vidp);
void graphing_destroy(struct graph_context*);

/* ALL context references below this point are silently assumed to 
 * be from a valid graphing_new call. */


/* ------------------------------------------- 
 *      Higher Level control functions
 * -------------------------------------------*/

/* update context video buffer,
 * true if there's data to push to parent, invoke frequently */ 
bool graph_refresh(struct graph_context*);

/* timestamps are assumed to increase monotonically,
 * this function makes sure that internal storage gets
 * flushed out over time */
void graph_tick(struct graph_context* ctx, long long int timestamp);


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
/* assumed sanitized inputs
 */
void draw_hline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col);

void draw_vline(struct graph_context* ctx, int x, int y,
	int height,uint32_t col);

void  draw_aaline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col);

void  draw_square(struct graph_context* ctx, int x, int y,
	int side,  uint32_t col);

void  draw_box(struct graph_context* ctx, int x, int y,
	int width, int height, uint32_t col);

void blend_square(struct graph_context* ctx, int x, int y,
	int side,  uint32_t col, float fact);

void blend_vline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col, float fact);

void blend_hline(struct graph_context* ctx, int x, int y,
	int width, uint32_t col, float fact);

void draw_text(struct graph_context* ctx, const char* msg, 
	int x, int y, uint32_t col);

void blend_text(struct graph_context* ctx, const char* msg, 
	int x, int y, uint32_t col, float fact);
#endif
