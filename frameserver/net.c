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
 * Foundation,Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
 *
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>
#include <inttypes.h>

#include <apr_general.h>
#include <apr_file_io.h>
#include <apr_strings.h>
#include <apr_network_io.h>
#include <apr_poll.h>
#include <apr_portable.h>

#include <arcan_shmif.h>

#include "frameserver.h"
#include "net.h"
#include "graphing/net_graph.h"

#ifndef DEFAULT_CLIENT_TIMEOUT
#define DEFAULT_CLIENT_TIMEOUT 2000000
#endif

#ifndef CLIENT_DISCOVER_DELAY
#define CLIENT_DISCOVER_DELAY 10
#endif

#ifndef OUTBUF_CAP
#define OUTBUF_CAP 65536
#endif

/*
 * Priority list;
 * 1. Get client/server graphing up and running.
 * 2. Test/fix/harden state transfers.
 * 3. Enable NaCL sessions.
 * 4. Fingerprinting of NaCL keys.
 * 5. Request/setup streaming sessions (e.g. audio/video).
 */

static const int outbuf_cap = OUTBUF_CAP;
static const int discover_delay = CLIENT_DISCOVER_DELAY;

/* IDENT:PKEY:ADDR (port is a compile-time constant)
 * max addr is ipv6 textual representation + strsep + port */
#define IDENT_SIZE 4
#define MAX_PUBLIC_KEY_SIZE 64
#define MAX_ADDR_SIZE 45
#define MAX_HEADER_SIZE 128

#ifdef _WIN32
/* Doesn't seem like mingw/apr actually gets the 
 * TransmitFile symbol so stub it here */
#define sleep(X) (Sleep(X * 1000))
BOOL PASCAL TransmitFile(SOCKET hs, HANDLE hf, DWORD nbtw, DWORD nbps, 
	LPOVERLAPPED lpo, LPTRANSMIT_FILE_BUFFERS lpTransmitBuffers, DWORD dfl){
    return false;
}
#endif

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

/* Used for both listening and outgoing sessions.
 * Important is (CONN_OFFLINE -> CONN_CONNECTED -> 
 * (parent app authenticates) -> CONN_AUTHENTICATED, then loop between
 * STATEXFER and AUTHENTICATED), each step can transition back into OFFLINE */
enum connection_state {
	CONN_OFFLINE = 0,
	CONN_DISCOVERING,
	CONN_CONNECTING,
	CONN_CONNECTED,
	CONN_DISCONNECTING,
	CONN_AUTHENTICATED,
	CONN_STATEXFER
};

int idcookie = 0;

struct {
	struct arcan_shmif_cont shmcont;

/* callback driven struct, basic one is just colors matching
 * some state of the server/client */
	struct graph_context* graphing;
	unsigned graphrate;

/* for future time-synchronization (ping/pongs interleaved
 * with regular messages */
	unsigned long long basestamp;

	apr_pool_t* mempool;
	apr_pollset_t* pollset;
	apr_socket_t* evsock; /* used as signaling / polling mechanism */

/* SHM-API interface */
	uint8_t* vidp, (* audp);
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;

/* intermediate storage (1:1 statechange vs. event msg),
 * this can be transferred to a connection */
	file_handle tmphandle;

	unsigned n_conn;

/* used to force a specific state-transfer size to child,
 * for those cases where we work with blocks rather than streams */
	size_t state_globsz;
	char* rledec_buf;
	size_t rledec_sz;

	enum connection_state connstate;
/* some incoming events are only valid in certain states 
 * (i.e. authenticated etc.) */
} netcontext = {0};

/* single-threaded multiplexing server with a fixed limit on number of 
 * connections, validator emits parsed packets to dispatch, in simple mode,
 * these just extract TLV, otherwise it only emits packets that NaCL 
 * guarantees CI on. */
struct conn_state {
	apr_socket_t* inout;
	enum connection_state connstate;

/* apr requires us to keep track of this one explicitly in order 
 * to flag some poll options on or off (writable-without-blocking 
 * being the most relevant) */
	apr_pollfd_t poll_state;

/* (poll-IN) -> incoming -> validator -> dispatch,
 * outgoing -> queueout -> (poll-OUT) -> flushout  */
	bool (*dispatch)(struct conn_state* self, char tag, int len, char* value);
	bool (*validator)(struct conn_state* self);
	bool (*flushout)(struct conn_state* self);
	bool (*queueout)(struct conn_state* self, char* buf, size_t buf_sz);

/* PING/PONG (for TCP) is bound to other messages */
	unsigned long long connect_stamp, last_ping, last_pong;
	int delay;

/* DEFAULT_OUTBUF_SZ / DEFAULT_INBUF_SZ */
	char* inbuffer;
	size_t buf_sz;
	int buf_ofs;

	char* outbuffer;
	size_t outbuf_sz;
	int outbuf_ofs;
	bool (*state_store)(unsigned long ofset, char* buf, int len);

/* a client may maintain 0..1 state-table that can be 
 * pushed between clients, these can be notably large ( think disk/vbox 
 * image transfer ) */
	char* statebuffer;
	size_t state_sz;
	bool state_in;

	int slot;
};

static bool err_catcher(struct conn_state* self, char tag, 
	int len, char* value)
{
	LOG("(net-srv) -- invalid dispatcher invoked, please report.\n");
	abort();
}

static bool err_catch_valid(struct conn_state* self)
{
	LOG("(net-srv) -- invalid validator invoked, please report.\n");
	abort();
}

static bool err_catch_flush(struct conn_state* self)
{
	LOG("(net-srv) -- invalid flusher invoked, please report.\n");
	abort();
}

static bool err_catch_queueout(struct conn_state* self, 
	char* buf, size_t buf_sz)
{
	LOG("(net-srv) -- invalid queueout invoked, please report.\n");
	abort();
}

static bool flushout_default(struct conn_state* self)
{
	apr_size_t nts = self->outbuf_ofs;
	if (nts == 0){
		static bool flush_warn = false;

/* don't terminate on this issue, as there might be a platform/pollset 
 * combination where this is broken yet will only yield higher CPU usage */
		if (!flush_warn){
			LOG("(net-srv) -- flush requested on empty conn_state, "
				"possibly broken poll.\n");
			flush_warn = true;
		}

		return true;
	}

	apr_status_t sv = apr_socket_send(self->inout, self->outbuffer, &nts);

	if (nts > 0){
		if (self->outbuf_ofs - nts == 0){
			self->outbuf_ofs = 0;
/* disable POLLOUT until more data has been queued 
 * (also check for a 'refill' function) */
		apr_pollset_remove(netcontext.pollset, &self->poll_state);
			self->poll_state.reqevents  = APR_POLLIN | APR_POLLHUP | APR_POLLERR;
			self->poll_state.rtnevents  = 0;
			apr_pollset_add(netcontext.pollset,&self->poll_state);
		} else {
/* partial write, slide */
			memmove(self->outbuffer, &self->outbuffer[nts], self->outbuf_ofs - nts);
			self->outbuf_ofs -= nts;
		}
	} else {
		char errbuf[64];
		apr_strerror(sv, errbuf, 64);
		LOG("(net-srv) -- send failed, %s\n", errbuf);
	}

	return (sv == APR_SUCCESS) && !APR_STATUS_IS_EOF(sv);
}

