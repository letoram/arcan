/*
 * Copyright: 2017-2019, Björn Ståhl
 * Description: A12 protocol state machine, main translation unit.
 * Maintains connection state, multiplex and demultiplex then routes
 * to the corresponding decoding/encode stages.
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://arcan-fe.com
 */
/* shared state machine structure */
#include "a12_int.h"
#include "a12.h"

#include "a12_decode.h"
#include "a12_encode.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

static int header_sizes[] = {
	MAC_BLOCK_SZ + 1, /* NO packet, just MAC + outer header */
	CONTROL_PACKET_SIZE,
	0, /* EVENT size is filled in at first open */
	1 + 4 + 2, /* VIDEO partial: ch, stream, len */
	1 + 4 + 2, /* AUDIO partial: ch, stream, len */
	1 + 4 + 2, /* BINARY partial: ch, stream, len */
	0
};

size_t a12int_header_size(int kind)
{
	return header_sizes[kind];
}

static uint8_t* grow_array(uint8_t* dst, size_t* cur_sz, size_t new_sz)
{
	if (new_sz < *cur_sz)
		return dst;

/* pick the nearest higher power of 2 for good measure */
	size_t pow = 1;
	while (pow < new_sz)
		pow *= 2;

/* wrap around? give up */
	if (pow < new_sz){
		debug_print(1, "possible queue size exceeded");
		free(dst);
		*cur_sz = 0;
		return NULL;
	}

	new_sz = pow;

	debug_print(2, "grow outqueue %zu => %zu", *cur_sz, new_sz);
	uint8_t* res = DYNAMIC_REALLOC(dst, new_sz);
	if (!res){
		debug_print(1, "couldn't grow queue");
		free(dst);
		*cur_sz = 0;
		return NULL;
	}

	*cur_sz = new_sz;
	return res;
}

static void step_sequence(struct a12_state* S, uint8_t* outb)
{
	pack_u64(S->current_seqnr++, outb);
/* DBEUG: replace sequence with 's' */
	for (size_t i = 0; i < 8; i++) outb[i] = 's';
}

/*
 * Used when a full byte buffer for a packet has been prepared, important
 * since it will also encrypt, generate MAC and add to buffer prestate.
 *
 * This is where more advanced and fair queueing should be made in order
 * to not have the bandwidth hungry channels (i.e. video) consume everything.
 * The rough idea is to have bins for a/v/b streams, with a priority on a/v
 * unless it is getting too 'old'. There are some complications:
 *
 * 1. stream cancellation, can only be done on non-delta/non-compressed
 *    so mostly usable for binary then
 * 2. control packets that are tied to an a/v/b frame
 *
 * Another issue is that the raw vframes are big and ugly, and here is the
 * place where we perform an unavoidable copy unless we want interleaving
 * (and then it becomes expensive to perform). Should be possible to set a
 * direct-to-drain descriptor here and do the write calls to the socket or
 * descriptor.
 */
