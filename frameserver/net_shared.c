#include "net_shared.h"
#include "frameserver.h"
#include "net.h"

#ifndef FRAME_HEADER_SIZE
#define FRAME_HEADER_SIZE 3
#endif

static bool err_catch_dispatch(struct conn_state* self, enum net_tags tag,
	size_t len, char* value)
{
	LOG("(net-srv) -- invalid dispatcher invoked, please report.\n");
	abort();
}

static bool err_catch_valid(struct conn_state* self,
	size_t len, char* buf, size_t* cons)
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
	enum net_tags tag, size_t len, char* buf)
{
	LOG("(net-conn) -- invalid decode state specified, please report.\n");
	abort();
}

static bool err_catch_buffer(struct conn_state* self)
{
	LOG("(net-conn) -- invalid buffer state specified, please report.\n");
	abort();
}

static bool err_catch_pack(struct conn_state* self,
	enum net_tags tag, size_t len, char* buf)
{
	LOG("(net-conn) -- invalid pack state specified, please report.\n");
	abort();
}

static bool err_catch_queueout(struct conn_state* self,
	size_t len, char* buf)
{
	LOG("(net-srv) -- invalid queueout invoked, please report.\n");
	abort();
}

apr_socket_t* net_prepare_socket(const char* host, apr_sockaddr_t*
	althost, int* sport, bool tcp, apr_pool_t* mempool)
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
			host, APR_INET, *sport, 0, mempool);
		if (rv != APR_SUCCESS){
			LOG("(net) -- couldn't setup host (%s):%d, giving up.\n",
				host ? host : "(DEFAULT)", *sport);
			goto sock_failure;
		}
	}

	rv = apr_socket_create(&ear_sock, addr->family, tcp ?
		SOCK_STREAM : SOCK_DGRAM, tcp ? APR_PROTO_TCP :
		APR_PROTO_UDP, mempool);

	if (rv != APR_SUCCESS){
		LOG("(net) -- couldn't create listening socket, on (%s):%d, "
			"giving up.\n", host ? host: "(DEFAULT)", *sport);
		goto sock_failure;
	}

	rv = apr_socket_bind(ear_sock, addr);
	if (rv != APR_SUCCESS){
		LOG("(net) -- couldn't bind to socket, giving up.\n");
		goto sock_failure;
	}

/* apparently only fixed in APR1.5 and beyond,
 * while the one in ubuntu and friends is 1.4 */
	if (!tcp){
#ifndef APR_SO_BROADCAST
		int sockdesc, one = 1;
		apr_os_sock_get(&sockdesc, ear_sock);
		setsockopt(sockdesc, SOL_SOCKET, SO_BROADCAST, (void *)&one, sizeof(int));
#ifdef SO_REUSEPORT
		setsockopt(sockdesc, SOL_SOCKET, SO_REUSEPORT, (void *)&one, sizeof(int));
#endif

#else
#ifndef APR_SO_REUSEPORT
#define APR_SO_REUSEPORT 15
#endif
		apr_socket_opt_set(ear_sock, APR_SO_BROADCAST, 1);
		apr_socket_opt_set(ear_sock, APR_SO_REUSEPORT, 1);
		apr_socket_opt_set(ear_sock, APR_SO_REUSEADDR, 1);
#endif
	}

	if (!tcp || apr_socket_listen(ear_sock, SOMAXCONN) == APR_SUCCESS){
		apr_sockaddr_t* addr = NULL;

		apr_socket_addr_get(&addr, APR_LOCAL, ear_sock);
		if (addr)
			*sport = addr->port;

		return ear_sock;
	}

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
	conn->dispatch  = err_catch_dispatch;
	conn->validator = err_catch_valid;
	conn->flushout  = err_catch_flush;
	conn->queueout  = err_catch_queueout;
	conn->decode    = err_catch_decode;
	conn->buffer    = err_catch_buffer;
	conn->pack      = err_catch_pack;
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

	struct conn_segcont* cont = kind == SEGMENT_TRANSFER ?
		&conn->state_out : &conn->state_in;

	if (cont->state != STATE_NONE){
			LOG("(net) cannot set new segment while there is an outgoing "
				"transfer already in progress.");
			goto fail;
	}

	cont->ctx = arcan_shmif_acquire(key, kind == SEGMENT_TRANSFER ?
		SEGID_ENCODER : SEGID_MEDIA, SHMIF_DISABLE_GUARD);

	struct arcan_shmif_cont* shms = &cont->ctx;

	cont->ofs = 0;
	cont->lim = shms->addr->w * shms->addr->h * ARCAN_SHMPAGE_VCHANNELS;

	arcan_shmif_calcofs(shms->addr,
		(uint8_t**) &cont->vidp, (uint8_t**) &cont->audp);

	arcan_shmif_setevqs(shms->addr, shms->esem,
		&cont->inevq, &cont->outevq, false);
	return;

