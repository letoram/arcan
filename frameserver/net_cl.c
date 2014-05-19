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
#include "net_shared.h"

static struct {
/* SHM-API interface */
	struct arcan_shmif_cont shmcont;

	apr_socket_t* evsock; 
	uint8_t* vidp, (* audp);
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;

	apr_pool_t* mempool;
	apr_pollset_t* pollset;

	file_handle tmphandle;

/* if we're forced to wait for a 
 * response from the parent before proceeding */
	bool blocked;

	struct conn_state conn;
} clctx = {0};

static bool queueout_data(struct conn_state* conn)
{
	if (conn->state_out.state == STATE_NONE)
		return true;

	if (conn->state_out.state == STATE_DATA){
		abort();
/* flush FD into outbuf at header ofset */
	}
	else if (conn->state_out.state == STATE_IMG){
		size_t ntc = conn->state_out.lim - conn->state_out.ofs;
		ntc = ntc > 32 * 1024 ? 32 * 1024 : ntc;
		conn->state_out.ofs += ntc;

		return conn->pack(&clctx.conn, TAG_STATE_DATABLOCK, 
			ntc, (char*) conn->state_out.vidp + conn->state_out.ofs);
	}

/* ignore for now */
	return true;
}

static void flushvid(struct conn_state* self)
{
	self->state_in.ctx.addr->vready = true;
	arcan_shmif_signal(&self->state_in.ctx, SHMIF_SIGVID);
	arcan_shmif_drop(&self->state_in.ctx);
	self->state_in.state = STATE_NONE;
	self->state_in.ofs = 0;
	self->state_in.lim = 0;
}

/*
 * The core protocol dictates a few features like
 * keepalive, session re-keying etc. Additional
 * TLV- based features can be defined in the net.c
 * and net_cl.c.
 *
 * Here, we add to option to support IMGOBJ and
 * DATAOBJ, both which need the main process to 
 * provide us with extra resources to direct the data.
 *
 */
static bool client_decode(struct conn_state* self, 
	enum net_tags tag, size_t len, char* val)
{
	if (self->connstate != CONN_AUTHENTICATED){
		LOG("(net-cl) permission error, block transfer to "
			"an unauthenticated session is not permitted.\n");
		return false;
	}

	switch (tag){
/* 
 * there are two ways in which we can propagate information
 * about an incoming image object, one is "in advance" by
 * having the parent give us an input segment, then we resize
 * that when we know the dimensions. The other is that we 
 * explicitly request a new segment to draw into, and then
 * we will have to wait for a response from the parent before
 * moving on.
 */
	case TAG_STATE_IMGOBJ:
		if (self->state_in.state == STATE_NONE){
			if (len < 4) /*w, h, little-endian */
				return false;
	
			int desw = (int16_t)val[0] | (int16_t)val[1] << 8;
			int desh = (int16_t)val[2] | (int16_t)val[3] << 8;

			printf("got request for image, %d x %d\n", desw, desh); 
			if (self->state_in.ctx.addr){
				if (!arcan_shmif_resize(&self->state_in.ctx, desw, desh)){
					LOG("incoming data segment outside allowed dimensions (%d x %d)"
						", terminating.\n", desw, desh);
					return false;
				}
				self->state_in.state = STATE_IMG;
			} 
			else {
				arcan_event outev = {
					.kind = EVENT_EXTERNAL_NOTICE_SEGREQ,
					.category = EVENT_EXTERNAL,
					.data.external.noticereq.width = desw,
					.data.external.noticereq.height = desh
				};

				arcan_event_enqueue(&clctx.outevq, &outev);
				clctx.blocked = true;
/* need to process the eventqueue here as there may be
 * packets pending */
			}
		}
	break;

	case TAG_STATE_EOB:
		if (self->state_in.state == STATE_IMG){
			flushvid(self);
		}
		else if (self->state_in.state == STATE_DATA){
			close(self->state_in.fd);
			self->state_in.fd = BADFD;
		}
	break;

	case TAG_STATE_DATABLOCK:
/* silent drop */
		if (self->state_in.state == STATE_NONE){
			return true; 
		}
/* streaming, no limit */
		else if (self->state_in.state == STATE_DATA){
			while(len > 0){
				size_t nw = write(self->state_in.fd, val, len);
				if (nw == -1 && (errno != EAGAIN || errno != EINTR))
					break;
				else 
					continue;	

				len -= nw;
				val += nw;
			}	
		}
		else if (self->state_in.state == STATE_IMG){
			ssize_t ub = self->state_in.lim - self->state_in.ofs;
			size_t ntw = ub > len ? len : ub; 
		 	memcpy(self->state_in.vidp + self->state_in.ofs, val, ntw);	
			self->state_in.ofs += ntw;
			if (self->state_in.ofs == self->state_in.lim)
				flushvid(self);
		}
		return true;
	break;

	case TAG_STATE_DATAOBJ:
		if (self->state_in.state == STATE_NONE){
			return true; /* silent drop */
		}
		else if (self->state_in.state == STATE_IMG){
			return false; /* protocol error */
		}
		else {
/* need some message to hint that we have a state transfer incoming */
		}
	break;	
/* 
 * flush package, this could potentially be locked to the 
 * responsiveness of the recipient.
 */
	default:
	break;
	}
	
