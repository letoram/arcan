/*
 * Arcan Networking Server Reference Frameserver
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: LibAPR (Apache2)
 */

/*
 * The networking frameserver / support is somewhat more involved than
 * the others, partly because it defines a set of support functions and
 * modes, but the actual communication logic etc. is part of the script.
 *
 * This means that server pub/priv. key storage and public key verification
 * is an external process from a controlling channel and not a part of
 * the implementation here.
 *
 * There are multiple modes which the networking code can be used,
 * for the server side, there is a public "gatekeeper" that listens for
 * requests on UDP and responds with a possible public-key, ident and
 * dstip:port for the connection.
 *
 * If the request supplied a non-empty public key, the response will be
 * encrypted using this key and provide a nonce of its own (or 0 when we
 * do not need / want a connection between the gatekeeper and the server,
 * then the nonce has to be registered in the client connection tracking
 * structure), which will be used as the base for a counter on the control
 * session.
 *
 * If the client accepts the public key (verification happens elsewhere,
 * on an offline channel, through communicating a fingerprint, etc.) it
 * connects to the server. This connection is encrypted, not authenticated.
 * The server should not rely on the client IP to maintain this connection,
 * it will be a configurable feature to use TOR or similar local proxy for
 * this session.
 *
 * By default, there's no explicit connection between the gatekeeper and the
 * other server, though without knowledge of the server public key it might be
 * hard to get known (though it can be configured to use no public- key,
 * for semi-trusted LANs etc.).
 *
 * The governing script has to explicitly acknowledge the authenticity of the
 * client (cache / key store of previously known ones etc.) when that is done
 * a session_key update will be sent (this can be re-keyed arbitrarily).
 *
 * A normal connection is only allowed to pass small control messages between
 * each-other. An authenticated session is allowed to do block based state
 * transfers and to initiate streaming sessions.
 */

#include "net_shared.h"
#include "net.h"
#include "frameserver.h"

#ifdef _WIN32
/* Doesn't seem like mingw/apr actually gets the
 * TransmitFile symbol so stub it here */
#define sleep(X) (Sleep(X * 1000))
BOOL PASCAL TransmitFile(SOCKET hs, HANDLE hf, DWORD nbtw, DWORD nbps,
	LPOVERLAPPED lpo, LPTRANSMIT_FILE_BUFFERS lpTransmitBuffers, DWORD dfl){
    return false;
}
#endif

/*
 * just rand() XoR key for use with higher level API (Arcan scripting),
 * purpose is just to enforce actual tracking in the script and preventing
 * hard-coded values.
 */
static int idcookie = 0;

static struct {
/* SHM-API interface */
	struct arcan_shmif_cont shmcont;
	apr_socket_t* evsock;
	uint8_t* vidp, (* audp);

/* for future time-synchronization (ping/pongs interleaved
 * with regular messages, compare drift with timestamps to
 * determine current channel latency */
	unsigned long long basestamp;

	apr_pool_t* mempool;
	apr_pollset_t* pollset;

	unsigned n_conn;

	int inport;
	char lt_keypair_pubkey[NET_KEY_SIZE], lt_keypair_privkey[NET_KEY_SIZE];
} srvctx = {
	.lt_keypair_pubkey = {'P', 'U', 'B', 'L', 'I', 'C'},
	.lt_keypair_privkey = {'P', 'R', 'I', 'V', 'A', 'T', 'E'}
};

/*
 * placeholder marker for data that should be rendered to the
 * primary output display
 */
#define GRAPH_EVENT(...) LOG(__VA_ARGS__)

static struct conn_state* init_conn_states(int limit)
{
	struct conn_state* active_cons = malloc(sizeof(struct conn_state) * limit);

	if (!active_cons)
		return NULL;

	memset(active_cons, '\0', sizeof(struct conn_state) * limit);

	for (int i = 0; i < limit; i++){
		net_setup_cell( &active_cons[i], &srvctx.shmcont, srvctx.pollset );
		active_cons->slot = i ^ idcookie;
	}

