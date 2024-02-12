/*
 A12, Arcan Line Protocol implementation

 Copyright (c) Bjorn Stahl
 All rights reserved.

 Redistribution and use in source and binary forms,
 with or without modification, are permitted provided that the
 following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 THE POSSIBILITY OF SUCH DAMAGE.
*/

#ifndef HAVE_A12
#define HAVE_A12

struct a12_state;

/*
 * the encryption related options need to be the same for both server-
 * and client- side or the communication will fail regardless of key validity.
 *
 * return the private key to use with the public key received (server only)
 * OR (migration to better process- separation friendly interface), got_session
 * set and key_pub + derived session will be provided rather than the key_priv.
 */
struct pk_response {
	bool authentic;

	uint8_t key_pub[32];
	uint8_t key_session[32];

/* If state store is provided / permitted for the key, return a lookup function
 * for creating or reading named resources from it */
	int (*state_access)(
		const uint8_t pub[static 32], const char* name, size_t sz, const char* mode);
};

/* response structure for a directory-open request.
 * proto 1,2 = ipvN address
 * proto 3 = tunnel */
struct a12_dynreq {
	char host[46];
	char pubk[32];
	uint16_t port;
	char authk[12];
	int proto;
};

struct appl_meta;
struct appl_meta {

/* These are used for local caching of contents, an update on the directory
 * bound to the context or freeing the a12 state machine will free them and
 * force-reload / re-join anyone within them. */
	FILE* handle;
	char* buf;
	uint64_t buf_sz;
	bool server_appl;
	void* server_tag;

	struct appl_meta* next;

	uint16_t identifier;
	uint16_t categories;
	uint16_t permissions;
	uint8_t hash[4];

	struct {
		char name[18];
		char short_descr[69];
	} appl;

	uint64_t update_ts;
};

struct a12_context_options {
/* Provide to enable asymetric key authentication, set valid in the return to
 * allow the key, otherwise the session may be continued for a random number of
 * time or bytes before being terminated. If want_session is requested, the
 * lookup function, if it is able to (legacy) should set got_session in the
 * reply and calculate the x25519 shared secret itself. */
	struct pk_response (*pk_lookup)(uint8_t pub[static 32], void*);
	void* pk_lookup_tag;

/* Client only, provide the private key to use with the connection. All [0]
 * key will disable attempts at asymetric operation. */
	uint8_t priv_key[32];

/* default is to add a round-trip and use an ephemeral public key to transfer
 * the real one, forces active MiM in order for an attacker to track Pk
 * (re-)use. */
	bool disable_ephemeral_k;

/* if set, the shared secret will be used to authenticate public keymaterial,
 * message and cipher state for the first packets before DH exchange has been
 * completed */
	char secret[32];

/* can be set to ROLE_PROBE, ROLE_SOURCE, ROLE_SINK or ROLE_DIR */
	int local_role;

/* send a ratchet rekey after roughly these many bytes have been observed on
 * the same shared secret (in and out). */
	size_t rekey_bytes;

/* if set, the a12_flush() will not return a buffer to write out, but rather
 * call into the sink as soon as there is data to send. This helps debugging
 * and simple applications, but limits data interleaving options.
 *
 * Return if the buffer could be flushed or not, failure to flush the buffer
 * marks the state machine as broken. */
	bool (*sink)(uint8_t* buf, size_t buf_sz, void* tag);
	void* sink_tag;
};

/*
 * Use in place of malloc/free on struct a12_context_options and other
 * structs that may act as temporary store for keymaterial.
 *
 * Will attempt to:
 * 1. allocate in memory marked as excluded from crash dumps
 * 2. overwrite on free
 *
 * This is not sufficient as the data might taint into registers and so on,
 * but there still are not any reliable mechanisms for achieving this.
 */
void* a12_sensitive_alloc(size_t nb);
void a12_sensitive_free(void*, size_t nb);

/*
 * build context and prepare packets for the connection initiator ('client')
 * the provided options structure will be modified by calls into a12_
 */
struct a12_state* a12_client(struct a12_context_options*);

