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

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_net.h"

/* Overall design / idea:
 * Each frameserver can be launched in either server (1..n connections) or client (1..1 connections) in either simple or advanced mode.
 *
 * a. There's a fixed limited number of simultaneous n connections
 *
 * b. The main loop polls on socket (FD transfer socket can be used), this can be externally interrupted through the wakeup_call callback,
 * and between polls the incoming eventqueue is flushed
 *
 * c. If advanced mode is enabled, the main server is not accessible until the client has successfully registered with
 * a dictionary service (which should also permit blacklisting) which returns whatever public key the client is supposed to use when connecting
 * (client -> LIST/DISCOVER -> server -> PUBKEY response -> client -> LIST/REGISTER (own PUBKEY encrypted) -> server -> REGISTER/DST (pubkey to use))
 * --> server response size should never be larger than client request size <--
 *
 * d. The shm-API may seem like an ill fit with the video/audio structure here, but is used for pushing monitoring graphs and/or aural alarms
 *
 * e. Client in 'direct' mode will just connect to a server and start pushing data / event in plaintext.
 * Client in 'dictionary' mode will try and figure out where to go from either an explicit directory service, or from local broadcasts,
 * or from an IPv6 multicast / network solicitation discovery
 */

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
	apr_pollset_t* pollset;
	
	uint8_t* vidp, (* audp);
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;

	file_handle tmphandle, restorehandle, storehandle;
	unsigned n_conn;
} netcontext = {0};

/* single-threaded multiplexing server with a fixed limit on number of connections,
 * validator emits parsed packets to dispatch, in simple mode, these just extract TLV,
 * otherwise it only emits packets that NaCL guarantees CI on. */
struct conn_state {
	apr_socket_t* input;
	bool (*dispatch)(struct conn_state* self, char tag, int len, char* value);
	bool (*validator)(struct conn_state* self);
	bool (*flushout)(struct conn_state* self);
	
	char* inbuffer;
	int buf_sz;
	int buf_ofs;
	int slot;
};

static bool err_catcher(struct conn_state* self, char tag, int len, char* value)
{
	LOG("arcan_frameserver(net-srv) -- invalid dispatcher invoked, please report.\n");
	abort();
}

static bool err_catch_valid(struct conn_state* self)
{
	LOG("arcan_frameserver(net-srv) -- invalid validator invoked, please report.\n");
	abort();
}

static bool err_catch_flush(struct conn_state* self)
{
	LOG("arcan_frameserver(net-srv) -- invalid validator invoked, please report.\n");
	abort();
}

static bool dispatch_tlv(struct conn_state* self, char tag, int len, char* value)
{
	LOG("tlv: %d, len: %d\n", (uint8_t) tag, len);
	return true;
}

#ifndef FRAME_HEADER_SIZE
#define FRAME_HEADER_SIZE 3
#endif

static bool validator_tlv(struct conn_state* self)
{
/* static as there's only ever 1:1 in our use-case */
	apr_size_t nr   = self->buf_sz - self->buf_ofs;

/* if, for some reason, poorly written packages have come this far, well no further */
	if (nr == 0)
		return false;

	apr_status_t sv = apr_socket_recv(self->input, &self->inbuffer[self->buf_ofs], &nr);
	
	if (sv == APR_SUCCESS){
		if (nr > 0){
			uint16_t len;
			self->buf_ofs += nr;

			if (self->buf_ofs < FRAME_HEADER_SIZE)
				return true;

decode:
/* check if header is broken */
			len = (uint8_t)self->inbuffer[1] | ((uint8_t)self->inbuffer[2] << 8);
			
			if (len > 65536 - FRAME_HEADER_SIZE)
				return false;

/* full packet */
			int buflen = len + FRAME_HEADER_SIZE;
			bool rv = true;

/* invoke next dispatcher, let any failure propagate */
			if (self->buf_ofs >= buflen){
				rv = self->dispatch(self, self->inbuffer[0], len, &self->inbuffer[FRAME_HEADER_SIZE]);

/* slide or reset */
				if (self->buf_ofs == buflen)
					self->buf_ofs = 0;
				else{
					memmove(self->inbuffer, &self->inbuffer[buflen], self->buf_ofs - buflen);
					self->buf_ofs -= buflen;
/* consume everything before returning */
					if (self->buf_ofs >= FRAME_HEADER_SIZE)
						goto decode;
				}
			}
		}
		return true;
	}
	
	return false;
}