	return active_cons;
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

static void authenticate(struct conn_state* active_cons, int nconns, int slot)
{
	if (slot == 0){
		LOG("Attempt to set authentication flag on broken domain\n");
		return;
	}

	struct conn_state* target_con = lookup_connection(active_cons, nconns, slot);
	if (!target_con || target_con->connstate != CONN_CONNECTED)
		return;

	target_con->connstate = CONN_AUTHENTICATED;
	GRAPH_EVENT("Slot %d authenticated", slot);
/* FIXME: Send session REKEY if encrypted */
}

static void disconnect(struct conn_state* active_cons, int nconns, int slot)
{
	if (slot == 0){
		for (int i = 0; i < nconns; i++)
			if (active_cons[i].connstate > CONN_OFFLINE){
				GRAPH_EVENT("Mass Disconnect (%i:%i)\n", i, active_cons[i].slot);
				apr_socket_close(active_cons[i].inout);
				apr_pollset_remove(srvctx.pollset, &active_cons[i].poll_state);
				net_setup_cell( &active_cons[i], &srvctx.shmcont, srvctx.pollset );
			}
	}
	else {
		struct conn_state* target_con = lookup_connection(active_cons,
			nconns, slot);
		if (target_con && target_con->connstate > CONN_OFFLINE){
			GRAPH_EVENT("Disconnecting %d\n", slot);
			apr_socket_close(target_con->inout);
			apr_pollset_remove(srvctx.pollset, &target_con->poll_state);
			net_setup_cell( target_con, &srvctx.shmcont, srvctx.pollset );
		}
		else
			LOG("Attempt to disconnect bad or already disconnected slot (%d)\n", slot);
	}
}

static void server_pack_data(struct conn_state* active_cons,
	int nconns, int id, enum net_tags tag, size_t buf_sz, char* buf)
{
	if (id > nconns || id < 0)
		return;

/* broadcast */
	if (id == 0){
		GRAPH_EVENT("broadcast (%zu) bytes\n", buf_sz);
		for(int i = 0; i < nconns; i++)
			if (active_cons[i].inout){
				if (!active_cons[i].pack(&active_cons[i], tag, buf_sz, buf))
					disconnect(active_cons, nconns, id);
			}
	}

/* unicast */
	else if (active_cons[id-1].inout){
		GRAPH_EVENT("queue (%zu) bytes to slot (%d)\n", buf_sz, id);
		if (!active_cons[id-1].pack(&active_cons[id-1], tag, buf_sz, buf))
			disconnect(active_cons, nconns, id);
	}
	else;

	return;
}

static void client_socket_close(struct conn_state* state)
{
	arcan_event rv = {
		.category = EVENT_NET,
		.net.kind = EVENT_NET_DISCONNECTED,
	};
	GRAPH_EVENT("close socket on (%d)\n", state->slot);

	net_setup_cell( state, &srvctx.shmcont, srvctx.pollset );
	arcan_shmif_enqueue(&srvctx.shmcont, &rv);
}

static bool server_process_inevq(struct conn_state* active_cons, int nconns)
{
	arcan_event ev;
	uint16_t msgsz = sizeof(ev.net.message) / sizeof(ev.net.message[0]);

	while (arcan_shmif_poll(&srvctx.shmcont, &ev) > 0)
		if (ev.category == EVENT_NET){
			switch (ev.net.kind){
			case EVENT_NET_INPUTEVENT:
				LOG("(net-srv) inputevent unfinished, implement "
					"event_pack()/unpack(), ignored\n");
			break;

/* don't confuse this one with EVENT_NET_DISCONNECTED, which is a
 * notification rather than a command */
			case EVENT_NET_DISCONNECT:
				disconnect(active_cons, nconns, ev.net.connid);
			break;

			case EVENT_NET_AUTHENTICATE:
				authenticate(active_cons, nconns, ev.net.connid);
			break;

			case EVENT_NET_CUSTOMMSG:
				GRAPH_EVENT("Parent pushed message (%s)\n", ev.net.message);
				server_pack_data(active_cons, nconns, ev.net.connid,
					TAG_NETMSG, msgsz, ev.net.message);
			break;

			default:
				LOG("(net-srv) unhandled network event, %d\n", ev.net.kind);
			}
		}
		else if (ev.category == EVENT_TARGET){
			switch (ev.tgt.kind){
				case TARGET_COMMAND_EXIT:
					LOG("(net-srv) parent requested termination, giving up.\n");
					return false;
				break;

			case TARGET_COMMAND_NEWSEGMENT:
				LOG("new segment arrived, id %d\n", ev.tgt.ioevs[1].iv);
				net_newseg(lookup_connection(active_cons, nconns,
					ev.tgt.ioevs[1].iv), ev.tgt.ioevs[0].iv, ev.tgt.message);
			break;

/*
 * parent signalling that the previously mapped segment can be used
 * to transfer now. ioevs[0] signals the slot that will be used.
 */
				case TARGET_COMMAND_STEPFRAME:

				break;

				case TARGET_COMMAND_REQFAIL:
					LOG("(net-srv) client disallowed connection");
				break;

				case TARGET_COMMAND_STORE:
				break;

				case TARGET_COMMAND_RESTORE:
				break;

				default:
					LOG("(net-srv) unhandled target event: %d\n", ev.tgt.kind);
			}
		}
		else;

	return true;
}


static void server_accept_connection(int limit, apr_socket_t* ear_sock,
	apr_pollset_t* pollset, struct conn_state* active_cons)
{
	apr_socket_t* newsock;
	if (apr_socket_accept(&newsock, ear_sock, srvctx.mempool) != APR_SUCCESS)
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
	active_cons[j].buffer    = net_buffer_basic;
	active_cons[j].validator = net_validator_tlv;
	active_cons[j].dispatch  = net_dispatch_tlv;
	active_cons[j].flushout  = net_flushout_default;
	active_cons[j].queueout  = net_queueout_default;
	active_cons[j].pack      = net_pack_basic;
	active_cons[j].decode    = net_hl_decode;
	active_cons[j].connstate = CONN_CONNECTED;
	active_cons[j].pollset   = srvctx.pollset;
	active_cons[j].connect_stamp = arcan_timemillis();

	apr_pollfd_t* pfd = &active_cons[j].poll_state;

	pfd->desc.s      = newsock;
	pfd->desc_type   = APR_POLL_SOCKET;
	pfd->client_data = &active_cons[j];
	pfd->reqevents   = APR_POLLHUP | APR_POLLERR | APR_POLLIN;
	pfd->rtnevents   = 0;
	pfd->p           = srvctx.mempool;

	apr_pollset_add(pollset, pfd);

/* figure out source address, add to event and fire */
	apr_sockaddr_t* addr;

	apr_socket_addr_get(&addr, APR_REMOTE, newsock);
	arcan_event outev = {
		.category = EVENT_NET,
		.net.kind = EVENT_NET_CONNECTED,
		.net.connid = active_cons[j].slot
	};

	size_t out_sz = sizeof(outev.net.host.addr) /
		sizeof(outev.net.host.addr[0]);
	apr_sockaddr_ip_getbuf(outev.net.host.addr, out_sz, addr);

	arcan_shmif_enqueue(&srvctx.shmcont, &outev);
}

static char* get_redir(char* pk, char* n,
	apr_sockaddr_t* src, char** outkey, int* redir_port)
{
/*
 * -- NOTE --
 * entry point for adding honeypot redirections, load balancing etc.
 * based on src addr, public key, name ...
 */

	*redir_port = srvctx.inport;
	*outkey = (char*) srvctx.lt_keypair_pubkey;

	return "0.0.0.0";
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
static void server_gatekeeper_message(apr_socket_t* gk_sock, char* ident)
{
/* partial reads etc. are just ignored, client have to resend. */
	char inbuf[NET_HEADER_SIZE];
	apr_size_t ntr = NET_HEADER_SIZE;

	apr_sockaddr_t src_addr;

	if (apr_socket_recvfrom(&src_addr, gk_sock, 0, inbuf, &ntr) != APR_SUCCESS ||
		ntr != NET_HEADER_SIZE)
			return;

	char* pubkey, (* name), (* cookie), (* host);
	int port;

	char* unpack = net_unpack_discover(inbuf, true,
		&pubkey, &name, &cookie, &host, &port);

	if (!unpack)
		return;

	char* redir_key;
	int redir_port;
	char* redir_addr = get_redir(pubkey, name,
		&src_addr, &redir_key, &redir_port);

/* server does not provide service to the addr/key/name combination */
	if (!redir_addr){
	 free(unpack);
	 return;
	}

	size_t outsz;
	char* outbuf = net_pack_discover(false,
		redir_key, ident, cookie, redir_addr, redir_port, &outsz);
	free(unpack);

	if (outbuf){
		src_addr.port = DEFAULT_DISCOVER_RESP_PORT;
		apr_socket_sendto(gk_sock, &src_addr, 0, outbuf, &outsz);
		free(outbuf);
	}
}

static apr_socket_t* server_prepare_gatekeeper(char* host)
{
	int port = DEFAULT_DISCOVER_REQ_PORT;
	return net_prepare_socket(host, NULL,
		&port, false, srvctx.mempool);
}

static void server_session(const char* host, char* ident, int limit)
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
		srvctx.mempool, 0) != APR_SUCCESS){
			LOG("(net-srv) -- Couldn't create server pollset, giving up.\n");
			return;
	}

	int sleeptime = 5 * 1000;
	int retrycount = 10;

	apr_socket_t* ear_sock;

