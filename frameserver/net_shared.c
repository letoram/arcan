#include "net_shared.h"
#include "frameserver.h"
#include "net.h"

#ifndef FRAME_HEADER_SIZE
#define FRAME_HEADER_SIZE 3
#endif

static const int outbuf_cap = OUTBUF_CAP;

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

static bool err_catch_decode(struct conn_state* self,
	enum net_tags tag, int len, char* buf)
{
	LOG("(net-conn) -- invalid decode state specified, please report.\n");
	abort();
}

static bool err_catch_queueout(struct conn_state* self, 
	char* buf, size_t buf_sz)
{
	LOG("(net-srv) -- invalid queueout invoked, please report.\n");
	abort();
}

apr_socket_t* net_prepare_socket(const char* host, apr_sockaddr_t* 
	althost, int sport, bool tcp, apr_pool_t* mempool)
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
		rv = apr_sockaddr_info_get(&addr, 
			host, APR_INET, sport, 0, mempool);
		if (rv != APR_SUCCESS){
			LOG("(net) -- couldn't setup host (%s):%d, giving up.\n", 
				host ? host : "(DEFAULT)", sport);
			goto sock_failure;
		}
	}

	rv = apr_socket_create(&ear_sock, addr->family, tcp ? 
		SOCK_STREAM : SOCK_DGRAM, tcp ? APR_PROTO_TCP : 
		APR_PROTO_UDP, mempool);

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

void net_setup_cell(struct conn_state* conn, 
	arcan_evctx* evq, apr_pollset_t* pollset)
{
	conn->inout     = NULL;
	conn->dispatch  = err_catcher;
	conn->validator = err_catch_valid;
	conn->flushout  = err_catch_flush;
	conn->queueout  = err_catch_queueout;
	conn->decode    = err_catch_decode;
	conn->pollset   = pollset;
	conn->outevq    = evq;
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

	if (conn->state_in.fd)
		close(conn->state_in.fd);
}

void net_newseg(struct conn_state* conn, int kind, char* key)
{	
	if (!conn){
		LOG("(net), invalid destination connection "
			"specified, shm request ignored.\n");
		goto fail;
	}

/* parent wants to send something */
	if (kind == 0){
		if (conn->state_out.state != STATE_NONE){
			LOG("(net-srv) cannot transfer while there is an outgoing "
				"transfer already in progress.");
			goto fail;
		}

		conn->state_out.ctx = arcan_shmif_acquire(
			key, SHMIF_OUTPUT, true, true );

		struct arcan_shmif_cont* shms = &conn->state_out.ctx;

		conn->state_out.ofs = 0;
		conn->state_out.lim = shms->addr->w * 
			shms->addr->h * ARCAN_SHMPAGE_VCHANNELS;
	
		arcan_shmif_calcofs(shms->addr, 
			(uint8_t**) &conn->state_out.vidp, 
			(uint8_t**) &conn->state_out.audp
		);	

		arcan_shmif_setevqs(shms->addr, shms->esem, 
			&conn->state_out.inevq, 
			&conn->state_out.outevq, false);

		return;
	}
/* server is ready to accept */
	else if (kind == 1){
	
		return;
	}
	
fail:
	LOG("(net) segment setup failed, notifying parent.\n");
}

bool net_dispatch_tlv(struct conn_state* self, char tag, 
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
		arcan_event_enqueue(self->outevq, &newev);
	break;

	case TAG_NETINPUT:
/* need to implement proper serialization of event structure first */
	break;

/*
 * For ping / pong, we discard everything above the timestamp,
 * it can be padded with noise to make side-channel analysis more difficult
 */
	case TAG_NETPING:
		if (len >= 4){
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

	default:
		return self->decode(self, tag, len, value);
	}

	return true;
}

bool net_flushout_default(struct conn_state* self)
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
		apr_pollset_remove(self->pollset, &self->poll_state);
			self->poll_state.reqevents  = APR_POLLIN | APR_POLLHUP | APR_POLLERR;
			self->poll_state.rtnevents  = 0;
			apr_pollset_add(self->pollset,&self->poll_state);
		} else {
/* partial write, slide */
			memmove(self->outbuffer, &self->outbuffer[nts], self->outbuf_ofs - nts);
			self->outbuf_ofs -= nts;
		}
	} else {
		char errbuf[64];
		apr_strerror(sv, errbuf, sizeof(errbuf));
		LOG("(net-srv) -- send failed, %s\n", errbuf);
	}

	return (sv == APR_SUCCESS) && !APR_STATUS_IS_EOF(sv);
}

bool net_queueout_default(struct conn_state* self, char* buf, size_t buf_sz)
{
	if ((self->outbuf_sz - self->outbuf_ofs) >= buf_sz){
		memcpy(&self->outbuffer[self->outbuf_ofs], buf, buf_sz);
		self->outbuf_ofs += buf_sz;

/* if we're not already in a pollout state, enable it */
		if ((self->poll_state.reqevents & APR_POLLOUT) == 0){
			apr_pollset_remove(self->pollset, &self->poll_state);
			self->poll_state.reqevents  = APR_POLLIN | APR_POLLOUT | 
				APR_POLLERR | APR_POLLHUP;
			self->poll_state.desc.s     = self->inout;
			self->poll_state.rtnevents  = 0;
			apr_pollset_add(self->pollset, &self->poll_state);
		}

		return true;
	}

	return false;
}

bool net_validator_tlv(struct conn_state* self)
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
	apr_strerror(sv, errbuf, sizeof(errbuf));
	LOG("(net-srv) -- error receiving data (%s), giving up.\n", errbuf);
	return false;
}


