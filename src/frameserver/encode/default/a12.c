/*
 * This is an interesting hybrid / use case in its own right. Expose the encode
 * session as a 'remote desktop' kind of scenario where the client is allowed to
 * provide input, but at the same time is receiving A/V/E data.
 */

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <pthread.h>
#include "frameserver.h"

#include "a12.h"

#include <errno.h>
#include <stdatomic.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <signal.h>
#include <netdb.h>
#include <poll.h>
#include <inttypes.h>

#include "anet_helper.h"

struct dispatch_data {
	struct arcan_shmif_cont* C;
	struct anet_options net_cfg;
	struct a12_vframe_opts video_cfg;
	struct a12_dynreq req;
	uint8_t chind;
	bool outbound;
	int socket;
};

struct {
	bool soft_auth;
	struct arcan_shmif_cont* C;
	pthread_mutex_t sync;
	int signal_pipe;

/* capped to 256 tunnels due to channel cap so just keep it in one static array
 * of pthread_ts, sweeping it is cheap versus the triggered action (encoding a
 * frame). */
	volatile _Atomic uint64_t framecount;
	volatile _Atomic uint8_t pending;
	struct {
		pthread_t pth;
		bool used;
	} tunnels[256];
	size_t n_tunnels;
} global =
{
	.sync = PTHREAD_MUTEX_INITIALIZER
};

static void flush_av(struct a12_state* S, struct dispatch_data* data);

static void empty_event_handler(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
/* a12_unpack for directory connection doesn't need any event response */
}

static void on_client_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	if (!cont){
		return;
	}

/* The client isn't 'normal' (afsrv_net for those) as such in that many of the
 * shmif events do not make direct sense to just forward verbatim. The input
 * model match 1:1, however, so forward those. */

	if (ev->category == EVENT_IO){
		arcan_shmif_enqueue(cont, ev);
	}
}

static struct pk_response key_auth_fixed(uint8_t pk[static 32], void* tag)
{
	struct dispatch_data* data = tag;

	struct pk_response auth = {};
	if (memcmp(data->req.pubk, pk, 32) == 0){
		auth.authentic = true;
	}
	return auth;
}

static void* tunnel_runner(void* data)
{
	struct dispatch_data* td = data;
	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	uint64_t msc = atomic_load(&global.framecount);

	size_t n_fd = 2;
	struct pollfd fds[3] = {
		{.fd = td->C->epipe, .events = POLLIN  | errmask},
		{.fd = td->socket,   .events = POLLIN  | errmask},
		{.fd = td->socket,   .events = POLLOUT | errmask},
	};

	struct a12_context_options a12opts = {
		.local_role = ROLE_SOURCE,
		.pk_lookup = key_auth_fixed,
		.pk_lookup_tag = data,
		.disable_ephemeral_k = true
	};

/* request contains the Kpub we should accept and the secret provided by the
 * directory itself. */
	struct anet_options anet = {
		.retry_count = 10,
		.opts = &a12opts,
		.host = td->req.host
	};

/* multiplexing and encoding options are interesting here when we go 1:* to
 * let multiple sources sink us (if that option is enabled).
 *
 * we need to:
 *    b. feed the encoder and flush on some timeout.
 *    c. react to STEPFRAMEs on the main segment.
 *
 * there are quite a few heuristic steps for the different state machines if
 * they start to drift, particularly have different encoder 'levels' after a
 * certain number of clients and forward the encoded ones. That'd still take
 * supporting 'raw' (ZSTD I/D frames) as fallback though.
 */
	struct a12_state* ast = a12_server(&a12opts);
	uint8_t* outbuf;
	size_t outbuf_sz = 0;

	for(;;){
		if (
				((-1 == poll(fds, n_fd, -1) && (errno != EAGAIN && errno != EINTR))) ||
				(fds[0].revents & errmask) || (fds[1].revents & errmask)
		){
				break;
		}

/* is there a new frame? */
		if (atomic_load(&global.framecount) != msc){
			flush_av(ast, td);
			msc = atomic_load(&global.framecount);
			atomic_fetch_add(&global.pending, -1);
		}

		if (fds[1].revents){
			uint8_t inbuf[9000];
			ssize_t nr = recv(td->socket, inbuf, 9000, 0);
			if (nr > 0){
				a12_unpack(ast, inbuf, nr, NULL, empty_event_handler);
			}
		}

		if (!outbuf_sz)
			outbuf_sz = a12_flush(ast, &outbuf, A12_FLUSH_ALL);

/* flush output buffer and tell outer worker */
		if (n_fd == 3 && (fds[2].revents & POLLOUT) && outbuf_sz){
			ssize_t nw = write(td->socket, outbuf, outbuf_sz);
			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
				write(global.signal_pipe, "", 1);
			}

			if (!outbuf_sz)
				outbuf_sz = a12_flush(ast, &outbuf, A12_FLUSH_ALL);
		}

/* update pollset if there is something to write, this will cause the next
 * poll to bring us into the flush stage */
		n_fd = outbuf_sz > 0 ? 3 : 2;
	}

	return NULL;
}