retry:
	ear_sock = net_prepare_socket(host, NULL, &srvctx.inport, true, srvctx.mempool);

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

	LOG("(net-srv) -- listening interface up on %s:%d\n",
		host ? host : "(global)", srvctx.inport);

	srvctx.pollset = poll_in;

/* the pollset is created noting that we have the responsibility for
 * assuring that the descriptors involved stay in scope, thus pfd needs to
 * be here or dynamically allocated */
	apr_pollfd_t pfd = {
		.p      = srvctx.mempool,
		.desc.s = ear_sock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN | APR_POLLHUP | APR_POLLERR,
		.rtnevents = 0,
		.client_data = ear_sock
	}, gkpfd;

	apr_pollfd_t epfd = {
		.p      = srvctx.mempool,
		.desc.s = srvctx.evsock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN,
		.rtnevents = 0,
		.client_data = srvctx.evsock
	};

/* should be solved in a pretty per host etc. manner and for
 * that matter, IPv6 */
	apr_socket_t* gk_sock = server_prepare_gatekeeper("0.0.0.0");
	if (gk_sock){
		LOG("(net-srv) -- gatekeeper listening on broadcast for %s\n",
			host ? host : "(global)");
		gkpfd.p = srvctx.mempool;
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
						.category = EVENT_NET,
						.net.kind = EVENT_NET_BROKEN
					};

					arcan_shmif_enqueue(&srvctx.shmcont, &errc);
					LOG("(net-srv) -- error on listening interface "
						"during poll, giving up.\n");
					return;
				}

				server_accept_connection(limit, ret_pfd[i].desc.s,
					poll_in, active_cons);
				continue;
			}
			else if (cb == gk_sock){
				server_gatekeeper_message(gk_sock, ident);
				continue;
			}