	return true;
}

static bool client_inevq_process(apr_socket_t* outconn)
{
	arcan_event ev;
	uint16_t msgsz = sizeof(ev.data.network.message) / 
		sizeof(ev.data.network.message[0]);

/* since we flush the entire eventqueue at once, it means that multiple
 * messages may possible be interleaved in one push (up to the 64k buffer)
 * before getting sent of to the TCP layer (thus not as wasteful as it might
 * initially seem).
 *
 * The real issue is buffer overruns though, which currently means that data
 * gets lost (for custommsg) or truncated State transfers won't ever overflow
 * and are only ever tucked on at the end */
	while ( 1 == arcan_event_poll(&clctx.inevq, &ev) )
		if (ev.category == EVENT_NET){
			switch (ev.kind){
			case EVENT_NET_INPUTEVENT:
				LOG("(net-cl) inputevent unfinished, implement "
					"event_pack()/unpack(), ignored\n");
			break;

			case EVENT_NET_CUSTOMMSG:
				if (clctx.conn.connstate < CONN_CONNECTED)
					break;

				if (strlen(ev.data.network.message) + 1 < msgsz)
					msgsz = strlen(ev.data.network.message) + 1;

				return clctx.conn.pack(&clctx.conn, 
					TAG_NETMSG, msgsz, ev.data.network.message);
			break;

			case EVENT_NET_GRAPHREFRESH:
			break;
			}
		}
		else if (ev.category == EVENT_TARGET){
			switch (ev.kind){
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
				net_newseg(&clctx.conn,	ev.data.target.ioevs[0].iv,
					ev.data.target.message);
			
/* output type? assume transfer request */	
				if (ev.data.target.ioevs[0].iv == 0){
					char outbuf[4] = {
						clctx.conn.state_out.ctx.addr->w,
						clctx.conn.state_out.ctx.addr->w >> 8,
						clctx.conn.state_out.ctx.addr->h,
						clctx.conn.state_out.ctx.addr->h >> 8
					};
					clctx.conn.state_out.state = STATE_IMG;
					return (clctx.conn.pack(
						&clctx.conn, TAG_STATE_IMGOBJ, 4, outbuf));
				} 
				else {
					if (clctx.blocked){
						clctx.blocked = false;
					}
				}

				close(clctx.tmphandle);
				clctx.tmphandle = 0;
			break;

/*
 * new transfer (fsrv<->fsrv) requested
 */
			case TARGET_COMMAND_FDTRANSFER:
				clctx.tmphandle = frameserver_readhandle(&ev);
			break;

			case TARGET_COMMAND_STORE:
				clctx.tmphandle = 0;
			break;

			case TARGET_COMMAND_RESTORE:
				clctx.tmphandle = 0;
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
		APR_INET, DEFAULT_DISCOVER_REQ_PORT, 0, clctx.mempool);

	apr_socket_t* broadsock = net_prepare_socket("0.0.0.0", NULL, 
		DEFAULT_DISCOVER_RESP_PORT, false, clctx.mempool);
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
							arcan_event_enqueue(&clctx.outevq, &ev);

/* flush the queue */
							while ( 1 == arcan_event_poll(&clctx.outevq, &dev)){
								if (dev.category == EVENT_TARGET && dev.kind == 
									TARGET_COMMAND_EXIT)
									return NULL;
							}
						}

					}
					else
						return strdup(&repmsg[MAX_PUBLIC_KEY_SIZE + IDENT_SIZE]);
				}
				else; /* our own request or bad response */
			}
		}
		else{ /* short read or, more likely, broken / purposely malformed */
			goto retry;
		}

		sleep(5);
	}

	char errbuf[64];
	apr_strerror(rv, errbuf, 64);
	LOG("(net-cl) -- send failed during discover, %s\n", errbuf);

	return NULL;
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
void arcan_net_client_session(const char* shmkey, 
	char* hoststr, enum client_modes mode)
{
	struct arcan_shmif_cont shmcont = 
		arcan_shmif_acquire(shmkey, SHMIF_INPUT, true, false);

	if (!shmcont.addr){
		LOG("(net-cl) couldn't setup shared memory connection\n");
		return;
	}

	arcan_shmif_setevqs(shmcont.addr, shmcont.esem, 
		&(clctx.inevq), &(clctx.outevq), false);

	apr_initialize();
	apr_pool_create(&clctx.mempool, NULL);

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

/* "normal" connection finally */
	apr_sockaddr_t* sa;
	apr_socket_t* sock;

/* obtain connection using a blocking socket */
	apr_sockaddr_info_get(&sa, hoststr, 
		APR_INET, DEFAULT_CONNECTION_PORT, 0, clctx.mempool);
	apr_socket_create(&sock, sa->family, 
		SOCK_STREAM, APR_PROTO_TCP, clctx.mempool);
	apr_socket_opt_set(sock, APR_SO_NONBLOCK, 0);
	apr_socket_timeout_set(sock, DEFAULT_CLIENT_TIMEOUT);
	apr_status_t rc = apr_socket_connect(sock, sa);

	if (rc != APR_SUCCESS){
		arcan_event ev = { 
						.category = EVENT_NET,
					 	.kind = EVENT_NET_NORESPONSE 
		};
		snprintf(ev.data.network.host.addr, 40, "%s", hoststr);
		arcan_event_enqueue(&clctx.outevq, &ev);
		return;
	}

/* connection completed */
	arcan_event ev = { 
		.category = EVENT_NET,
		.kind = EVENT_NET_CONNECTED
 	};

	snprintf(ev.data.network.host.addr, 40, "%s", hoststr);
	arcan_event_enqueue(&clctx.outevq, &ev);

/* 
 * setup a pollset for incoming / outgoing and for event notification,
 * we'll use a signaling socket to be able to have the shared memory
 * event-queue poll and monitored in the operation as we're waiting
 * on incoming / outgoing 
 */
#ifdef _WIN32
#else
	if (getenv("ARCAN_SOCKIN_FD")){
		int sockin_fd;
		sockin_fd = strtol( getenv("ARCAN_SOCKIN_FD"), NULL, 10 );
	
		if (apr_os_sock_put(
			&clctx.evsock, &sockin_fd, clctx.mempool) != APR_SUCCESS){
			LOG("(net) -- Couldn't convert FD socket to APR, giving up.\n");
			return;
		}
	}
	else {
		LOG("(net) -- No event socket found, giving up.\n");
		return;
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
		return;
	}

#ifndef _WIN32
	apr_pollset_add(clctx.pollset, &epfd);
#endif
	apr_pollset_add(clctx.pollset, &clctx.conn.poll_state);

/* setup client connection context, this rather awkward structure
 * is to be able to re-use a lot of the server-side code */
	net_setup_cell(&clctx.conn, &clctx.outevq, clctx.pollset);
	clctx.conn.inout = sock;
	clctx.conn.decode = client_decode;
	clctx.conn.pack = net_pack_basic;
	clctx.conn.buffer = net_buffer_basic;
	clctx.conn.validator = net_validator_tlv;
	clctx.conn.dispatch = net_dispatch_tlv;
	clctx.conn.flushout = net_flushout_default;
	clctx.conn.queueout = net_queueout_default;
	clctx.conn.connstate = CONN_CONNECTED;

/* main client loop */
	while (true){
		if (clctx.blocked){
			if (!client_inevq_process(sock))
				break;
			continue;
		}

		if (!queueout_data(&clctx.conn))
			break;

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
					.kind = EVENT_NET_DISCONNECTED
				};

				if (ret_pfd[i].rtnevents & (APR_POLLHUP | APR_POLLERR | APR_POLLNVAL)){
					LOG("(net-cl) -- poll on socket failed, shutting down.\n");
				}

				if (ret_pfd[i].rtnevents & APR_POLLOUT)
					clctx.conn.flushout(&clctx.conn);

				if (clctx.conn.buffer(&clctx.conn))
					continue;
					
				arcan_event_enqueue(&clctx.outevq, &ev);
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
	return;
}