static bool queueout_default(struct conn_state* self, char* buf, size_t buf_sz)
{
	if ( (self->outbuf_sz - self->outbuf_ofs) >= buf_sz){
		memcpy(&self->outbuffer[self->outbuf_ofs], buf, buf_sz);
		self->outbuf_ofs += buf_sz;

/* if we're not already in a pollout state, enable it */
		if ((self->poll_state.reqevents & APR_POLLOUT) == 0){
			apr_pollset_remove(netcontext.pollset, &self->poll_state);
			self->poll_state.reqevents  = APR_POLLIN | APR_POLLOUT | 
				APR_POLLERR | APR_POLLHUP;
			self->poll_state.desc.s     = self->inout;
			self->poll_state.rtnevents  = 0;
			apr_pollset_add(netcontext.pollset, &self->poll_state);
		}

		return true;
	}

	return false;
}

static bool state_decode(struct conn_state* self, int len, char* data)
{
/* first char, transfer mode */
	char mode = data[0];
	uint32_t repc;
	uint64_t ofs;
	size_t block_sz;
	int nbpb, block_cnt = 0;

/* then 64-bit offset */
	memcpy(&ofs, &data[1], sizeof(uint64_t));

/* self must be able to manage a datawrite at ofs + data */
	switch (mode){
		case STATE_RAWBLOCK:
			if (!self->state_store(ofs, &data[1 + sizeof(uint64_t)], len))
				return false;
		break;

/* data contains counter and remaining of block is pattern.
 * self must be able to manage ( len-(11 bytes) ) * counter
 * this expands in 64k- sized (aligned against blocksize) writes
 * through the state_store */
		case STATE_RLEBLOCK:
/* extract counter */
			memcpy(&repc, &data[1 + sizeof(uint64_t)], sizeof(uint32_t));
			block_sz = len - 1 - sizeof(uint64_t) - sizeof(uint32_t);

/* fill the rledec buffer with number of repetitions of pattern 
 * that can fit in the decode buffer (or if the number requested is 
 * smaller than what we can fit, cap) */
			nbpb = netcontext.rledec_sz / block_sz;
			if (netcontext.rledec_sz > repc * block_sz)
				nbpb = repc * block_sz;

			if (block_sz == 1)
				memset(netcontext.rledec_buf, data[len - block_sz], nbpb);
			else
				for (int i = 0; i < nbpb; i++)
					memcpy(&netcontext.rledec_buf[i * block_sz], 
						&data[len - block_sz], block_sz);

/* flush (using rledec_buf), repc repetitions of data to store */
			while (repc){
				int ntc = repc > nbpb ? nbpb : repc;
				if (!self->state_store(ofs + block_sz * block_cnt, 
					netcontext.rledec_buf, ntc * block_sz))
					return false;

				block_cnt += ntc;
				repc -= ntc;
			}

		break;
	}

	return true;
}

static bool dispatch_tlv(struct conn_state* self, char tag, 
	int len, char* value)
{
	arcan_event newev = {.category = EVENT_NET};
	LOG("(net), TLV frame received (%d:%d)\n", tag, len);

	switch(tag){
	case TAG_NETMSG:
		newev.kind = EVENT_NET_CUSTOMMSG;
		snprintf(newev.data.network.message,
			sizeof(newev.data.network.message)/sizeof(newev.data.network.message[0]),
		"%s", value);
		arcan_event_enqueue(&netcontext.outevq, &newev);
	break;

	case TAG_NETINPUT:
/* need to implement proper serialization of event structure first */
	break;

	case TAG_NETPING:
		if (len == 4){
			uint32_t inl;
			memcpy(&inl, value, sizeof(uint32_t));
			inl = ntohl(inl);
			self->last_ping = inl;

			char outbuf[5];
			outbuf[0] = TAG_NETPONG;
			inl = htonl(arcan_timemillis());
			memcpy(&outbuf[1], &inl, sizeof(uint32_t));
		}
		else
			return false; /* Protocol ERROR */

/* four bytes, unsigned, big-endian */
	break;

	case TAG_NETPONG:
		if (len == 4){
			uint32_t inl;
			memcpy(&inl, value, sizeof(uint32_t));
			inl = ntohl(inl);
			self->last_pong = inl;
		}
		else
			return false; /* Protocol ERROR */
	break;

	case TAG_STATE_XFER:
		return state_decode(self, len, value);
	break;

	default:
		LOG("(net-cl), unknown tag(%d) with %d bytes payload.\n", tag, len);
	}

	return true;
}

#ifndef FRAME_HEADER_SIZE
#define FRAME_HEADER_SIZE 3
#endif

static bool validator_tlv(struct conn_state* self)
{
	apr_size_t nr   = self->buf_sz - self->buf_ofs;

/* if, for some reason, poorly written packages 
 * have come this far, well no further */
	if (nr == 0)
		return false;

	apr_status_t sv = apr_socket_recv(self->inout,
		&self->inbuffer[self->buf_ofs], &nr);
	if (APR_STATUS_IS_EOF(sv))
		return false;
	
	if (sv == APR_SUCCESS){
		if (nr > 0){
			uint16_t len;
			self->buf_ofs += nr;

			if (self->buf_ofs < FRAME_HEADER_SIZE)
				return true;

decode:
/* check if header is broken */
			len = (uint8_t)self->inbuffer[1] | ((uint8_t)self->inbuffer[2] << 8);

			if (len > outbuf_cap - FRAME_HEADER_SIZE)
				return false;

/* full packet */
			int buflen = len + FRAME_HEADER_SIZE;

/* invoke next dispatcher, let any failure propagate */
			if (self->buf_ofs >= buflen){
				self->dispatch(self, self->inbuffer[0], len, 
					&self->inbuffer[FRAME_HEADER_SIZE]);

/* slide or reset */
				if (self->buf_ofs == buflen)
					self->buf_ofs = 0;
				else{
					memmove(self->inbuffer, &self->inbuffer[buflen], 
						self->buf_ofs - buflen);
					self->buf_ofs -= buflen;

/* consume everything before returning */
					if (self->buf_ofs >= FRAME_HEADER_SIZE)
						goto decode;
				}
			}
		}
		return true;
	}

	char errbuf[64];
	apr_strerror(sv, errbuf, 64);
	LOG("(net-srv) -- error receiving data (%s), giving up.\n", errbuf);
	return false;
}