void a12int_append_out(
	struct a12_state* S, uint8_t type, uint8_t* out, size_t out_sz,
	uint8_t* prepend, size_t prepend_sz)
{
/*
 * QUEUE-slot here,
 * should also have the ability to probe the size of the queue slots
 * so that encoders can react on backpressure
 */

/* this means we can just continue our happy stream-cipher and apply to our
 * outgoing data */
	if (S->in_encstate){
/*
 * cipher_update(&S->out_cstream, prepend, prepend_sz);
 * cipher_update(&S->out_cstream, out, out_sz)
 */
	}

/* begin a new MAC, chained on our previous one
	blake2bp_state mac_state = S->mac_init;
	blake2bp_update(&mac_state, S->last_mac_out, MAC_BLOCK_SZ);
	blake2bp_update(&mac_state, &type, 1);
	blake2bp_update(&mac_state, prepend, prepend_sz);
	blake2bp_update(&mac_state, out, out_sz);
 */

/* grow write buffer if the block doesn't fit */
	size_t required = S->buf_ofs + MAC_BLOCK_SZ + out_sz + 1 + prepend_sz;

	S->bufs[S->buf_ind] = grow_array(
		S->bufs[S->buf_ind],
		&S->buf_sz[S->buf_ind],
		required
	);

/* and if that didn't work, fatal */
	if (S->buf_sz[S->buf_ind] < required){
		debug_print(1, "realloc failed: size (%zu) vs required (%zu)",
			S->buf_sz[S->buf_ind], required);

		S->state = STATE_BROKEN;
		return;
	}
	uint8_t* dst = S->bufs[S->buf_ind];

/* prepend MAC
	blake2bp_final(&mac_state, S->last_mac_out, MAC_BLOCK_SZ);
	memcpy(&dst[S->buf_ofs], S->last_mac_out, MAC_BLOCK_SZ);
 */

/* DEBUG: replace mac with 'm' */
	for (size_t i = 0; i < MAC_BLOCK_SZ; i++)
		dst[i] = 'm';
	S->buf_ofs += MAC_BLOCK_SZ;

/* our packet type */
	dst[S->buf_ofs++] = type;

/* any possible prepend-to-data block */
	if (prepend_sz){
		memcpy(&dst[S->buf_ofs], prepend, prepend_sz);
		S->buf_ofs += prepend_sz;
	}

/* and our data block, this costs us an extra copy which isn't very nice -
 * might want to set a target descriptor immediately for some uses here,
 * the problem is proper interleaving of packets while respecting kernel
 * buffer behavior */
	memcpy(&dst[S->buf_ofs], out, out_sz);
	S->buf_ofs += out_sz;
}

static void reset_state(struct a12_state* S)
{
	S->left = header_sizes[STATE_NOPACKET];
	S->state = STATE_NOPACKET;
	S->decode_pos = 0;
	S->in_channel = -1;
	S->mac_dec = S->mac_init;
}

static struct a12_state* a12_setup(uint8_t* authk, size_t authk_sz)
{
	struct a12_state* res = DYNAMIC_MALLOC(sizeof(struct a12_state));
	if (!res)
		return NULL;

/* the authk- argument setup should really be reworked */
	uint8_t empty_key[16] = {0};
	size_t empty_sz = 16;
	if (!authk){
		authk = empty_key;
		authk_sz = empty_sz;
	}

	*res = (struct a12_state){};
	if (-1 == blake2bp_init_key(&res->mac_init, 16, authk, authk_sz)){
		DYNAMIC_FREE(res);
		return NULL;
	}

	res->cookie = 0xfeedface;
	return res;
}

static void a12_init()
{
	static bool init;
	if (init)
		return;

/* make one nonsense- call first to figure out the current packing size */
	uint8_t outb[512];
	ssize_t evsz = arcan_shmif_eventpack(
		&(struct arcan_event){.category = EVENT_IO}, outb, 512);

	header_sizes[STATE_EVENT_PACKET] = evsz + SEQUENCE_NUMBER_SIZE;
	init = true;
}

struct a12_state* a12_channel_build(uint8_t* authk, size_t authk_sz)
{
	a12_init();

	struct a12_state* res = a12_setup(authk, authk_sz);
	if (!res)
		return NULL;

	return res;
}

struct a12_state* a12_channel_open(uint8_t* authk, size_t authk_sz)
{
	a12_init();

	struct a12_state* S = a12_setup(authk, authk_sz);
	if (!S)
		return NULL;

/* send initial hello packet */
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	step_sequence(S, outb);

	outb[17] = 0;

	debug_print(1, "channel open, add control packet");
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);

	return S;
}

void
a12_channel_close(struct a12_state* S)
{
	if (!S || S->cookie != 0xfeedface)
		return;

	DYNAMIC_FREE(S->bufs[0]);
	DYNAMIC_FREE(S->bufs[1]);
	*S = (struct a12_state){};
	S->cookie = 0xdeadbeef;

	DYNAMIC_FREE(S);
}

/*
 * NOPACKET:
 * MAC
 * command byte
 */
