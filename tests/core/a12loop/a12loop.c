/*
 * Testing and fuzzing harness for the A12 implementation
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <arcan/a12.h>

#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>

#include <errno.h>
#include <unistd.h>
#include <poll.h>
#include <assert.h>

extern void arcan_random(uint8_t*, size_t);
#define clsrv_okstate() (a12_poll(cl) != -1 && a12_poll(srv) != -1)

static uint8_t clpriv[32];
static uint8_t srvpriv[32];

static struct pk_response key_auth_cl(uint8_t pk[static 32])
{
/* don't really care for the time being, just return a key */
	struct pk_response auth;
	auth.authentic = true;
	memcpy(auth.key, clpriv, 32);
	return auth;
}

static struct pk_response key_auth_srv(uint8_t pk[static 32])
{
	struct pk_response auth;
	auth.authentic = true;
	memcpy(auth.key, srvpriv, 32);
	return auth;
}

extern void arcan_random(uint8_t* buf, size_t buf_sz);

static void data_round_corrupt(
	struct a12_state* cl, struct a12_state* srv, bool cl_round)
{
	uint8_t* buf;
	struct a12_state* src, (* dst);

	if (cl_round){
		src = cl;
		dst = srv;
	}
	else {
		src = srv;
		dst = cl;
	}

	size_t out = a12_flush(src, &buf, 0);

	if (out){
		arcan_random(buf, 8);
		a12_unpack(dst, buf, out, NULL, NULL);
	}
}

static size_t data_round(
	struct a12_state* cl, struct a12_state* srv, bool cl_round)
{
	uint8_t* buf;
	struct a12_state* src, (* dst);
	if (!clsrv_okstate())
		return 0;

	if (cl_round){
		src = cl;
		dst = srv;
	}
	else {
		src = srv;
		dst = cl;
	}

	size_t out = a12_flush(src, &buf, 0);

	if (out)
		a12_unpack(dst, buf, out, NULL, NULL);

	return out;
}

#define FLUSH(X, Y) do {\
	for(;data_round((X), (Y), false) || data_round((X), (Y), true);){}\
} while(0)

static bool run_auth_test(struct a12_state* cl, struct a12_state* srv)
{
	int s1, s2;
	bool cl_round = true;

/* loop while there is still data to be pumped and authentication is still going */
	do {
		data_round(cl, srv, cl_round);
		s1 = a12_poll(cl);
		s2 = a12_poll(srv);
		if (s1 == -1 || s2 == -1)
			break;

		cl_round = !cl_round;
	} while (s1 > 0 || s2 > 0 || !a12_auth_state(cl) || !a12_auth_state(srv));

	a12int_trace(A12_TRACE_SYSTEM, "auth-over:client=%d:server=%d", s1, s2);
	return a12_auth_state(cl) && a12_auth_state(srv);
}

/* send a few thousand events back and forth */
static bool event_test(struct a12_state* cl, struct a12_state* srv)
{
	size_t i = 0;
	for (; i < 1000 && clsrv_okstate(); i++){
		struct arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_RESET,
			.tgt.ioevs[0].uiv = i
		};

		a12_channel_enqueue(cl, &ev);
		a12_channel_enqueue(srv, &ev);

		FLUSH(cl, srv);
	}

	return i == 1000;
}

struct video_tag {
	shmif_pixel* buffer;
	size_t buf_n_px;
	size_t w;
	bool match;
	shmif_pixel* srv_buf;
};

static void video_signal_raw(
	size_t x1, size_t y1, size_t x2, size_t y2, void* tag)
{
	struct video_tag* data = tag;
	assert(data->srv_buf);
	data->match = true;

	for (size_t y = y1; y < y2; y++){
		for (size_t x = x1; x < x2; x++){
			size_t ofs = y * data->w + x;
			assert(ofs < data->buf_n_px);
			if (data->buffer[ofs] != data->srv_buf[ofs]){
				data->match = false;
				break;
			}
		}
	}
}