/* used for BOTH allocating and cleaning up after a user has disconnected */
static inline void setup_cell(struct conn_state* conn)
{
	conn->inout     = NULL;
	conn->dispatch  = err_catcher;
	conn->validator = err_catch_valid;
	conn->flushout  = err_catch_flush;
	conn->queueout  = err_catch_queueout;

/* any future command that wish to change these values are expected to
 * realloc/resize appropriately */
	conn->buf_sz    = DEFAULT_INBUF_SZ;
	conn->outbuf_sz = DEFAULT_OUTBUF_SZ;
	conn->buf_ofs   = 0;

	if (conn->inbuffer)
		memset(conn->inbuffer, '\0', conn->buf_sz);
	else
		conn->inbuffer = malloc(conn->buf_sz);

	if (conn->outbuffer)
		memset(conn->outbuffer, '\0', conn->outbuf_sz);
	else
		conn->outbuffer = malloc(conn->outbuf_sz);

	if (!conn->inbuffer)
		conn->buf_sz = 0;

	if (!conn->outbuffer)
		conn->outbuf_sz = 0;

	if (conn->statebuffer){
		free(conn->statebuffer);
		conn->statebuffer = NULL;
		conn->state_sz = 0;
	}

/* scenario specific, some may enforce the same state size for everyone,
 * some unique per client */
	if (netcontext.state_globsz){
		conn->state_sz    = netcontext.state_globsz;
		conn->statebuffer = malloc(conn->state_sz);
		if (conn->statebuffer)
			memset(conn->statebuffer, '\0', conn->state_sz);
		else
			conn->state_sz = 0;
	}
}

static struct conn_state* init_conn_states(int limit)
{
	struct conn_state* active_cons = malloc(sizeof(struct conn_state) * limit);

	if (!active_cons)
		return NULL;

	memset(active_cons, '\0', sizeof(struct conn_state) * limit);

	for (int i = 0; i < limit; i++){
		setup_cell( &active_cons[i] );
		active_cons->slot = i ^ idcookie;
	}

	return active_cons;
}

static void client_socket_close(struct conn_state* state)
{
	arcan_event rv = {.kind = EVENT_NET_DISCONNECTED, .category = EVENT_NET};
	LOG("(net-srv) -- disconnecting client. %d\n", state->slot);

	setup_cell(state);
	arcan_event_enqueue(&netcontext.outevq, &rv);
	graph_log_disconnect(netcontext.graphing, state->slot, 
		"" /* NOTE: push IP? */);
}

static void server_accept_connection(int limit, apr_socket_t* ear_sock, 
	apr_pollset_t* pollset, struct conn_state* active_cons)
{
	apr_socket_t* newsock;
	if (apr_socket_accept(&newsock, ear_sock, 
		netcontext.mempool) != APR_SUCCESS)
		return;

/* find an open spot */
	int j;
	for (j = 0; j < limit && active_cons[j].inout != NULL; j++);

/* house full, ignore and move on */
	if (active_cons[j].inout != NULL){
		apr_socket_close(newsock);
		return;
	}

/* add and setup real callthroughs */
	active_cons[j].inout     = newsock;
	active_cons[j].validator = validator_tlv;
	active_cons[j].dispatch  = dispatch_tlv;
	active_cons[j].flushout  = flushout_default;
	active_cons[j].queueout  = queueout_default;
	active_cons[j].connect_stamp = arcan_timemillis();
	active_cons[j].connstate = CONN_CONNECTED;

	apr_pollfd_t* pfd = &active_cons[j].poll_state;

	pfd->desc.s      = newsock;
	pfd->desc_type   = APR_POLL_SOCKET;
	pfd->client_data = &active_cons[j];
	pfd->reqevents   = APR_POLLHUP | APR_POLLERR | APR_POLLIN;
	pfd->rtnevents   = 0;
	pfd->p           = netcontext.mempool;

	apr_pollset_add(pollset, pfd);

/* figure out source address, add to event and fire */
	apr_sockaddr_t* addr;

	apr_socket_addr_get(&addr, APR_REMOTE, newsock);
	arcan_event outev = {
					.kind = EVENT_NET_CONNECTED, 
					.category = EVENT_NET, 
					.data.network.connid = active_cons[j].slot
	};

	size_t out_sz = sizeof(outev.data.network.host.addr) / 
		sizeof(outev.data.network.host.addr[0]);
	apr_sockaddr_ip_getbuf(outev.data.network.host.addr, out_sz, addr);

	arcan_event_enqueue(&netcontext.outevq, &outev);
	graph_log_connection(netcontext.graphing, active_cons[j].slot, 
		outev.data.network.host.addr);
}

static uint32_t version_magic(bool req)
{
	char buf[32], (* ch) = buf;
	sprintf(buf, "%s_ARCAN_%d_%d", req ? "REQ" : "REP", 
		ARCAN_VERSION_MAJOR, ARCAN_VERSION_MINOR);

	uint32_t hash = 5381;
	int c;

	while ((c = *(ch++)))
		hash = ((hash << 5) + hash) + c;

	return hash;
}

/* something to read on gk_sock, silent discard if it's not a 
 * valid discover message. gk_redir is a srcaddr:port to which the 
 * recipient should try and connect. IF this is set to 0.0.0.0, 
 * the recipient is expected to just use the source address.
 *
 * the explicit alternative to this (as gk_sock may be INADDR_ANY etc. 
 * would be to send a garbage message first, enable IP_PKTINFO/IP_RECVDSTADDR
 * on the socket and check CMSG for a response, then send the real 
 * response using that. It's not particularly portable though, 
 * but a relevant side-note
 */