/*
 * build context and prepare packets for the listening end ('server')
 * the provided options structure will be modified by calls into a12_
 */
struct a12_state* a12_server(struct a12_context_options*);

/*
 * Free the state block
 * This will return false if there are still mapped/active channels
 */
bool
a12_free(struct a12_state*);

/*
 * Used by the canonical key lookup function that provides the pk_response.
 * Provide the remote public key in pubk, and the local private key in privk.
 * Calculate the session key and local public key and set in [dst].
 */
void a12_set_session(
	struct pk_response* dst, uint8_t pubk[static 32], uint8_t privk[static 32]);

/*
 * Take an incoming byte buffer and append to the current state of
 * the channel. Any received events will be pushed via the callback.
 *
 * If _set_destination_raw has been used, [cont] will be NULL.
 */
void a12_unpack(
	struct a12_state*, const uint8_t*, size_t, void* tag, void (*on_event)
		(struct arcan_shmif_cont* cont, int chid, struct arcan_event*, void*));

/*
 * Set the specified context as the recipient of audio/video buffers
 * for a specific channel id.
 */
void a12_set_destination(
	struct a12_state*, struct arcan_shmif_cont* wnd, uint8_t chid);

/*
 * Similar to [a12_set_destination] but using a callback configuration
 * to request destination buffers for audio,
 * and to signal dirty updates.
 */
struct a12_unpack_cfg {
	void* tag;

/* [Optional] if provided, compressed video, image and text formats
 * may be forwarded without decompression or rasterization */
	void* (*request_compressed_vbuffer)(
		int fourcc[static 4], size_t nb, void* tag);

/* Will be used on resize- calls, the caller assumes ownership of the
 * returned buffer and will deallocate with [free] when ready. Set stride
 * in number of BYTES per row (>= w * sizeof(shmif_pixel)).
 * [flags] matches context render hint flags from shmif header
 */
	shmif_pixel* (*request_raw_buffer)(
		size_t w, size_t h, size_t* stride, int flags, void* tag);

/* The number of BYTES requests sets an upper limit of the number of
 * bytes that may be provided through calls into [signal_audio],
 * the bytes are guaranteed complete samples:
 *
 * [ n_ch * n_samples * sizeof(shmif_asample) == n_bytes ]
 */
	shmif_asample* (*request_audio_buffer)(
		size_t n_ch, size_t samplerate, size_t size_bytes, void* tag);

/* Mark a region of the previously requested buffer as updated, this may only
 * come as an effect of _unpack call, contents of the buffer will not be
 * modified again until this function returns. */
	void (*signal_video)(
		size_t x1, size_t y1, size_t x2, size_t y2, void* tag);

/* n BYTES have been written into the buffer allocated through
 * request_audio_buffer */
	void (*signal_audio)(size_t bytes, void* tag);

/* only used with local_role == MODE_DIRECTORY wherein someone requests
 * to open a resource through us. */
	bool (*directory_open)(struct a12_state*,
		uint8_t ident_req[static 32],
		uint8_t mode,
		struct a12_dynreq* out,
		void* tag);


	void (*on_discover)(struct a12_state*,
		int, const char*, bool, uint8_t[static 32], void*);
	void* on_discover_tag;
};

void a12_set_destination_raw(struct a12_state*,
	uint8_t ch, struct a12_unpack_cfg cfg, size_t unpack_cfg_sz);

/*
 * Set the active channel used for tagging outgoing packages
 */
void a12_set_channel(struct a12_state* S, uint8_t chid);