static shmif_pixel* video_signal_alloc(
	size_t w, size_t h, size_t* stride, int fl, void* tag)
{
	struct video_tag* data = tag;
	if (data->srv_buf)
		free(data->srv_buf);

	assert(w == data->w);

	*stride = sizeof(shmif_pixel) * w;
	size_t buf_sz = *stride * h;
	data->srv_buf = malloc(buf_sz);
	return data->srv_buf;
}

static bool video_test_raw(struct a12_state* cl, struct a12_state* srv)
{
/* deliberately !%2 */
	size_t w = 513;
	size_t h = 513;
	size_t buf_sz = w * h * sizeof(shmif_pixel);
	struct video_tag tag =
	{
		.buffer = malloc(buf_sz),
		.buf_n_px = w * h,
		.w = w,
		.match = true
	};

	a12_set_destination_raw(srv, 0,
		(struct a12_unpack_cfg){
		.tag = &tag,
		.signal_video = video_signal_raw,
		.request_raw_buffer = video_signal_alloc,
		}, sizeof(struct a12_unpack_cfg)
	);

	for (size_t i = 0; i < 10 && clsrv_okstate(); i++){
/* update buffer */
//		arcan_random((uint8_t*)tag.buffer, buf_sz);
		memset(tag.buffer, 0xff, buf_sz);

		if (!tag.match)
			break;

		a12_channel_vframe(cl,
		&(struct shmifsrv_vbuffer){
			.buffer = tag.buffer,
			.w = w,
			.h = h,
			.pitch = w,
			.stride = w * sizeof(shmif_pixel),
		},
		(struct a12_vframe_opts){
		});

		FLUSH(cl, srv);
	}

	free(tag.buffer);
	free(tag.srv_buf);
	a12_set_destination_raw(srv, 0,
		(struct a12_unpack_cfg){}, sizeof(struct a12_unpack_cfg));

	return tag.match && clsrv_okstate();
}

struct audio_tag {
	shmif_asample* buffer;
	size_t buf_sz;
	size_t n_ch;
	size_t srate;
	bool match;
};

static void audio_signal_raw(size_t bytes, void* tag)
{
//	struct audio_tag* buf = tag;

/* use first n- bytes from the buffer - check that they follow our 'signal' */
}

static shmif_asample* audio_buffer_alloc(
	size_t n_ch, size_t samplerate, size_t bytes, void* tag)
{
	struct audio_tag* at = tag;
	if (!at->buffer)
		at->buffer = NULL;

	at->n_ch = n_ch;
	at->srate = samplerate;
	at->buffer = malloc(bytes);

	return at->buffer;
}

static bool audio_test_raw(struct a12_state* cl, struct a12_state* srv)
{
/* deliberately !%2 */
	struct audio_tag tag =
	{
		.buffer = NULL,
		.match = true
	};

	a12_set_destination_raw(srv, 0,
		(struct a12_unpack_cfg){
		.tag = &tag,
		.signal_audio = audio_signal_raw,
		.request_audio_buffer = audio_buffer_alloc,
		}, sizeof(struct a12_unpack_cfg)
	);

	for (size_t i = 0; i < 10 &&
		a12_poll(srv) != -1 && a12_poll(cl) != -1 && tag.match; i++){

	/* send abuffer */
		FLUSH(cl, srv);
	}

	free(tag.buffer);
	a12_set_destination_raw(srv, 0,
		(struct a12_unpack_cfg){}, sizeof(struct a12_unpack_cfg));

	return tag.match && (a12_poll(cl) != -1 && a12_poll(srv) != -1);
}

struct test_pass {
	bool (*pass)(struct a12_state*, struct a12_state*);
	const char* name;
	bool ignore;
};

/* normally possible with multiples, but not for this test */
struct blob_md {
	int got_job;
};

static struct a12_bhandler_res bhandler(
	struct a12_state* S, struct a12_bhandler_meta md, void* tag)
{
	struct blob_md* bmd = tag;

	struct a12_bhandler_res res = {
		.flag = A12_BHANDLER_DONTWANT,
		.fd = -1
	};

/* status update? */
	if (bmd->got_job){
		return res;
	}

	if (!md.known_size)
		return res;

	if (md.streaming)
		return res;

