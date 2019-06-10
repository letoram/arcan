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

int a12_trace_targets = 0;
FILE* a12_trace_dst = NULL;

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

static uint8_t* grow_array(uint8_t* dst, size_t* cur_sz, size_t new_sz, int ind)
{
	if (new_sz < *cur_sz)
		return dst;

/* pick the nearest higher power of 2 for good measure */
	size_t pow = 1;
	while (pow < new_sz)
		pow *= 2;

/* wrap around? give up */
	if (pow < new_sz){
		a12int_trace(A12_TRACE_SYSTEM, "possible queue size exceeded");
		free(dst);
		*cur_sz = 0;
		return NULL;
	}

	new_sz = pow;

	a12int_trace(A12_TRACE_ALLOC,
		"grow outqueue(%d) %zu => %zu", ind, *cur_sz, new_sz);
	uint8_t* res = DYNAMIC_REALLOC(dst, new_sz);
	if (!res){
		a12int_trace(A12_TRACE_SYSTEM, "couldn't grow queue");
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
void a12int_append_out(struct a12_state* S, uint8_t type,
	uint8_t* out, size_t out_sz, uint8_t* prepend, size_t prepend_sz)
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
		required,
		S->buf_ind
	);

/* and if that didn't work, fatal */
	if (S->buf_sz[S->buf_ind] < required){
		a12int_trace(A12_TRACE_SYSTEM,
			"realloc failed: size (%zu) vs required (%zu)", S->buf_sz[S->buf_ind], required);

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

	header_sizes[STATE_EVENT_PACKET] = evsz + SEQUENCE_NUMBER_SIZE + 1;
	init = true;
}

struct a12_state* a12_build(uint8_t* authk, size_t authk_sz)
{
	a12_init();

	struct a12_state* res = a12_setup(authk, authk_sz);
	if (!res)
		return NULL;

	return res;
}

struct a12_state* a12_open(uint8_t* authk, size_t authk_sz)
{
	a12_init();

	struct a12_state* S = a12_setup(authk, authk_sz);
	if (!S)
		return NULL;

/* send initial hello packet */
	a12int_trace(A12_TRACE_MISSING, "authentication material in Hello");
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	step_sequence(S, outb);

	outb[17] = 0;

	a12int_trace(A12_TRACE_SYSTEM, "channel open, add control packet");
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);

	return S;
}

void
a12_channel_close(struct a12_state* S)
{
	if (!S || S->cookie != 0xfeedface){
		return;
	}

	if (S->channels[S->out_channel].active){
		S->channels[S->out_channel].cont = NULL;
		S->channels[S->out_channel].active = false;
	}

	a12int_trace(A12_TRACE_SYSTEM, "closing channel (%"PRIu8")", S->out_channel);
}

bool
a12_free(struct a12_state* S)
{
	if (!S || S->cookie != 0xfeedface){
		return false;
	}

	for (size_t i = 0; i < 256; i++){
		if (S->channels[S->out_channel].active){
			a12int_trace(A12_TRACE_SYSTEM, "free with channel (%zu) active", i);
			return false;
		}
	}

	a12int_trace(A12_TRACE_ALLOC, "a12-state machine freed");
	DYNAMIC_FREE(S->bufs[0]);
	DYNAMIC_FREE(S->bufs[1]);
	*S = (struct a12_state){};
	S->cookie = 0xdeadbeef;

	DYNAMIC_FREE(S);
	return true;
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
		a12int_trace(A12_TRACE_SYSTEM,
			"channel broken, unknown command val: %"PRIu8, S->state);
		S->state = STATE_BROKEN;
		return;
	}

	a12int_trace(A12_TRACE_TRANSFER,
		"left: %"PRIu16", state: %"PRIu8, S->left, S->state);
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
		a12int_trace(A12_TRACE_CRYPTO, "authentication mismatch on packet");
		S->state = STATE_BROKEN;
		return false;
	}

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
		a12int_trace(A12_TRACE_DEBUG, "no segment mapped on channel");
		return;
	}

	a12int_trace(A12_TRACE_MISSING, "binary stream not implemented");