static void server_gatekeeper_message(apr_socket_t* gk_sock, 
	const char* gk_redir)
{
/* partial reads etc. are just ignored, client have to resend. */
	char gk_inbuf[MAX_HEADER_SIZE], gk_outbuf[MAX_HEADER_SIZE];
	apr_size_t ntr = MAX_HEADER_SIZE;
	apr_sockaddr_t src_addr;

	if (strlen(gk_redir) >= MAX_ADDR_SIZE)
		return;

/* with matching cookie, use public key (or plaintext if 0) */
	if (apr_socket_recvfrom(&src_addr, gk_sock, 0, gk_inbuf, &ntr) == 
		APR_SUCCESS && ntr == MAX_HEADER_SIZE){
		uint32_t srcmagic;
		memcpy(&srcmagic, gk_inbuf, IDENT_SIZE);

		if (version_magic(true) == ntohl(srcmagic)){
			char pkey[64];
			memcpy(pkey, &gk_inbuf[IDENT_SIZE], MAX_PUBLIC_KEY_SIZE);

/* construct reply dynamically to allow different gk_redirections 
 * (honeypots etc.) and different public keys */
			uint32_t repmagic = htonl(version_magic(false));
			memcpy(gk_outbuf, &repmagic, sizeof(uint32_t));
			memset(&gk_outbuf[IDENT_SIZE], 0, MAX_PUBLIC_KEY_SIZE);
			memcpy(&gk_outbuf[IDENT_SIZE + MAX_PUBLIC_KEY_SIZE], gk_redir, 
				strlen(gk_redir));

/* shortread, shortwrite etc. are all ignored, assumes that OS 
 * will just gladly accept without blocking (too long),
 * it's ~128bytes so ... */
			apr_size_t tosend = MAX_HEADER_SIZE;
			src_addr.port = DEFAULT_DISCOVER_RESP_PORT;
			apr_socket_sendto(gk_sock, &src_addr, 0, gk_outbuf, &tosend);
			graph_log_discover_req(netcontext.graphing, srcmagic, "req" 
				/* NOTE: useful to log? */);
		}
		else;

	}
}

static apr_socket_t* server_prepare_socket(const char* host, apr_sockaddr_t* 
	althost, int sport, bool tcp)
{
	char errbuf[64];
	apr_socket_t* ear_sock = NULL;
	apr_sockaddr_t* addr;
	apr_status_t rv;

	if (althost)
		addr = althost;
	else {
/* we bind here rather than parent => xfer(FD) as this is never
 * supposed to use privileged ports. */
		rv = apr_sockaddr_info_get(&addr, host, APR_INET, sport, 0, 
			netcontext.mempool);
		if (rv != APR_SUCCESS){
			LOG("(net) -- couldn't setup host (%s):%d, giving up.\n", 
				host ? host : "(DEFAULT)", sport);
			goto sock_failure;
		}
	}

	rv = apr_socket_create(&ear_sock, addr->family, tcp ? 
		SOCK_STREAM : SOCK_DGRAM, tcp ? APR_PROTO_TCP : 
		APR_PROTO_UDP, netcontext.mempool);

	if (rv != APR_SUCCESS){
		LOG("(net) -- couldn't create listening socket, on (%s):%d, "
			"giving up.\n", host ? host: "(DEFAULT)", sport);
		goto sock_failure;
	}

	rv = apr_socket_bind(ear_sock, addr);
	if (rv != APR_SUCCESS){
		LOG("(net) -- couldn't bind to socket, giving up.\n");
		goto sock_failure;
	}

	apr_socket_opt_set(ear_sock, APR_SO_REUSEADDR, 1);

/* apparently only fixed in APR1.5 and beyond, 
 * while the one in ubuntu and friends is 1.4 */
	if (!tcp){
#ifndef APR_SO_BROADCAST
		int sockdesc, one = 1;
		apr_os_sock_get(&sockdesc, ear_sock);
		setsockopt(sockdesc, SOL_SOCKET, SO_BROADCAST, (void *)&one, sizeof(int));
#else
		apr_socket_opt_set(ear_sock, APR_SO_BROADCAST, 1);
#endif
	}

	if (!tcp || apr_socket_listen(ear_sock, SOMAXCONN) == APR_SUCCESS)
		return ear_sock;

sock_failure:
	apr_strerror(rv, errbuf, 64);
	LOG("(net) -- preparing listening socket failed, reason: %s\n", errbuf);

	apr_socket_close(ear_sock);
	return NULL;
}

static apr_socket_t* server_prepare_gatekeeper(char* host)
{
/* encryption, key storage etc. missing from here */
	return server_prepare_socket(host, NULL, DEFAULT_DISCOVER_REQ_PORT, false);
}

static void server_queueout_data(struct conn_state* active_cons, 
	int nconns, char* buf, size_t buf_sz, int id)
{
	if (id > nconns || id < 0)
		return;

/* broadcast */
	if (id == 0)
		for(int i = 0; i < nconns; i++){
			if (active_cons[i].inout)
				active_cons[i].queueout(&active_cons[i], buf, buf_sz);
		}

/* unicast */
	else if (active_cons[id-1].inout)
		active_cons[id-1].queueout(&active_cons[id-1], buf, buf_sz);
	else;

	return;
}

static inline struct conn_state* lookup_connection(struct conn_state* 
	active_cons, int nconns, int id)
{
	for (int i = 0; i < nconns; i++){
		if (active_cons[i].slot == id)
			return &active_cons[i];
	}

	return NULL;
}

static void disconnect(struct conn_state* active_cons, int nconns, int slot)
{
	if (slot == 0){
		for (int i = 0; i < nconns; i++)
			if (active_cons[i].connstate > CONN_OFFLINE){
				LOG("Mass Disconnect (%i:%i)\n", i, active_cons[i].slot);
				apr_socket_close(active_cons[i].inout);
				apr_pollset_remove(netcontext.pollset, &active_cons[i].poll_state);
				setup_cell(&active_cons[i]);
			}
	}
	else {
		struct conn_state* target_con = lookup_connection(active_cons, 
			nconns, slot);
		if (target_con && target_con->connstate > CONN_OFFLINE){
			apr_socket_close(target_con->inout);
			apr_pollset_remove(netcontext.pollset, &target_con->poll_state);
			setup_cell(target_con);
			graph_log_disconnect(netcontext.graphing, slot, "forced");
		}
	}
}

