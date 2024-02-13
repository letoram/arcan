#ifndef HAVE_A12_INT
#define HAVE_A12_INT

#include "blake3.h"
#include "pack.h"

#if defined(WANT_H264_DEC) || defined(WANT_H264_ENC)
#include <libavcodec/avcodec.h>
#include <libavcodec/version.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#endif

#ifndef ZSTD_DEFAULT_LEVEL
#define ZSTD_DEFAULT_LEVEL 3
#endif

#ifndef ZSTD_VIDEO_LEVEL
#define ZSTD_VIDEO_LEVEL 2
#endif

#ifndef VIDEO_FRAME_DRIFT_WINDOW
#define VIDEO_FRAME_DRIFT_WINDOW 8
#endif

#define MAC_BLOCK_SZ 16
#define NONCE_SIZE 8
#define CONTROL_PACKET_SIZE 128
#define CIPHER_ROUNDS 8

#ifndef BLOB_QUEUE_CAP
#define BLOB_QUEUE_CAP (128 * 1024)
#endif

/* safe UDP beacon, increase in controlled LANs */
#ifndef BEACON_KEY_CAP
#define BEACON_KEY_CAP 15
#endif

#ifndef DYNAMIC_FREE
#define DYNAMIC_FREE free
#endif

#ifndef DYNAMIC_MALLOC
#define DYNAMIC_MALLOC malloc
#endif

#ifndef DYNAMIC_REALLOC
#define DYNAMIC_REALLOC realloc
#endif

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

enum {
	STATE_NOPACKET       = 0, /* nopacket -> control                         */
	STATE_CONTROL_PACKET = 1, /* control  -> a, v, e, blob, broken, nopacket */
	STATE_EVENT_PACKET   = 2, /* event    -> nopacket, broken                */
	STATE_AUDIO_PACKET   = 3, /* audio    -> nopacket, broken                */
	STATE_VIDEO_PACKET   = 4, /* video    -> nopacket, broken                */
	STATE_BLOB_PACKET    = 5, /* blob     -> nopacket, broken                */
	STATE_1STSRV_PACKET  = 6, /* mac+nonce -> control                        */
	STATE_BROKEN
};

enum control_commands {
	COMMAND_HELLO        = 0, /* initial keynegotiation          */
	COMMAND_SHUTDOWN     = 1, /* graceful exit                   */
	COMMAND_NEWCH        = 2, /* channel = triple (A|V|meta)     */
	COMMAND_CANCELSTREAM = 3, /* abort ongoing video transfer    */
	COMMAND_VIDEOFRAME   = 4, /* next packets will be video data */
	COMMAND_AUDIOFRAME   = 5, /* next packets will be audio data */
	COMMAND_BINARYSTREAM = 6, /* cut and paste, state, font, ... */
	COMMAND_PING         = 7, /* keepalive, latency masurement   */
	COMMAND_REKEY        = 8, /* new x25519 change               */
	COMMAND_DIRLIST      = 9, /* request list of items           */
	COMMAND_DIRSTATE     = 10,/* update / present a new appl     */
	COMMAND_DIRDISCOVER  = 11,/* dynamic source/dir entry        */
	COMMAND_DIROPEN      = 12,/* mediate access to a dyn src/dir */
	COMMAND_DIROPENED    = 13,/* replies to DIROPEN (src/sink)   */
	COMMAND_TUNDROP      = 14,/* state change on DIROPENED con   */
};

enum hello_mode {
	HELLO_MODE_NOASYM  = 0,
	HELLO_MODE_REALPK  = 1,
	HELLO_MODE_EPHEMPK = 2
};

enum channel_cfg {
	CHANNEL_INACTIVE = 0, /* nothing mapped in the channel          */
	CHANNEL_SHMIF    = 1, /* shmif context set                      */
	CHANNEL_RAW      = 2  /* raw user-callback provided destination */
};

#define SEQUENCE_NUMBER_SIZE 8

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

enum {
	POSTPROCESS_VIDEO_RGBA   = 0,
	POSTPROCESS_VIDEO_RGB    = 1,
	POSTPROCESS_VIDEO_RGB565 = 2,
	POSTPROCESS_VIDEO_H264   = 5, /* ffmpeg or native decompressor        */
	POSTPROCESS_VIDEO_TZSTD  = 7, /* ZSTD+tpack                           */
	POSTPROCESS_VIDEO_DZSTD  = 8, /* ZSTD - P frame                       */
	POSTPROCESS_VIDEO_ZSTD   = 9  /* ZSTD - I frame                       */
};