/*
 * Returns the number of bytes that are pending for output on the channel,
 * this needs to be rate-limited by the caller in order for events and data
 * streams to be interleaved and avoid a poor user experience.
 *
 * Unless flushed >often< in response to unpack/enqueue/signal, this will grow
 * and buffer until there's no more data to be had. Internally, a12 n-buffers
 * and a12_flush act as a buffer step. The typical use is therefore:
 *
 * 1. [build state machine, a12_client, a12_server]
 * while active:
 * 2. [if output buffer set, write to network channel]
 * 3. [enqueue events, add audio/video buffers]
 * 4. [if output buffer empty, a12_flush] => buffer size
 *
 * [allow_blob] behavior depends on value:
 *
 *    A12_FLUSH_NOBLOB : ignore all queued binary blobs
 *    A12_FLUSH_CHONLY : blocking (font/state) transfers for the current channel
 *    A12_FLUSH_ALL    : any pending data blobs
 *
 * These should be set when there are no audio/video frames from the source that
 * should be prioritised, and when the segment on the channel is in the preroll
 * state.
 */
enum a12_blob_mode {
	A12_FLUSH_NOBLOB = 0,
	A12_FLUSH_CHONLY,
	A12_FLUSH_ALL
};
size_t
a12_flush(struct a12_state*, uint8_t**, int allow_blob);

/*
 * Add a data transfer object to the active outgoing channel. The state machine
 * will duplicate the descriptor in [fd]. These will not necessarily be
 * transfered in order or immediately, but subject to internal heuristics
 * depending on current buffer pressure and bandwidth.
 *
 * For streaming descriptor types (non-seekable), size can be 0 and the stream
 * will be continued until the data source dies or the other end cancels.
 *
 * A number of subtle rules determine which order the binary streams will be
 * forwarded, so that a blob transfer can be ongoing for a while without
 * blocking interactivity due to an updated font and so on.
 *
 * Therefore, the incoming order of descrevents() may be different from the
 * outgoing one. For the current and expected set of types, this behavior is
 * safe, but something to consider if the need arises to add additional ones.
 *
 * This function will not immediately cause any data to be flushed out, but
 * rather checked whenever buffers are being swapped and appended as size
 * permits. There might also be, for instance, a ramp-up feature for fonts so
 * that the initial blocks might have started to land on the other side, and if
 * the transfer is not cancelled due to a local cache, burst out.
 */
enum a12_bstream_type {
	A12_BTYPE_STATE = 0,
	A12_BTYPE_FONT = 1,
	A12_BTYPE_FONT_SUPPL = 2,
	A12_BTYPE_BLOB = 3,

/* directory mode only */
	A12_BTYPE_CRASHDUMP = 4,
	A12_BTYPE_APPL = 5,
	A12_BTYPE_APPL_RESOURCE = 6,
	A12_BTYPE_APPL_CONTROLLER = 7
};

/* BCHUNKSTATE response/initiator */
void
a12_enqueue_bstream(struct a12_state*,
	int fd, int type, uint32_t id, bool streaming,
	size_t sz, const char extid[static 16]);

void
a12_enqueue_blob(
	struct a12_state*, const char* const, size_t, uint32_t id,
	int type, const char extid[static 16]);

/* Used on a channel mapped for use as a tunnel as a response to
 * request_dynamic_resource when there is no direct / usable network path.
 * Returns false if the channel isn't mapped for that kind of use. */
bool
	a12_write_tunnel(struct a12_state*, uint8_t chid, const uint8_t* const, size_t);

bool
	a12_set_tunnel_sink(struct a12_state*, uint8_t chid, int fd);

void
	a12_drop_tunnel(struct a12_state*, uint8_t chid);

/* get the descriptor bound to a tunnel.
 *  -1, ok = true : no tunnel bound
 *  >0, ok = true : tunnel active and bound
 *  >0, ok = false : tunnel bound but dead */
int
	a12_tunnel_descriptor(struct a12_state* S, uint8_t chid, bool* ok);

/*
 * Get a status code indicating the state of the connection.
 *
 * <0 = dead/erroneous state
 *  0 = inactive (waiting for data)
 *  1 = processing (more data needed)
 */
int
a12_poll(struct a12_state*);

enum authentic_state {
	AUTH_UNAUTHENTICATED   = 0, /* first packet, authk- use and nonce                    */
	AUTH_SERVER_HBLOCK     = 1, /* server received client HELLO with nonce               */
	AUTH_POLITE_HELLO_SENT = 2, /* client->server, HELLO (ephemeral Pubk)                */
	AUTH_EPHEMERAL_PK      = 3, /* server->client, HELLO (ephemeral Pubk, switch cipher) */
	AUTH_REAL_HELLO_SENT   = 4, /* client->server, HELLO (real Pubk, switch cipher)      */
	AUTH_FULL_PK           = 5, /* server->client, HELLO - now rekeying can be scheduled */
};

