/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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

#ifndef HAVE_ARCAN_FRAMESERVER_NET
#define HAVE_ARCAN_FRAMESERVER_NET

#define DEFAULT_DISCOVER_PORT 6680
#define DEFAULT_CONNECTION_PORT 6681

enum NET_TAGS {
	TAG_NETMSG           = 0, /* client <-> client, client<->server   */
	TAG_STATE_XFER       = 1, /* server push to client                */
	TAG_STATE_XFER_REQ   = 2, /* server req. client to push to server */
	TAG_STATE_XFER_DELTA = 3, /* delta against prev. key-frame, initial is 0 */
	TAG_NETINPUT         = 4  /* specialized netmsg for input event streams  */
};

void arcan_frameserver_net_run(const char* resource, const char* shmkey);

#endif