size_t a12int_header_size(int type);

struct ZSTD_CCtx_s;
struct ZSTD_DCtx_s;

struct audio_frame {
	uint32_t id;

	uint32_t rate;
	uint8_t encoding;
	uint8_t channels;
	uint8_t format;
	uint16_t nsamples;
	uint8_t commit;

/* only used for some postprocessing mode (i.e. decompression) */
	uint8_t* inbuf;
	size_t inbuf_pos;
	size_t inbuf_sz;
	size_t expanded_sz;
};

struct binary_frame {
	int tmp_fd;
	int type;
	bool active;
	int tunnel;
	uint64_t size;
	uint32_t identifier;
	uint8_t checksum[16];
	int64_t streamid; /* actual type is uint32 but -1 for cancel */
	char extid[16];
	struct ZSTD_DCtx_s* zstd;
};

struct video_frame {
	uint32_t id;
	uint16_t sw, sh;
	uint16_t w, h;
	uint16_t x, y;
	uint32_t flags;
	uint8_t postprocess;
	uint8_t commit; /* finish after this transfer? */

	uint8_t* inbuf; /* decode buffer, not used for all modes */
	uint32_t inbuf_pos;
	uint32_t inbuf_sz; /* bytes-total counter */
 /* separation between input-frame buffer and
	* decompression postprocessing, avoid 'zip-bombing' */
	uint32_t expanded_sz;
	size_t row_left;
	size_t out_pos;

	uint8_t pxbuf[4];
	uint8_t carry;

/* these allocations are not kept in the frame struct, but
 * rather contained in the ffmpeg structure for that channel */
#ifdef WANT_H264_DEC
	struct {
		AVCodecParserContext* parser;
		AVCodecContext* context;
		AVPacket* packet;
		AVFrame* frame;
		struct SwsContext* scaler;
	} ffmpeg;
#endif

	struct ZSTD_DCtx_s* zstd;

	/* bytes left on current row for raw-dec */
};

struct blob_out;
struct blob_out {
	uint8_t checksum[16];
	int fd;
	uint8_t chid;
	int type;
	uint32_t identifier;
	char extid[16];
	size_t left;
	char* buf;
	size_t buf_sz;
	bool streaming;
	bool active;
	uint64_t streamid;
	uint64_t rampup_seqnr;

	struct ZSTD_CCtx_s* zstd;
	struct blob_out* next;
};

struct a12_channel {
	int active;
	struct arcan_shmif_cont* cont;
	struct a12_unpack_cfg raw;

/* can have one of each stream- type being prepared for unpack at the same time */
	struct {
		struct video_frame vframe;
		struct audio_frame aframe;
		struct binary_frame bframe;
	} unpack_state;

/* used for both encoding and decoding, state is aliased into unpack_state */
	struct shmifsrv_vbuffer acc;

	struct {
		uint8_t* compression;
		struct ZSTD_CCtx_s* zstd;
#if defined(WANT_H264_ENC) || defined(WANT_H264_DEC)
		struct {
			AVCodecParserContext* parser;
			AVCodecContext* encdec;
			const AVCodec* codec;
			AVFrame* frame;
			AVPacket* packet;
			struct SwsContext* scaler;
			size_t w, h;
			bool failed;
		} videnc;
#endif
	};
};

struct a12_state;
struct a12_state {
	struct a12_context_options* opts;
	struct appl_meta* directory;
	uint64_t directory_clk;
	bool notify_dynamic;