/*
 * if there is a checksum, ask the local cache process and see if we know
 * about it already, if so, cancel the binary stream and substitute in the
 * copy we get from the cache, but still need to process and discard
 * incoming packages in the meanwhile.
 */
}

static void command_audioframe(struct a12_state* S)
{
	uint8_t channel = S->decode[16];
	struct audio_frame* aframe = &S->channels[channel].unpack_state.aframe;
	struct arcan_shmif_cont* cont = S->channels[channel].cont;

	aframe->format = S->decode[22];
	aframe->encoding = S->decode[23];
	aframe->channels = S->decode[22];
	unpack_u16(&aframe->nsamples, &S->decode[24]);
	unpack_u32(&aframe->rate, &S->decode[26]);
	S->in_channel = -1;

/* developer error (or malicious client), set to skip decode/playback */
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM,
			"no segment mapped on channel %d", (int)channel);
		aframe->commit = 255;
		return;
	}

/* this requires an extended resize (theoretically, practically not),
 * and in those cases we want to copy-out the vbuffer state if set and
 * then rebuild */
	if (cont->samplerate != aframe->rate){
		a12int_trace(A12_TRACE_MISSING,
			"rate mismatch: %zu <-> %"PRIu32, cont->samplerate, aframe->rate);
	}

/* format should be paired against AUDIO_SAMPLE_TYPE */
	if (aframe->channels != ARCAN_SHMIF_ACHANNELS){
		a12int_trace(A12_TRACE_MISSING, "channel format repack");
	}

/* just plug the samples into the normal abuf- as part of the shmif-cont */
/* normal dynamic rate adjustment compensating for clock drift etc. go here */
}

static void command_newchannel(
struct a12_state* S, void (*on_event)
	(struct arcan_shmif_cont*, int chid, struct arcan_event*, void*), void* tag)
{
	uint8_t channel = S->decode[16];
	uint8_t new_channel = S->decode[18];
	uint8_t type = S->decode[19];
	uint8_t direction = S->decode[20];
	uint32_t cookie;
	unpack_u32(&cookie, &S->decode[21]);

	a12int_trace(A12_TRACE_ALLOC, "new channel: %"PRIu8" => %"PRIu8""
		", kind: %"PRIu8", cookie: %"PRIu8"", channel, new_channel, type, cookie);

/* helper srv need to perform the additional segment push here,
 * so our 'file descriptor' in slot 0 is actually the new channel id */
	struct arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_NEWSEGMENT
	};
	ev.tgt.ioevs[0].iv = new_channel;
	ev.tgt.ioevs[1].iv = direction != 0;
	ev.tgt.ioevs[2].iv = type;
	ev.tgt.ioevs[3].uiv = cookie;

	on_event(S->channels[channel].cont, channel, &ev, tag);
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
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=videoframe_header:status=EINVAL:channel=%d", (int) channel);
		vframe->commit = 255;
		return;
	}

	if (vframe->sw != cont->w || vframe->sh != cont->h){
		arcan_shmif_resize(cont, vframe->sw, vframe->sh);
		if (vframe->sw != cont->w || vframe->sh != cont->h){
			a12int_trace(A12_TRACE_SYSTEM, "parent size rejected");
			vframe->commit = 255;
		}
		else
			a12int_trace(A12_TRACE_VIDEO, "kind=resized:channel=%d:"
				"new_w=%zu:new_h=%zu", (int) channel, (size_t) vframe->sw, (size_t) vframe->sh);
	}

	a12int_trace(A12_TRACE_VIDEO, "kind=frame_header:method=%d:"
		"source_w=%zu:source_h=%zu:dst_w=%zu:dst_h=%zu:x=%zu,y=%zu",
		(int) vframe->postprocess, (size_t) vframe->w, (size_t) vframe->h,
		(size_t) vframe->sw, (size_t) vframe->sh, (size_t) vframe->x, (size_t) vframe->y
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
		a12int_trace(A12_TRACE_TRANSFER,
			"row-length: %zu at buffer pos %"PRIu32, vframe->row_left, vframe->inbuf_pos);
	}
	else {
		if (vframe->expanded_sz > vframe->w * vframe->h * sizeof(shmif_pixel)){
			vframe->commit = 255;
			a12int_trace(A12_TRACE_SYSTEM,
				"incoming frame exceeding reasonable constraints");
			return;
		}
		if (vframe->inbuf_sz > vframe->expanded_sz){
			vframe->commit = 255;
			a12int_trace(A12_TRACE_SYSTEM,
				"incoming buffer expands to less than target");
			return;
		}

		vframe->out_pos = vframe->y * cont->pitch + vframe->x;
		vframe->inbuf_pos = 0;
		vframe->inbuf = malloc(vframe->inbuf_sz);
		if (!vframe->inbuf){
			a12int_trace(A12_TRACE_ALLOC,
				"couldn't allo cate intermediate buffer store");
			return;
		}
		vframe->row_left = vframe->w;
		a12int_trace(A12_TRACE_VIDEO, "compressed buffer in");
	}
}