static void process_nopacket(struct a12_state* S)
{
/* only work with a whole packet */
	if (S->left > 0)
		return;

	S->mac_dec = S->mac_init;
/* MAC(MAC_IN | KEY)
	blake2bp_update(&S->mac_dec, S->last_mac_in, MAC_BLOCK_SZ);
 */

/* save last known MAC for later comparison */
	memcpy(S->last_mac_in, S->decode, MAC_BLOCK_SZ);

/* CRYPTO-fixme: if we are in stream cipher mode, decode just the one byte
 * blake2bp_update(&S->mac_dec, &S->decode[MAC_BLOCK_SZ], 1); */

	S->state = S->decode[MAC_BLOCK_SZ];

	if (S->state >= STATE_BROKEN){
		debug_print(1, "channel broken, unknown command val: %"PRIu8, S->state);
		S->state = STATE_BROKEN;
		return;
	}

	debug_print(2, "left: %"PRIu16", state: %"PRIu8, S->left, S->state);
	S->left = header_sizes[S->state];
	S->decode_pos = 0;
}

static bool process_mac(struct a12_state* S)
{
	uint8_t final_mac[MAC_BLOCK_SZ];

/*
 * Authentication is on the todo when everything is not in flux and we can
 * do the full verification & validation process
 */
	return true;

	blake2bp_update(&S->mac_dec, S->decode, S->decode_pos);
	blake2bp_final(&S->mac_dec, final_mac, MAC_BLOCK_SZ);

/* Option to continue with broken authentication, ... */
	if (memcmp(final_mac, S->last_mac_in, MAC_BLOCK_SZ) != 0){
		debug_print(1, "authentication mismatch on packet \n");
		S->state = STATE_BROKEN;
		return false;
	}

	debug_print(2, "authenticated packet");
	return true;
}

static void command_binarystream(struct a12_state* S)
{
	uint8_t channel = S->decode[16];
/*
 * need to flag that the next event is to be deferred (though it will also
 * be marked as a descrevent- so that might actually suffice)
 */
	struct arcan_shmif_cont* cont = S->channels[channel].cont;
	if (!cont){
		debug_print(1, "no segment mapped on channel");
		return;
	}

}

static void command_audioframe(struct a12_state* S)
{
	uint8_t channel = S->decode[16];
	struct audio_frame* aframe = &S->channels[channel].unpack_state.aframe;
/* new astream, from FREADME.md:
 * [18..21] : stream-id
 * [22] : format
 * [23] : encoding
 * [24] : rate
 * [25] : n-samples */
	aframe->format = S->decode[22];
	aframe->encoding = S->decode[23];
	aframe->nsamples = S->decode[24];
	aframe->rate = S->decode[25];
	S->in_channel = -1;
}