	uint8_t last_mac_in[MAC_BLOCK_SZ];

/* data needed to synthesize the next package */
	uint64_t current_seqnr;
	uint64_t last_seen_seqnr;
	uint64_t out_stream;
	int64_t shutdown_id;
	bool advenc_broken;

/* The biggest concern of congestion is video frames as that tends to be most
 * primary data. The decision to act upon this is still up to the tool feeding
 * the state machine, there might be other priorities and factors to weigh in
 * on. While we indirectly do measure latency and so on, the better congestion
 * control channel for that is left up to the carrier. */
	struct {
		uint32_t frame_window[VIDEO_FRAME_DRIFT_WINDOW]; /* seqnrs tied to vframes */
		size_t pending; /* updated whenever we send something out */
	} congestion_stats;
	struct a12_iostat stats;

/* tracks a pending dynamic directory resource */
	struct {
		bool active;
		uint8_t priv_key[32];
		uint8_t req_key[32];
		void(* closure)(struct a12_state*, struct a12_dynreq, void* tag);
		void* tag;

	} pending_dynamic;

/* populate and forwarded output buffer */
	size_t buf_sz[2];
	uint8_t* bufs[2];
	uint8_t buf_ind;
	size_t buf_ofs;

/* linked list of pending binary transfers, can be re-ordered and affect
 * blocking / transfer state of events on the other side */
	struct blob_out* pending;
	size_t active_blobs;

/* current event handler for binary transfer cache oracle */
	struct a12_bhandler_res
		(*binary_handler)(struct a12_state*, struct a12_bhandler_meta, void*);
	void* binary_handler_tag;

/* multiple- channels over the same state tracker for subsegment handling */
	struct a12_channel channels[256];

/* current decoding state, tracked / used by the process_* functions */
	int in_channel;
	uint32_t in_stream;

/* current encoding state, manipulate with set_channel */
	int out_channel;

	void (*on_discover)(struct a12_state*, int type,
		const char* petname, bool found, uint8_t pubk[static 32], void*);
	void* discover_tag;

	void (*on_auth)(struct a12_state*, void*);
	void* auth_tag;

/*
 * Incoming buffer, size of the buffer == size of the type - when there
 * is nothing left in the current frame, forward / dispatch to the correct
 * decode vframe/aframe/bframe routine.
 */
	uint8_t decode[65536];
	uint16_t decode_pos;
	uint16_t left;
	uint8_t state;

/* overflow state tracking cookie */
	volatile uint32_t cookie;

/* curve25519 keys (client), and rekeying sequence number (both), hardening
 * note - this should be moved to a separate allocation that is madvised to
 * MADV_DONTDUMP */
	struct {
		uint8_t ephem_priv[32];
		uint8_t real_priv[32];
		uint8_t remote_pub[32];
		uint8_t local_pub[32];
		uint8_t ticket[32];

		size_t rekey_count;
		size_t rekey_base_count;
		bool own_rekey;
	} keys;

/* client side needs to send the first packet with MAC+nonce, server side
 * needs to interpret first packet with MAC+nonce */
	bool server;
	bool cl_firstout;
	int authentic;
	int remote_mode;
	char* endpoint;

/* saved between calls to unpack, see end of a12_unpack for explanation */
	bool auth_latched;
	size_t prepend_unpack_sz;
	uint8_t* prepend_unpack;

	blake3_hasher out_mac, in_mac;

	struct chacha_ctx* enc_state;
	struct chacha_ctx* dec_state;
};

enum {
	STREAM_FAIL_OUTDATED = 0,
	STREAM_FAIL_UNKNOWN = 1,
	STREAM_FAIL_ALREADY_KNOWN = 2
};
void a12int_stream_fail(struct a12_state* S, uint8_t ch, uint32_t id, int fail);
void a12int_stream_ack(struct a12_state* S, uint8_t ch, uint32_t id);

void a12int_append_out(
	struct a12_state* S, uint8_t type,
	const uint8_t* const out, size_t out_sz,
	uint8_t* prepend, size_t prepend_sz);

void a12int_step_vstream(struct a12_state* S, uint32_t id);

/* takes ownership of appl_meta */
void a12int_set_directory(struct a12_state*, struct appl_meta*);

/*
 * For a state in directory server mode,
 * and with the other end having requested notifications as part of a
 * previous dirlist request.
 */
void
	a12int_notify_dynamic_resource(
		struct a12_state*,
		const char* petname,
		uint8_t kpub[static 32],
		uint8_t role, bool added);

/* get the current directory -
 * this is only valid between a12* calls on the state.
 * The clock is an atomic counter that increments each time the directory
 * is updated. */
struct appl_meta* a12int_get_directory(struct a12_state*, uint64_t* clk);

/* Send the command to get a directory listing,
 * results will be provided as BCHUNKHINT events for appls and NETSTATE
 * ones for entries tied to dynamic sources / directories.
 *
 * If notify is set changes will be sent dynamically */
void a12int_request_dirlist(struct a12_state*, bool notify);

#endif
