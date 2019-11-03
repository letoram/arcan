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

#include "anet_helper.h"

struct dispatch_data {
	struct arcan_shmif_cont* C;
	struct anet_options net_cfg;
	struct a12_vframe_opts video_cfg;

	unsigned long* row_sums;
};

static void on_client_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	if (!cont){
		return;
	}

/* The client isn't normal as such in that many of the shmif events do
 * not make direct sense to just forward verbatim. The input model match
 * 1:1, however, so forward those. */

	if (ev->category == EVENT_IO){
		arcan_shmif_enqueue(cont, ev);
	}
}

static unsigned long djb_hash(const uint8_t* buf, size_t len)
{
	unsigned long vl = 5381;
	for (size_t i = 0; i < len; i++){
		vl = ((vl << 5) + vl + buf[i]);
	}
	return vl;
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

	bool dirty = false;
	for (size_t i = 0; i < C->h; i++){
		unsigned long row = djb_hash(&C->vidb[i * C->stride], C->stride);
		if (row != data->row_sums[i]){
			if (y_in > i)
				y_in = i;
			if (y_out < i)
				y_out = i;
			dirty = true;
		}
		data->row_sums[i] = row;
	}

	if (!dirty)
		return;

	C->dirty.y1 = y_in;
	C->dirty.y2 = y_out;
	a12_channel_vframe(S, &(struct shmifsrv_vbuffer){
		.buffer = C->vidp,
		.w = C->w,
		.h = C->h,
		.pitch = C->pitch,
		.stride = C->stride,
		.region = C->dirty
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
	struct arcan_event ev;
	struct dispatch_data* data = tag;

	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	size_t n_fd = 2;
	struct pollfd fds[3] = {
		{.fd = data->C->epipe, POLLIN | errmask},
		{.fd = fd, POLLIN | errmask},
		{.fd = fd, POLLOUT | errmask}
	};

	a12_set_destination(S, data->C, 0);

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
		}

/* update pollset if there is something to write, this will cause the next
 * poll to bring us into the flush stage */
		n_fd = outbuf_sz > 0 ? 3 : 2;
	}

/* always clean-up the client socket */
	shutdown(fd, SHUT_RDWR);
	close(fd);
}

static void decode_args(struct arg_arr* arg, struct dispatch_data* dst)
{
	if (!arg_lookup(arg, "port", 0, &dst->net_cfg.port)){
		dst->net_cfg.port = "6680";
	}

	arg_lookup(arg, "host", 0, &dst->net_cfg.host);

	dst->video_cfg = (struct a12_vframe_opts){
	.method = VFRAME_METHOD_DPNG,
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

	dst->net_cfg.opts = a12_sensitive_alloc(sizeof(struct a12_context_options));
	a12_plain_kdf(NULL, dst->net_cfg.opts);

/* authk,
 * privk(id) - use
 * pubk(accept),
 */
}

void a12_serv_run(struct arg_arr* arg, struct arcan_shmif_cont cont)
{
	struct dispatch_data data = {
		.C = &cont
	};

/*
 * grab a per-line checksum buffer for some dirty region tracking
 */
	size_t sum_sz = cont.h * sizeof(unsigned long);
	data.row_sums = malloc(sum_sz);
	memset(data.row_sums, '\0', sum_sz);

	decode_args(arg, &data);
/*
 * For the sake of oversimplification, use a single active client mode for
 * the time being. The other option is the complex (multiple active clients)
 * and the expensive (one active client, multiple observers).
 */
	char* errdst;
	if (!anet_listen(&data.net_cfg, &errdst, dispatch_single, &data)){
		arcan_shmif_last_words(&cont, errdst);
	}

	arcan_shmif_drop(&cont);
	exit(EXIT_SUCCESS);
}