enum self_roles {
	ROLE_NONE   = 0, /* legacy compatibility */
	ROLE_SOURCE = 1,
	ROLE_SINK   = 2,
	ROLE_PROBE  = 3, /* terminate after authenticate, don't activate source */
	ROLE_DIR    = 4
};

/*
 * Get the authentication state,
 * return values are as set above.
 */
int
a12_auth_state(struct a12_state*);

/*
 * For sessions that support multiplexing operations for multiple
 * channels, switch the active encoded channel to the specified ID.
 */
void
a12_set_channel(struct a12_state*, uint8_t chid);

/*
 * Enable debug tracing out to a FILE, set mask to the bitmap of
 * message types you are interested in messages from.
 */
enum trace_groups {
/* video system state transitions */
	A12_TRACE_VIDEO = 1,

/* audio system state transitions / data */
	A12_TRACE_AUDIO = 2,

/* system/serious errors */
	A12_TRACE_SYSTEM = 4,

/* event transfers in/out */
	A12_TRACE_EVENT = 8,

/* data transfer statistics */
	A12_TRACE_TRANSFER = 16,

/* debug messages, when patching / developing  */
	A12_TRACE_DEBUG = 32,

/* missing feature warning */
	A12_TRACE_MISSING = 64,

/* memory allocation status */
	A12_TRACE_ALLOC = 128,

/* crypto- system state transition */
	A12_TRACE_CRYPTO = 256,

/* video frame compression/transfer details */
	A12_TRACE_VDETAIL = 512,

/* binary blob transfer state information */
	A12_TRACE_BTRANSFER = 1024,

/* key-authentication and configuration warnings */
	A12_TRACE_SECURITY = 2048,

/* actions related to the directory mode and discovery */
	A12_TRACE_DIRECTORY = 4096,
};

void
a12_set_trace_level(int mask, FILE* dst);

/*
 * forward a vbuffer from shm
 */
enum a12_vframe_method {
	VFRAME_METHOD_DEFER = -1, /* will be ignored */
	VFRAME_METHOD_NORMAL = 0, /* to deprecate */
	VFRAME_METHOD_RAW_NOALPHA = 1,
	VFRAME_METHOD_RAW_RGB565 = 2,
	VFRAME_METHOD_H264 = 5,
	VFRAME_METHOD_TPACK_ZSTD = 7,
	VFRAME_METHOD_ZSTD = 8,
	VFRAME_METHOD_DZSTD = 9
};

enum a12_stream_types {
	STREAM_TYPE_VIDEO = 0,
	STREAM_TYPE_AUDIO = 1,
	STREAM_TYPE_BINARY = 2
};

enum a12_vframe_compression_bias {
	VFRAME_BIAS_LATENCY = 0,
	VFRAME_BIAS_BALANCED,
	VFRAME_BIAS_QUALITY,
};

/* properties to forward to the last stage in order to avoid extra
 * repacks or conversions */
enum a12_vframe_postprocess {
	VFRAME_POSTPROCESS_SRGB = 1,
	VFRAME_POSTPROCESS_ORIGO_LL = 2
};

/*
 * Open ended question here is if it is worth it (practically speaking) to
 * allow caching of various blocks and subregions vs. just normal compression.
 * The case can be made for CURSOR-type subsegments and possibly first frame of
 * a POPUP and some other types.
 */
struct a12_vframe_opts {
	enum a12_vframe_method method;
	enum a12_vframe_compression_bias bias;
	enum a12_vframe_postprocess postprocess;

	int ratefactor; /* overrides bitrate, crf (0..51) */
	size_t bitrate; /* kbit/s */
};

enum a12_aframe_method {
	AFRAME_METHOD_RAW = 0,
};