/* used for BOTH allocating and cleaning up after a user has disconnected */
static inline void setup_cell(struct conn_state* conn)
{
	conn->input    = NULL;
	conn->dispatch = err_catcher;
	conn->validator= err_catch_valid;
	conn->flushout = err_catch_flush;
	conn->buf_sz   = 1024 * 64;
	conn->buf_ofs  = 0;

	if (conn->inbuffer)
		memset(conn->inbuffer, '\0', conn->buf_sz);
	else
		conn->inbuffer = malloc(conn->buf_sz);
		
	if (!conn->inbuffer)
		conn->buf_sz = 0;
}

static struct conn_state* init_conn_states(int limit)
{
	struct conn_state* active_cons = malloc(sizeof(struct conn_state) * limit);
	
	if (!active_cons)
		return NULL;

	memset(active_cons, '\0', sizeof(struct conn_state) * limit);

	for (int i = 0; i < limit; i++){
		setup_cell( &active_cons[i] );
		active_cons->slot = i;
	}

	return active_cons;
}

static void client_socket_close(struct conn_state* state)
{
	arcan_event rv = {.kind = EVENT_NET_DISCONNECTED, .category = EVENT_NET};
	setup_cell(state);
	arcan_event_enqueue(&netcontext.outevq, &rv);
}

static void server_accept_connection(int limit, apr_socket_t* ear_sock, apr_pollset_t* pollset, struct conn_state* active_cons)
{
	apr_socket_t* newsock;

	apr_pollfd_t pfd = {
		.p           = netcontext.mempool,
		.desc.s      = ear_sock,
		.desc_type   = APR_POLL_SOCKET,
		.reqevents   = APR_POLLIN | APR_POLLHUP | APR_POLLERR, 
		.rtnevents   = 0
	};

	if (apr_socket_accept(&newsock, ear_sock, netcontext.mempool) != APR_SUCCESS)
		return;

/* find an open spot */
	int j;
	for (j = 0; j < limit && active_cons[j].input != NULL; j++);

/* house full, ignore and move on */
	if (active_cons[j].input != NULL){
		apr_socket_close(newsock);
		return;
	}

/* add and setup real callthroughs */
	active_cons[j].input = newsock;
	active_cons[j].validator = validator_tlv;
	active_cons[j].dispatch  = dispatch_tlv;

/* add to table, depending on how the pollset was created, this object is copied or a pointer is maintained,
 * the behavior we rely on is that of it being copied */
	pfd.desc.s      = newsock;
	pfd.desc_type   = APR_POLL_SOCKET;
	pfd.client_data = &active_cons[j];

	apr_pollset_add(pollset, &pfd);
}