static void command_videoframe(struct a12_state* S)
{
	uint8_t channel = S->decode[16];
	struct video_frame* vframe = &S->channels[channel].unpack_state.vframe;
 /* new vstream, from README.md:
	* currently unused
	* [36    ] : dataflags: uint8
	*/
/* [18..21] : stream-id: uint32 */
	vframe->postprocess = S->decode[22]; /* [22] : format : uint8 */
/* [23..24] : surfacew: uint16
 * [25..26] : surfaceh: uint16 */
	unpack_u16(&vframe->sw, &S->decode[23]);
	unpack_u16(&vframe->sh, &S->decode[25]);
/* [27..28] : startx: uint16 (0..outw-1)
 * [29..30] : starty: uint16 (0..outh-1) */
	unpack_u16(&vframe->x, &S->decode[27]);
	unpack_u16(&vframe->y, &S->decode[29]);
/* [31..32] : framew: uint16 (outw-startx + framew < outw)
 * [33..34] : frameh: uint16 (outh-starty + frameh < outh) */
	unpack_u16(&vframe->w, &S->decode[31]);
	unpack_u16(&vframe->h, &S->decode[33]);
/* [35] : dataflags */
	unpack_u32(&vframe->inbuf_sz, &S->decode[36]);
/* [41]     : commit: uint8 */
	unpack_u32(&vframe->expanded_sz, &S->decode[40]);
	vframe->commit = S->decode[44];

	S->in_channel = -1;

/* If channel set, apply resize immediately - synch cost should be offset with
 * the buffering being performed at lower layers. Right now the rejection of a
 * resize is not being forwarded, which can cause problems in some edge cases
 * where the WM have artificially restricted the size of a client window etc. */
	struct arcan_shmif_cont* cont = S->channels[channel].cont;
	if (!cont){
		debug_print(1, "no segment mapped on channel");
		vframe->commit = 255;
		return;
	}

	if (vframe->sw != cont->w || vframe->sh != cont->h){
		arcan_shmif_resize(cont, vframe->sw, vframe->sh);
		if (vframe->sw != cont->w || vframe->sh != cont->h){
			debug_print(1, "parent size rejected");
			vframe->commit = 255;
		}
		else
			debug_print(1, "resized segment to %"PRIu32",%"PRIu32, vframe->sw, vframe->sh);
	}

	debug_print(2, "new vframe (%d): %"PRIu16"*%"
		PRIu16"@%"PRIu16",%"PRIu16"+%"PRIu16",%"PRIu16,
		vframe->postprocess,
		vframe->sw, vframe->sh, vframe->x, vframe->y, vframe->w, vframe->h
	);

/* Validation is done just above, making sure the sub- region doesn't extend
 * the specified source surface. Remaining length- field is verified before
 * the write in process_video. */

/* For RAW pixels, note that we count row, pos, etc. in the native
 * shmif_pixel and thus use pitch instead of stride */
	if (vframe->postprocess == POSTPROCESS_VIDEO_RGBA ||
		vframe->postprocess == POSTPROCESS_VIDEO_RGB565 ||
		vframe->postprocess == POSTPROCESS_VIDEO_RGB){
		vframe->row_left = vframe->w;
		vframe->out_pos = vframe->y * cont->pitch + vframe->x;
		debug_print(3,
			"row-length: %zu at buffer pos %"PRIu32, vframe->row_left, vframe->inbuf_pos);
	}
	else {
		if (vframe->expanded_sz > vframe->w * vframe->h * sizeof(shmif_pixel)){
			vframe->commit = 255;
			debug_print(1, "incoming frame exceeding reasonable constraints");
			return;
		}
		if (vframe->inbuf_sz > vframe->expanded_sz){
			vframe->commit = 255;
			debug_print(1, "incoming buffer expands to less than target");
			return;
		}

		vframe->out_pos = vframe->y * cont->pitch + vframe->x;
		vframe->inbuf_pos = 0;
		vframe->inbuf = malloc(vframe->inbuf_sz);
		if (!vframe->inbuf){
			debug_print(1, "couldn't allocate intermediate buffer store");
			return;
		}
		vframe->row_left = vframe->w;
		debug_print(2, "compressed buffer in\n");
	}
}

/*
 * Control command,
 * current MAC calculation in s->mac_dec
 */
static void process_control(struct a12_state* S)
{
	if (!process_mac(S))
		return;

/* ignore these two for now
	uint64_t last_seen;
	uint8_t entropy[8];
 */

	uint8_t command = S->decode[17];

	switch(command){
	case COMMAND_HELLO:
		debug_print(1, "HELO");
	/*
	 * CRYPTO- fixme: Update keymaterial etc. here.
	 * Verify that this is the first packet.
	 */
	break;
	case COMMAND_SHUTDOWN: break;
	case COMMAND_ENCNEG: break;
	case COMMAND_REKEY: break;
	case COMMAND_CANCELSTREAM: break;
	case COMMAND_NEWCH: break;
	case COMMAND_FAILURE: break;
	case COMMAND_VIDEOFRAME:
		command_videoframe(S);
	break;
	case COMMAND_AUDIOFRAME:
		command_audioframe(S);
	break;
	case COMMAND_BINARYSTREAM:
		command_binarystream(S);
	break;
	default:
		debug_print(1, "unhandled control message");
	break;
	}

	debug_print(2, "decode control packet");
	reset_state(S);
}

