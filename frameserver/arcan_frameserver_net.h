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

#ifndef HAVE_ARCAN_FRAMESERVER_NET
#define HAVE_ARCAN_FRAMESERVER_NET

#ifndef DEFAULT_DISCOVER_REQ_PORT
#define DEFAULT_DISCOVER_REQ_PORT 6681
#endif

#ifndef DEFAULT_DISCOVER_RESP_PORT
#define DEFAULT_DISCOVER_RESP_PORT 6682
#endif

/* this is just used as a hint (when using discovery mode) */
#ifndef DEFAULT_CONNECTION_PORT
#define DEFAULT_CONNECTION_PORT 6680
#endif

/* should be >= 64k */
#ifndef DEFAULT_INBUF_SZ
#define DEFAULT_INBUF_SZ 65536
#endif

/* should be >= 64k */
#ifndef DEFAULT_OUTBUF_SZ
#define DEFAULT_OUTBUF_SZ 65536
#endif

#ifndef DEFAULT_CONNECTION_CAP
#define DEFAULT_CONNECTION_CAP 64 
#endif

/* only effective for state transfer over the TCP channel,
 * additional state data won't be pushed until buffer status is below SATCAP * OUTBUF_SZ */
#ifndef DEFAULT_OUTBUF_SATCAP
#define DEFAULT_OUTBUF_SATCAP 0.5
#endif

enum NET_TAGS {
	TAG_NETMSG           = 0, /* client <-> client, client<->server          */
	TAG_STATE_XFER       = 1, /* server push to client                       */
	TAG_STATE_XFER_DELTA = 2, /* server req. client to push to server        */
	TAG_STATE_XFER_META  = 3, /* delta against prev. key-frame, initial is 0 */
	TAG_NETINPUT         = 4, /* specialized netmsg for input event streams  */
	TAG_NETPING          = 5,
	TAG_NETPONG          = 6  
};

/* Overall design / idea:
 * Each frameserver can be launched in either server (1..n connections) or client (1..1 connections) in either simple or advanced mode.
 *
 * a. There's a fixed limited number of simultaneous n connections
 *
 * b. The main loop polls on socket (FD transfer socket can be used), this can be externally interrupted through the wakeup_call callback,
 * and between polls the incoming eventqueue is flushed
 *
 * c. If advanced mode is enabled, the main server is not accessible until the client has successfully registered with
 * a dictionary service (which should also permit blacklisting, honeypot redirection etc.) which returns whatever public key the client is supposed to use when connecting
 * (client -> LIST/DISCOVER -> server -> PUBKEY response -> client -> LIST/REGISTER (own PUBKEY encrypted) -> server -> REGISTER/DST (pubkey to use))
 * --> server response size should never be larger than client request size <--
 *
 * d. The shm-API may seem like an ill fit with the video/audio structure here, but is used for pushing monitoring graphs and/or aural alarms
 *
 * e. Client in 'direct' mode will just connect to a server and start pushing data / event in plaintext.
 * Client in 'dictionary' mode will try and figure out where to go from either an explicit directory service, or from local broadcasts,
 * or from an IPv6 multicast / network solicitation discovery
 */

void arcan_frameserver_net_run(const char* resource, const char* shmkey);

#endif
