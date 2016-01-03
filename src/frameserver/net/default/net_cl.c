/*
 * Arcan Networking Client Reference Frameserver
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: LibAPR (Apache2)
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
#include "net_shared.h"

static struct {
/* SHM-API interface */
	struct arcan_shmif_cont shmcont;

	apr_socket_t* evsock;
	uint8_t* vidp, (* audp);

	apr_pool_t* mempool;
	apr_pollset_t* pollset;

	file_handle tmphandle;

	char* name;
	char public_key[NET_KEY_SIZE];
	char private_key[NET_KEY_SIZE];

	struct conn_state conn;
} clctx = {
	.public_key = {'C', 'L', 'I', 'E', 'N', 'T', 'P', 'U', 'B', 'L', 'I', 'C'},
	.name = "anonymous"
};

static ssize_t queueout_data(struct conn_state* conn)
{
	if (conn->state_out.state == STATE_NONE)
		return 0;

	size_t ntc = conn->state_out.lim - conn->state_out.ofs;

	if (conn->state_out.state == STATE_DATA){
		abort();
/* flush FD into outbuf at header ofset */
	}
	else if (conn->state_out.state == STATE_IMG){
		ntc = ntc > 32 * 1024 ? 32 * 1024 : ntc;
		conn->state_out.ofs += ntc;

		if (ntc == 0){
			if (!conn->pack(&clctx.conn, TAG_STATE_EOB,
				0, (char*) conn->state_out.shmcont.vidp))
				return -1;
		}

		if (!conn->pack(&clctx.conn, TAG_STATE_DATABLOCK,
			ntc, (char*) conn->state_out.shmcont.vidp + conn->state_out.ofs))
			return -1;
	}

/* ignore for now */
	return ntc;
}

static bool client_inevq_process(apr_socket_t* outconn)
{
	arcan_event ev;
	uint16_t msgsz = sizeof(ev.net.message) / sizeof(ev.net.message[0]);

/* since we flush the entire eventqueue at once, it means that multiple
 * messages may possible be interleaved in one push (up to the 64k buffer)
 * before getting sent of to the TCP layer (thus not as wasteful as it might
 * initially seem).
 *
 * The real issue is buffer overruns though, which currently means that data
 * gets lost (for custommsg) or truncated State transfers won't ever overflow
 * and are only ever tucked on at the end */
	while ( 1 == arcan_shmif_poll(&clctx.shmcont, &ev) )
		if (ev.category == EVENT_NET){
			switch (ev.net.kind){
			case EVENT_NET_INPUTEVENT:
				LOG("(net-cl) inputevent unfinished, implement "
					"event_pack()/unpack(), ignored\n");
			break;

			case EVENT_NET_CUSTOMMSG:
				if (clctx.conn.connstate < CONN_CONNECTED)
					break;

				if (strlen(ev.net.message) + 1 < msgsz)
					msgsz = strlen(ev.net.message) + 1;

				return clctx.conn.pack(&clctx.conn, TAG_NETMSG, msgsz, ev.net.message);
			break;

			default:
			break;
			}
		}
		else if (ev.category == EVENT_TARGET){
			switch (ev.tgt.kind){
			case TARGET_COMMAND_EXIT:
				return false;
			break;

/*
 * new transfer (arcan->fsrv) requested, or pending
 * request to accept incoming transfer.
 * reject: transfer pending or non-authenticated
 * accept: switch to STATEXFER mode
 */
			case TARGET_COMMAND_NEWSEGMENT:
				net_newseg(&clctx.conn,	ev.tgt.ioevs[0].iv, ev.tgt.message);

/* output type? assume transfer request */
				if (ev.tgt.ioevs[0].iv == 0){
					char outbuf[4] = {
						clctx.conn.state_out.shmcont.addr->w,
						clctx.conn.state_out.shmcont.addr->w >> 8,
						clctx.conn.state_out.shmcont.addr->h,
						clctx.conn.state_out.shmcont.addr->h >> 8
					};
					clctx.conn.state_out.state = STATE_IMG;
					return (clctx.conn.pack(
						&clctx.conn, TAG_STATE_IMGOBJ, 4, outbuf));
				}
				else {
					if (clctx.conn.blocked){
						clctx.conn.blocked = false;
					}
				}

				close(clctx.tmphandle);
				clctx.tmphandle = 0;
			break;

/*
 * new transfer (fsrv<->fsrv) requested
 */
			case TARGET_COMMAND_STORE:
			break;

			case TARGET_COMMAND_RESTORE:
			break;

			case TARGET_COMMAND_STEPFRAME:
				queueout_data(&clctx.conn);
			break;

			default:
				; /* just ignore */
		}
		}
		else;

	return true;
}