static void process_event(struct a12_state* S,
	void* tag, void (*on_event)(struct arcan_shmif_cont* wnd, int chid, struct arcan_event*, void*))
{
	if (!process_mac(S))
		return;

	uint8_t channel = S->decode[16];

	struct arcan_event aev;
	unpack_u64(&S->last_seen_seqnr, S->decode);

	if (-1 == arcan_shmif_eventunpack(
		&S->decode[SEQUENCE_NUMBER_SIZE], S->decode_pos - SEQUENCE_NUMBER_SIZE, &aev)){
		debug_print(1, "broken event packet received");
	}
	else if (on_event){
		debug_print(2, "unpack event to %d", channel);
		on_event(S->channels[channel].cont, 0, &aev, tag);
	}

	reset_state(S);
}

/*
 * We have an incoming video packet, first we need to match it to the channel
 * that it represents (as we might get interleaved updates) and match the state
 * we are building.  With real MAC, the return->reenter loop is wrong.
 */
static void process_video(struct a12_state* S)
{
	if (!process_mac(S))
		return;

/* in_channel is used to track if we are waiting for the header or not */
	if (S->in_channel == -1){
		uint32_t stream;
		S->in_channel = S->decode[0];
		unpack_u32(&stream, &S->decode[1]);
		unpack_u16(&S->left, &S->decode[5]);
		S->decode_pos = 0;
		debug_print(2,
			"video[%d:%"PRIx32"], left: %"PRIu16, S->in_channel, stream, S->left);
		return;
	}

/* the 'video_frame' structure for the current channel (segment) tracks
 * decode buffer etc. for the current stream */
	struct video_frame* cvf = &S->channels[S->in_channel].unpack_state.vframe;
	struct arcan_shmif_cont* cont = S->channels[S->in_channel].cont;
	if (!S->channels[S->in_channel].cont){
		debug_print(1, "data on unmapped channel");
		reset_state(S);
		return;
	}

/* postprocessing that requires an intermediate decode buffer before pushing */
	if (a12int_buffer_format(cvf->postprocess)){
		size_t left = cvf->inbuf_sz - cvf->inbuf_pos;

		if (left >= S->decode_pos){
			memcpy(&cvf->inbuf[cvf->inbuf_pos], S->decode, S->decode_pos);
			cvf->inbuf_pos += S->decode_pos;
			left -= S->decode_pos;

			if (cvf->inbuf_sz == cvf->inbuf_pos){
				debug_print(2, "decode-buffer size reached");
			}
		}
		else if (left != 0){
			debug_print(1, "overflow, stream length and packet size mismatch");
		}

/* buffer is finished, decode and commit to designated channel context */
		if (left == 0)
			a12int_decode_vbuffer(S, cvf, cont);

		reset_state(S);
		return;
	}

/* if we are in discard state, just continue */
	if (cvf->commit == 255){
		debug_print(2, "discard state, ignore video");
		reset_state(S);
		return;
	}

/* we use a length field that match the width*height so any
 * overflow / wrap tricks won't work */
	if (cvf->inbuf_sz < S->decode_pos){
		debug_print(1, "mischevios client, byte count mismatch "
			"(%"PRIu16" - %"PRIu16, cvf->inbuf_sz, S->decode_pos);
		reset_state(S);
		return;
	}

	a12int_unpack_vbuffer(S, cvf, cont);
	reset_state(S);
}

static void process_audio(struct a12_state* S)
{
	if (!process_mac(S))
		return;

/* FIXME: header-stage then frame-stage, decode into context based on channel,
 * just copy what is done in process video really */
}

static void process_binary(struct a12_state* S)
{
	if (!process_mac(S))
		return;

/* FIXME: forward as descriptor and stream into/out from it, or dump to memtemp
 * and read full first */
}

void a12_set_destination(
	struct a12_state* S, struct arcan_shmif_cont* wnd, int chid)
{
	if (!S){
		debug_print(1, "invalid set_destination call");
		return;
	}

