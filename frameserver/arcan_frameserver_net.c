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
 * a. There's a limited number of simultaneously sessions, which can be either depleting (each validated session decrements
 * the number and is never replenished) or fixed (only ever allow n connections).
 *
 * b. The main loop selects on socket and events (FD transfer socket can be used, MessageLoop on windows, if the socket triggers, it is thrown unto a dispatch thread
 * and if an event is triggered, the full event queue gets processed and possibly pushed to a thread (with separate event queueing etc.)
 *
 * c. If advanced mode is enabled, the main server is not accessible until the client has successfully registered with
 * a dictionary service, which adds client and public key to a shared database (that the server thread uses for validation) which
 * also permits blacklisting etc.
 *
 * d. The shm-API seems ill fit with the video/audio structure here, but can be made of good monitoring use by
 * using the audio layer as "severe sound alerts" and render connection / etc. statistics to the video part
 *
 * e. Client in 'direct' mode will just connect to a server and start pushing data / event in plaintext.
 * Client in 'dictionary' mode will try and figure out where to go from either an explicit directory service, or from local broadcasts,
 * or from an IPv6 multicast / network solicitation discovery */

#define LOCK() (apr_thread_mutex_lock(netcontext.conn_cont_lock));
#define UNLOCK() (apr_thread_mutex_unlock(netcontext.conn_cont_lock));

enum client_modes {
	CLIENT_SIMPLE,
	CLIENT_DISCOVERY,
	CLIENT_DISCOVERY_NACL
};

enum server_modes {
	SERVER_SIMPLE,
	SERVER_SIMPLE_DISCOVERABLE,
	SERVER_DIRECTORY,
	SERVER_DIRECTORY_NACL,
};
	
struct {
	struct frameserver_shmcont shmcont;
	apr_thread_mutex_t* conn_cont_lock;
	apr_pool_t* mempool;

	uint8_t* vidp, (* audp);
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;
	
	unsigned n_conn;
} netcontext;

/* these will be running in a multithreaded manner, with a fixed number of slots
 * one thread / socket dispatch */
static void server_dispatch(bool have_directory, bool have_nacl)
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
static char* host_discover(char* host, int* port, bool usenacl)
{
	return NULL;
}

/* Missing hoststr means we broadcast our request and bonds with the first/best session to respond */
static void client_session(char* hoststr, int port, enum client_modes mode)
{
	switch (mode){
		case CLIENT_SIMPLE:
			if (hoststr == NULL){
				LOG("arcan_frameserver(net) -- direct client mode specified, but server argument missing, giving up.\n");
				return;
			}

			port = port <= 0 ? DEFAULT_CONNECTION_PORT : port;
		break;

		case CLIENT_DISCOVERY:
		case CLIENT_DISCOVERY_NACL:
			hoststr = host_discover(hoststr, &port, mode == CLIENT_DISCOVERY_NACL);
			if (!hoststr){
				LOG("arcan_frameserver(net) -- couldn't find any Arcan- compatible server.\n");
				return;
			}
		break;
	}

/* "normal" connect finally */
	apr_sockaddr_t* sa;
	apr_socket_t* sock;

/* obtain connection */
	apr_sockaddr_info_get(&sa, hoststr, APR_INET, port, 0, netcontext.mempool);
	apr_socket_create(&sock, sa->family, SOCK_STREAM, APR_PROTO_TCP, netcontext.mempool);
	apr_socket_opt_set(sock, APR_SO_NONBLOCK, 0);
	apr_socket_timeout_set(sock, 10 * 1000 * 1000); /* microseconds */
	
/* connect or time-out? */
	apr_status_t rc = apr_socket_connect(sock, sa);

/* didn't work, give up (send an event about that) */
	if (rc != APR_SUCCESS){
		arcan_event ev = { .category = EVENT_NET, .kind = EVENT_NET_NORESPONSE };
		snprintf(ev.data.network.hostaddr, 40, "%s", hoststr);
		arcan_event_enqueue(&netcontext.outevq, &ev);
		return;
	}

	arcan_event ev = { .category = EVENT_NET, .kind = EVENT_NET_CONNECTED };
	snprintf(ev.data.network.hostaddr, 40, "%s", hoststr);
	arcan_event_enqueue(&netcontext.outevq, &ev);

	apr_pollset_t* pset;
	apr_pollfd_t pfd = { netcontext.mempool, APR_POLL_SOCKET, APR_POLLIN, 0, { NULL }, NULL };
/* pr_status_t apr_os_sock_put(apr_socket_t** sock, apr_os_sock_t* thesock, apr_pool_t* cont) (FD to socket) */

	apr_pollset_create(&pset, 2 /* just event- in and socket */, netcontext.mempool, 0);
	apr_pollset_add(pset, &pfd);
	
	while (true){
		apr_int32_t pnum;
		const apr_pollfd_t* ret_pfd;
		apr_status_t status = apr_pollset_poll(pset, -1 /* timeout */, &pnum, &ret_pfd);

		for (int i = 0; i < pnum; i++){
			void* cb = ret_pfd[i].client_data;
		}
	}

	return;
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

/* using the shared memory context as a graphing / logging window, for event passing,
 * the sound as a possible alert, but also for the guard thread */
	netcontext.shmcont = frameserver_getshm(shmkey, true);
	if (!frameserver_shmpage_resize(&netcontext.shmcont, 256, 256, 4, 0, 0)) return;
	frameserver_shmpage_calcofs(netcontext.shmcont.addr, &(netcontext.vidp), &(netcontext.audp) );
	frameserver_shmpage_setevqs(netcontext.shmcont.addr, netcontext.shmcont.esem, &(netcontext.inevq), &(netcontext.outevq), false);
	frameserver_semcheck(netcontext.shmcont.vsem, -1);

/* APR as a wrapper for all socket communication */
	apr_initialize();
	apr_pool_create(&netcontext.mempool, NULL);
		
	const char* rk;

	if (arg_lookup(args, "mode", 0, &rk) && (rk && strcmp("client", rk) == 0)){
		char* dsthost = NULL, (* portstr) = NULL, (* style) = NULL;

		arg_lookup(args, "host", 0, (const char**) &dsthost);
		arg_lookup(args, "port", 0, (const char**) &portstr);
		arg_lookup(args, "style",0, (const char**) &style);

		client_session(dsthost, portstr ? atoi(portstr) : 0, CLIENT_SIMPLE);
	}
	else if (arg_lookup(args, "mode", 0, &rk) && (rk && strcmp("server", rk) == 0)){
/* sweep list of interfaces to bind to (interface=ip,port) and if none, bind to all of them */
		char* style = NULL;
		arg_lookup(args, "style", 0, (const char**) &style);
		
		server_session(SERVER_SIMPLE, false);
	}
	else {
		LOG("arcan_frameserver(net), unknown mode specified.\n");
		goto cleanup;
	}
		
cleanup:
	apr_pool_destroy(netcontext.mempool);
	arg_cleanup(args);
}
