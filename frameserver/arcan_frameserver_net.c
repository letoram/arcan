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

/* Discover port also acts as a gatekeeper, you register through this
 * and at the same time, provide your public key */
#define DEFAULT_DISCOVER_PORT 6680

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

#include <apr_general.h>
#include <apr_file_io.h>
#include <apr_strings.h>
#include <apr_network_io.h>
#include <apr_poll.h>
#include <apr_thread_mutex.h>
#include <apr_thread_proc.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_net.h"

/* Overall design / idea:
 * Each frameserver can be launched in either server (1..n connections) or client (1..1 connections).
 *
 * For server mode;
 * a. There's a limited number of simultaneously sessions, which can be either depleting (each validated session decrements
 * the number and is never replenished) or fixed (only ever allow n connections).
 *
 * b. The main loop selects on socket and events, if the socket triggers, it is thrown unto a dispatch thread
 * and if an event is triggered, the full event queue gets processed and possibly pushed to a thread (with separate event queueing etc.)
 *
 * c. If an event triggers a discover-server requests, a broadcast thread is spawned off (unless one exists already).
 * this one retrieves a database handle via the usual FD transfer means, this one can be shared by multiple frameservers all acting as
 * directories. -- This is controlled via UDP, only ever 
 */

#define LOCK() (apr_thread_mutex_lock(netcontext.conn_cont_lock));
#define UNLOCK() (apr_thread_mutex_unlock(netcontext.conn_cont_lock));
	
struct {
	struct frameserver_shmcont shmcont;
	apr_thread_mutex_t* conn_cont_lock;
	apr_pool_t* mempool;
	
/* basic tracking for "rendering" log output */
	unsigned n_conn;
	unsigned valid_errors;

} netcontext;

/* these will be running in a multithreaded manner, with a fixed number of slots
 * one thread / socket dispatch */
static void server_dispatch()
{
/* require untrusted (just raw),
 * secure (we know the person sending but not who he is)
 * verified (pre-known public key) -- based on a global setting */
	
/* apr_thread_exit() */
}

/* listen until we get terminated,
 * since this session is connected to a video object
 * we can render to the video buffer as a means of showing trace- status */
static void server_session(int sport, int limit)
{
	apr_socket_t* ear_sock;
	int errc = 0;
	
	
	apr_thread_mutex_create(&netcontext.conn_cont_lock, APR_THREAD_MUTEX_UNNESTED, netcontext.mempool);

/* easiest possible, just a limit of connections, threads allocated on a shared pool,
 * loop until parent kills us off, drop connection on any anomaly. */
	while (true){
		int rv;
		apr_socket_t* insock;

		if ( (rv = apr_socket_accept(&insock, ear_sock, netcontext.mempool)) == APR_SUCCESS){
			LOCK();
			if (netcontext.n_conn < limit){
				netcontext.n_conn++;
				UNLOCK();
/* spawn thread in server_dispatch */
			}
			else {
				UNLOCK();
/* sorry, drop connection */
			}
		}

	}
}

/*
 * if explicit host, send UDP there, wait for response.
 */ 
static char* host_discover(char* host)
{
		return NULL;
}

/* Missing hoststr means we broadcast our request and bonds with the first/best session to respond */
static void client_session(char* hoststr, int port)
{
	port = port <= 0 ? DEFAULT_DISCOVER_PORT : 0;

/* returns the host we're supposed to use for main control */
	hoststr = host_discover(hoststr);

	if (!hoststr){
		LOG("arcan_frameserver(net) -- couldn't find any Arcan- compatible server.\n");
		return;
	}


}

/* for the discovery service (if active), we toggle it with an event and a FD push (to a sqlite3 db)
 * we need a udp port bound, a ~4 + 32 byte message (identstr + pubkey) 
 * which returns a corresponding reply (and really, track dst in a DB
 * that also has known pubkeys / IDs, blacklisted ones and a temporary
 * table that is dropped every oh so often that counts number of replies
 * to outgoing IPs and stops after n tries. */
void arcan_frameserver_net_run(const char* resource, const char* shmkey)
{
	struct arg_arr* args = arg_unpack(resource);
	if (!args || !shmkey)
		goto cleanup;

	apr_initialize();
	apr_pool_create(&netcontext.mempool, NULL);
	
	const char* rk;
	if (arg_lookup(args, "mode", 0, &rk) &&
		(rk && strcmp("client", rk) == 0)){
			char* dsthost = NULL, (* portstr) = NULL;
			arg_lookup(args, "host", 0, (const char**) &dsthost);
			arg_lookup(args, "port", 0, (const char**) &portstr);

			client_session(dsthost, portstr ? atoi(portstr) : 0);
		}
		else{
			LOG("arcan_frameserver(net), missing mode argument (client)\n");
			goto cleanup;
		}
		
cleanup:
	apr_pool_destroy(netcontext.mempool);
	arg_cleanup(args);
}