	if (chid != 0){
		debug_print(1, "multi-channel support unfinished");
		return;
	}

	S->channels[0].cont = wnd;
	S->channels[0].active = false;
}

void
a12_channel_unpack(struct a12_state* S, const uint8_t* buf,
	size_t buf_sz, void* tag, void (*on_event)
	(struct arcan_shmif_cont*, int chid, struct arcan_event*, void*))
{
	if (S->state == STATE_BROKEN)
		return;

/* Unknown state? then we're back waiting for a command packet */
	if (S->left == 0)
		reset_state(S);

/* iteratively flush, we tail- recurse should the need arise, optimization
 * here would be to forward buf immediately if it fits - saves a copy */
	size_t ntr = buf_sz > S->left ? S->left : buf_sz;

	memcpy(&S->decode[S->decode_pos], buf, ntr);
	S->left -= ntr;
	S->decode_pos += ntr;
	buf_sz -= ntr;

/* crypto- fixme: if we are in decipher-state, update cipher with ntr */

/* do we need to buffer more? */
	if (S->left)
		return;

/* otherwise dispatch based on state */
	switch(S->state){
	case STATE_NOPACKET:
		process_nopacket(S);
	break;
	case STATE_CONTROL_PACKET:
		process_control(S);
	break;
	case STATE_VIDEO_PACKET:
		process_video(S);
	break;
	case STATE_AUDIO_PACKET:
		process_audio(S);
	break;
	case STATE_EVENT_PACKET:
		process_event(S, tag, on_event);
	break;
	default:
		debug_print(1, "unknown state");
		S->state = STATE_BROKEN;
		return;
	break;
	}

/* slide window and tail- if needed */
	if (buf_sz)
		a12_channel_unpack(S, &buf[ntr], buf_sz, tag, on_event);
}

size_t
a12_channel_flush(struct a12_state* S, uint8_t** buf)
{
	if (S->buf_ofs == 0 || S->state == STATE_BROKEN || S->cookie != 0xfeedface)
		return 0;

	size_t rv = S->buf_ofs;

/* switch out "output buffer" and return how much there is to send, it is
 * expected that by the next non-0 returning channel_flush, its contents have
 * been pushed to the other side */
	*buf = S->bufs[S->buf_ind];
	S->buf_ofs = 0;
	S->buf_ind = (S->buf_ind + 1) % 2;

	return rv;
}

int
a12_channel_poll(struct a12_state* S)
{
	if (!S || S->state == STATE_BROKEN || S->cookie != 0xfeedface)
		return -1;

	return S->left > 0 ? 1 : 0;
}

/*
 * This function merely performs basic sanity checks of the input sources
 * then forwards to the corresponding _encode method that match the set opts.
 */