struct a12_aframe_opts {
	enum a12_aframe_method method;
};

struct a12_aframe_cfg {
	uint8_t channels;
	uint32_t samplerate;
};

/*
 * Register a handler that deals with binary- transfer cache lookup and
 * storage allocation. The supplied [on_bevent] handler is invoked twice:
 *
 * 1. When the other side has initiated a binary transfer. The type, size
 *    and possible checksum (all may be unknown) is provided.
 *
 * 2. When the transfer has completed or been cancelled.
 *
 * Each channel can only have one transfer in- flight, so it is safe to
 * track the state per-channel and not try to pair multiple transfers.
 *
 * Cancellation will be triggered on DONTWANT / CACHED. Otherwise the
 * new file descriptor will be populated and when the transfer is
 * completed / cancelled, the handler will be invoked again. It is up
 * to the handler to close any descriptor.
 */
enum a12_bhandler_flag {
	A12_BHANDLER_CACHED = 0,
	A12_BHANDLER_NEWFD,
	A12_BHANDLER_DONTWANT,
	A12_BHANDLER_NEWFD_NOCOMPRESS
};

enum a12_bhandler_state {
	A12_BHANDLER_CANCELLED = 0,
	A12_BHANDLER_COMPLETED,
	A12_BHANDLER_INITIALIZE
};

struct a12_bhandler_meta {
	enum a12_bhandler_state state;
	enum a12_bstream_type type;
	uint8_t checksum[16];
	uint64_t known_size;
	bool streaming;
	uint8_t channel;
	uint64_t streamid;
	uint32_t identifier;
	char extid[17];
	int fd;
	struct arcan_shmif_cont* dcont;
};
struct a12_bhandler_res {
	enum a12_bhandler_flag flag;
	int fd;
};
void
a12_set_bhandler(struct a12_state*,
	struct a12_bhandler_res (*on_bevent)(
		struct a12_state* S, struct a12_bhandler_meta, void* tag),
	void* tag
);

/*
 * The following functions provide data over a channel, each channel corresponds
 * to a subsegment, with the special ID(0) referring to the primary segment. To
 * modify which subsegment actually receives some data, use the a12_set_channel
 * function.
 */

/*
 * Forward an event. Any associated descriptors etc.  will be taken over by the
 * transfer, and it is responsible for closing them on completion.
 *
 * Return:
 * false - congestion, flush some data and try again.
 */
bool
a12_channel_enqueue(struct a12_state*, struct arcan_event*);

/* Encode and transfer an audio frame with a number of samples in the native
 * audio sample format and the samplerate etc. configuration that matches */
void
a12_channel_aframe(
	struct a12_state* S, shmif_asample* buf,
	size_t n_samples,
	struct a12_aframe_cfg cfg,
	struct a12_aframe_opts opts
);

/* Encode and transfer a video frame based on the video buffer structure
 * provided as part of arcan_shmif_server. Depending on the state of [vb]
 * the compression [opts] might get ignored. This can happen in the case
 * of a client forwarding a precompressed buffer. */
void
a12_channel_vframe(
	struct a12_state* S,
	struct shmifsrv_vbuffer* vb,
	struct a12_vframe_opts opts
);

/*
 * Forward / start a new channel intended for the 'real' client. If this
 * comes as a NEWSEGMENT event from the 'real' arcan instance, make sure
 * to also tie this to the segment via 12_channel_set_destination.
 *
 * [chid] is the assigned channel ID for the connection.
 * [output] is set to true for an output segment (server populates buffer)
 *          and is commonly false. (ioev[1].iv)
 * [segkind] matches a possible SEGID (ioev[2].iv)
 * [cookie] is paired to a SEGREQ event from the other side (ioev[3].iv)
 */
void
a12_channel_new(struct a12_state* S,
	uint8_t chid, uint8_t segkind, uint32_t cookie);

/*
 * Send the 'shutdown' command with an optional 'last_words' message,
 * this should be done before the _close and typically matches either
 * the client _drop:ing a segment (shmifsrv- side) or an _EXIT event
 * (shmif-client) side.
 */