static apr_socket_t* server_prepare_socket(const char* host, int sport, int limit, apr_pollset_t** poll_in, struct conn_state** active_cons)
{
	apr_socket_t* ear_sock;
	apr_sockaddr_t* addr;
	apr_status_t rv;
	
/* we bind here rather than parent => xfer(FD) as this is never supposed to use privileged ports. */
	rv = apr_sockaddr_info_get(&addr, host, APR_INET, sport, 0, netcontext.mempool);
	if (rv != APR_SUCCESS){
		LOG("arcan_frameserver(net-srv) -- couldn't setup host (%s):%d, giving up.\n", host ? host : "(DEFAULT)", sport);
		goto sock_failure;
	}

	rv = apr_socket_create(&ear_sock, addr->family, SOCK_STREAM, APR_PROTO_TCP, netcontext.mempool);
	if (rv != APR_SUCCESS){
		LOG("arcan_frameserver(net-srv) -- couldn't create listening socket, on (%s):%d, giving up.\n", host ? host: "(DEFAULT)", sport);
		goto sock_failure;
	}

	rv = apr_socket_bind(ear_sock, addr);
	if (rv != APR_SUCCESS){
		LOG("arcan_frameserver(net-srv) -- couldn't bind to socket, giving up.\n");
		goto sock_failure;
	}
	
	*active_cons = init_conn_states(limit);
	if (!(*active_cons))
		goto sock_failure;

	apr_pollfd_t pfd = {
		.p      = netcontext.mempool,
		.desc.s = ear_sock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN | APR_POLLHUP | APR_POLLERR,
		.rtnevents = 0,
		.client_data = ear_sock
	};

	const apr_pollfd_t* new_pfd;
	apr_pollset_create(poll_in, limit + 2, netcontext.mempool, 0);
	apr_pollset_add(*poll_in, &pfd);

	if (apr_socket_listen(ear_sock, SOMAXCONN) == APR_SUCCESS)
		return ear_sock;

sock_failure:
	apr_socket_close(ear_sock);
	return NULL;
}

static void server_session(const char* host, int sport, int limit)
{
	int errc = 0, thd_ofs = 0;
	apr_status_t rv;
	apr_pollset_t* poll_in;
	apr_int32_t pnum;
	const apr_pollfd_t* ret_pfd;
	struct conn_state* active_cons;

	host  = host  ? host  : "0.0.0.0";
	sport = sport ? sport : DEFAULT_CONNECTION_PORT;
	limit = limit ? limit : 5;

	apr_socket_t* ear_sock = server_prepare_socket(host, sport, limit, &poll_in, &active_cons);
	if (!ear_sock)
		return;

	netcontext.pollset = poll_in;
	
	while (true){
		apr_status_t status = apr_pollset_poll(poll_in, -1 /* timeout */, &pnum, &ret_pfd);
		for (int i = 0; i < pnum; i++){
			void* cb = ret_pfd[i].client_data;
			int evs  = ret_pfd[i].rtnevents;

			if (cb == ear_sock){
				if ((evs & APR_POLLHUP) > 0 || (evs & APR_POLLERR) > 0){
/* broken, give up */
					arcan_event errc = {.kind = EVENT_NET_BROKEN, .category = EVENT_NET};
					arcan_event_enqueue(&netcontext.outevq, &errc);
					return;
				}

				server_accept_connection(limit, ear_sock, poll_in, active_cons);
				continue;
			}
	
/* always process incoming data first, as there can still be something in buffer when HUP / ERR is triggered */
			bool res = true;
			struct conn_state* state = ret_pfd[i].client_data;
			
			if ((evs & APR_POLLIN) > 0)
				res = state->validator(state);

/* will only be triggered intermittently, as event processing *MAY* queue output to one or several
 * connected clients, and until finally flushed, they'd get APR_POLLOUT enabled */
			if ((evs & APR_POLLOUT) > 0)
				res = state->flushout(state);
			
			if ( !res || (ret_pfd[i].rtnevents & APR_POLLHUP) > 0 || (ret_pfd[i].rtnevents & APR_POLLERR) > 0){
				apr_socket_close(ret_pfd[i].desc.s);
				client_socket_close(ret_pfd[i].client_data);
				apr_pollset_remove(poll_in, &ret_pfd[i]);
			}
			;
		}
		;
	}

	return;
}

/* place-holder, replace with real graphing */
static void flush_statusimg(uint8_t r, uint8_t g, uint8_t b)
{
	uint8_t* canvas = netcontext.vidp;
	
	for (int y = 0; y < netcontext.shmcont.addr->storage.h; y++)
		for (int x = 0; x < netcontext.shmcont.addr->storage.h; x++)
		{
			*(canvas++) = r;
			*(canvas++) = g;
			*(canvas++) = b;
			*(canvas++) = 0xff;
		}

	netcontext.shmcont.addr->vready = true;
	frameserver_semcheck(netcontext.shmcont.vsem, INFINITE);
}