static bool queue_binary_stream(struct a12_state* S, struct arcan_event* ev)
{
	switch (ev->tgt.kind){
		case TARGET_COMMAND_STORE:
		case TARGET_COMMAND_BCHUNK_OUT:
		case TARGET_COMMAND_RESTORE:
		case TARGET_COMMAND_BCHUNK_IN:{
			char msg[512];
			a12int_trace(A12_TRACE_MISSING,
				"ignoring descriptor event: %s", arcan_shmif_eventstr(ev, msg, 512));
			return true;
		}
		break;
		case TARGET_COMMAND_FONTHINT:
		if (ev->tgt.ioevs[0].iv != -1){
			a12int_trace(A12_TRACE_MISSING,
				"ignoring font descriptor, should be blocking transfer");
		}
		case TARGET_COMMAND_NEWSEGMENT:
			a12int_trace(A12_TRACE_SYSTEM,
				"newsegment- event forwarded, api use error");
		return false;
		break;
		default:
		break;
	}
/* if S->binary_pending */
	return false;
}

/*
 * Control command,
 * current MAC calculation in s->mac_dec
 */
static void process_control(struct a12_state* S, void (*on_event)
	(struct arcan_shmif_cont*, int chid, struct arcan_event*, void*), void* tag)
{
	if (!process_mac(S))
		return;

/* ignore these for now
	uint64_t last_seen = S->decode[0];
	uint8_t entropy[8] = S->decode[8];
	uint8_t channel = S->decode[16];
 */

	uint8_t command = S->decode[17];

	switch(command){
	case COMMAND_HELLO:
		a12int_trace(A12_TRACE_MISSING, "Key negotiation, verification");
	/*
	 * CRYPTO- fixme: Update keymaterial etc. here.
	 * Verify that this is the first packet.
	 */
	break;
	case COMMAND_SHUTDOWN:
	/* terminate specific channel */
	break;
	case COMMAND_NEWCH:
		command_newchannel(S, on_event, tag);
	break;
	case COMMAND_CANCELSTREAM:
		a12int_trace(A12_TRACE_MISSING, "Stream cancellation");
	break;
	case COMMAND_PING:
		a12int_trace(A12_TRACE_MISSING, "Check ping packet");
	break;
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
		a12int_trace(A12_TRACE_SYSTEM, "Unknown message type: %d", (int)command);
	break;
	}

	reset_state(S);
}

static void process_event(struct a12_state* S, void* tag,
	void (*on_event)(
		struct arcan_shmif_cont* wnd, int chid, struct arcan_event*, void*))
{
	if (!process_mac(S))
		return;

	uint8_t channel = S->decode[8];

	struct arcan_event aev;
	unpack_u64(&S->last_seen_seqnr, S->decode);