static bool server_process_inevq(struct conn_state* active_cons, int nconns)
{
	arcan_event ev;
	uint16_t msgsz = sizeof(ev.data.network.message) / 
		sizeof(ev.data.network.message[0]);
	char outbuf[ msgsz + 3 ];

/*	outbuf[0] = tag, [1] = lsb, [2] = msb -- payload + FRAME_HEADER_SIZE */

	while ( arcan_event_poll(&netcontext.inevq, &ev) == 1 )
		if (ev.category == EVENT_NET){
			switch (ev.kind){
			case EVENT_NET_INPUTEVENT:
				LOG("(net-srv) inputevent unfinished, implement "
					"event_pack()/unpack(), ignored\n");
			break;

/* don't confuse this one with EVENT_NET_DISCONNECTED, which is a 
 * notification rather than a command */
			case EVENT_NET_DISCONNECT:
				disconnect(active_cons, nconns, ev.data.network.connid);
			break;
				
			case EVENT_NET_GRAPHREFRESH:
				if (netcontext.shmcont.addr->vready == false && 
					graph_refresh(netcontext.graphing))
					netcontext.shmcont.addr->vready = true;
			break;

			case EVENT_NET_CUSTOMMSG:
				LOG("(net-srv) broadcast %s\n", ev.data.network.message);
				outbuf[0] = TAG_NETMSG;
				outbuf[1] = msgsz;
				outbuf[2] = msgsz >> 8;
				memcpy(&outbuf[3], ev.data.network.message, msgsz);
				server_queueout_data(active_cons, nconns, outbuf, msgsz + 3, 
					ev.data.network.connid);
				graph_log_tlv_out(netcontext.graphing, 0, ev.data.network.message, 
					TAG_NETMSG, msgsz);
				break;
			}
		}
		else if (ev.category == EVENT_TARGET){
			switch (ev.kind){
				case TARGET_COMMAND_EXIT:
					LOG("(net-srv) parent requested termination, giving up.\n");
					return false;
				break;

				case TARGET_COMMAND_FDTRANSFER:
					netcontext.tmphandle = frameserver_readhandle(&ev);
				break;

/* active slot -> fdtransfer -> store or restore */
				case TARGET_COMMAND_STORE:
					netcontext.tmphandle = 0;
				break;

				case TARGET_COMMAND_RESTORE:
					netcontext.tmphandle = 0;
				break;
				default:
					; /* just ignore */
			}
		}
		else;

	return true;
}

static void server_session(const char* host, int limit)
{
	apr_pollset_t* poll_in;
	apr_int32_t pnum;
	const apr_pollfd_t* ret_pfd;
	struct conn_state* active_cons;

	host = host ? host : APR_ANYADDR;

	active_cons = init_conn_states(limit);
	if (!active_cons)
		return;

/* we need 1 for each connection (limit) one for the 
 * gatekeeper and finally one for each IP (multihomed) */
	int timeout = -1;
#ifdef _WIN32
   timeout = 10000;
#endif

	if (apr_pollset_create(&poll_in, limit + 4, 
		netcontext.mempool, 0) != APR_SUCCESS){
			LOG("(net-srv) -- Couldn't create server pollset, giving up.\n");
			return;
	}

	int sleeptime = 5 * 1000; 
	int retrycount = 10;
	apr_socket_t* ear_sock;
	
retry:
	ear_sock = server_prepare_socket(host, NULL, DEFAULT_CONNECTION_PORT, true);
	if (!ear_sock){
		if (retrycount--){
			LOG("(net-srv) -- Couldn't prepare listening socket, retrying %d more"
				"	times in %d seconds.\n", retrycount + 1, sleeptime / 1000);
			arcan_timesleep(sleeptime);
			goto retry;
		}
		else
			return;
	}

	LOG("(net-srv) -- listening interface up on %s\n", host ? host : "(global)");
	netcontext.pollset = poll_in;

/* the pollset is created noting that we have the responsibility for
 * assuring that the descriptors involved stay in scope, thus pfd needs to 
 * be here or dynamically allocated */
	apr_pollfd_t pfd = {
		.p      = netcontext.mempool,
		.desc.s = ear_sock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN | APR_POLLHUP | APR_POLLERR,
		.rtnevents = 0,
		.client_data = ear_sock
	}, gkpfd;

	apr_pollfd_t epfd = {
		.p      = netcontext.mempool,
		.desc.s = netcontext.evsock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN,
		.rtnevents = 0,
		.client_data = netcontext.evsock
	};

/* should be solved in a pretty per host etc. manner and for 
 * that matter, IPv6 */
	apr_socket_t* gk_sock = server_prepare_gatekeeper("0.0.0.0");
	if (gk_sock){
		LOG("(net-srv) -- gatekeeper listening on broadcast for %s\n", 
			host ? host : "(global)");
		gkpfd.p = netcontext.mempool;
		gkpfd.desc.s = gk_sock;
		gkpfd.rtnevents = 0;
		gkpfd.reqevents = APR_POLLIN;
		gkpfd.desc_type = APR_POLL_SOCKET;
		gkpfd.client_data = gk_sock;
		apr_pollset_add(poll_in, &gkpfd);
	}

#ifndef _WIN32
	apr_pollset_add(poll_in, &epfd);
#endif
	apr_pollset_add(poll_in, &pfd);

	while (true){
		apr_pollset_poll(poll_in, timeout, &pnum, &ret_pfd);

		for (int i = 0; i < pnum; i++){
			void* cb = ret_pfd[i].client_data;
			int evs  = ret_pfd[i].rtnevents;

			if (cb == ear_sock){
				if ((evs & APR_POLLHUP) > 0 || (evs & APR_POLLERR) > 0){
					arcan_event errc = {
									.kind = EVENT_NET_BROKEN, 
									.category = EVENT_NET
					};

					arcan_event_enqueue(&netcontext.outevq, &errc);
					LOG("(net-srv) -- error on listening interface "
						"during poll, giving up.\n");
					graph_log_conn_error(netcontext.graphing, 0, "listen");
					return;
				}

				server_accept_connection(limit, ret_pfd[i].desc.s, 
					poll_in, active_cons);
				continue;
			}
			else if (cb == gk_sock){
				server_gatekeeper_message(gk_sock, "0.0.0.0");
				continue;
			}
/* this socket is used for OOB FD transfers and as a pollable semaphore */
			else if (cb == netcontext.evsock){
				char flushb[256];
				apr_size_t szv = 256;

				apr_socket_recv(netcontext.evsock, flushb, &szv);
				if (!server_process_inevq(active_cons, limit))
					break;

				continue;
			}
			else;

/* always process incoming data first, as there can still 
 * be something in buffer when HUP / ERR is triggered */
			bool res = true;
			struct conn_state* state = cb;

			if ((evs & APR_POLLIN) > 0)
				res = state->validator(state);

/* will only be triggered intermittently, as event processing *MAY*
 * queue output to one or several connected clients, and until finally
 * flushed, they'd get APR_POLLOUT enabled */
			if ((evs & APR_POLLOUT) > 0)
				res = state->flushout(state);

			if ( !res || (ret_pfd[i].rtnevents & APR_POLLHUP) > 0 || 
				(ret_pfd[i].rtnevents & APR_POLLERR) > 0){
				LOG("(net-srv) -- (%s), terminating client connection (%d).\n",
					res ? "HUP/ERR" : "flush failed", i);
				apr_socket_close(ret_pfd[i].desc.s);
				client_socket_close(ret_pfd[i].client_data);
				apr_pollset_remove(poll_in, &ret_pfd[i]);
				graph_log_conn_error(netcontext.graphing, state->slot, "hup/err");
			}
			;
		}

/* Win32 workaround, the approach of using an OS primitive that blends
 * with a pollset is a bit messy in windows as apparently Semaphores
 * didn't work, Winsock is just terrible and the parent process doesn't
 * link / use APR, so we fall back to an aggressive timeout */
		if (!server_process_inevq(active_cons, limit))
            break;
		;
	}

    LOG("(net-srv) -- shutting down server session.\n");
	apr_socket_close(ear_sock);
	return;
}