	a12int_trace(A12_TRACE_BTRANSFER, "new_transfer");
	return res;
}

static bool test_bxfer(struct a12_state* cl, struct a12_state* srv)
{
	struct blob_md blob;

/* increment each time the test is run up to a cap */
	static size_t base_sz = 1024;
	if (base_sz < 10 * 1024)
		base_sz *= 2;

	FILE* fpek = fopen("bxfer.temp", "w+");
	if (!fpek)
		return false;

	unlink("bxfer.temp");

	char* buf = malloc(base_sz);
	memset(buf, 'a', base_sz);
	fwrite(buf, base_sz, 1, fpek);

	int myfd = fileno(fpek);

	a12_set_bhandler(srv, bhandler, &blob);

/* send same file twice, the second time we should be able to just reject */
	for (size_t i = 0; i < 2 && a12_poll(cl) != -1 && a12_poll(srv) != -1; i++){
		a12_enqueue_bstream(cl, myfd, A12_BTYPE_BLOB, false, base_sz);
		FLUSH(cl, srv);
	}

	fclose(fpek);
	a12_set_bhandler(srv, NULL, NULL);
	return true;
}

static bool buffer_sink(uint8_t* buf, size_t nb, void* tag)
{
	struct a12_state* dst = tag;
	a12_unpack(dst, buf, nb, NULL, NULL);
	return a12_poll(dst) != -1;
}

int main(int argc, char** argv)
{
	arcan_random(clpriv, 32);
	arcan_random(srvpriv, 32);

	struct a12_context_options cl_opts = {
		.pk_lookup = key_auth_cl,
		.disable_cipher = true,
		.disable_ephemeral_k = false
	};


	struct a12_context_options srv_opts = cl_opts;
	memcpy(cl_opts.priv_key, clpriv, 32);
	srv_opts.pk_lookup = key_auth_srv;

/* parse arguments from cmdline, ... */
	a12_set_trace_level(
		A12_TRACE_CRYPTO |
		A12_TRACE_SYSTEM |
		A12_TRACE_VIDEO  |
		A12_TRACE_BTRANSFER |
		A12_TRACE_AUDIO |
		0,
		stderr
	);

/*
 * sink- based data transfer (FOR ONE CONTEXT) is easier to debug
 * as the packet that caused an issue will have its synthesis path
 * fresh in the backtrace. NEVER do this in process on BOTH.
 */
	struct a12_state* srv = a12_server(&srv_opts);

/*	cl_opts.sink = buffer_sink;
	  cl_opts.sink_tag = srv;
 */
	struct a12_state* cl = a12_client(&cl_opts);

/* authentication is always needed */
	printf("authenticating: ");
	if (!run_auth_test(cl, srv)){
		printf(" fail\n");
		return EXIT_FAILURE;
	}
	printf(" ok\n");

	struct test_pass passes[] = {
	{
		.pass = event_test,
		.name = "Event",
	},
	{
		.pass = video_test_raw,
		.name = "Video(Raw)",
	},
	{
		.pass = audio_test_raw,
		.name = "Audio(Raw)",
		.ignore = true
	},
	{
		.pass = test_bxfer,
		.name = "Binary",
		.ignore = true
	}
/* checklist:
 * - working audio
 * - working bchunk
 *   - bchunk-handler stream-cancel (caching)
 *
 * - working 1-round x25519
 * - working 2-round x25519
 *
 * - video-encode cancel-fallback
 * - video-encode passthrough
 *
 * 9. working x264 passthrough and fallback
 * 10. working subchannel alloc
 * 11. working output segment
 * 12. working rekey
 */
	};

	size_t pc = 0;
	for(;;){
		for (size_t i = 0; i < sizeof(passes) / sizeof(passes[0]); i++){
			struct test_pass* ct = &passes[i];
			if (ct->ignore)
				continue;
			bool pass = ct->pass(cl, srv);
			printf("[%zu] %s - %s\n", pc, ct->name, pass ? "ok" : "fail");
			if (!pass)
				return EXIT_FAILURE;
		}
		pc++;
	}
	return EXIT_SUCCESS;
}