/* place-holder, replace with full server/client mode */
static char* host_discover(char* host, int* port, bool usenacl)
{
	return NULL;
}

/* partially unknown number of bytes (>= 1) to process on socket */
static bool client_data_tlvdisp(struct conn_state* self, char tag, int len, char* val)
{
	arcan_event outev;

	switch (tag){
		case TAG_NETMSG:
		break;

/* divert coming len bytes to the designated stream output */
		case TAG_STATE_XFER:
		break;

/* unpack arcan_event */
		case TAG_NETINPUT: break;

		default:
			LOG("arcan_frameserver_net(client) -- unknown packet type (%d), ignored\n", (int)tag); 
	}
	
	return true;
}

static bool client_data_process(apr_socket_t* inconn)
{
/* only one client- connection for the life-time of the process, so this bit
 * is in order to share parsing code between client and server parts */
	static struct conn_state cs = {0};
	if (cs.input == NULL){
		setup_cell(&cs);
		cs.input = inconn;
		cs.dispatch = client_data_tlvdisp;
	}

	bool rv = validator_tlv(&cs);

	if (!rv){
		arcan_event ev = {.category = EVENT_NET, .kind = EVENT_NET_DISCONNECTED};
		apr_socket_close(inconn);
		arcan_event_enqueue(&netcontext.outevq, &ev);
		flush_statusimg(255, 0, 0);
	}

	return rv;
}

/* *blocking* data- transfer, no intermediate buffering etc. 
 * addr   : destination socket
 * buf    : output buffer, assumed to already have TLV headers etc.
 * buf_sz : size of buffer
 * returns false if the data couldn't be sent */
static void client_data_push(apr_socket_t* addr, char* buf, size_t buf_sz)
{
	apr_size_t ofs = 0;

	while (ofs != buf_sz){
		apr_size_t ds = buf_sz - ofs;
		apr_status_t rv = apr_socket_send(addr, &buf[ofs], &ds);
		ofs += ds;

/* failure will trigger HUP/ERR/something on next poll */
		if (rv != APR_SUCCESS)
			break;
	}
}

static bool client_inevq_process(apr_socket_t* outconn)
{
	arcan_event* ev;
	uint16_t msgsz = sizeof(ev->data.network.message) / sizeof(ev->data.network.message[0]);
	char outbuf[ msgsz + 3];
	
/*	outbuf[0] = tag, [1] = lsb, [2] = msb -- payload + FRAME_HEADER_SIZE */
	while ( (ev = arcan_event_poll(&netcontext.inevq)) )
		if (ev->category == EVENT_NET){
			switch (ev->kind){
				case EVENT_NET_INPUTEVENT:
					LOG("arcan_frameserver(net-cl) inputevent unfinished, implement event_pack()/unpack(), ignored\n");
				break;

				case EVENT_NET_CUSTOMMSG:
					outbuf[0] = TAG_NETMSG;
					outbuf[1] = msgsz;
					outbuf[2] = msgsz >> 8;
					memcpy(&outbuf[3], ev->data.network.message, msgsz);
					client_data_push(outconn, outbuf, msgsz + 3);
				break;
			}
		}
		else if (ev->category == EVENT_TARGET){
			switch (ev->kind){
				case TARGET_COMMAND_EXIT:	return false;	break;
				case TARGET_COMMAND_FDTRANSFER: netcontext.tmphandle = frameserver_readhandle(ev); break;
				case TARGET_COMMAND_STORE:
					netcontext.storehandle = netcontext.tmphandle;
					netcontext.tmphandle = 0;
				break;
				case TARGET_COMMAND_RESTORE:
					netcontext.restorehandle = netcontext.tmphandle;
					netcontext.tmphandle = 0;
				break;
				default:
					; /* just ignore */
			}
		}
		else;

	return true;
}

static void pollset_wakeup()
{
	if (netcontext.pollset)
		apr_pollset_wakeup(netcontext.pollset);
}