/* Client Discovery Protocol Implementation
 * ----------
 * Every (discover_delay) seconds, the client sends a UDP packet to 
 * either a IPv4 broadcast or a dictionary server. The request packet is 
 * comprised of a MAX_HEADER_SIZE packet, with a 4 byte network byte order
 * magic value that encodes the version number and if it is a request or
 * response (see version_magic function) along with a MAX_PUBLIC_KEY_SIZE
 * public key (NaCL generated) and the rest of the packet will be ignored
 * (req/rep are the same size to prevent magnification) Servers responds
 * with 1..n similar packets, but are encrypted with the public key of the
 * client and contains a public key and destination host (port is hardcoded
 * at build time, see DEFAULT_DISCOVER_*_PORT).
 *
 * if passive, the event interface will be used to propagate info on 
 * servers up to the FE
 */
static char* host_discover(char* host, bool usenacl, bool passive)
{
/*	const int addr_maxlen = 45; RFC4291 */
	char reqmsg[ MAX_HEADER_SIZE ], repmsg[ MAX_HEADER_SIZE + 1 ];

	memset(reqmsg, 0, MAX_HEADER_SIZE);
	uint32_t mv = htonl( version_magic(true) );
	memcpy(reqmsg, &mv, sizeof(uint32_t));
	repmsg[MAX_HEADER_SIZE] = '\0';

	apr_status_t rv;
	apr_sockaddr_t* addr;

/* specific, single, redirector host OR IPV4 broadcast */
	apr_sockaddr_info_get(&addr, host ? host : "255.255.255.255", 
		APR_INET, DEFAULT_DISCOVER_REQ_PORT, 0, netcontext.mempool);
	apr_socket_t* broadsock = server_prepare_socket("0.0.0.0", NULL, 
		DEFAULT_DISCOVER_RESP_PORT, false);
	if (!broadsock){
		LOG("(net-cl) -- host discover failed, couldn't prepare"
			"	listening socket.\n");
		return NULL;
	}

	apr_socket_timeout_set(broadsock, DEFAULT_CLIENT_TIMEOUT);

	while (true){
		apr_size_t nts = MAX_HEADER_SIZE, ntr;
		apr_sockaddr_t recaddr;
retry:

		if ( ( rv = apr_socket_sendto(broadsock, addr, 0, 
			reqmsg, &nts) ) != APR_SUCCESS)
			break;
		graph_log_discover_req(netcontext.graphing, mv, 
			host ? host : "broadcast");

		ntr = MAX_HEADER_SIZE;
		rv  = apr_socket_recvfrom(&recaddr, broadsock, 0, repmsg, &ntr);

		if (rv == APR_SUCCESS){
			if (ntr == MAX_HEADER_SIZE){
				uint32_t magic, rmagic;
				memcpy(&magic, repmsg, 4);
				rmagic = ntohl(magic);

				if (version_magic(false) == rmagic){
/* if no IP is set, the IP is that of the sending source */
					if (strncmp(&repmsg[MAX_PUBLIC_KEY_SIZE + IDENT_SIZE], 
						"0.0.0.0", 7) == 0){
						char strbuf[MAX_ADDR_SIZE];
						apr_sockaddr_ip_getbuf(strbuf, MAX_ADDR_SIZE, &recaddr);
						graph_log_discover_rep(netcontext.graphing, rmagic, strbuf);

/* passive, will background scan until the FE terminate */
						if (!passive){
							apr_socket_close(broadsock);
							return strdup(strbuf);
						}
						else {
							arcan_event ev = {
											.category = EVENT_NET, 
											.kind = EVENT_NET_DISCOVERED
							};
							arcan_event dev;

							strncpy(ev.data.network.host.addr, strbuf, MAX_ADDR_SIZE);
							arcan_event_enqueue(&netcontext.outevq, &ev);

/* flush the queue */
							while ( 1 == arcan_event_poll(&netcontext.outevq, &dev)){
								if (dev.category == EVENT_TARGET && dev.kind == 
									TARGET_COMMAND_EXIT)
									return NULL;
							}
						}

					}
					else{
						graph_log_discover_rep(netcontext.graphing, rmagic, 
							&repmsg[MAX_PUBLIC_KEY_SIZE + IDENT_SIZE]);
						return strdup(&repmsg[MAX_PUBLIC_KEY_SIZE + IDENT_SIZE]);
					}
				}
				else; /* our own request or bad response */
			}
		}
		else{ /* short read or, more likely, broken / purposely malformed */
			graph_log_conn_error(netcontext.graphing, mv, "resp. mismatch");
			goto retry;
		}

		sleep(discover_delay);
	}

	char errbuf[64];
	apr_strerror(rv, errbuf, 64);
	LOG("(net-cl) -- send failed during discover, %s\n", errbuf);
	graph_log_conn_error(netcontext.graphing, 0, "UDP sendto failed");

	return NULL;
}

/* partially unknown number of bytes (>= 1) to process on socket */
static bool client_data_tlvdisp(struct conn_state* self, 
	char tag, int len, char* val)
{
	arcan_event outev;

/*GRAPH HOOK: OK DATA */
	switch (tag){
	case TAG_NETMSG:
		outev.category = EVENT_NET;
		outev.kind = EVENT_NET_CUSTOMMSG;
		snprintf(outev.data.network.message,
			sizeof(outev.data.network.message) / 
			sizeof(outev.data.network.message[0]), "%s", val);
		arcan_event_enqueue(&netcontext.outevq, &outev);
		graph_log_tlv_in(netcontext.graphing, 0, 
			outev.data.network.message, TAG_NETMSG, len);
	break;

/* RLE compressed keyframe */
	case TAG_STATE_XFER:
		graph_log_tlv_in(netcontext.graphing, 0, "state", TAG_STATE_XFER, len);
	break;

/* unpack arcan_event */
	case TAG_NETINPUT: break;

	default:
		LOG("arcan_frameserver_net(client) -- unknown packet type (%d), ignored\n", (int)tag);
	}

	return true;
}