	if (-1 == arcan_shmif_eventunpack(
		&S->decode[SEQUENCE_NUMBER_SIZE+1],
		S->decode_pos-SEQUENCE_NUMBER_SIZE-1, &aev))
	{
		a12int_trace(A12_TRACE_SYSTEM, "broken event packet received");
	}
	else if (on_event){
		a12int_trace(A12_TRACE_EVENT, "unpack event to %d", channel);
		on_event(S->channels[channel].cont, channel, &aev, tag);
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
		a12int_trace(A12_TRACE_VIDEO,
			"kind=header:channel=%"PRIu16":size=%"PRIu16, S->in_channel, S->left);
		return;
	}

/* the 'video_frame' structure for the current channel (segment) tracks
 * decode buffer etc. for the current stream */
	struct video_frame* cvf = &S->channels[S->in_channel].unpack_state.vframe;
	struct arcan_shmif_cont* cont = S->channels[S->in_channel].cont;
	if (!S->channels[S->in_channel].cont){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:source=video:type=EINVALCH:val=%d", (int) S->in_channel);
		reset_state(S);
		return;
	}

/* postprocessing that requires an intermediate decode buffer before pushing */
	if (a12int_buffer_format(cvf->postprocess)){
		size_t left = cvf->inbuf_sz - cvf->inbuf_pos;
		a12int_trace(A12_TRACE_VIDEO,
			"kind=decbuf:channel=%"PRIu16":size=%"PRIu16":left=%zu",
			S->in_channel, S->decode_pos, left
		);

/* buffer and slide? */
		if (left >= S->decode_pos){
			memcpy(&cvf->inbuf[cvf->inbuf_pos], S->decode, S->decode_pos);
			cvf->inbuf_pos += S->decode_pos;
			left -= S->decode_pos;
		}
/* other option is to terminate here as the client is misbehaving */
		else if (left != 0){
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=error:source=video:channel=%"PRIu16":type=EOVERFLOW", S->in_channel);
			reset_state(S);
		}

/* buffer is finished, decode and commit to designated channel context
 * unless it has already been marked as something to ignore and discard */
		if (left == 0 && cvf->commit != 255){
			a12int_trace(
				A12_TRACE_VIDEO, "kind=decbuf:channel=%d:commit", (int)S->in_channel);
			a12int_decode_vbuffer(S, cvf, cont);
		}

		reset_state(S);
		return;
	}

/* if we are in discard state, just continue */
	if (cvf->commit == 255){
		a12int_trace(A12_TRACE_VIDEO, "kind=discard");
		reset_state(S);
		return;
	}

/* we use a length field that match the width*height so any
 * overflow / wrap tricks won't work */
	if (cvf->inbuf_sz < S->decode_pos){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:source=video:channel=%"PRIu16":type=EOVERFLOW", S->in_channel);
		reset_state(S);
		return;
	}

/* finally unpack the raw video buffer */
	a12int_unpack_vbuffer(S, cvf, cont);
	reset_state(S);
}

static void process_audio(struct a12_state* S)
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
		a12int_trace(A12_TRACE_AUDIO,
			"audio[%d:%"PRIx32"], left: %"PRIu16, S->in_channel, stream, S->left);
		return;
	}

/* the 'audio_frame' structure for the current channel (segment) only
 * contains the metadata, we use the mapped shmif- segment to actually
 * buffer, assuming we have no compression */
	struct audio_frame* caf = &S->channels[S->in_channel].unpack_state.aframe;
	struct arcan_shmif_cont* cont = S->channels[S->in_channel].cont;
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM,
			"audio data on unmapped channel (%d)", (int) S->in_channel);
		reset_state(S);
		return;
	}

/* passed the header stage, now it's the data block, make sure the segment
 * has registered that it can provide audio */
	if (!cont->audp){
		a12int_trace(A12_TRACE_AUDIO,
			"frame-resize, rate: %"PRIu32", channels: %"PRIu8,
			caf->rate, caf->channels
		);
		if (!arcan_shmif_resize_ext(cont,
			cont->w, cont->h, (struct shmif_resize_ext){
				.abuf_sz = 1024, .samplerate = caf->rate,
				.abuf_cnt = 16, .vbuf_cnt = 1
			})){
			a12int_trace(A12_TRACE_ALLOC, "frame-resize failed");
			caf->commit = 255;
			return;
		}
	}

/* Flush out into caf abuffer, assumed that the context has been set
 * to match the defined source format in a previous stage. Resampling
 * might be needed here, both for rate and for drift/buffer */
	size_t samples_in = S->decode_pos >> 1;
	size_t pos = 0;