/*
 * host   : destination index server (or NULL for broadcast)
 * optkey : if (!passive) retry until we get a response where public key
 *          OR name matches optkey. If NULL, just use the first reply received.
 * passive : never quit, just forward responses to parent.
 *
 * returns a point to a dynamically allocated buffer that will also
 * free up (replhost, replkey) or NULL.
 */
static bool host_discover(const char* reqhost,
	const char* optkey, bool passive,
	char** outhost, int* outport, char** pkey)
{
	char* reqmsg, repbuf[ NET_HEADER_SIZE ];
	bool retv = false;

/* no strict requirements for this one, only used in limiting
 * replay / DoS- response possibility. */
	int32_t magic_v = rand();
	char magic[5] = {0};
	memcpy(magic, &magic_v, sizeof(int32_t));

	size_t dst_sz;
	reqmsg = net_pack_discover(true,
		clctx.public_key, clctx.name, (char*)magic, "", 0, &dst_sz);

	apr_status_t rv;
	apr_sockaddr_t* addr;

/* specific, single, redirector host OR IPV4 broadcast,
 * multicast groups, IPv6 support etc. should go here */
	apr_sockaddr_info_get(&addr, reqhost ? reqhost : "255.255.255.255",
		APR_INET, DEFAULT_DISCOVER_REQ_PORT, 0, clctx.mempool);

	int rport = DEFAULT_DISCOVER_RESP_PORT;
	apr_socket_t* broadsock = net_prepare_socket("0.0.0.0", NULL,
		&rport, false, clctx.mempool);

	if (!broadsock){
		LOG("(net-cl) -- host discover failed, couldn't prepare"
			"	listening socket.\n");
		return NULL;
	}
	apr_socket_timeout_set(broadsock, DEFAULT_CLIENT_TIMEOUT);

	while (true){
		apr_size_t nts = dst_sz, ntr;
		apr_sockaddr_t recaddr;
		arcan_event dev;

/* we only retry on full timeout, never on a broken incoming package
 * else broken replies could be used to amplify */
		if ( ( rv = apr_socket_sendto(broadsock, addr, 0,
			reqmsg, &nts) ) != APR_SUCCESS)
			break;

retry_partial:
/* flush and check for exit */
		while (arcan_shmif_poll(&clctx.shmcont, &dev) > 0)
			if (dev.category == EVENT_TARGET && dev.tgt.kind == TARGET_COMMAND_EXIT)
				return NULL;

		ntr = NET_HEADER_SIZE;
		rv  = apr_socket_recvfrom(&recaddr, broadsock, 0, repbuf, &ntr);

		if (rv != APR_SUCCESS)
			goto done;

		char* repmsg, (* name), (* cookie);
		if (ntr != NET_HEADER_SIZE || !(repmsg = net_unpack_discover(
			repbuf, false, pkey, &name, &cookie, outhost, outport))){
			goto retry_partial;
		}

		if (memcmp(cookie, (char*)magic, 4) != 0){
			free(repmsg);
			goto retry_partial;
		}

/* valid, unpacked package */
/* if no IP is set, the IP is that of the sending source */
		if (strcmp(*outhost, "0.0.0.0") == 0)
			apr_sockaddr_ip_getbuf(*outhost, NET_ADDR_SIZE - 5, &recaddr);

/* passive, will background scan until we get killed or sent
 * TARGET_COMMAND_EXIT */
		if (passive){
			arcan_event ev = {
				.category = EVENT_NET,
				.net.kind = EVENT_NET_DISCOVERED
			};
			strncpy(ev.net.host.addr, *outhost, NET_ADDR_SIZE);
			strncpy(ev.net.host.key, *pkey, NET_KEY_SIZE);
			strncpy(ev.net.host.key, name, NET_NAME_SIZE);

			arcan_shmif_enqueue(&clctx.shmcont, &ev);
		}
		else if (optkey == NULL ||
			strcmp(optkey, *pkey) == 0 || strcmp(name, optkey) == 0){
			retv = true;
			apr_socket_close(broadsock);
			goto done;
		}

		free(repmsg);
	}

done:
	free(	reqmsg );
	return retv;
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" host    \t url       \t connect to specified host \n"
		" ident   \t name      \t set your (human readable) identity \n"
		" pubkey  \t pubk      \t use the specified base64 25519 public key\n"
		" privkey \t privk     \t use the specified base64 25519 private key\n"
    " reqkey  \t pubk      \t only accept a host with a specific public key\n"
		"---------\t-----------\t-----------------\n");
}