static bool client_data_process(apr_socket_t* inconn, const apr_pollfd_t* desc)
{
	static arcan_event ev = {
					.category = EVENT_NET,
				 	.kind = EVENT_NET_DISCONNECTED
	};
	
/* only one client- connection for the life-time of the process, so this bit
 * is in order to share parsing code between client and server parts */
	static struct conn_state cs = {0};
	if (cs.inout == NULL){
		setup_cell(&cs);
		cs.inout = inconn;
		cs.dispatch = client_data_tlvdisp;
	}

	if (desc->rtnevents & (APR_POLLHUP | APR_POLLERR | APR_POLLNVAL)){
		LOG("(net-cl) -- poll on socket failed, shutting down.\n");
		apr_socket_close(inconn);
		arcan_event_enqueue(&netcontext.outevq, &ev);
		graph_log_conn_error(netcontext.graphing, 0, "broken poll");
		
		return false;
	}
	
	if (!validator_tlv(&cs)){
		LOG("(net-cl) -- validator failed, shutting down.\n");
		apr_socket_close(inconn);
		arcan_event_enqueue(&netcontext.outevq, &ev);
		graph_log_conn_error(netcontext.graphing, 0, "broken validation");
		return false;
	}

	return true;
}

/* *blocking* data- transfer, no intermediate buffering etc.
 * addr   : destination socket
 * buf    : output buffer, assumed to already have TLV headers etc.
 * buf_sz : size of buffer
 * returns false if the data couldn't be sent */
static bool client_data_push(apr_socket_t* addr, char* buf, size_t buf_sz)
{
	apr_size_t ofs = 0;

	while (ofs != buf_sz){
		apr_size_t ds = buf_sz - ofs;
		apr_status_t rv = apr_socket_send(addr, &buf[ofs], &ds);
		if (APR_STATUS_IS_EOF(rv) || rv != APR_SUCCESS)
			return false;
			
		ofs += ds;
	}

	return true;
}

static bool client_inevq_process(apr_socket_t* outconn)
{
	arcan_event ev;
	uint16_t msgsz = sizeof(ev.data.network.message) / 
		sizeof(ev.data.network.message[0]);
	char outbuf[ msgsz + 3];
	outbuf[msgsz + 2] = 0;

/* since we flush the entire eventqueue at once, it means that multiple
 * messages may possible be interleaved in one push (up to the 64k buffer)
 * before getting sent of to the TCP layer (thus not as wasteful as it might
 * initially seem).
 *
 * The real issue is buffer overruns though, which currently means that data
 * gets lost (for custommsg) or truncated State transfers won't ever overflow
 * and are only ever tucked on at the end */
	while ( 1 == arcan_event_poll(&netcontext.inevq, &ev) )
		if (ev.category == EVENT_NET){
			switch (ev.kind){
			case EVENT_NET_INPUTEVENT:
				LOG("(net-cl) inputevent unfinished, implement "
					"event_pack()/unpack(), ignored\n");
			break;

			case EVENT_NET_CUSTOMMSG:
				if (netcontext.connstate < CONN_CONNECTED)
					break;

				if (strlen(ev.data.network.message) + 1 < msgsz)
					msgsz = strlen(ev.data.network.message) + 1;

				outbuf[0] = TAG_NETMSG;
				outbuf[1] = msgsz;
				outbuf[2] = msgsz >> 8;
				memcpy(&outbuf[3], ev.data.network.message, msgsz);
				if (client_data_push(outconn, outbuf, msgsz + 3)){
					graph_log_tlv_out(netcontext.graphing, 0, ev.data.network.message,
						TAG_NETMSG, msgsz);
				}
				else
					return false;
	
			break;

			case EVENT_NET_GRAPHREFRESH:
				if (netcontext.shmcont.addr->vready == false && 
					graph_refresh(netcontext.graphing))
					netcontext.shmcont.addr->vready = true;
			break;
			}
		}
		else if (ev.category == EVENT_TARGET){
			switch (ev.kind){
			case TARGET_COMMAND_EXIT: return false; break;

			case TARGET_COMMAND_FDTRANSFER:
				netcontext.tmphandle = frameserver_readhandle(&ev);
			break;

			case TARGET_COMMAND_STORE:
				netcontext.tmphandle = 0;
			break;
			case TARGET_COMMAND_RESTORE:
				netcontext.tmphandle = 0;
			break;
			default:
				; /* just ignore */
		}
		}
		else;

	return true;
}

/*
 * Missing hoststr; we broadcast our request and 
 * bonds with the first/best session to respond
 *
 * hoststr == =passive, never leave the discover loop,
 * just push detected server responses to parent
 *
 * hoststr == =19.ip.address forward discover requests to
 * specified destination
 *
 * hoststr == NULL, get first / best (we're in a trusted network)
 *
 * mode -> CLIENT_DISCOVERY_NACL, only accept requests that use
 * our per/session public key
 */