/* assumed s16, stereo for now, if the sender didn't align properly, shame */
	while (samples_in > 1){
		int16_t l, r;
		unpack_s16(&l, &S->decode[pos]);
		pos += 2;
		unpack_s16(&r, &S->decode[pos]);
		pos += 2;
		cont->audp[cont->abufpos++] = SHMIF_AINT16(l);
		cont->audp[cont->abufpos++] = SHMIF_AINT16(r);
		samples_in -= 2;

		if (cont->abufcount - cont->abufpos <= 1){
			a12int_trace(A12_TRACE_AUDIO,
				"forward %zu samples", (size_t) cont->abufpos);
			arcan_shmif_signal(cont, SHMIF_SIGAUD);
		}
	}

/* now we can subtract the number of SAMPLES from the audio stream
 * packet, when that reases zero we reset state, this incorrectly
 * assumes 2 channels though */
	caf->nsamples -= S->decode_pos >> 1;
	if (!caf->nsamples && cont->abufused){
/* might also be a slush buffer left */
		if (cont->abufused)
			arcan_shmif_signal(cont, SHMIF_SIGAUD);
	}

	a12int_trace(A12_TRACE_TRANSFER,
		"audio packet over, samples left: %zu", (size_t) caf->nsamples);
	reset_state(S);
}

static void process_binary(struct a12_state* S)
{
	if (!process_mac(S))
		return;

	a12int_trace(A12_TRACE_MISSING, "binary packet / header incomplete");
}

void a12_set_destination(
struct a12_state* S, struct arcan_shmif_cont* wnd, uint8_t chid)
{
	if (!S){
		a12int_trace(A12_TRACE_DEBUG, "invalid set_destination call");
		return;
	}

	S->channels[chid].cont = wnd;
	S->channels[chid].active = wnd != NULL;
}

void
a12_unpack(struct a12_state* S, const uint8_t* buf,
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
		process_control(S, on_event, tag);
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
		a12int_trace(A12_TRACE_SYSTEM, "unknown state");
		S->state = STATE_BROKEN;
		return;
	break;
	}

/* slide window and tail- if needed */
	if (buf_sz)
		a12_unpack(S, &buf[ntr], buf_sz, tag, on_event);
}

size_t
a12_flush(struct a12_state* S, uint8_t** buf)
{
	if (S->state == STATE_BROKEN || S->cookie != 0xfeedface)
		return 0;

/* nothing in the outgoing buffer? then we can pull in whatever
 * data transfer is pending */
	if (S->buf_ofs == 0){
		return 0;
	}

	size_t rv = S->buf_ofs;
	int old_ind = S->buf_ind;

/* switch out "output buffer" and return how much there is to send, it is
 * expected that by the next non-0 returning channel_flush, its contents have
 * been pushed to the other side */
	*buf = S->bufs[S->buf_ind];
	S->buf_ofs = 0;
	S->buf_ind = (S->buf_ind + 1) % 2;
	a12int_trace(A12_TRACE_ALLOC, "locked %d, new buffer: %d", old_ind, S->buf_ind);

	return rv;
}

int
a12_poll(struct a12_state* S)
{
	if (!S || S->state == STATE_BROKEN || S->cookie != 0xfeedface)
		return -1;

	return S->left > 0 ? 1 : 0;
}