fail:
	LOG("(net) segment setup failed, notifying parent.\n");
}

#include <assert.h>
bool net_buffer_basic(struct conn_state* self)
{
	size_t consumed = 0;
	apr_size_t nr = self->buf_sz - self->buf_ofs;
	assert(self->buf_ofs >= 0);

/* consume full buffer, shouldn't occur in normal operations
 * but if we populate the buffer in beforehand to test other stages
 * it might */
	if (nr == 0 &&
		!self->validator(self, self->buf_sz, self->inbuffer, &consumed))
		return false;

	if (consumed)
		goto slide;

	apr_status_t sv = apr_socket_recv(self->inout,
		&self->inbuffer[self->buf_ofs], &nr);

	if (APR_STATUS_IS_EOF(sv)){
		LOG("(net) EOF detected, giving up.\n");
		return false;
	}

	if (sv != APR_SUCCESS){
		LOG("(net) Error reading from socket\n");
		return false;
	}

	self->buf_ofs += nr;
	if (self->buf_ofs > FRAME_HEADER_SIZE){
		if (self->validator(self, self->buf_sz, self->inbuffer, &consumed))
			goto slide;
		else
			return false;
	}
	else
		return true;

slide:
/* buffer more */
/* slide or reset */
	if (consumed == self->buf_sz){
		self->buf_ofs = 0;
		printf("reset\n");
	}
	else {
		memmove(self->inbuffer, &self->inbuffer[consumed], self->buf_sz - consumed);
		self->buf_ofs -= consumed;
	}
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

bool net_hl_decode(struct conn_state* self,
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
				self->state_in.lim = desw * desh * ARCAN_SHMPAGE_VCHANNELS;
				self->state_in.state = STATE_IMG;
			}
			else {
				arcan_event outev = {
					.kind = EVENT_EXTERNAL_SEGREQ,
					.category = EVENT_EXTERNAL,
					.data.external.noticereq.width = desw,
					.data.external.noticereq.height = desh
				};

				arcan_event_enqueue(self->outevq, &outev);
				self->blocked = true;
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

char* net_unpack_discover(char* inb, bool req, char** pk,
	char** name, char** cookie, char** host, int* port)
{
	uint32_t mv;
	memcpy(&mv, inb, sizeof(uint32_t));
	mv = ntohl(mv);

	if (!version_magic(req))
		return NULL;

/* constant should be equal to number of fields in packet */
	char* res = malloc(NET_HEADER_SIZE + 5);
	memset(res, '\0', NET_HEADER_SIZE + 5);

/* set offsets into chunk buffer, implicitly adding '\0' to each str */
	*cookie = &res[NET_IDENT_SIZE + 1];
	*name = &res[NET_IDENT_SIZE + NET_COOKIE_SIZE + 2];
	*pk = &res[NET_IDENT_SIZE + NET_COOKIE_SIZE + NET_NAME_SIZE + 3];
	*host = &res[NET_IDENT_SIZE + NET_COOKIE_SIZE +
		NET_NAME_SIZE + NET_KEY_SIZE + 4];

/* unpack into chunk buffer */
	memcpy(*cookie, &inb[NET_IDENT_SIZE], NET_COOKIE_SIZE);
	memcpy(*name, &inb[NET_IDENT_SIZE + NET_COOKIE_SIZE], NET_NAME_SIZE);
	memcpy(*pk, &inb[NET_IDENT_SIZE + NET_COOKIE_SIZE +
		NET_NAME_SIZE], NET_KEY_SIZE);
	memcpy(*host, &inb[NET_IDENT_SIZE +
		NET_COOKIE_SIZE + NET_NAME_SIZE + NET_KEY_SIZE], NET_ADDR_SIZE);

/* parse host and extract port */
	char* ofp = *host + NET_ADDR_SIZE;
	*port = 0;

	while (ofp > *host){
		if (*ofp == ':'){
			*ofp = '\0';
			*port = strtol(ofp+1, NULL, 10);
			break;
		}

		ofp--;
	}

	printf("discover(inc): key[%s], port[%d], cookie[%d, %d, %d, %d], host[%s]\n", *pk, *port, (*cookie)[0], (*cookie)[1], (*cookie)[2], (*cookie)[3], *host);

	return res;
}

char* net_pack_discover(bool req,
	char* key, char* name, char* cookie, char* host, int port, size_t* d_sz)
{
	if (!key || !name || !cookie || !host || strlen(host) > NET_ADDR_SIZE - 5)
		return NULL;

	char* res = malloc(NET_HEADER_SIZE);

	uint32_t mv = htonl( version_magic(req) );
	memset(res, '\0', NET_HEADER_SIZE);

/* calculate offsets */
	char* ofs_cookie = &res[NET_IDENT_SIZE];
	char* ofs_name = &res[NET_IDENT_SIZE + NET_COOKIE_SIZE];
	char* ofs_key = &res[NET_IDENT_SIZE + NET_COOKIE_SIZE + NET_NAME_SIZE];
	char* ofs_host = &res[NET_IDENT_SIZE + NET_COOKIE_SIZE +
		NET_NAME_SIZE + NET_KEY_SIZE];

/* set fields */
	memcpy(res, &mv, sizeof(uint32_t));
	memcpy(ofs_cookie, cookie, NET_COOKIE_SIZE);
	strncpy(ofs_name, name, NET_NAME_SIZE);
	memcpy(ofs_key, key, NET_KEY_SIZE);
 	snprintf(ofs_host, NET_ADDR_SIZE, "%s:%d", host, port);

	printf("discover(out): key[%s], port[%d], cookie[%d, %d, %d, %d], host[%s]\n",
		ofs_key, port, ofs_cookie[0], ofs_cookie[1], ofs_cookie[2], ofs_cookie[3], ofs_host);

	*d_sz = NET_HEADER_SIZE;
	return res;
}

bool net_pack_basic(struct conn_state* state,
	enum net_tags tag, size_t sz, char* buf)
{
	size_t left = state->outbuf_sz - state->outbuf_ofs;

	if (sz + FRAME_HEADER_SIZE > state->outbuf_sz){
		LOG("(net) packed buffer size would exceed build-time limit.\n");
		return false;
	}

	if (left < sz + FRAME_HEADER_SIZE){
		if (!state->flushout(state)){
			LOG("(net) buffer management failure in pack-out/flush.\n");
			return false;
		}
	}

	state->outbuffer[state->outbuf_ofs + 0] = tag;
	state->outbuffer[state->outbuf_ofs + 1] = (uint8_t) sz;
	state->outbuffer[state->outbuf_ofs + 2] = (uint8_t) (sz >> 8);

	memcpy(state->outbuffer + state->outbuf_ofs + FRAME_HEADER_SIZE, buf, sz);
	state->outbuf_ofs += FRAME_HEADER_SIZE + sz;

	return state->queueout(state, state->outbuf_ofs, state->outbuffer);
}

bool net_dispatch_tlv(struct conn_state* self, enum net_tags tag,
	size_t len, char* value)
{
	arcan_event newev = {.category = EVENT_NET};
	LOG("(net), TLV frame received (%d:%zu)\n", tag, len);

	switch(tag){
	case TAG_NETMSG:
		newev.kind = EVENT_NET_CUSTOMMSG;
		snprintf(newev.data.network.message,
			sizeof(newev.data.network.message) /
			sizeof(newev.data.network.message[0]), "%s", value);
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

/*
 * By default, this hook doesn't do anything else.
 * If we have intermediate write buffers, additional packaging
 * reordering strategies, other output services etc.
 * this is the place to introduce them.
 */
bool net_queueout_default(struct conn_state* self, size_t buf_sz, char* buf)
{
	return self->flushout(self);
}

/*
 * can assume, we have at least FRAME_HEADER_SIZE bytes in buf
 * extract tag (first byte), extract length (two bytes, LE) and forward
 */
bool net_validator_tlv(struct conn_state* self,
	size_t len, char* buf, size_t* consumed)
{
	size_t block = (uint8_t)self->inbuffer[1] |
		((uint8_t)self->inbuffer[2] << 8);

	if (self->inbuffer[0] >= TAG_LAST_VALUE)
		return false;

/* request a larger buffer */
	if (block + FRAME_HEADER_SIZE > len)
		return true;

	*consumed = block + FRAME_HEADER_SIZE;

	return self->dispatch(self, self->inbuffer[0],
		block, self->inbuffer + FRAME_HEADER_SIZE);
}

