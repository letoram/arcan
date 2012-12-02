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

struct graph_context;

enum graphing_mode {
	GRAPH_NET_SERVER,
	GRAPH_NET_CLIENT
};

/* allocate and populate a context structure based on the desired graphing mode,
 * note that these graphs are streaming, any history buffer etc. is left as an exercise
 * for whatever frontend is using these. */
struct graph_context* graphing_new(enum graphing_mode, int width, int height, uint32_t* vidp);

void graph_limits(struct graph_context*, int n_connections);

/* change graphing options, refresh rate etc. planar or interleaved view etc. */
/* void graph_hinting(struct graph_context*, unsigned time_resolution, bool cycle, bool labels); */

/* push an update to the graphing buffer,
 * true if internal video buffer should be populated
 * false if there's no update */
bool graph_refresh(struct graph_context*);

/* indicate that a client has connected to a server,
 * label is any identification tag that might be rendered or not (depending on text state) */
void graph_log_connection(struct graph_context*, const char* label);
void graph_log_disconnect(struct graph_context*, const char* label);

/* some kind of data packet has arrived,
 * timestamp is to determine horizontal- scale based on history buffer
 * stateid allows different grouping / colour
 */
void graph_log_message(struct graph_context*, unsigned long timestamp, size_t pkg_sz, int stateid, bool oob);