static void client_session(char* hoststr, enum client_modes mode)
{
	if ( (mode == CLIENT_DISCOVERY && hoststr == NULL) || 
		mode == CLIENT_DISCOVERY_NACL){
		bool passive = false;

		if (hoststr){
			if (hoststr[0] == '=')
				hoststr++;
			if (strcmp(hoststr, "passive") == 0){
				hoststr = NULL;
				passive = true;	
			}
		}

		hoststr = host_discover(hoststr, mode == CLIENT_DISCOVERY_NACL, passive);
		if (!hoststr){
			LOG("(net) -- couldn't find any Arcan- compatible server.\n");
			return;
		}
	}

/* "normal" connect finally */
	apr_sockaddr_t* sa;
	apr_socket_t* sock;

/* obtain connection */
	apr_sockaddr_info_get(&sa, hoststr, APR_INET, DEFAULT_CONNECTION_PORT, 
		0, netcontext.mempool);
	apr_socket_create(&sock, sa->family, SOCK_STREAM, 
		APR_PROTO_TCP, netcontext.mempool);
	apr_socket_opt_set(sock, APR_SO_NONBLOCK, 0);
	apr_socket_timeout_set(sock, DEFAULT_CLIENT_TIMEOUT);

/* connect or time-out? */
	apr_status_t rc = apr_socket_connect(sock, sa);

/* didn't work, give up (send an event about that) */
	if (rc != APR_SUCCESS){
		arcan_event ev = { 
						.category = EVENT_NET,
					 	.kind = EVENT_NET_NORESPONSE 
		};
		snprintf(ev.data.network.host.addr, 40, "%s", hoststr);
		arcan_event_enqueue(&netcontext.outevq, &ev);
		graph_log_conn_error(netcontext.graphing, 0, hoststr);
		return;
	}

/* connection completed */
	arcan_event ev = { 
					.category = EVENT_NET,
				 	.kind = EVENT_NET_CONNECTED
 	};
	snprintf(ev.data.network.host.addr, 40, "%s", hoststr);
	arcan_event_enqueue(&netcontext.outevq, &ev);
	graph_log_connected(netcontext.graphing, hoststr);
	netcontext.connstate = CONN_CONNECTED;

/* setup a pollset for incoming / outgoing and for event notification */
	apr_pollset_t* pset;
	apr_pollfd_t pfd = {
		.p = netcontext.mempool,
		.desc.s = sock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN | APR_POLLHUP | APR_POLLERR | APR_POLLNVAL,
		.rtnevents = 0,
		.client_data = &sock
	};

	apr_pollfd_t epfd = {
		.p = netcontext.mempool,
		.desc.s = netcontext.evsock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN,
		.rtnevents = 0,
		.client_data = &netcontext.evsock
	};

	int timeout = -1;

#ifdef _WIN32
    timeout = 1000;
#endif

	if (apr_pollset_create(&pset, 1, netcontext.mempool, 0) != APR_SUCCESS){
		LOG("(net) -- couldn't allocate pollset. Giving up.\n");
		return;
	}

#ifndef _WIN32
	apr_pollset_add(pset, &epfd);
#endif

	apr_pollset_add(pset, &pfd);

/* main client loop */
	while (true){
		const apr_pollfd_t* ret_pfd;
		apr_int32_t pnum;
		apr_status_t status = apr_pollset_poll(pset, timeout, &pnum, &ret_pfd);

		if (status != APR_SUCCESS && status != APR_EINTR && status != APR_TIMEUP){
			LOG("(net-cl) -- broken poll, giving up.\n");
			graph_log_conn_error(netcontext.graphing, 0, "pollset_poll");
			break;
		}

/* can just be socket or event-queue, dispatch accordingly */
		for (int i = 0; i < pnum; i++)
			if (ret_pfd[i].client_data == &sock){
				if (!client_data_process(sock, &ret_pfd[i]))
					goto giveup;
			}
			else if (ret_pfd[i].client_data == &netcontext.evsock){
				char flushb[256];
				apr_size_t szv = 256;

				apr_socket_recv(netcontext.evsock, flushb, &szv);
				if (!client_inevq_process(sock))
					break;
			}

/* graph rebuilds are initiated as program- side events */
		if (!client_inevq_process(sock))
			break;
	}

giveup:
    LOG("(net-cl) -- shutting down client session.\n");
	return;
}

void arcan_frameserver_net_run(const char* resource, const char* shmkey)
{
	struct arg_arr* args = arg_unpack(resource);
	if (!args || !shmkey)
		goto cleanup;

/* make ID slot cookies predictable only in debug,
 * to ensure that the parent process doesn't assume these are
 * allowed or indexed sequentially. */
#ifdef _DEBUG
	srand(0xfeedface);
#endif

	idcookie = rand();
	
/* default graphing output overrides? */
	unsigned gwidth = 256, gheight = 256;
	const char* rk;
	uint32_t* gbufptr = NULL;

	if (arg_lookup(args, "width", 0, &rk) ){
		unsigned neww = strtoul(rk, NULL, 10);
		if (neww > 0 && neww <= ARCAN_SHMPAGE_MAXW)
			gwidth = neww;
	}

	if (arg_lookup(args, "height", 0, &rk) ){
		unsigned newh = strtoul(rk, NULL, 10);
		if (newh > 0 && newh <= ARCAN_SHMPAGE_MAXH) 
			gheight = newh;
	}

/* using the shared memory context as a graphing / logging window,
 * for event passing, the sound as a possible alert, 
 * but also for the guard thread*/
	netcontext.shmcont  = arcan_shmif_acquire(shmkey, SHMIF_INPUT, true);

	if (!arcan_shmif_resize(&netcontext.shmcont, gwidth, gheight))
		return;

	arcan_shmif_calcofs(netcontext.shmcont.addr, 
		&(netcontext.vidp), &(netcontext.audp) );

	arcan_shmif_setevqs(netcontext.shmcont.addr, 
		netcontext.shmcont.esem, &(netcontext.inevq), 
		&(netcontext.outevq), false);

/* resize guarantees at least 32bit alignment (possibly 64, 128) */
	gbufptr = (uint32_t*) netcontext.vidp;

/* APR as a wrapper for all socket communication */
	apr_initialize();
	apr_pool_create(&netcontext.mempool, NULL);
	netcontext.basestamp = arcan_timemillis();
	netcontext.rledec_sz = DEFAULT_RLEDEC_SZ;
	netcontext.rledec_buf = malloc(netcontext.rledec_sz);

/* for win32, we transfer the first one in the HANDLE of the shmpage */
#ifdef _WIN32
#else
	if (getenv("ARCAN_SOCKIN_FD")){
		int sockin_fd;
		sockin_fd = strtol( getenv("ARCAN_SOCKIN_FD"), NULL, 10 );
		if (apr_os_sock_put(&netcontext.evsock, &sockin_fd, 
			netcontext.mempool) != APR_SUCCESS){
			LOG("(net) -- Couldn't convert FD socket to APR, giving up.\n");
		}
	}
	else {
		LOG("(net) -- No event socket found, giving up.\n");
		goto cleanup;
	}
#endif

	if (arg_lookup(args, "mode", 0, &rk) && strcmp("client", rk) == 0){
		char* dsthost = NULL;

		arg_lookup(args, "host", 0, (const char**) &dsthost);
		netcontext.graphing = graphing_new(gwidth, gheight, gbufptr);
		graphing_switch_mode(netcontext.graphing, GRAPH_NET_CLIENT);
		if (dsthost)
			client_session(dsthost, CLIENT_SIMPLE);
		else
			client_session(dsthost, CLIENT_DISCOVERY);
	}
	else if (arg_lookup(args, "mode", 0, &rk) && strcmp("server", rk) == 0){
/* sweep list of interfaces to bind to (interface=ip,port) 
 * and if none, bind to all of them */
		char* listenhost = NULL;
		char* limstr = NULL;

		arg_lookup(args, "host", 0, (const char**) &listenhost);
		arg_lookup(args, "limit", 0, (const char**) &limstr);

		long int limv = DEFAULT_CONNECTION_CAP;
		if (limstr){
			limv = strtol(limstr, NULL, 10);
			if (limv <= 0 || limv > DEFAULT_CONNECTION_CAP)
				limv = DEFAULT_CONNECTION_CAP;
		}

		netcontext.graphing = graphing_new(gwidth, gheight, gbufptr);
		graphing_switch_mode(netcontext.graphing, GRAPH_NET_SERVER_SINGLE);
		server_session(listenhost, limv);
	}
	else {
		LOG("(net), unknown mode specified.\n");
		goto cleanup;
	}

cleanup:
	apr_pool_destroy(netcontext.mempool);
	arg_cleanup(args);
}