static void on_sink_dir(struct a12_state* S, struct a12_dynreq req, void* tag)
{
	struct dispatch_data* data = tag;

/* 1 - inbound, 2 - outbound, 4 - tunnel */
	if (req.proto == 4){
		int sv[2];
		socketpair(AF_UNIX, SOCK_STREAM, 0, sv);

/* hand the one descriptor to pair[0] then give a thread pair[1], when we get a
 * frame inbound, have an atomic counter increment and let the last to finish
 * decrement */
		a12_set_tunnel_sink(S, data->chind++, sv[0]);
		struct dispatch_data* td = malloc(sizeof(struct dispatch_data));
		*td = (struct dispatch_data){
			.socket = sv[1],
			.req = req,
			.C = global.C
		};

		for (size_t i = 0; i < COUNT_OF(global.tunnels); i++){
			if (global.tunnels[i].used)
				continue;

/* threads normally poll on the tunnel unless EINTR killed, when killed they
 * check how many pending consumers there is for the current thread, dispatch
 * encode, lock then flush into the main a12 state, decrement count and signal
 * that there is data to flush onwards. */
			global.tunnels[i].used = true;
			global.n_tunnels++;
			pthread_attr_t pthattr;
			pthread_attr_init(&pthattr);
			pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
			pthread_create(&global.tunnels[i].pth, &pthattr, tunnel_runner, td);
			return;
		}
	}

}

static void flush_av(struct a12_state* S, struct dispatch_data* data)
{
/* so we have a video and/or audio buffer, forward that to the a12 state */
	a12_set_channel(S, 0);

/* video buffer? we don't have any guarantee that there is a significant change
 * (the dirty region yields no guarantees here), due to just how costly the enc.
 * stage can be, run a row- row- checksum check against the dirty region */
	struct arcan_shmif_cont* C = data->C;
	size_t y_in = C->h;
	size_t y_out = 0;

	if (data->C->addr->abufused[0]){
/* forward audio as well */
		data->C->addr->abufused[0] = 0;
	}
/*
 * S, buffer, n_samples, cfg on channels and samplerate,
 * then method to raw
	a12_channel_aframe(S, &(struct shmifsrv_abuffer)
 */
	if (!C->addr->vready)
		return;

/* this is a design flaw in the encode- stage, ideally the cached dirty in
 * cont should be updated on the STEPFRAME - as to not expose the page layout */
	struct arcan_shmif_region dregion = atomic_load(&C->addr->dirty);

/* sanity check */
	if (dregion.x1 > dregion.x2)
		dregion.x1 = 0;
	if (dregion.x2 > C->w)
		dregion.x2 = C->w;

	if (dregion.y1 > dregion.y2)
		dregion.y1 = 0;
	if (dregion.y2 > C->h)
		dregion.y2 = C->h;

	a12_channel_vframe(S, &(struct shmifsrv_vbuffer){
		.buffer = C->vidp,
		.w = C->w,
		.h = C->h,
		.pitch = C->pitch,
		.stride = C->stride,
		.region = dregion,
		.flags = {
			.subregion = true
		},
	}, data->video_cfg);
}

static void process_shmif(struct a12_state* S, struct dispatch_data* data)
{
	arcan_event ev;
	while(arcan_shmif_poll(data->C, &ev) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		switch(ev.tgt.kind){

/* this is a good testing basis for adaptive heavy preview- frame delivery
 * that gets sent in advanced, and forwarded unless the main frame arrives
 * in time. Then the SNR can be adjusted to match the quality of the link
 * for the time being. */
		case TARGET_COMMAND_STEPFRAME:{
			flush_av(S, data);
			arcan_shmif_signal(data->C, SHMIF_SIGVID | SHMIF_SIGAUD);
		}
		default:
		break;
		}
	}
}

