#ifndef HAVE_A12_INT
#define HAVE_A12_INT

/* crypto / line format */
#include "blake2.h"
#include "pack.h"

/* this is frightening */
#define MINIZ_USE_UNALIGNED_LOADS_AND_STORES 0
#define MINIZ_LITTLE_ENDIAN 1
#define MINIZ_HAS_64BIT_REGISTERS 1
#define MINIZ_UNALIGNED_USE_MEMCPY
#include "miniz/miniz.h"

#if defined(WANT_H264_DEC) || defined(WANT_H264_ENC)
#include <libavcodec/avcodec.h>
#include <libavcodec/version.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#endif

#define MAC_BLOCK_SZ 16
#define CONTROL_PACKET_SIZE 128

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
	STATE_NOPACKET = 0,
	STATE_CONTROL_PACKET = 1,
	STATE_EVENT_PACKET = 2,
	STATE_AUDIO_PACKET = 3,
	STATE_VIDEO_PACKET = 4,
	STATE_BLOB_PACKET = 5,
	STATE_BROKEN
};

enum control_commands {
	COMMAND_HELLO = 0,
	COMMAND_SHUTDOWN = 1,
	COMMAND_NEWCH = 2,
	COMMAND_CANCELSTREAM = 3,
	COMMAND_VIDEOFRAME = 4,
	COMMAND_AUDIOFRAME = 5,
	COMMAND_BINARYSTREAM = 6,
	COMMAND_PING = 7,
	COMMAND_REKEY = 8
};

#define SEQUENCE_NUMBER_SIZE 8

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

enum {
	POSTPROCESS_VIDEO_RGBA = 0,
	POSTPROCESS_VIDEO_RGB = 1,
	POSTPROCESS_VIDEO_RGB565 = 2,
	POSTPROCESS_VIDEO_DMINIZ = 3,
	POSTPROCESS_VIDEO_MINIZ = 4,
	POSTPROCESS_VIDEO_H264 = 5,
	POSTPROCESS_VIDEO_TZ = 6
};

size_t a12int_header_size(int type);

struct audio_frame {
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
	uint64_t size;
	uint8_t checksum[16];
	int64_t streamid; /* actual type is uint32 but -1 for cancel */
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

#ifdef WANT_H264_DEC
	struct {
		AVCodecParserContext* parser;
		AVCodecContext* context;
		AVPacket* packet;
		AVFrame* frame;
		struct SwsContext* scaler;
	} ffmpeg;
#endif

	/* bytes left on current row for raw-dec */
};

struct blob_out;
struct blob_out {
	uint8_t checksum[16];
	int fd;
	uint8_t chid;
	int type;
	size_t left;
	bool streaming;
	bool active;
	uint64_t streamid;
	struct blob_out* next;
};

struct a12_state;
struct a12_state {
	struct a12_context_options* opts;

/* we need to prepend this when we build the next MAC */
	uint8_t last_mac_out[MAC_BLOCK_SZ];
	uint8_t last_mac_in[MAC_BLOCK_SZ];

/* data needed to synthesize the next package */
	uint64_t current_seqnr;
	uint64_t last_seen_seqnr;
	uint64_t out_stream;

/* populate and forwarded output buffer */
	size_t buf_sz[2];
	uint8_t* bufs[2];
	uint8_t buf_ind;
	size_t buf_ofs;

/* linked list of pending binary transfers, can be re-ordered and affect
 * blocking / transfer state of events on the other side */
	struct blob_out* pending;

/* current event handler for binary transfer cache oracle */
	struct a12_bhandler_res
		(*binary_handler)(struct a12_state*, struct a12_bhandler_meta, void*);
	void* binary_handler_tag;

/* multiple- channels over the same state tracker for subsegment handling */
	struct {
		bool active;
		struct arcan_shmif_cont* cont;

/* can have one of each stream- type being prepared for unpack at the same time */
		struct {
			struct video_frame vframe;
			struct audio_frame aframe;
			struct binary_frame bframe;
		} unpack_state;

/* encoding (recall, both sides can actually do this) */
		struct shmifsrv_vbuffer acc;
		union {
			uint8_t* compression;
#ifdef WANT_H264_ENC
			struct {
				AVCodecContext* encoder;
				AVCodec* codec;
				AVFrame* frame;
				AVPacket* packet;
				struct SwsContext* scaler;
				size_t w, h;
				bool failed;
			} videnc;
#endif
		};
	} channels[256];

/* current decoding state, tracked / used by the process_* functions */
	int in_channel;
	uint32_t in_stream;

/* current encoding state, manipulate with set_channel */
	int out_channel;

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

/* built at initial setup, then copied out for every time we add data */
	blake2bp_state mac_init, mac_dec;

/* when the channel has switched to a streamcipher, this is set to true */
	bool in_encstate;
};

void a12int_append_out(
	struct a12_state* S, uint8_t type, uint8_t* out, size_t out_sz,
	uint8_t* prepend, size_t prepend_sz);

#endif