void
a12_channel_new(struct a12_state* S,
	uint8_t chid, uint8_t segkind, uint32_t cookie)
{
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	step_sequence(S, outb);

	outb[17] = COMMAND_NEWCH;
	outb[18] = chid;
	outb[19] = segkind;
	outb[20] = 0;
	pack_u32(cookie, &outb[21]);
	step_sequence(S, outb);

	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

void
a12_set_channel(struct a12_state* S, uint8_t chid)
{
	a12int_trace(A12_TRACE_SYSTEM, "channel_out=%"PRIu8, chid);
	S->out_channel = chid;
}

void
a12_channel_aframe(struct a12_state* S,
		shmif_asample* buf,
		size_t n_samples,
		struct a12_aframe_cfg cfg,
		struct a12_aframe_opts opts)
{
	if (!S || S->cookie != 0xfeedface || S->state == STATE_BROKEN)
		return;

/* use a fix size now as the outb- writer lacks queueing and interleaving */
	size_t chunk_sz = 16428;

	a12int_trace(A12_TRACE_AUDIO,
		"encode %zu samples @ %"PRIu32" Hz /%"PRIu8" ch",
		n_samples, cfg.samplerate, cfg.channels
	);
	a12int_encode_araw(S, S->out_channel, buf, n_samples/2, cfg, opts, chunk_sz);
}

/*
 * This function merely performs basic sanity checks of the input sources
 * then forwards to the corresponding _encode method that match the set opts.
 */
void
a12_channel_vframe(struct a12_state* S,
	struct shmifsrv_vbuffer* vb, struct a12_vframe_opts opts)
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
		a12int_trace(A12_TRACE_SYSTEM,
			"client provided bad/broken subregion (%zu+%zu > %zu)"
			"(%zu+%zu > %zu)", x, w, vb->w, y, h, vb->h
		);
		x = 0;
		y = 0;
		w = vb->w;
		h = vb->h;
	}

/* option: quadtree delta- buffer and only distribute the updated
 * cells? should cut down on memory bandwidth on decode side and
 * on rle/compressing */

/* dealing with each flag:
 * origo_ll - do the coversion in our own encode- stage
 * ignore_alpha - set pxfmt to 3
 * subregion - feed as information to the delta encoder
 * srgb - info to encoder, other leave be
 * vpts - tag into the system as it is used for other things
 *
 * then we have the problem of the meta- area that should take
 * other package types when we get there
 */
	a12int_trace(A12_TRACE_VIDEO,
		"out vframe: %zu*%zu @%zu,%zu+%zu,%zu", vb->w, vb->h, w, h, x, y);
#define argstr S, vb, opts, x, y, w, h, chunk_sz, S->out_channel

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
/*
 * FLIV and dav1d missing
 */
	default:
		a12int_trace(A12_TRACE_SYSTEM, "unknown format: %d\n", opts.method);
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

static bool setup_new_channel(struct a12_state* S, struct arcan_event* ev)
{
	return true;
}

bool
a12_channel_enqueue(struct a12_state* S, struct arcan_event* ev)
{
	if (!S || S->cookie != 0xfeedface || !ev)
		return false;

/* binary streams gets added to their own 'add when there is output space'
 * while newsegment has its entirely own treatment */
	if (arcan_shmif_descrevent(ev)){
/* this one should have already been handled through a12_channel_new */
		if (ev->tgt.kind == TARGET_COMMAND_NEWSEGMENT)
			return true;
		else
			return queue_binary_stream(S, ev);
	}

/*
 * MAC and cipher state is managed in the append-outb stage
 */
	uint8_t outb[header_sizes[STATE_EVENT_PACKET]];
	size_t hdr = SEQUENCE_NUMBER_SIZE + 1;
	outb[SEQUENCE_NUMBER_SIZE] = S->out_channel;
	step_sequence(S, outb);

	ssize_t step = arcan_shmif_eventpack(ev, &outb[hdr], sizeof(outb) - hdr);
	if (-1 == step)
		return true;

	a12int_append_out(S, STATE_EVENT_PACKET, outb, step + hdr, NULL, 0);

	a12int_trace(A12_TRACE_EVENT,
		"kind=enqueue:eventstr=%s", arcan_shmif_eventstr(ev, NULL, 0));
	return true;
}

void
a12_set_trace_level(int mask, FILE* dst)
{
	a12_trace_targets = mask;
	a12_trace_dst = dst;
}

static const char* groups[] = {
	"video",
	"audio",
	"system",
	"event",
	"transfer",
	"debug",
	"missing",
	"alloc",
	"crypto",
	"vdetail",
	"btransfer"
};

static unsigned i_log2(uint32_t n)
{
	unsigned res = 0;
	while (n >>= 1) res++;
	return res;
}

const char* a12int_group_tostr(int group)
{
	unsigned ind = i_log2(group);
	if (ind > sizeof(groups)/sizeof(groups[0]))
		return "bad";
	else
		return groups[ind];
}