static void dispatch_single(struct a12_state* S, int fd, void* tag)
{
	struct dispatch_data* data = tag;

	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	size_t n_fd = 2;
	struct pollfd fds[3] = {
		{.fd = data->C->epipe, .events = POLLIN | errmask},
		{.fd = fd, .events = POLLIN | errmask},
		{.fd = fd, .events = POLLOUT | errmask}
	};

	a12_set_destination(S, data->C, 0);

/* send so the other end wakes up - we don't set an ident / title though */
	struct arcan_event ev = {
		.ext.kind = ARCAN_EVENT(REGISTER),
		.category = EVENT_EXTERNAL,
		.ext.registr = {
			.kind = SEGID_MEDIA
		}
	};
	a12_channel_enqueue(S, &ev);

	uint8_t* outbuf = NULL;
	size_t outbuf_sz = 0;
	uint8_t inbuf[9000];

	for(;;){
/* break out and clean-up on pollset error */
		if (
				((-1 == poll(fds, n_fd, -1) && (errno != EAGAIN || errno != EINTR))) ||
				(fds[0].revents & errmask) || (fds[1].revents & errmask)
		){
				break;
		}

/* shmif takes priority */
		if (fds[0].revents){
			process_shmif(S, data);
		}

/* incoming data? update a12 state machine */
		if (fds[1].revents){
			ssize_t nr = recv(fd, inbuf, 9000, 0);

/* half-open client closed? or other error? give up */
			if ((-1 == nr && errno != EAGAIN &&
				errno != EWOULDBLOCK && errno != EINTR) || 0 == nr){
				break;
			}

/* populate state buffer, refill if needed */
			a12_unpack(S, inbuf, nr, NULL, on_client_event);
		}

		if (!outbuf_sz)
			outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);

/* flush output buffer */
		if (n_fd == 3 && (fds[2].revents & POLLOUT) && outbuf_sz){
			ssize_t nw = write(fd, outbuf, outbuf_sz);
			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}

			if (!outbuf_sz)
				outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);
		}

/* update pollset if there is something to write, this will cause the next
 * poll to bring us into the flush stage */
		n_fd = outbuf_sz > 0 ? 3 : 2;
	}

/* always clean-up the client socket */
	shutdown(fd, SHUT_RDWR);
	close(fd);
}

static bool decode_args(struct arg_arr* arg, struct dispatch_data* dst)
{
	dst->net_cfg.port;

	if (arg_lookup(arg, "port", 0, &dst->net_cfg.port)){
		if (!dst->net_cfg.port || strlen(dst->net_cfg.port) == 0){
			arcan_shmif_last_words(dst->C, "missing port value");
			return false;
		}
	}
	else
		dst->net_cfg.port = "6680";

	if (arg_lookup(arg, "softauth", 0, NULL)){
		global.soft_auth = true;
	}

	dst->net_cfg.opts = a12_sensitive_alloc(sizeof(struct a12_context_options));

/* outbound instead of inbound */
	dst->outbound |= arg_lookup(arg, "host", 0, &dst->net_cfg.host);
	dst->outbound |= arg_lookup(arg, "tag", 0, &dst->net_cfg.key);

/* and use the keystore but not the connection info in it */
	if (dst->net_cfg.key && dst->net_cfg.host)
		dst->net_cfg.ignore_key_host = true;

	const char* pass;
	if (arg_lookup(arg, "pass", 0, &pass)){
		if (!pass){
			arcan_shmif_last_words(dst->C, "missing pass key");
			free(dst->net_cfg.opts);
			return false;
		}
		size_t len = strlen(pass);

/* empty length is allowed */
		if (len && len > 32){
			arcan_shmif_last_words(dst->C, "password is too long");
			free(dst->net_cfg.opts);
			return false;
		}
		memcpy(dst->net_cfg.opts->secret, pass, len);
	}

	dst->video_cfg = (struct a12_vframe_opts){
		.method = VFRAME_METHOD_DZSTD,
		.bias = VFRAME_BIAS_QUALITY
	};

	const char* method;
	if (arg_lookup(arg, "vcodec", 0, &method) && method){
		if (strcasecmp(method, "h264") == 0){
			dst->video_cfg.method = VFRAME_METHOD_H264;
		}
		else if (strcasecmp(method, "raw") == 0){
			dst->video_cfg.method = VFRAME_METHOD_RAW_NOALPHA;
		}
		else if (strcasecmp(method, "raw565") == 0){
			dst->video_cfg.method = VFRAME_METHOD_RAW_RGB565;
		}
		else if (strcasecmp(method, "dpng") == 0){
/* no-op, default */
		}
		else
			LOG("unknown vcodec: %s\n", method);
	}

	const char* bias;
	if (arg_lookup(arg, "bias", 0, &bias) && bias){
		if (strcasecmp(bias, "latency") == 0){
			dst->video_cfg.bias = VFRAME_BIAS_LATENCY;
		}
		else if (strcasecmp(bias, "balanced") == 0){
			dst->video_cfg.bias = VFRAME_BIAS_BALANCED;
		}
		else if (strcasecmp(bias, "quality") == 0){
			dst->video_cfg.bias = VFRAME_BIAS_QUALITY;
		}
		else
			LOG("unknown vcodec bias: %s\n", bias);
	}

	const char* tmp = NULL;
	if (arg_lookup(arg, "trace", 0, &tmp) && tmp){
		char* out;
		long arg = strtol(tmp, &out, 10);
		if (!arg && out == tmp)
			a12_set_trace_level(arg, stderr);
		else
			a12_set_trace_level(arg, stderr);
	}

	return true;
}

