#include <arcan_shmif.h>
#include "a12.h"
#include "blake2.h"
#include <inttypes.h>
#include <string.h>

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

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

#define DECODE_BUFFER_CAP 9000

#ifndef debug_print
#define debug_print(fmt, ...) \
            do { if (DEBUG) fprintf(stderr, "%s:%d:%s(): " fmt "\n", \
						"a12:", __LINE__, __func__,##__VA_ARGS__); } while (0)
#endif

enum {
	STATE_NOPACKET = 0,
	STATE_CONTROL_PACKET,
	STATE_PREHEADER,
	STATE_EVENT_PACKET,
	STATE_AUDIO_PACKET,
	STATE_VIDEO_PACKET,
	STATE_BLOB_PACKET,
	STATE_BROKEN
};

/*
 * Notes for dealing with A/W/B -
 *  need to add functions to set destination buffers for that
 *  immediately, and if there's any kind of recovery etc. function
 *  needed to accommodate the state transition in case of buffer
 *  invalidation.
 */

struct a12_state {
/* we need to prepend this when we build the next MAC */
	uint8_t last_mac_out[MAC_BLOCK_SZ];
	uint8_t last_mac_in[MAC_BLOCK_SZ];

/* data needed to synthesize the next package */
	uint64_t current_seqnr;
	uint64_t last_seen_seqnr;

/* populate and forwarded output buffer */
	size_t buf_sz[2];
	uint8_t* bufs[2];
	uint8_t buf_ind;
	size_t buf_ofs;

/* fixed size incoming buffer as either the compressed decoders need to buffer
 * and request output store, or we have a known 'we need to decode this much' */
	uint8_t decode[9000];
	size_t decode_pos;
	size_t left;
	uint8_t state;

/* overflow state tracking cookie */
	volatile uint32_t cookie;

/* built at initial setup, then copied out for every time we add data */
	blake2bp_state mac_init, mac_dec;

/* when the channel has switched to a streamcipher, this is set to true */
	bool in_encstate;
};

static uint8_t* grow_array(uint8_t* dst, size_t* cur_sz, size_t new_sz)
{
	if (new_sz < *cur_sz)
		return dst;

	uint8_t* res = DYNAMIC_REALLOC(dst, new_sz);
	if (!res){
		return dst;
	}

	*cur_sz = new_sz;
	return res;
}

/*
 * Used when a full byte buffer for a packet has been prepared, important
 * since it will also encrypt, generate MAC and add to buffer prestate
 */
static void append_outb(struct a12_state* S, uint8_t* out, size_t out_sz)
{
/* this means we can just continue our happy stream-cipher and apply to our
 * outgoing data */
	if (S->in_encstate){
/* cipher_update(&S->out_cstream, out, out_sz) */
	}

/* copy preseed state */
	blake2bp_state mac_state = S->mac_init;
	blake2bp_update(&mac_state, S->last_mac_out, MAC_BLOCK_SZ);
	blake2bp_update(&mac_state, out, out_sz);

/* grow buffer if its too small */
	size_t required =
		S->buf_sz[S->buf_ind] + MAC_BLOCK_SZ + out_sz + S->buf_ofs + 1;
	S->bufs[S->buf_ind] = grow_array(
		S->bufs[S->buf_ind],
		&S->buf_sz[S->buf_ind],
		required
	);

/* and if that didn't work, fatal */
	if (S->buf_sz[S->buf_ind] < required){
		return;
	}

/* prepend MAC */
	blake2bp_final(&mac_state, S->last_mac_out, MAC_BLOCK_SZ);
	memcpy(&(S->bufs[S->buf_ind][S->buf_ofs]), S->last_mac_out, MAC_BLOCK_SZ);
	S->buf_ofs += MAC_BLOCK_SZ;

/* and our data block */
	memcpy(&(S->bufs[S->buf_ind][S->buf_ofs]), out, out_sz);
	S->buf_ofs += out_sz;

	debug_print("queued output package: %zu\n", out_sz);
}

static struct a12_state*
a12_setup(uint8_t* authk, size_t authk_sz)
{
	struct a12_state* res = DYNAMIC_MALLOC(sizeof(struct a12_state));
	if (res)
		return NULL;

	*res = (struct a12_state){};
	if (-1 == blake2bp_init_key(&res->mac_init, 16, authk, authk_sz)){
		DYNAMIC_FREE(res);
		return NULL;
	}

	res->cookie = 0xfeedface;

	return res;
}

struct a12_state*
a12_channel_build(uint8_t* authk, size_t authk_sz)
{
	struct a12_state* res = a12_setup(authk, authk_sz);
	if (!res)
		return NULL;

/* then blake2sp_update(S, in, inlen) and blake2sp_final(S, outlen) */
	return res;
}

struct a12_state* a12_channel_open(uint8_t* authk, size_t authk_sz)
{
	struct a12_state* res = a12_setup(authk, authk_sz);
	if (!res)
		return NULL;

/* client starts at half-length */
	res->current_seqnr = (uint64_t)1 << (uint64_t)32;

/* hello authentication packet, we add the seqnr here as there might
 * be encrypt-then-MAC going on in append_outb */
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	memcpy(&outb[MAC_BLOCK_SZ], &res->current_seqnr, sizeof(uint64_t));
	append_outb(res, outb, CONTROL_PACKET_SIZE);
	res->current_seqnr++;

	return res;
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
 * written as tail-recursive, one logical block (at most, or buffering) per call
 */
void
a12_channel_unpack(struct a12_state* S, const uint8_t* buf, size_t buf_sz)
{
	if (S->state == STATE_BROKEN)
		return;

/* Unknown state? then we're back waiting for a command packet */
	if (S->left == 0){
		S->left = MAC_BLOCK_SZ + 1;
		S->state = STATE_NOPACKET;
		S->decode_pos = 0;
		S->mac_dec = S->mac_init;
	}

	size_t ntr = buf_sz > S->left ? S->left : buf_sz;
	if (ntr > DECODE_BUFFER_CAP)
		ntr = DECODE_BUFFER_CAP;

/* first add to scratch buffer */
	memcpy(&S->decode[S->decode_pos], buf, ntr);
	S->left -= ntr;
	S->decode_pos += ntr;

/* special case for NOPACKET as that transitions data-dependent */
	if (S->state == STATE_NOPACKET){
		if (S->left > 0)
			return;

/* copy key, prepend last MAC */
		S->mac_dec = S->mac_init;
		blake2bp_update(&S->mac_dec, S->last_mac_in, MAC_BLOCK_SZ);

/* save last known MAC for later comparison */
		memcpy(S->last_mac_in, S->decode, MAC_BLOCK_SZ);

/* CRYPTO-fixme: if we are in stream cipher mode, decode just the one byte */
		blake2bp_update(&S->mac_dec, &S->decode[MAC_BLOCK_SZ], 1);
		S->state = S->decode[MAC_BLOCK_SZ];
		if (S->state >= STATE_BROKEN){
			debug_print("channel broken, unknown command val: %"PRIu8, S->state);
			return;
		}

		if (S->state == STATE_CONTROL_PACKET)
			S->left = CONTROL_PACKET_SIZE;

/* hacky calculation, based on knowledge about the shmif- evpack, the real
 * version is on hold, see readme for explanation */
		else if (S->state == STATE_EVENT_PACKET)
			S->left = sizeof(struct arcan_event) + 2 + 8 + 1;

/* actual length comes in subheader so wait until then */
		else if (
			S->state == STATE_VIDEO_PACKET ||
				S->state == STATE_AUDIO_PACKET || S->state == STATE_BLOB_PACKET){
				S->left = 13;
		}

		S->decode_pos = 0;
	}

/* Buffer criterion filled, everything up to decode_pos is safe */
	if (!S->left){
		switch (S->state){
		case STATE_NOPACKET : break;
		case STATE_CONTROL_PACKET : {
			uint8_t final_mac[MAC_BLOCK_SZ];
			blake2bp_update(&S->mac_dec, S->decode, S->decode_pos);
			blake2bp_final(&S->mac_dec, final_mac, MAC_BLOCK_SZ);

/* Option to continue with broken authentication, ... */
			if (memcmp(final_mac, S->last_mac_in, MAC_BLOCK_SZ) != 0){
				debug_print("authentication mismatch on packet \n");
				S->state = STATE_BROKEN;
				return;
			}

/* crypto-fixme: place to decrypt stream */
			S->state = STATE_NOPACKET;
		}
		break;
		case STATE_EVENT_PACKET :{
			uint8_t final_mac[MAC_BLOCK_SZ];
			blake2bp_update(&S->mac_dec, S->decode, S->decode_pos);
			blake2bp_final(&S->mac_dec, final_mac, MAC_BLOCK_SZ);
			if (memcmp(final_mac, S->last_mac_in, MAC_BLOCK_SZ) != 0){
				debug_print("authentication mismatch on packet\n");
				S->state = STATE_BROKEN;
				return;
			}

			uint8_t chid;
			struct arcan_event ev;
			memcpy(&S->last_seen_seqnr, S->decode, sizeof(uint64_t));
			memcpy(&chid, &S->decode[8], 1);
			arcan_shmif_eventunpack(&S->decode[9], sizeof(struct arcan_event)+2, &ev);
/* if not descrevent, forward to parent- for interpretation */

			S->state = STATE_NOPACKET;
		}
		break;
		case STATE_VIDEO_PACKET : break;
		case STATE_AUDIO_PACKET : break;
		case STATE_BLOB_PACKET : break;
		default:
		break;
		}
	}

	buf += ntr;
	buf_sz -= ntr;
	if (buf_sz)
		a12_channel_unpack(S, buf, buf_sz);
}

size_t
a12_channel_flush(struct a12_state* S, uint8_t** buf)
{
	if (S->buf_ofs == 0 || S->state == STATE_BROKEN || S->cookie != 0xfeedface)
		return 0;

	size_t rv = S->buf_ofs;

	*buf = S->bufs[S->buf_ind];
	S->buf_ofs = 0;
	S->buf_ind = (S->buf_ind + 1) % 2;

	return rv;
}

int
a12_channel_poll(struct a12_state* S)
{
	if (S->state == STATE_BROKEN)
		return -1;

	return 0;
}

void
a12_channel_enqueue(struct a12_state* S, struct arcan_event* ev)
{
	if (!S || S->cookie != 0xfeedface || !ev)
		return;

/* ignore descriptor- passing events for the time being as they add
 * queueing requirements, possibly compression and so on */
	if (arcan_shmif_descrevent(ev)){
		char msg[512];
		struct arcan_event aev = *ev;
		debug_print("ignoring descriptor event: %s\n",
			arcan_shmif_eventstr(&aev, msg, 512));

		return;
	}

	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	memcpy(&outb[MAC_BLOCK_SZ], &S->current_seqnr, sizeof(uint64_t));
	append_outb(S, outb, CONTROL_PACKET_SIZE);
	S->current_seqnr++;
}