void
a12_channel_shutdown(struct a12_state* S, const char* last_words);

/* Close / destroy the active channel, if this is the primary (0) all
 * channels will be closed and the connection terminated */
void
a12_channel_close(struct a12_state*);

/*
 * Cancel the binary stream that is ongoing in a specific channel
 */
void a12_stream_cancel(struct a12_state* S, uint8_t chid);

/*
 * Check the status flag of the state machine
 */
bool a12_ok(struct a12_state* S);

/*
 * Check the state of the remote end primary channel (source, sink, ...)
 */
int a12_remote_mode(struct a12_state* S);

/*
 * Cancel a video stream that is ongoing in a specific channel
 */
enum stream_cancel {
	STREAM_CANCEL_DONTWANT = 0,
	STREAM_CANCEL_DECODE_ERROR = 1,
	STREAM_CANCEL_KNOWN = 2
};
void a12_vstream_cancel(struct a12_state* S, uint8_t chid, int reason);

/*
 * Mark the state as completed / shutdown after any PING with [id] has been
 * received. This is used to queue up a state or other binary transfer and
 * shutdown when that has been completed or cancelled.
 */
void a12_shutdown_id(struct a12_state* S, uint32_t id);

struct a12_iostat {
	size_t b_in;
	size_t b_out;
	size_t vframe_backpressure; /* number of encoded vframes vs. pending */
	size_t roundtrip_latency;
	size_t ms_vframe;           /* for last encoded video frame */
	float ms_vframe_px;
	size_t packets_pending;     /* delta between seqnr and last-seen seqnr */
};

/* get / set a string representation for logging and similar operations
 * where there is a need for a traceable origin e.g. IP address */
const char* a12_get_endpoint(struct a12_state* S);
void a12_set_endpoint(struct a12_state* S, const char*);

/*
 * Sample the current rolling state statistics
 */
struct a12_iostat a12_state_iostat(struct a12_state* S);

/*
 * Try to negotiate a connection for a directory resource based on an announced
 * public key. An ephemeral keypair will be generated and part of the reply.
 *
 * This should be used either directly and lets the outer key.
 *
 * The contents of dynreq will be free:d automatically after callback
 * completion.
 */
bool a12_request_dynamic_resource(
	struct a12_state* S,
	uint8_t ident_pubk[static 32],
	bool prefer_tunnel,
	void(*request_reply)(struct a12_state*, struct a12_dynreq, void* tag),
	void* tag);

void a12_supply_dynamic_resource(struct a12_state* S, struct a12_dynreq);

/*
 * debugging / tracing bits, just define a namespace that can be used
 * for wrapper tools to log with the same syntax and behaviour as the
 * implementation files
 */
extern int a12_trace_targets;
extern FILE* a12_trace_dst;

const char* a12int_group_tostr(int group);

#ifndef a12int_trace

#ifdef WITH_TRACY
#include "tracy/TracyC.h"
#define a12int_trace(group, fmt, ...) \
	do { \
	    TracyCZone(___trace_ctx, true); \
	    const char *___trace_name = a12int_group_tostr(group); \
	    TracyCZoneName(___trace_ctx, ___trace_name, strlen(___trace_name)); \
	    char ___trace_buf[512]; \
	    int ___trace_strlen = snprintf(___trace_buf, 512, \
				"group=%s:function=%s:" fmt "\n", \
				___trace_name, __func__,##__VA_ARGS__); \
	    TracyCZoneText(___trace_ctx, ___trace_buf, MIN(511, ___trace_strlen)); \
	    TracyCZoneEnd(___trace_ctx); \
	} while (0)
#else
#define a12int_trace(group, fmt, ...) \
	do { \
	    if (a12_trace_dst && (a12_trace_targets & group)) \
		    fprintf(a12_trace_dst, \
				"group=%s:function=%s:" fmt "\n", \
				a12int_group_tostr(group), __func__,##__VA_ARGS__); \
	} while (0)
#endif // WITH_TRACY

#endif // a12int_trace
#endif // HAVE_A12