static void shutdown_workers()
{
/* If the tunnel connection died there's little recourse and we could just let
 * the context die, or we can switch to a reconnect-/recover- migrate mode, but
 * that would require new tunnels anyway. If we have mixed direct sinks inbound
 * or outbound we can let those continue and try to recover the tunnel at a
 * later point. */
	LOG("EIMPL: graceful shutdown");
}

static void dispatch_multiple(
	struct arcan_shmif_cont* C, struct a12_state* S, int connfd, int signal)
{
/*
 * The data from the different tunneled sinks go through here so we must be
 * ready to maintain the state machine as a normal loop. The signal pipe has
 * multiple possible writers and we just use it to indicate that it is time
 * to check the state machine for outbound packets.
 */
	size_t n_fd = 2;
	static const short errmask = POLLERR | POLLNVAL | POLLHUP;

	struct pollfd fds[4] = {
		{.fd = C->epipe, .events = POLLIN | errmask},
		{.fd = connfd, .events = POLLIN | errmask},
		{.fd = signal, .events = POLLIN | errmask},
		{.fd = C->epipe, .events = POLLOUT | errmask}
	};

	uint8_t* outbuf = NULL;
	size_t outbuf_sz = 0;
	bool gotframe = false;
	bool waitframe = false;

	for(;;){
		if ((-1 == poll(fds, n_fd, -1) && (errno != EAGAIN && errno != EINTR))){
			break;
		}

/* flush directory control connection */
		struct arcan_event ev;
		if (fds[1].revents & POLLIN){
			uint8_t inbuf[9000];
			ssize_t nr = recv(connfd, inbuf, 9000, 0);
			if (nr > 0)
				a12_unpack(S, inbuf, nr, NULL, empty_event_handler);
		}

		if (fds[1].revents & errmask){
			LOG("directory-connection terminated");
			shutdown_workers();
			return;
		}

/* signalled that there is more data to unpack, it's just used to wakeup so
 * flush it out */
		if (fds[3].revents & POLLIN){
			uint8_t rcvbuf[256];
			read(fds[3].fd, rcvbuf, 256);
		}

/* we still have things to write, change the pollset until socket is writable */
		if (outbuf_sz && n_fd == 3){
			ssize_t nw = write(connfd, outbuf, outbuf_sz);
			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}
		}

/* check if there is more tunnel data to forward */
		if (!outbuf_sz){
			outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);

			ssize_t nw = write(connfd, outbuf, outbuf_sz);
			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}
		}

		n_fd = outbuf_sz ? 3 : 2;

/* flush out shmif connection */
		while (arcan_shmif_poll(C, &ev) > 0){
			if (ev.category == EVENT_TARGET){
				if (ev.tgt.kind == TARGET_COMMAND_STEPFRAME){
					gotframe = true;
				}
				else if (ev.tgt.kind == TARGET_COMMAND_EXIT){
					return;
				}
			}
		}

/* all workers are done, readly for new frame */
		if (waitframe && !atomic_load(&global.pending)){
			waitframe = false;
			arcan_shmif_signal(C, SHMIF_SIGVID | SHMIF_SIGAUD);
		}

/* signal all the workers that we have a new frame pending to be consumed, this
 * is where a framequeue would copy the current frame, signal shmif that we are
 * done and move on */
		if (gotframe && !waitframe && !atomic_load(&global.pending)){
			atomic_fetch_add(&global.framecount, 1);
			atomic_store(&global.pending, global.n_tunnels);
			for (size_t i = 0, count = global.n_tunnels; i < 256 && count; i++){
				if (!global.tunnels[i].used)
					continue;
				pthread_kill(global.tunnels[i].pth, SIGINT);
				count--;
			}
			waitframe = true;
		}

	}
}