/* this socket is used for OOB FD transfers and as a pollable semaphore */
			else if (cb == srvctx.evsock){
				char flushb[256];
				apr_size_t szv = sizeof(flushb);

				apr_socket_recv(srvctx.evsock, flushb, &szv);
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
				res = state->buffer(state);

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

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" host    \t name      \t bind and listen on specific host\n"
		" port    \t number    \t listen on the specified port\n"
		" limit   \t n_conn    \t limit number of allowed connections\n"
		" ident   \t name      \t use this human-readable identity\n"
		"---------\t-----------\t----------------\n"
	);
}

int afsrv_netsrv(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	if (!con){
		dump_help();
		return EXIT_FAILURE;
	}

	int gwidth = 256;
	int gheight = 256;

	apr_initialize();
	apr_pool_create(&srvctx.mempool, NULL);

/* for win32, we transfer the first one in the HANDLE of the shmpage */
#ifdef _WIN32
#else
	int sockin_fd = con->epipe;
	if (apr_os_sock_put(&srvctx.evsock, &sockin_fd,
		srvctx.mempool) != APR_SUCCESS){
		LOG("(net) -- Couldn't convert FD socket to APR, giving up.\n");
		return EXIT_FAILURE;
	}
#endif

/* make ID slot cookies predictable only in debug,
 * to ensure that the parent process doesn't assume these are
 * allowed or indexed sequentially. */
#ifdef _DEBUG
	srand(0xfeedface);
#endif

	idcookie = rand();

	struct arcan_shmif_cont shmcont = *con;

	if (!arcan_shmif_resize(&shmcont, gwidth, gheight))
		return EXIT_FAILURE;

	char* listenhost = NULL;
	char* limstr = NULL;
	char* identstr = "anonymous";

	arg_lookup(args, "host", 0, (const char**) &listenhost);
	arg_lookup(args, "limit", 0, (const char**) &limstr);
	arg_lookup(args, "ident", 0, (const char**) &identstr);

	const char* tmpstr;
	srvctx.inport = 0;
	if (arg_lookup(args, "port", 0, &tmpstr)){
		srvctx.inport = strtoul(tmpstr, NULL, 10);
	}

	long int limv = DEFAULT_CONNECTION_CAP;
	if (limstr)
		limv = strtol(limstr, NULL, 10);

	if (limv <= 0 || limv > DEFAULT_CONNECTION_CAP)
		limv = DEFAULT_CONNECTION_CAP;

	server_session(listenhost, identstr, limv);
	return EXIT_SUCCESS;
}