int afsrv_netcl(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	if (!con){
		dump_help();
		return EXIT_FAILURE;
	}

	const char* host = NULL;
	arg_lookup(args, "host", 0, &host);

	struct arcan_shmif_cont shmcont = *con;

	if (!shmcont.addr){
		LOG("(net-cl) couldn't setup shared memory connection\n");
		return EXIT_FAILURE;
	}

	arg_lookup(args, "ident", 0, (const char**) &clctx.name);

	const char* pubkey = NULL, (* privkey) = NULL;
	if (arg_lookup(args, "pubkey", 0, &pubkey)){
	}

	if (arg_lookup(args, "privkey", 0, &privkey)){
	}

	else{
/* generate public/private keypair */
	}

	apr_initialize();
	apr_pool_create(&clctx.mempool, NULL);

	const char* reqkey = NULL;
	char* hoststr, (* hostkey);
	int outport = DEFAULT_CONNECTION_PORT;

	arg_lookup(args, "reqkey", 0, &reqkey);

	if (host && strcmp(host, ":discovery") == 0){
		host_discover(host, reqkey, true, &hoststr, &outport, &hostkey);
		return EXIT_SUCCESS;
	}

	if (!host_discover(host, reqkey,
		false, &hoststr, &outport, &hostkey)){
		LOG("(net) -- couldn't find any Arcan- compatible server.\n");
		return EXIT_FAILURE;
	}

/* "normal" connection finally */
	apr_sockaddr_t* sa;
	apr_socket_t* sock;

/* obtain connection using a blocking socket */
	apr_sockaddr_info_get(&sa, hoststr,
		APR_INET, outport, 0, clctx.mempool);
	apr_socket_create(&sock, sa->family,
		SOCK_STREAM, APR_PROTO_TCP, clctx.mempool);
	apr_socket_opt_set(sock, APR_SO_NONBLOCK, 0);
	apr_socket_timeout_set(sock, DEFAULT_CLIENT_TIMEOUT);
	apr_status_t rc = apr_socket_connect(sock, sa);

	if (rc != APR_SUCCESS){
		arcan_event ev = {
			.category = EVENT_NET,
			.net.kind = EVENT_NET_NORESPONSE
		};
		snprintf(ev.net.host.addr, 40, "%s", hoststr);
		arcan_shmif_enqueue(&clctx.shmcont, &ev);
		return EXIT_SUCCESS;
	}

/* connection completed */
	arcan_event ev = {
		.category = EVENT_NET,
		.net.kind = EVENT_NET_CONNECTED
 	};

	snprintf(ev.net.host.addr, 40, "%s", hoststr);
	arcan_shmif_enqueue(&clctx.shmcont, &ev);

/*
 * setup a pollset for incoming / outgoing and for event notification,
 * we'll use a signaling socket to be able to have the shared memory
 * event-queue poll and monitored in the operation as we're waiting
 * on incoming / outgoing
 */
#ifdef _WIN32
#else
	int sockin_fd = con->epipe;

	if (apr_os_sock_put(
		&clctx.evsock, &sockin_fd, clctx.mempool) != APR_SUCCESS){
		LOG("(net) -- Couldn't convert FD socket to APR, giving up.\n");
		return EXIT_FAILURE;
	}
#endif

	apr_pollfd_t pfd = {
		.p = clctx.mempool,
		.desc.s = sock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN | APR_POLLHUP | APR_POLLERR | APR_POLLNVAL,
		.rtnevents = 0,
		.client_data = &sock
	};
	clctx.conn.poll_state = pfd;

	apr_pollfd_t epfd = {
		.p = clctx.mempool,
		.desc.s = clctx.evsock,
		.desc_type = APR_POLL_SOCKET,
		.reqevents = APR_POLLIN,
		.rtnevents = 0,
		.client_data = &clctx.evsock
	};

	int timeout = -1;

#ifdef _WIN32
    timeout = 1000;
#endif

	if (apr_pollset_create(&clctx.pollset, 1, clctx.mempool, 0) != APR_SUCCESS){
		LOG("(net) -- couldn't allocate pollset. Giving up.\n");
		return EXIT_FAILURE;
	}

#ifndef _WIN32
	apr_pollset_add(clctx.pollset, &epfd);
#endif
	apr_pollset_add(clctx.pollset, &clctx.conn.poll_state);

/* setup client connection context, this rather awkward structure
 * is to be able to re-use a lot of the server-side code */
	net_setup_cell(&clctx.conn, &clctx.shmcont, clctx.pollset);
	clctx.conn.inout = sock;
	clctx.conn.decode = net_hl_decode;
	clctx.conn.pack = net_pack_basic;
	clctx.conn.buffer = net_buffer_basic;
	clctx.conn.validator = net_validator_tlv;
	clctx.conn.dispatch = net_dispatch_tlv;
	clctx.conn.flushout = net_flushout_default;
	clctx.conn.queueout = net_queueout_default;
	clctx.conn.connstate = CONN_CONNECTED;

/* main client loop */
	while (true){
		if (clctx.conn.blocked){
			if (!client_inevq_process(sock))
				break;
			continue;
		}

		ssize_t q_sz = queueout_data(&clctx.conn);
		if (-1 == q_sz)
			break;
		else if (q_sz > 0)
			continue;

		const apr_pollfd_t* ret_pfd;
		apr_int32_t pnum;
		apr_status_t status = apr_pollset_poll(
			clctx.pollset, timeout, &pnum, &ret_pfd);

		if (status != APR_SUCCESS && status != APR_EINTR && status != APR_TIMEUP){
			LOG("(net-cl) -- broken poll, giving up.\n");
			break;
		}

/*
 * client socket: check if it's still alive and buffer / parse
 * event socket: process event-loop
 */
		for (int i = 0; i < pnum; i++){
			if (ret_pfd[i].client_data == &sock){
				static arcan_event ev = {
					.category = EVENT_NET,
					.net.kind = EVENT_NET_DISCONNECTED
				};

				if (ret_pfd[i].rtnevents & (APR_POLLHUP | APR_POLLERR | APR_POLLNVAL)){
					LOG("(net-cl) -- poll on socket failed, shutting down.\n");
				}

				if (ret_pfd[i].rtnevents & APR_POLLOUT)
					clctx.conn.flushout(&clctx.conn);

				if (clctx.conn.buffer(&clctx.conn))
					continue;

				arcan_shmif_enqueue(&clctx.shmcont, &ev);
				apr_socket_close(clctx.conn.inout);
				goto giveup;
			}

/* we're not really concerned with the data on the socket,
 * it's just used as a pollable indicator */
			char flushb[256];
			apr_size_t szv = sizeof(flushb);
			apr_socket_recv(clctx.evsock, flushb, &szv);

			if (!client_inevq_process(sock))
				break;
		}
	}

giveup:
    LOG("(net-cl) -- shutting down client session.\n");
	return EXIT_SUCCESS;
}