static struct pk_response key_auth_local(uint8_t pk[static 32], void* tag)
{
	struct pk_response auth = {0};
	char* tmp;
	uint16_t tmpport;

/*
 * here is the option of deferring pubk- auth to arcan end by sending it as a
 * message onwards and wait for an accept or reject event before moving on.
 */
	if (a12helper_keystore_accepted(pk, "*") || global.soft_auth){
		uint8_t key_priv[32];
		auth.authentic = true;
		a12helper_keystore_hostkey("default", 0, key_priv, &tmp, &tmpport);
		a12_set_session(&auth, pk, key_priv);
	}

	return auth;
}

void a12_serv_run(struct arg_arr* arg, struct arcan_shmif_cont cont)
{
	struct dispatch_data data = {
		.C = &cont,
		.chind = 1
	};

	if (!decode_args(arg, &data)){
		return;
	}

	global.C = &cont;
	data.net_cfg.opts->pk_lookup = key_auth_local;
	data.net_cfg.keystore.type = A12HELPER_PROVIDER_BASEDIR;
	const char* err;
	data.net_cfg.keystore.directory.dirfd = a12helper_keystore_dirfd(&err);
	if (!a12helper_keystore_open(&data.net_cfg.keystore)){
		arcan_shmif_last_words(&cont, "couldn't open keystore");
		arcan_shmif_drop(&cont);
		return;
	}

/* Ideally all encode etc. operations should get a socket token from afsrv
 * net and prevent bind/etc. operations themselves. Most of the provisions
 * are there to do this as BCHUNK style transfers from net in discovery to
 * here, but the actual routing / plumbing etc. is deferred until 0.9 when
 * we focus on hardening. */
	data.net_cfg.opts->local_role = ROLE_SOURCE;

	if (data.outbound){
		struct anet_cl_connection con = anet_cl_setup(&data.net_cfg);

		if (con.auth_failed){
			LOG("encode_outbound:authentication_rejected");
			arcan_shmif_last_words(&cont, "outbound auth failed");
			return;
		}
		if (con.errmsg){
			LOG("encode_outbound:failed:reason=%s", con.errmsg);
			arcan_shmif_last_words(&cont, con.errmsg);
			return;
		}

		if (a12_remote_mode(con.state) == ROLE_DIR){
			uint8_t nk[32] = {0}; /* won't be used right now */
			const char* identity = NULL;
			arg_lookup(arg, "ident", 0, &identity);
			struct arcan_event ev = {
				.ext.kind = ARCAN_EVENT(REGISTER),
				.category = EVENT_EXTERNAL
			};

/* start by REGISTER the source -
 * also need option to pass keymaterial in ARG in order for directory to
 * spawn us directly as an arcan_headless with enc arguments.
 */

/* if there's no identity provided, use the segid GUID even though it's likely
 * to be generated on the fly rather than tracked since define_recordtarget
 * doesn't provide it - though arcan_headless might. */
			if (!identity || !strlen(identity)){
				uint64_t uid[2];
				arcan_shmif_guid(&cont, uid);
				snprintf(ev.ext.registr.title,
					64, "enc_%"PRIu64":%"PRIu64, uid[0], uid[1]);
			}
			else
				snprintf(ev.ext.registr.title, 64, "%s", identity);
			a12_channel_enqueue(con.state, &ev);

			a12_request_dynamic_resource(con.state,
				nk, arg_lookup(arg, "tunnel", 0, NULL), on_sink_dir, &data);

/* pipe-pair for tunnel threads to wake up the main dispatch so that it will
 * flush its inbound buffer onwards */
			int pair[2];
			pipe(pair);
			global.signal_pipe = pair[1];

/* we still need to process the main a12 state here in order for new tunnel
 * requests to arrive and to coordinate the shmif context for new information
 * and have a frame queue of either raw or encoded frames that each tunnel then
 * consumes and transcodes based on their state or forwards as is. */
			dispatch_multiple(&cont, con.state, con.fd, pair[0]);
		}
		else if (a12_remote_mode(con.state) == ROLE_SINK){
			dispatch_single(con.state, con.fd, &data);
		}
		else {
			arcan_shmif_last_words(&cont, "role-mismatch, expecting sink or dir");
			shutdown(con.fd, SHUT_RDWR);
			close(con.fd);
			return;
		}
	}

/*
 * For the sake of oversimplification, use a single active client mode for
 * the time being. The other option is the complex (multiple active clients)
 * and the expensive (one active client, multiple observers).
 */
	else {
		char* errdst;
		if (!anet_listen(&data.net_cfg, &errdst, dispatch_single, &data)){
			arcan_shmif_last_words(&cont, errdst);
		}
	}

	arcan_shmif_drop(&cont);
	exit(EXIT_SUCCESS);
}
