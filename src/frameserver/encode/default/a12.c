/*
 * This is an interesting hybrid / use case in its own right. Expose the encode
 * session as a 'remote desktop' kind of scenario where the client is allowed to
 * provide input, but at the same time is receiving A/V/E data.
 */

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include "a12.h"

#include <errno.h>
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
	bool outbound;
};

struct {
	bool soft_auth;
} global;

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
	dst->net_cfg.port = "6680";

	if (arg_lookup(arg, "port", 0, &dst->net_cfg.port)){
		if (!dst->net_cfg.port || strlen(dst->net_cfg.port) == 0){
			arcan_shmif_last_words(dst->C, "missing port value");
			return false;
		}
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
	if (arg_lookup(arg, "vcodec_bias", 0, &bias) && bias){
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
		long arg = strtol(tmp, NULL, 10);
		a12_set_trace_level(arg, stderr);
	}

	return true;
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
		.C = &cont
	};

	if (!decode_args(arg, &data)){
		return;
	}

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
			arcan_shmif_last_words(&cont, "eimpl: encode-sink to directory");
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