static void(*pollset_wakeup_fun)(void) = pollset_wakeup;

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
		flush_statusimg(255, 0, 0);
		return;
	}

	arcan_event ev = { .category = EVENT_NET, .kind = EVENT_NET_CONNECTED };
	snprintf(ev.data.network.hostaddr, 40, "%s", hoststr);
	arcan_event_enqueue(&netcontext.outevq, &ev);
	flush_statusimg(0, 255, 0);

	apr_pollset_t* pset;
	apr_pollfd_t pfd = {
		.p = netcontext.mempool,
		.desc.s = sock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN | APR_POLLHUP | APR_POLLERR,
		.rtnevents = 0,
		.client_data = &sock
	};

/*
 * parent can chose to signal when outgoing event-queue is sufficiently full (not necessarily after just one)
 * on POSIX, we do this through a signal-handler, on Win32 through WM_ message loop, both are mapped to the
 * wakeup_call(void*) callback that the _net.h exposes. If the underlying APR implementation is sufficiently broken,
 * we result to just a millisecond timeout on poll
 */
	int timeout = -1;
	if (apr_pollset_create(&pset, 1, netcontext.mempool, APR_POLLSET_WAKEABLE) == APR_ENOTIMPL){
		pollset_wakeup_fun = NULL;
		timeout = 100000;
	}

	apr_pollset_add(pset, &pfd);
	
	while (true){
		const apr_pollfd_t* ret_pfd;
		apr_int32_t pnum;

		apr_status_t status = apr_pollset_poll(pset, timeout, &pnum, &ret_pfd);
		if (status != APR_SUCCESS && status != APR_EINTR){
			LOG("arcan_frameserver(net-cl) -- broken poll, giving up.\n");
			break;
		}

/* can just be socket or event-queue, dispatch accordingly */
		if (pnum > 0)
			if (ret_pfd[0].client_data == &sock)
				client_data_process(sock);

		if (!client_inevq_process(sock))
			break;
	}

	return;
}

wakeup_trigger arcan_frameserver_net_wakeup_call(){ return pollset_wakeup; }

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
 * the sound as a possible alert, but also for the guard thread*/
	netcontext.shmcont = frameserver_getshm(shmkey, true);
	
	if (!frameserver_shmpage_resize(&netcontext.shmcont, 256, 256, 4, 0, 0))
		return;

	frameserver_shmpage_calcofs(netcontext.shmcont.addr, &(netcontext.vidp), &(netcontext.audp) );
	frameserver_shmpage_setevqs(netcontext.shmcont.addr, netcontext.shmcont.esem, &(netcontext.inevq), &(netcontext.outevq), false);
	frameserver_semcheck(netcontext.shmcont.vsem, -1);
	flush_statusimg(128, 128, 128);

/* APR as a wrapper for all socket communication */
	apr_initialize();
	apr_pool_create(&netcontext.mempool, NULL);
	
	const char* rk;

	if (arg_lookup(args, "mode", 0, &rk) && (rk && strcmp("client", rk) == 0)){
		char* dsthost = NULL, (* portstr) = NULL;

		arg_lookup(args, "host", 0, (const char**) &dsthost);
		arg_lookup(args, "port", 0, (const char**) &portstr);

		client_session(dsthost, portstr ? atoi(portstr) : 0, CLIENT_SIMPLE);
	}
	else if (arg_lookup(args, "mode", 0, &rk) && (rk && strcmp("server", rk) == 0)){
/* sweep list of interfaces to bind to (interface=ip,port) and if none, bind to all of them */
		char* listenhost = NULL, (* portstr) = NULL;
		arg_lookup(args, "host", 0, (const char**) &listenhost);
		arg_lookup(args, "port", 0, (const char**) &portstr);

		server_session(listenhost, portstr ? atoi(portstr) : 0, false);
	}
	else {
		LOG("arcan_frameserver(net), unknown mode specified.\n");
		goto cleanup;
	}
		
cleanup:
	apr_pool_destroy(netcontext.mempool);
	arg_cleanup(args);
}