void
a12_channel_vframe(struct a12_state* S,
	uint8_t chid, struct shmifsrv_vbuffer* vb, struct a12_vframe_opts opts)
{
	if (!S || S->cookie != 0xfeedface || S->state == STATE_BROKEN)
		return;

/* use a fix size now as the outb- writer lacks queueing and interleaving */
	size_t chunk_sz = 32768;

/* avoid dumb updates */
	size_t x = 0, y = 0, w = vb->w, h = vb->h;
	if (vb->flags.subregion){
		x = vb->region.x1;
		y = vb->region.y1;
		w = vb->region.x2 - x;
		h = vb->region.y2 - y;
	}

/* sanity check against a dumb client here as well */
	if (x + w > vb->w || y + h > vb->h){
		debug_print(1, "client provided bad/broken subregion (%zu+%zu > %zu)"
			"(%zu+%zu > %zu)", x, w, vb->w, y, h, vb->h);
		x = 0;
		y = 0;
		w = vb->w;
		h = vb->h;
	}

/* option: determine region delta, quick xor and early out - protects
 * against buggy clients sending updates even if there are none, not
 * uncommon with retro- like games various toolkits and 3D clients */

/* option: quadtree delta- buffer and only distribute the updated
 * cells? should cut down on memory bandwidth on decode side and
 * on rle/compressing */

/* dealing with each flag:
 * origo_ll - do the coversion in our own encode- stage
 * ignore_alpha - set pxfmt to 3
 * subregion - feed as information to the delta encoder
 * srgb - info to encoder, other leave be
 * vpts - possibly add as feedback to a scheduler and if there is
 *        near-deadline data, send that first or if it has expired,
 *        drop the frame. This is only a real target for game/decode
 *        but that decision can be pushed to the caller.
 *
 * then we have the problem of the meta- area
 */

	debug_print(2, "out vframe: %zu*%zu @%zu,%zu+%zu,%zu", vb->w, vb->h, w, h, x, y);
#define argstr S, vb, opts, x, y, w, h, chunk_sz, chid

	switch(opts.method){
	case VFRAME_METHOD_RAW_RGB565:
		a12int_encode_rgb565(argstr);
	break;
	case VFRAME_METHOD_NORMAL:
		if (vb->flags.ignore_alpha)
			a12int_encode_rgb(argstr);
		else
			a12int_encode_rgba(argstr);
	break;
	case VFRAME_METHOD_RAW_NOALPHA:
		a12int_encode_rgb(argstr);
	break;
	case VFRAME_METHOD_DPNG:
		a12int_encode_dpng(argstr);
	break;
	case VFRAME_METHOD_H264:
		a12int_encode_h264(argstr);
	break;
	default:
		debug_print(0, "unknown format: %d\n", opts.method);
	break;
	}
}

static ssize_t get_file_size(int fd)
{
	struct stat fdinf;
	if (fstat(fd, &fdinf) == -1)
		return -1;

	return fdinf.st_size;
}

void
a12_channel_enqueue(struct a12_state* S, struct arcan_event* ev)
{
	if (!S || S->cookie != 0xfeedface || !ev)
		return;

	int transfer_fd = -1;
	ssize_t transfer_sz = -1;

/* ignore descriptor- passing events for the time being as they add
 * queueing requirements, possibly compression and so on */
	if (arcan_shmif_descrevent(ev)){
		char msg[512];
		debug_print(1, "ignoring descriptor event: %s",
			arcan_shmif_eventstr(ev, msg, 512));

		switch (ev->tgt.kind){
			case TARGET_COMMAND_STORE:
			case TARGET_COMMAND_BCHUNK_OUT:
/* this means the OTHER side should provide us with data */
			break;
			case TARGET_COMMAND_RESTORE:
			case TARGET_COMMAND_BCHUNK_IN:
/* this means the OTHER side should receive data from us */
			break;
			case TARGET_COMMAND_FONTHINT:
/* this MAY mean the OTHER side should receive data from us,
 * since it is a font we have reasonable expectations on the
 * size and can just throw it in a memory buffer by queueing
 * it outright */
			if (ev->tgt.ioevs[0].iv != -1){
				transfer_fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, false);
				transfer_sz = get_file_size(transfer_fd);
				if (transfer_sz <= 0){
					debug_print(1, "ignoring font-transfer, couldn't resolve source");
					return;
				}
			}
			break;
			case TARGET_COMMAND_NEWSEGMENT:
/* when forwarded, this means not more than relay the info about
 * the event - what is also needed is for the corresponding side
 * (server or client) to set new local primitives and treat them
 * as a new channel */
			break;
			default:
			break;
		}
	}

/*
 * MAC and cipher state is managed in the append-outb stage
 */
	uint8_t outb[header_sizes[STATE_EVENT_PACKET]];
	step_sequence(S, outb);

	ssize_t step = arcan_shmif_eventpack(
		ev, &outb[SEQUENCE_NUMBER_SIZE], sizeof(outb) - SEQUENCE_NUMBER_SIZE);
	if (-1 == step)
		return;

	a12int_append_out(S,
		STATE_EVENT_PACKET, outb, step + SEQUENCE_NUMBER_SIZE, NULL, 0);

	debug_print(2, "enqueue event %s", arcan_shmif_eventstr(ev, NULL, 0));
}
