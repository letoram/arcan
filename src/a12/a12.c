/*
 * Copyright: 2017-2020, Björn Ståhl
 * Description: A12 protocol state machine, main translation unit.
 * Maintains connection state, multiplex and demultiplex then routes
 * to the corresponding decoding/encode stages.
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://arcan-fe.com
 */
/* shared state machine structure */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <inttypes.h>
#include <string.h>
#include <math.h>

#include "a12.h"
#include "a12_int.h"

#include "a12_decode.h"
#include "a12_encode.h"
#include "arcan_mem.h"
#include "external/chacha.c"
#include "external/x25519.h"

#include <sys/mman.h>
#include <sys/types.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

int a12_trace_targets = 0;
FILE* a12_trace_dst = NULL;

/* generated on first init call, ^ with keys when not in use to prevent
 * a read gadget to extract without breaking ASLR */
static uint8_t priv_key_cookie[32];

static int header_sizes[] = {
	MAC_BLOCK_SZ + 8 + 1, /* The outer frame */
	CONTROL_PACKET_SIZE,
	0, /* EVENT size is filled in at first open */
	1 + 4 + 2, /* VIDEO partial: ch, stream, len */
	1 + 4 + 2, /* AUDIO partial: ch, stream, len */
	1 + 4 + 2, /* BINARY partial: ch, stream, len */
	MAC_BLOCK_SZ + 8 + 1, /* First packet server side */
	0
};

extern void arcan_random(uint8_t* dst, size_t);

size_t a12int_header_size(int kind)
{
	return header_sizes[kind];
}

static void unlink_node(struct a12_state*, struct blob_out*);

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

/* init the new region */
	memset(&res[*cur_sz], '\0', new_sz - *cur_sz);

	*cur_sz = new_sz;
	return res;
}

static void toggle_key_mask(uint8_t key[static 32])
{
	for (size_t i = 0; i < 32; i++)
		key[i] ^= priv_key_cookie[i];
}

/* never permit this to be traced in a normal build */
static void trace_crypto_key(bool srv, const char* domain, uint8_t* buf, size_t sz)
{
#ifdef _DEBUG
	char conv[sz * 3 + 2];
	for (size_t i = 0; i < sz; i++){
		sprintf(&conv[i * 3], "%02X%s", buf[i], i == sz - 1 ? "" : ":");
	}
	a12int_trace(A12_TRACE_CRYPTO, "%s%s:key=%s", srv ? "server:" : "client:", domain, conv);
#endif
}

/* set the LAST SEEN sequence number in a CONTROL message */
static void step_sequence(struct a12_state* S, uint8_t* outb)
{
	pack_u64(S->last_seen_seqnr, outb);
}

static void fail_state(struct a12_state* S)
{
#ifndef _DEBUG
/* overwrite all relevant state, dealloc mac/chacha */
#endif
	S->state = STATE_BROKEN;
}

static void send_hello_packet(struct a12_state* S,
	int mode, uint8_t pubk[static 32], uint8_t entropy[static 8])
{
/* construct the reply with the proper public key */
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	step_sequence(S, outb);
	memcpy(&outb[8], entropy, 8);
	memcpy(&outb[21], pubk, 32);

/* channel-id is empty */
	outb[17] = COMMAND_HELLO;
	outb[18] = ASHMIF_VERSION_MAJOR;
	outb[19] = ASHMIF_VERSION_MINOR;
	outb[20] = mode;

/* send it back to client */
	a12int_append_out(S,
		STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
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
 * place where we perform an unavoidable copy unless we want interleaving (and
 * then it becomes expensive to perform). Practically speaking it is not that
 * bad to encrypt accordingly, it is a stream cipher afterall, BUT having a
 * continous MAC screws with that. Now since we have a few bytes entropy and a
 * counter as part of the message, replay attacks won't work BUT any
 * reordering would then still need to account for rekeying.
 */
void a12int_append_out(struct a12_state* S, uint8_t type,
	uint8_t* out, size_t out_sz, uint8_t* prepend, size_t prepend_sz)
{
	if (S->state == STATE_BROKEN)
		return;

/*
 * QUEUE-slot here,
 * should also have the ability to probe the size of the queue slots
 * so that encoders can react on backpressure
 */
	a12int_trace(A12_TRACE_CRYPTO,
		"type=%d:size=%zu:prepend_size=%zu:ofs=%zu", type, out_sz, prepend_sz, S->buf_ofs);

/* grow write buffer if the block doesn't fit */
	size_t required = S->buf_ofs +
		header_sizes[STATE_NOPACKET] + out_sz + prepend_sz + 1;

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

/* reserve space for the MAC and remember where it starts and ends */
	size_t mac_pos = S->buf_ofs;
	S->buf_ofs += MAC_BLOCK_SZ;
	size_t data_pos = S->buf_ofs;

/* MISSING OPTIMIZATION, extract n bytes of the cipherstream and apply copy
 * operation rather than in-place modification, align with MAC block size and
 * continuously update as we fetch as well */

/* 8 byte sequence number */
	pack_u64(S->current_seqnr++, &dst[S->buf_ofs]);
	S->buf_ofs += 8;

/* 1 byte command data */
	dst[S->buf_ofs++] = type;

/* any possible prepend-to-data block */
	if (prepend_sz){
		memcpy(&dst[S->buf_ofs], prepend, prepend_sz);
		S->buf_ofs += prepend_sz;
	}

/* and our data block */
	memcpy(&dst[S->buf_ofs], out, out_sz);
	S->buf_ofs += out_sz;

	size_t used = S->buf_ofs - data_pos;

/* if we are the client and haven't sent the first authentication request
 * yet, setup the nonce part of the cipher to random and shorten the MAC */
	size_t mac_sz = MAC_BLOCK_SZ;
	if (!S->authentic && !S->server){
		mac_sz >>= 1;
		arcan_random(&dst[mac_sz], mac_sz);

/* depending on flag, we need POLITE, REAL HELLO or full */
		S->authentic = AUTH_FULL_PK;
		if (S->dec_state){
			chacha_set_nonce(S->dec_state, &dst[mac_sz]);
			chacha_set_nonce(S->enc_state, &dst[mac_sz]);
			a12int_trace(A12_TRACE_CRYPTO, "kind=cipher:status=init_nonce");
			if (S->opts->pk_lookup){
				S->authentic = AUTH_REAL_HELLO_SENT;
			}
		}

		trace_crypto_key(S->server, "nonce", &dst[mac_sz], mac_sz);
/* don't forget to add the nonce to the first message MAC */
		blake3_hasher_update(&S->out_mac, &dst[mac_sz], mac_sz);
	}

/* apply stream-cipher to buffer contents */
	if (S->enc_state)
		chacha_apply(S->enc_state, &dst[data_pos], used);

/* update MAC */
	blake3_hasher_update(&S->out_mac, &dst[data_pos], used);

/* sample MAC and write to buffer pos, remember it for debugging - no need to
 * chain separately as 'finalize' is not really finalized */
	blake3_hasher_finalize(&S->out_mac, &dst[mac_pos], mac_sz);
	a12int_trace(A12_TRACE_CRYPTO, "kind=mac_enc:position=%zu", S->out_mac.counter);
	trace_crypto_key(S->server, "mac_enc", &dst[mac_pos], mac_sz);

/* if we have set a function, that will get the buffer immediately and then
 * we set the internal buffering state, this is a short-path that can be used
 * immediately and then we reset it. */
	if (S->opts->sink){
		if (!S->opts->sink(dst, S->buf_ofs, S->opts->sink_tag)){
			fail_state(S);
		}
		S->buf_ofs = 0;
	}
}

static void reset_state(struct a12_state* S)
{
/* the 'reset' from an erroneous state is basically disconnect, just right
 * now it finishes and let validation failures etc. handle that particular
 * scenario */
	S->left = header_sizes[STATE_NOPACKET];
	S->state = STATE_NOPACKET;
	S->decode_pos = 0;
	S->in_channel = -1;
}

static void derive_encdec_key(
	const char* ssecret, size_t secret_len,
	uint8_t out_mac[static BLAKE3_KEY_LEN],
	uint8_t out_srv[static BLAKE3_KEY_LEN],
	uint8_t  out_cl[static BLAKE3_KEY_LEN])
{
	blake3_hasher temp;
	blake3_hasher_init_derive_key(&temp, "arcan-a12 init-packet");
	blake3_hasher_update(&temp, ssecret, secret_len);

/* mac = H(ssecret_kdf) */
	blake3_hasher_finalize(&temp, out_mac, BLAKE3_KEY_LEN);

/* client = H(H(ssecret_kdf)) */
	blake3_hasher_update(&temp, out_mac, BLAKE3_KEY_LEN);
	blake3_hasher_finalize(&temp, out_cl, BLAKE3_KEY_LEN);

/* server = H(H(H(ssecret_kdf))) */
	blake3_hasher_update(&temp, out_cl, BLAKE3_KEY_LEN);
	blake3_hasher_finalize(&temp, out_srv, BLAKE3_KEY_LEN);
}

static void update_keymaterial(
	struct a12_state* S, char* secret, size_t len, uint8_t* nonce)
{
/* KDF mode for building the initial keys */
	uint8_t mac_key[BLAKE3_KEY_LEN];
	uint8_t srv_key[BLAKE3_KEY_LEN];
	uint8_t  cl_key[BLAKE3_KEY_LEN];
	_Static_assert(BLAKE3_KEY_LEN >= MAC_BLOCK_SZ, "misconfigured blake3 size");

	derive_encdec_key(S->opts->secret, len, mac_key, srv_key, cl_key);

	blake3_hasher_init_keyed(&S->out_mac, mac_key);
	blake3_hasher_init_keyed(&S->in_mac,  mac_key);

/* and this will only be used until completed x25519 */
	if (!S->opts->disable_cipher){
		if (!S->dec_state){
			S->dec_state = malloc(sizeof(struct chacha_ctx));
			if (!S->dec_state){
				fail_state(S);
				return;
			}

			S->enc_state = malloc(sizeof(struct chacha_ctx));
			if (!S->enc_state){
				free(S->dec_state);
				fail_state(S);
				return;
			}
		}

/* depending on who initates the connection, the cipher key will be different,
 *
 * server encodes with srv_key and decodes with cl_key
 * client encodes with cl_key and decodes with srv_key
 *
 * two keys derived from the same shared secret is preferred over different
 * positions in the cipherstream to prevent bugs that could affect position
 * stepping to accidentally cause multiple ciphertexts being produced from the
 * same key at the same position.
 *
 * the cipher-state is incomplete as we still need to apply the nonce from the
 * helo packet before the setup is complete. */
		_Static_assert(BLAKE3_KEY_LEN == 16 || BLAKE3_KEY_LEN == 32, "misconfigured blake3 size");
		if (S->server){
			trace_crypto_key(S->server, "enc_key", srv_key, BLAKE3_KEY_LEN);
			trace_crypto_key(S->server, "dec_key", cl_key, BLAKE3_KEY_LEN);

			chacha_setup(S->dec_state, cl_key, BLAKE3_KEY_LEN, 0, 8);
			chacha_setup(S->enc_state, srv_key, BLAKE3_KEY_LEN, 0, 8);
		}
		else {
			trace_crypto_key(S->server, "dec_key", srv_key, BLAKE3_KEY_LEN);
			trace_crypto_key(S->server, "enc_key", cl_key, BLAKE3_KEY_LEN);

			chacha_setup(S->enc_state, cl_key, BLAKE3_KEY_LEN, 0, 8);
			chacha_setup(S->dec_state, srv_key, BLAKE3_KEY_LEN, 0, 8);
		}
	}

/* not all calls will need to set the nonce state, first packets is deferred */
	if (nonce && S->enc_state){
		chacha_set_nonce(S->enc_state, nonce);
		chacha_set_nonce(S->dec_state, nonce);
	}
}

static struct a12_state* a12_setup(struct a12_context_options* opt, bool srv)
{
	struct a12_state* res = DYNAMIC_MALLOC(sizeof(struct a12_state));
	if (!res)
		return NULL;
	*res = (struct a12_state){
		.server = srv
	};

	size_t len = 0;
	if (!opt->secret[0]){
		sprintf(opt->secret, "SETECASTRONOMY");
	}
	len = strlen(opt->secret);
	res->opts = opt;

	update_keymaterial(res, opt->secret, len, NULL);

/* easy-dump for quick debugging (i.e. cmp side vs side to find offset,
 * open/init/replay to step mac construction */
/* #define LOG_MAC_DATA */
#ifdef LOG_MAC_DATA
	FILE* keys = fopen("macraw.key", "w");
	fwrite(mac_key, BLAKE3_KEY_LEN, 1, keys);
	fclose(keys);

	if (srv){
			res->out_mac.log = fopen("srv.macraw.out", "w");
			res->in_mac.log = fopen("srv.macraw.in", "w");
	}
	else{
			res->out_mac.log = fopen("cl.macraw.out", "w");
			res->in_mac.log = fopen("cl.macraw.in", "w");
	}
#endif

	res->cookie = 0xfeedface;

/* start counting binary stream identifiers on 3 (video = 1, audio = 2) */
	res->out_stream = 3;

	return res;
}

static void a12_init()
{
	static bool init;
	if (init)
		return;

	arcan_random(priv_key_cookie, 32);

/* make one nonsense- call first to figure out the current packing size */
	uint8_t outb[512];
	ssize_t evsz = arcan_shmif_eventpack(
		&(struct arcan_event){.category = EVENT_IO}, outb, 512);

	header_sizes[STATE_EVENT_PACKET] = evsz + SEQUENCE_NUMBER_SIZE + 1;
	init = true;
}

struct a12_state* a12_server(struct a12_context_options* opt)
{
	if (!opt)
		return NULL;

	a12_init();

	struct a12_state* res = a12_setup(opt, true);
	if (!res)
		return NULL;

	res->state = STATE_1STSRV_PACKET;
	res->left = header_sizes[res->state];

	return res;
}

struct a12_state* a12_client(struct a12_context_options* opt)
{
	if (!opt)
		return NULL;

	a12_init();
	int mode = 0;
	int state = AUTH_FULL_PK;

	struct a12_state* S = a12_setup(opt, false);
	if (!S)
		return NULL;

/* use x25519? - pull out the public key from the supplied private and set
 * one or two rounds of exchange state, otherwise just mark the connection
 * as preauthenticated should the server reply use the correct PSK */
	uint8_t empty[32] = {0};
	uint8_t outpk[32];

	if (memcmp(empty, opt->priv_key, 32) != 0){
		memcpy(S->keys.real_priv, opt->priv_key, 32);

/* single round, use correct key immediately */
		if (opt->disable_ephemeral_k){
			mode = HELLO_MODE_REALPK;
			state = AUTH_REAL_HELLO_SENT;
			memset(opt->priv_key, '\0', 32);
			x25519_public_key(S->keys.real_priv, outpk);
			trace_crypto_key(S->server, "cl-priv", S->keys.real_priv, 32);
		}

/* double-round, start by generating ephemeral key */
		else {
			mode = HELLO_MODE_EPHEMK;
			x25519_private_key(S->keys.ephem_priv);
			x25519_public_key(S->keys.ephem_priv, outpk);
			state = AUTH_POLITE_HELLO_SENT;
		}

		toggle_key_mask(S->keys.real_priv);
	}

	uint8_t nonce[8];
	arcan_random(nonce, 8);

	trace_crypto_key(S->server, "hello-pub", outpk, 32);
	send_hello_packet(S, mode, outpk, nonce);
	S->authentic = state;

	return S;
}

void
a12_channel_shutdown(struct a12_state* S, const char* last_words)
{
	if (!S || S->cookie != 0xfeedface){
		return;
	}

	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	step_sequence(S, outb);
	outb[16] = S->out_channel;
	outb[17] = COMMAND_SHUTDOWN;
	snprintf((char*)(&outb[18]), CONTROL_PACKET_SIZE - 19, "%s", last_words);

	a12int_trace(A12_TRACE_SYSTEM, "channel open, add control packet");
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

void
a12_channel_close(struct a12_state* S)
{
	if (!S || S->cookie != 0xfeedface){
		return;
	}

	a12int_encode_drop(S, S->out_channel, false);
	a12int_decode_drop(S, S->out_channel, false);

	if (S->channels[S->out_channel].active){
		S->channels[S->out_channel].cont = NULL;
		S->channels[S->out_channel].active = false;
	}

	a12int_trace(A12_TRACE_SYSTEM, "closing channel (%d)", S->out_channel);
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

static void update_mac_and_decrypt(const char* source,
	blake3_hasher* hash, struct chacha_ctx* ctx, uint8_t* buf, size_t sz)
{
	a12int_trace(A12_TRACE_CRYPTO, "src=%s:mac_update=%zu", source, sz);
	blake3_hasher_update(hash, buf, sz);
	if (ctx)
		chacha_apply(ctx, buf, sz);
}

/*
 * NOPACKET:
 * MAC
 * command byte
 */
static void process_nopacket(struct a12_state* S)
{
/* save MAC tag for later comparison when we have the final packet */
	memcpy(S->last_mac_in, S->decode, MAC_BLOCK_SZ);
	trace_crypto_key(S->server, "ref_mac", S->last_mac_in, MAC_BLOCK_SZ);
	update_mac_and_decrypt(__func__, &S->in_mac, S->dec_state, &S->decode[MAC_BLOCK_SZ], 9);

/* remember the last sequence number of the packet we processed */
	unpack_u64(&S->last_seen_seqnr, &S->decode[MAC_BLOCK_SZ]);

/* and finally the actual type in the inner block */
	int state_id = S->decode[MAC_BLOCK_SZ + 8];

	if (state_id >= STATE_BROKEN){
		a12int_trace(A12_TRACE_SYSTEM,
			"channel broken, unknown command val: %"PRIu8, S->state);
		S->state = STATE_BROKEN;
		return;
	}

/* transition to state based on type, from there we know how many bytes more
 * we need to process before the MAC can be checked */
	S->state = state_id;
	a12int_trace(A12_TRACE_TRANSFER, "seq: %"PRIu64
		" left: %"PRIu16", state: %"PRIu8, S->last_seen_seqnr, S->left, S->state);
	S->left = header_sizes[S->state];
	S->decode_pos = 0;
}

/*
 * FIRST:
 * MAC[8]
 * Nonce[8]
 * command byte (always control)
 */
static void process_srvfirst(struct a12_state* S)
{
/* only foul play could bring us here */
	if (S->authentic){
		fail_state(S);
		return;
	}

	size_t mac_sz = MAC_BLOCK_SZ >> 1;
	size_t nonce_sz = 8;
	uint8_t nonce[nonce_sz];

	a12int_trace(A12_TRACE_CRYPTO, "kind=mac:status=half_block");
	memcpy(S->last_mac_in, S->decode, mac_sz);
	memcpy(nonce, &S->decode[mac_sz], nonce_sz);

/* read the rest of the control packet */
	S->authentic = AUTH_SERVER_HBLOCK;
	S->left = CONTROL_PACKET_SIZE;
	S->state = STATE_CONTROL_PACKET;
	S->decode_pos = 0;

/* update MAC calculation with nonce and seqn+command byte */
	blake3_hasher_update(&S->in_mac, nonce, nonce_sz);
	blake3_hasher_update(&S->in_mac, &S->decode[mac_sz+nonce_sz], 8 + 1);

	if (S->dec_state){
		chacha_set_nonce(S->dec_state, nonce);
		chacha_set_nonce(S->enc_state, nonce);

		a12int_trace(A12_TRACE_CRYPTO, "kind=cipher:status=init_nonce");
		trace_crypto_key(S->server, "nonce", nonce, nonce_sz);

/* decrypt command byte and seqn */
		size_t base = mac_sz + nonce_sz;
		chacha_apply(S->dec_state, &S->decode[base], 9);
		if (S->decode[base + 8] != STATE_CONTROL_PACKET){
			a12int_trace(A12_TRACE_CRYPTO, "kind=error:status=bad_key_or_nonce");
			fail_state(S);
			return;
		}
	}
}

static void command_cancelstream(
	struct a12_state* S, uint32_t streamid, uint8_t reason)
{
	struct blob_out* node = S->pending;
	a12int_trace(A12_TRACE_SYSTEM, "stream_cancel:%"PRIu32":%"PRIu8, streamid, reason);

/* the other end indicated that the current codec or data source is broken,
 * propagate the error to the client (if in direct passing mode) otherwise just
 * switch the encoder for next frame */
	if (streamid == 1){
		if (reason == VSTREAM_CANCEL_DECODE_ERROR){
		}

/* other reasons means that the image contents is already known or too dated,
 * currently just ignore that - when we implement proper image hashing and can
 * use that for known types (cursor, ...) then reconsider */
		return;
	}
	else if (streamid == 2){
	}

/* try the blobs first */
	while (node){
		if (node->streamid == streamid){
			a12int_trace(A12_TRACE_BTRANSFER,
				"kind=cancelled:stream=%"PRIu32":source=remote", streamid);
			unlink_node(S, node);
			return;
		}
		node = node->next;
	}

}

static void command_binarystream(struct a12_state* S)
{
/*
 * unpack / validate header
 */
	uint8_t channel = S->decode[16];
	struct binary_frame* bframe = &S->channels[channel].unpack_state.bframe;

/*
 * sign of a very broken client (or state tracking), starting a new binary
 * stream on a channel where one already exists.
 */
	if (bframe->active){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:source=binarystream:kind=EEXIST:ch=%d", (int) channel);
		a12_stream_cancel(S, channel);
		bframe->active = false;
		if (bframe->tmp_fd > 0)
			bframe->tmp_fd = -1;
		return;
	}

	uint32_t streamid;
	unpack_u32(&streamid, &S->decode[18]);
	bframe->streamid = streamid;
	unpack_u64(&bframe->size, &S->decode[22]);
	bframe->type = S->decode[30];
	memcpy(bframe->checksum, &S->decode[35], 16);
	bframe->tmp_fd = -1;

	bframe->active = true;
	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=header:stream=%"PRId64":left=%"PRIu64":ch=%d",
		bframe->streamid, bframe->size, channel
	);

/*
 * If there is a checksum, ask the local cache process and see if we know about
 * it already, if so, cancel the binary stream and substitute in the copy we
 * get from the cache, but still need to process and discard incoming packages
 * in the meanwhile.
 *
 * This is the point where, for non-streams, provide a table of hashes first
 * and support resume at the first missing or broken hash
 */
	int sc = A12_BHANDLER_DONTWANT;
	struct a12_bhandler_meta bm = {
		.state = A12_BHANDLER_INITIALIZE,
		.known_size = bframe->size,
		.streamid = bframe->streamid,
		.fd = -1
	};

	if (S->binary_handler){
		struct a12_bhandler_res res = S->binary_handler(S, bm, S->binary_handler_tag);
		bframe->tmp_fd = res.fd;
		sc = res.flag;
	}

	if (sc == A12_BHANDLER_DONTWANT || sc == A12_BHANDLER_CACHED){
		a12_stream_cancel(S, channel);
		a12int_trace(A12_TRACE_BTRANSFER,
			"kind=reject:stream=%"PRId64":ch=%d", bframe->streamid, channel);
	}
}

void a12_vstream_cancel(struct a12_state* S, uint8_t channel, int reason)
{
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	step_sequence(S, outb);
	struct video_frame* vframe = &S->channels[channel].unpack_state.vframe;
	vframe->commit = 255;

	outb[16] = channel;
	outb[17] = COMMAND_CANCELSTREAM;
	outb[18] = 1;
	outb[19] = reason;

	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

void a12_stream_cancel(struct a12_state* S, uint8_t channel)
{
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};
	step_sequence(S, outb);
	struct binary_frame* bframe = &S->channels[channel].unpack_state.bframe;

/* API misuse, trying to cancel a stream that is not active */
	if (!bframe->active)
		return;

	outb[16] = channel;
	outb[17] = COMMAND_CANCELSTREAM;
	pack_u32(bframe->streamid, &outb[18]); /* [18 .. 21] stream-id */
	bframe->active = false;
	bframe->streamid = -1;
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);

/* forward the cancellation request to the eventhandler, due to the active tracking
 * we are protected against bad use (handler -> cancel -> handler) */
	if (S->binary_handler){
		struct a12_bhandler_meta bm = {
			.fd = bframe->tmp_fd,
			.state = A12_BHANDLER_CANCELLED,
			.streamid = bframe->streamid,
			.channel = channel
		};
		S->binary_handler(S, bm, S->binary_handler_tag);
	}

	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=cancelled:ch=%"PRIu8":stream=%"PRId64, channel, bframe->streamid);
	bframe->tmp_fd = -1;
}

static void command_audioframe(struct a12_state* S)
{
	uint8_t channel = S->decode[16];
	struct audio_frame* aframe = &S->channels[channel].unpack_state.aframe;

	aframe->format = S->decode[22];
	aframe->encoding = S->decode[23];
	aframe->channels = S->decode[22];
	unpack_u16(&aframe->nsamples, &S->decode[24]);
	unpack_u32(&aframe->rate, &S->decode[26]);
	S->in_channel = -1;

/* developer error (or malicious client), set to skip decode/playback */
	if (!S->channels[channel].active){
		a12int_trace(A12_TRACE_SYSTEM,
			"no segment mapped on channel %d", (int)channel);
		aframe->commit = 255;
		return;
	}

/* this requires an extended resize (theoretically, practically not),
 * and in those cases we want to copy-out the vbuffer state if set and
	if (cont->samplerate != aframe->rate){
		a12int_trace(A12_TRACE_MISSING,
			"rate mismatch: %zu <-> %"PRIu32, cont->samplerate, aframe->rate);
	}
 */

/* format should be paired against AUDIO_SAMPLE_TYPE
	if (aframe->channels != ARCAN_SHMIF_ACHANNELS){
		a12int_trace(A12_TRACE_MISSING, "channel format repack");
	}
*/
/* just plug the samples into the normal abuf- as part of the shmif-cont */
/* normal dynamic rate adjustment compensating for clock drift etc. go here */
}

/*
 * used if a12_set_destination_raw has been set for the channel, some of the
 * other metadata (typically cont->flags) have already been set - only the parts
 * that take a resize request is considered
 */
static void update_proxy_vcont(
	struct a12_channel* channel, struct video_frame* vframe)
{
	struct arcan_shmif_cont* cont = channel->cont;
	if (!channel->raw.request_raw_buffer)
		goto fail;

	cont->vidp = channel->raw.request_raw_buffer(vframe->sw, vframe->sh,
		&channel->cont->stride, channel->cont->hints, channel->raw.tag);

	cont->pitch = channel->cont->stride / sizeof(shmif_pixel);
	cont->w = vframe->sw;
	cont->h = vframe->sh;

	if (!cont->vidp)
		goto fail;

	return;

	fail:
		cont->w = 0;
		cont->h = 0;
		vframe->commit = 255;
}

static bool update_proxy_acont(
	struct a12_channel* channel, struct audio_frame* aframe)
{
	if (!channel->raw.request_audio_buffer)
		goto fail;

	channel->cont->audp =
		channel->raw.request_audio_buffer(
			aframe->channels, aframe->rate,
			sizeof(AUDIO_SAMPLE_TYPE) * aframe->channels,
			channel->raw.tag
	);

	if (!channel->cont->audp)
		goto fail;

	return true;

fail:
	aframe->commit = 255;
	return false;
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
		", kind: %"PRIu8", cookie: %"PRIu32"", channel, new_channel, type, cookie);

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

void a12int_stream_fail(struct a12_state* S, uint8_t ch, uint32_t id, int fail)
{
	uint8_t outb[CONTROL_PACKET_SIZE] = {0};

	step_sequence(S, outb);
	arcan_random(&outb[8], 8);

	outb[16] = ch;
	outb[17] = 3; /* stream-cancel */
	pack_u32(id, &outb[18]);
	outb[22] = (uint8_t) fail; /* user-cancel, can't handle, already cached */

	a12int_append_out(S,
		STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

static void command_videoframe(struct a12_state* S)
{
	uint8_t ch = S->decode[16];
	int method = S->decode[22];

	struct a12_channel* channel = &S->channels[ch];
	struct video_frame* vframe = &S->channels[ch].unpack_state.vframe;

/*
 * allocation and tracking for this one is subtle! nderef- etc. has been here
 * in the past. The reason is that codec can be swapped at the encoder side
 * and that some codecs need to retain state between frames.
 */
	if (!a12int_vframe_setup(channel, vframe, method)){
		vframe->commit = 255;
		a12int_stream_fail(S, ch, 1, STREAM_FAIL_UNKNOWN);
		return;
	}

/* new vstream, from README.md:
	* currently unused
	* [36    ] : dataflags: uint8
	*/
/* [18..21] : stream-id: uint32 */
	vframe->postprocess = method; /* [22] : format : uint8 */
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
	struct arcan_shmif_cont* cont = channel->cont;
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=videoframe_header:status=EINVAL:channel=%d", (int) ch);
		vframe->commit = 255;
		return;
	}

/* set the possible consumer presentation / repacking options, or resize
 * if the source / destination dimensions no longer match */
	bool hints_changed = false;
	if ((vframe->postprocess == POSTPROCESS_VIDEO_TZ ||
		vframe->postprocess == POSTPROCESS_VIDEO_TZSTD) &&
		!(cont->hints & SHMIF_RHINT_TPACK)){
		cont->hints |= SHMIF_RHINT_TPACK;
		hints_changed = true;
	}
	else if ((cont->hints & SHMIF_RHINT_TPACK) &&
		(vframe->postprocess != POSTPROCESS_VIDEO_TZ &&
		 vframe->postprocess != POSTPROCESS_VIDEO_TZSTD)){
		cont->hints = cont->hints & (~SHMIF_RHINT_TPACK);
		hints_changed = true;
	}

/* always request a new video buffer between frames for raw mode so the
 * caller has the option of mapping each to different destinations */
	if (channel->active == CHANNEL_RAW)
		update_proxy_vcont(channel, vframe);

/* shmif itself only needs the one though */
	else if (hints_changed || vframe->sw != cont->w || vframe->sh != cont->h){
			arcan_shmif_resize(cont, vframe->sw, vframe->sh);

		if (vframe->sw != cont->w || vframe->sh != cont->h){
			a12int_trace(A12_TRACE_SYSTEM, "parent size rejected");
			vframe->commit = 255;
		}
		else
			a12int_trace(A12_TRACE_VIDEO, "kind=resized:channel=%d:hints=%d:"
				"new_w=%zu:new_h=%zu", (int) ch, (int) cont->hints,
				(size_t) vframe->sw, (size_t) vframe->sh
			);
	}

	a12int_trace(A12_TRACE_VIDEO, "kind=frame_header:method=%d:"
		"source_w=%zu:source_h=%zu:w=%zu:h=%zu:x=%zu,y=%zu:"
		"bytes_in=%zu:bytes_out=%zu",
		(int) vframe->postprocess, (size_t) vframe->sw, (size_t) vframe->sh,
		(size_t) vframe->w, (size_t) vframe->h, (size_t) vframe->x, (size_t) vframe->y,
		(size_t) vframe->inbuf_sz, (size_t) vframe->expanded_sz
	);

/* Validation is done just above, making sure the sub- region doesn't extend
 * the specified source surface. Remaining length- field is verified before
 * the write in process_video. */
	if (vframe->x >= vframe->sw || vframe->y >= vframe->sh){
		vframe->commit = 255;
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:status=EINVAL:x=%zu:y=%zu:w=%zu:h=%zu",
			(size_t) vframe->x, (size_t) vframe->y, (size_t) vframe->w, (size_t) vframe->h
		);
		return;
	}

/* For RAW pixels, note that we count row, pos, etc. in the native
 * shmif_pixel and thus use pitch instead of stride */
	if (vframe->postprocess == POSTPROCESS_VIDEO_RGBA ||
		vframe->postprocess == POSTPROCESS_VIDEO_RGB565 ||
		vframe->postprocess == POSTPROCESS_VIDEO_RGB){
		vframe->row_left = vframe->w - vframe->x;
		vframe->out_pos = vframe->y * cont->pitch + vframe->x;
		a12int_trace(A12_TRACE_TRANSFER,
			"row-length: %zu at buffer pos %"PRIu32, vframe->row_left, vframe->inbuf_pos);
	}
/* this includes TPACK */
	else {
		size_t ulim = vframe->w * vframe->h * sizeof(shmif_pixel);
		if (vframe->expanded_sz > ulim){
			vframe->commit = 255;
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=error:status=EINVAL:expanded=%zu:limit=%zu",
				(size_t) vframe->expanded_sz, (size_t) ulim
			);
			return;
		}
/* rather arbitrary, but if this condition occurs, the producer should have
 * simply sent the data raw - the odd case is possibly miniz/tpack where the
 * can be a header and a non-compressible buffer. */
		if (vframe->inbuf_sz > vframe->expanded_sz + 24){
			vframe->commit = 255;
			a12int_trace(A12_TRACE_SYSTEM, "incoming buffer (%"
				PRIu32") expands to less than target (%"PRIu32")",
				vframe->inbuf_sz, vframe->expanded_sz
			);
			vframe->inbuf_pos = 0;
			return;
		}

/* out_pos gets validated in the decode stage, so no OOB ->y ->x */
		vframe->out_pos = vframe->y * cont->pitch + vframe->x;
		vframe->inbuf_pos = 0;
		vframe->inbuf = malloc(vframe->inbuf_sz);
		if (!vframe->inbuf){
			a12int_trace(A12_TRACE_ALLOC,
				"couldn't allocate intermediate buffer store");
			return;
		}
		vframe->row_left = vframe->w;
		a12int_trace(A12_TRACE_VIDEO, "compressed buffer in (%"
			PRIu32") to offset (%zu)", vframe->inbuf_sz, vframe->out_pos);
	}
}

/*
 * Binary transfers comes in different shapes:
 *
 *  - [bchunk-in / bchunk-out] non-critical blob transfer, typically on
 *                             clipboard, can be queued and interleaved
 *                             when no-other relevant transfer going on.
 *
 *  - [store] priority state serialization, may be overridden by future reqs.
 *
 *  - [restore] block / priority - changes event interpretation context after.
 *
 *  - [fonthint] affects visual output, likely to be cacheable, higher
 *               priority during the preroll stage
 *
 * [out and store] are easier to send on a non-output segment over an
 * asymmetric connection as they won't fight with other transfers.
 *
 */
void a12_enqueue_bstream(
	struct a12_state* S, int fd, int type, bool streaming, size_t sz)
{
	struct blob_out* next = malloc(sizeof(struct blob_out));
	if (!next){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=ENOMEM");
		return;
	}

	*next = (struct blob_out){
		.type = type,
		.streaming = streaming,
		.fd = -1,
		.chid = S->out_channel
	};

	struct blob_out** parent = &S->pending;
	size_t n_streaming = 0;
	size_t n_known = 0;

	while(*parent){
		if ((*parent)->streaming)
			n_streaming++;
		else
			n_known += (*parent)->left;
		parent = &(*parent)->next;

/* [MISSING]
 * Insertion priority sort goes here, be wary of channel-id in heuristic
 * though, and try to prioritize channel that has focus over those that
 * don't - and if not appending, the unlink at the fail-state need to
 * preserve forward integrity
 **/
	}
	*parent = next;

/* note, next->fd will be non-blocking */
	next->fd = arcan_shmif_dupfd(fd, -1, false);
	if (-1 == next->fd){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EBADFD");
		goto fail;
	}

/* For the streaming descriptor, we can only work with the reported size
 * and that one can still be unknown (0), i.e. the stream continues to work
 * until cancelled.
 *
 * For the file-backed one, we are expecting seek operations to work and
 * will use that size indicator along with a checksum calculation to allow
 * the other side to cancel the transfer if it is already known */
	if (streaming){
		next->streaming = true;
		return;
	}

	off_t fend = lseek(fd, 0, SEEK_END);
	if (fend == 0){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EEMPTY");
		*parent = NULL;
		free(next);
		return;
	}

	if (-1 == fend){
/* force streaming if the host system can't manage */
		switch(errno){
		case ESPIPE:
		case EOVERFLOW:
			next->streaming = true;
			a12int_trace(A12_TRACE_BTRANSFER,
				"kind=added:type=%d:stream=yes:size=%zu:queue=%zu:total=%zu\n",
				type, next->left, n_streaming, n_known
			);
			return;
		break;
		case EINVAL:
		case EBADF:
		default:
			a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EBADFD");
		break;
		}
	}

	if (-1 == lseek(fd, 0, SEEK_SET)){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=ESEEK");
		goto fail;
	}

/* this has the normal sigbus problem, though we don't care about that much now
 * being in the same sort of privilege domain - we can also defer the entire
 * thing and simply thread- process it, which is probably the better solution */
	void* map = mmap(NULL, fend, PROT_READ, MAP_FILE | MAP_PRIVATE, fd, 0);

	if (!map){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EMMAP");
		goto fail;
	}

/* the crypted packages are MACed together, but we always use the primitive
 * for btransfer- checksums so the other side can compare against a cache and
 * cancel the stream */
	blake3_hasher hash;
	blake3_hasher_init(&hash);
	blake3_hasher_update(&hash, map, fend);
	blake3_hasher_finalize(&hash, next->checksum, 16);
	munmap(map, fend);
	next->left = fend;
	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=added:type=%d:stream=no:size=%zu", type, next->left);
	S->active_blobs++;
	return;

fail:
	if (-1 != next->fd)
		close(next->fd);

	*parent = NULL;
	free(next);
}

static bool authdec_buffer(const char* src, struct a12_state* S, size_t block_sz)
{
	size_t mac_size = MAC_BLOCK_SZ;

	if (S->authentic == AUTH_SERVER_HBLOCK){
		mac_size = 8;
		trace_crypto_key(S->server, "auth_mac_in", S->last_mac_in, mac_size);
	}

	update_mac_and_decrypt(__func__, &S->in_mac, S->dec_state, S->decode, block_sz);

	uint8_t ref_mac[MAC_BLOCK_SZ];
	blake3_hasher_finalize(&S->in_mac, ref_mac, mac_size);

	a12int_trace(A12_TRACE_CRYPTO,
		"kind=mac_dec:src=%s:pos=%zu", src, S->in_mac.counter);
	trace_crypto_key(S->server, "auth_mac_rf", ref_mac, mac_size);
	bool res = memcmp(ref_mac, S->last_mac_in, mac_size) == 0;

	if (!res){
		trace_crypto_key(S->server, "bad_mac", S->last_mac_in, mac_size);
	}

	return res;
}

static void hello_auth_server_hello(struct a12_state* S)
{
	uint8_t pubk[32];
	uint8_t nonce[8];
	int cfl = S->decode[20];
	a12int_trace(A12_TRACE_CRYPTO, "state=complete:method=%d", cfl);
	arcan_random(nonce, 8);

/* public key is the real one */
	if (cfl == 1){
		if (!S->opts->pk_lookup){
			a12int_trace(A12_TRACE_CRYPTO, "state=eimpl:kind=x25519-no-lookup");
			fail_state(S);
			return;
		}

/* authenticate it against whatever keystore we have, get the proper priv.key */
		trace_crypto_key(S->server, "state=client_pk", &S->decode[21], 32);
		struct pk_response res = S->opts->pk_lookup(&S->decode[21]);
		if (!res.authentic){
			a12int_trace(A12_TRACE_CRYPTO, "state=eperm:kind=x25519-pk-fail");
			fail_state(S);
			return;
		}

		x25519_public_key(res.key, pubk);
		arcan_random(nonce, 8);
		send_hello_packet(S, 1, pubk, nonce);
		trace_crypto_key(S->server, "state=client_pk_ok:respond_pk", pubk, 32);

/* now we can switch keys */
		x25519_shared_secret((uint8_t*)S->opts->secret, res.key, &S->decode[21]);
		trace_crypto_key(S->server, "state=server_ssecret", (uint8_t*)S->opts->secret, 32);
		update_keymaterial(S, S->opts->secret, 32, nonce);

/* and done */
		S->authentic = AUTH_FULL_PK;
		return;
	}

/* psk method only */
	if (cfl != 2){
		a12int_trace(A12_TRACE_CRYPTO, "state=ok:full_auth");
		S->authentic = AUTH_FULL_PK;
		return;
	}

/* public key is ephemeral, generate new pair, send a hello out with the
 * new one THEN derive new keys for authentication and so on */
	uint8_t ek[32];
	x25519_private_key(ek);
	x25519_public_key(ek, pubk);
	send_hello_packet(S, 2, pubk, nonce);

/* client will receive hello, we will geat real Pk and mode[1] like normal */
	x25519_shared_secret((uint8_t*)S->opts->secret, ek, &S->decode[21]);
	trace_crypto_key(S->server, "ephem_pub", pubk, 32);
	update_keymaterial(S, S->opts->secret, 32, nonce);
	S->authentic = AUTH_EPHEMERAL_PK;
}

static void hello_auth_client_hello(struct a12_state* S)
{
	if (!S->opts->pk_lookup){
		a12int_trace(A12_TRACE_CRYPTO, "state=eimpl:kind=x25519-no-lookup");
		fail_state(S);
		return;
	}

	trace_crypto_key(S->server, "server_pk", &S->decode[21], 32);
	struct pk_response res = S->opts->pk_lookup(&S->decode[21]);
	if (!res.authentic){
		a12int_trace(A12_TRACE_CRYPTO, "state=eperm:kind=25519-pk-fail");
		fail_state(S);
	}

/* there we go, shared secret is in store, use the server nonce and
 * any other crypto operations will be the rekeying */
	trace_crypto_key(S->server, "state=client_priv", res.key, 32);
	x25519_shared_secret((uint8_t*)S->opts->secret, res.key, &S->decode[21]);
	trace_crypto_key(S->server, "state=client_ssecret", (uint8_t*)S->opts->secret, 32);
	update_keymaterial(S, S->opts->secret, 32, &S->decode[8]);

	S->authentic = AUTH_FULL_PK;
}

static void process_hello_auth(struct a12_state* S)
{
	/*
- [18]      Version major : uint8 (shmif-version until 1.0)
- [19]      Version minor : uint8 (shmif-version until 1.0)
- [20]      Flags         : uint8
- [21+ 32]  x25519 Pk     : blob
	 */
	if (S->authentic == AUTH_SERVER_HBLOCK){
		hello_auth_server_hello(S);
		return;
	}
/* the client has received the server ephemeral pubk,
 * now we can send the real one after a keyswitch to a shared secret */
	else if (S->authentic == AUTH_POLITE_HELLO_SENT){
		uint8_t nonce[8];

		trace_crypto_key(S->server, "ephem-pub-in", &S->decode[21], 32);
		x25519_shared_secret((uint8_t*)S->opts->secret, S->keys.ephem_priv, &S->decode[21]);
		update_keymaterial(S, S->opts->secret, 32, &S->decode[8]);

/* unmask the private key */
		uint8_t realpk[32];
		toggle_key_mask(S->keys.real_priv);
			x25519_public_key(S->keys.real_priv, realpk);
		toggle_key_mask(S->keys.real_priv);

		S->authentic = AUTH_REAL_HELLO_SENT;
		arcan_random(nonce, 8);
		send_hello_packet(S, 1, realpk, nonce);
	}
/* the server and client are both using a shared secret from the ephemeral key
 * now, and this message contains the real public key of the client, treat it
 * the same as AUTH_SERVER_HBLOCK though we know the mode */
	else if (S->authentic == AUTH_EPHEMERAL_PK){
		hello_auth_server_hello(S);
	}
/* client side, authenticate public key, keyswitch to session */
	else if (S->authentic == AUTH_REAL_HELLO_SENT){
		hello_auth_client_hello(S);
	}
	else {
		a12int_trace(A12_TRACE_CRYPTO,
			"HELLO after completed authxchg (%d)", S->authentic);
		fail_state(S);
		return;
	}
}

/*
 * Control command,
 * current MAC calculation in s->mac_dec
 */
static void process_control(struct a12_state* S, void (*on_event)
	(struct arcan_shmif_cont*, int chid, struct arcan_event*, void*), void* tag)
{
	if (!authdec_buffer(__func__, S, header_sizes[S->state])){
		fail_state(S);
		return;
	}

/* ignore these for now
	uint64_t last_seen = S->decode[0];
	uint8_t entropy[8] = S->decode[8];
	uint8_t channel = S->decode[16];
 */

	uint8_t command = S->decode[17];
	if (S->authentic < AUTH_FULL_PK && command != COMMAND_HELLO){
		a12int_trace(A12_TRACE_CRYPTO,
			"illegal command (%d) on non-auth connection", (int) command);
		fail_state(S);
		return;
	}

	switch(command){
	case COMMAND_HELLO:
		process_hello_auth(S);
	break;
	case COMMAND_SHUTDOWN:
	/* terminate specific channel */
	break;
	case COMMAND_NEWCH:
		command_newchannel(S, on_event, tag);
	break;
	case COMMAND_CANCELSTREAM:{
		uint32_t streamid;
		unpack_u32(&streamid, &S->decode[18]);
		command_cancelstream(S, streamid, S->decode[22]);
	}
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
	case COMMAND_REKEY:
/* 1. note the sequence number that we are supposed to switch.
 * 2. generate new keypair and add to the rekey slot.
 * 3. if this is not a rekey response package, send the new pubk in response */
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
	if (!authdec_buffer(__func__, S, header_sizes[S->state])){
		a12int_trace(A12_TRACE_CRYPTO, "MAC mismatch on event packet");
		fail_state(S);
		return;
	}

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

static void process_blob(struct a12_state* S)
{
/* do we have the header bytes or not? the actual callback is triggered
 * inside of the binarystream rather than of the individual blobs */
	if (S->in_channel == -1){
		update_mac_and_decrypt(__func__, &S->in_mac,
			S->dec_state, S->decode, header_sizes[S->state]);

		S->in_channel = S->decode[0];
		unpack_u32(&S->in_stream, &S->decode[1]);
		unpack_u16(&S->left, &S->decode[5]);
		S->decode_pos = 0;
		a12int_trace(A12_TRACE_BTRANSFER,
			"kind=header:channel=%d:size=%"PRIu16, S->in_channel, S->left);

		return;
	}

/* did we receive a message on a dead channel? */
	struct binary_frame* cbf = &S->channels[S->in_channel].unpack_state.bframe;
	if (!authdec_buffer(__func__, S, S->decode_pos)){
		fail_state(S);
		return;
	}

	struct arcan_shmif_cont* cont = S->channels[S->in_channel].cont;
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EINVAL:"
			"ch=%d:message=no segment mapped", S->in_channel);
		reset_state(S);
		return;
	}

/* we can't stop the other side from sending data to a dead stream, so just
 * discard the data and hope that a previously sent cancelstream will take */
	if (cbf->streamid != S->in_stream || -1 == cbf->streamid){
		a12int_trace(A12_TRACE_BTRANSFER, "kind=notice:ch=%d:src_stream=%"PRIu32
			":dst_stream=%"PRId64":message=data on cancelled stream",
			S->in_channel, S->in_stream, cbf->streamid);
		reset_state(S);
		return;
	}

/* or worse, a data block referencing a transfer that has not been set up? */
	if (!cbf->active){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EINVAL:"
			"ch=%d:message=blob on inactive channel", S->in_channel);
		reset_state(S);
		return;
	}

/* Flush it out to the assigned descriptor, this is currently likely to be
 * blocking and can cascade quite far down the chain, consider a drag and drop
 * that routes via a pipe onwards to another client. Normal splice etc.
 * operations won't work so we are left with this. To not block video/audio
 * processing we would have to buffer / flush this separately, with a big
 * complexity leap. */
	if (-1 != cbf->tmp_fd){
			size_t pos = 0;

			while(pos < S->decode_pos){
				ssize_t status = write(cbf->tmp_fd, &S->decode[pos], S->decode_pos - pos);
				if (-1 == status){
					if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
						continue;

/* so there was a problem writing (dead pipe, out of space etc). send a cancel
 * on the stream,this will also forward the status change to the event handler
 * itself who is responsible for closing the tmp_fd */
					a12_stream_cancel(S, S->in_channel);
					reset_state(S);
					return;
				}
				else
					pos += status;
			}
		}

	if (cbf->size > 0){
		cbf->size -= S->decode_pos;

		if (!cbf->size){
			a12int_trace(A12_TRACE_BTRANSFER,
				"kind=completed:ch=%d:stream=%"PRId64, S->in_channel, cbf->streamid);
			cbf->active = false;
			if (!S->binary_handler)
				return;

/* finally forward all the metadata to the handler and let the recipient
 * pack it into the proper event structure and so on. */
			struct a12_bhandler_meta bm = {
				.type = cbf->type,
				.streamid = cbf->streamid,
				.channel = S->in_channel,
				.fd = cbf->tmp_fd,
				.dcont = cont,
				.state = A12_BHANDLER_COMPLETED
			};

/* note that we do trust the provided checksum here, to actually re-verify that
 * a possibly cache- stored checksum matches the transfer is up to the callback
 * handler. otherwise a possible scenario is to have a client taint a binary
 * cache, but such trust compartmentation should be handled by real separation
 * between clients. */
			memcpy(&bm.checksum, cbf->checksum, 16);
			cbf->tmp_fd = -1;
			S->binary_handler(S, bm, S->binary_handler_tag);

			return;
		}
	}

/*
 * More data to come on the channel, just reset and wait for the next packet
 */
	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=data:ch=%d:left:%"PRIu64, S->in_channel, cbf->size);

	reset_state(S);
}

/*
 * We have an incoming video packet, first we need to match it to the channel
 * that it represents (as we might get interleaved updates) and match the state
 * we are building.
 */
static void process_video(struct a12_state* S)
{
	if (S->in_channel == -1){
		uint32_t stream;

/* note that the data is still unauthenticated, we need to know how much
 * left to expect and buffer that before we can authenticate */
		update_mac_and_decrypt(__func__,
			&S->in_mac, S->dec_state, S->decode, S->decode_pos);
		S->in_channel = S->decode[0];
		unpack_u32(&stream, &S->decode[1]);
		unpack_u16(&S->left, &S->decode[5]);
		S->decode_pos = 0;

		a12int_trace(A12_TRACE_VIDEO,
			"kind=header:channel=%d:size=%"PRIu16, S->in_channel, S->left);
		return;
	}

/* the 'video_frame' structure for the current channel (segment) tracks
 * decode buffer etc. for the current stream */
	struct a12_channel* ch = &S->channels[S->in_channel];
	struct video_frame* cvf = &ch->unpack_state.vframe;

	if (!authdec_buffer(__func__, S, S->decode_pos)){
		fail_state(S);
		return;
	}
	else {
		a12int_trace(A12_TRACE_CRYPTO, "kind=frame_auth");
	}

/* if we are in discard state, just continue */
	if (cvf->commit == 255){
		a12int_trace(A12_TRACE_VIDEO, "kind=discard");
		reset_state(S);
		return;
	}

	struct arcan_shmif_cont* cont = ch->cont;
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:source=video:type=EINVALCH:val=%d", (int) S->in_channel);
		reset_state(S);
		return;
	}

/* postprocessing that requires an intermediate decode buffer before pushing */
	if (a12int_buffer_format(cvf->postprocess)){
		size_t left = cvf->inbuf_sz - cvf->inbuf_pos;
		a12int_trace(A12_TRACE_VIDEO,
			"kind=decbuf:channel=%d:size=%"PRIu16":left=%zu",
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
				"kind=error:source=video:channel=%d:type=EOVERFLOW", S->in_channel);
			reset_state(S);
		}

/* buffer is finished, decode and commit to designated channel context
 * unless it has already been marked as something to ignore and discard */
		if (left == 0 && cvf->commit != 255){
			a12int_trace(
				A12_TRACE_VIDEO, "kind=decbuf:channel=%d:commit", (int)S->in_channel);
			a12int_decode_vbuffer(S, ch, cvf, cont);
		}

		reset_state(S);
		return;
	}

/* we use a length field that match the width*height so any
 * overflow / wrap tricks won't work */
	if (cvf->inbuf_sz < S->decode_pos){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:source=video:channel=%d:type=EOVERFLOW", S->in_channel);
		cvf->commit = 255;
		reset_state(S);
		return;
	}

/* finally unpack the raw video buffer */
	a12int_unpack_vbuffer(S, cvf, cont);
	reset_state(S);
}

static void drain_audio(struct a12_channel* ch)
{
	struct arcan_shmif_cont* cont = ch->cont;
	if (ch->active == CHANNEL_RAW){
		if (ch->raw.signal_audio)
			ch->raw.signal_audio(cont->abufused, ch->raw.tag);
		cont->abufused = 0;
		return;
	}

	arcan_shmif_signal(cont, SHMIF_SIGAUD);
}

static void process_audio(struct a12_state* S)
{
/* in_channel is used to track if we are waiting for the header or not */
	if (S->in_channel == -1){
		uint32_t stream;
		S->in_channel = S->decode[0];
		unpack_u32(&stream, &S->decode[1]);
		unpack_u16(&S->left, &S->decode[5]);
		S->decode_pos = 0;
		update_mac_and_decrypt(__func__,
			&S->in_mac, S->dec_state, S->decode, header_sizes[S->state]);
		a12int_trace(A12_TRACE_AUDIO,
			"audio[%d:%"PRIx32"], left: %"PRIu16, S->in_channel, stream, S->left);
		return;
	}

/* the 'audio_frame' structure for the current channel (segment) only
 * contains the metadata, we use the mapped shmif- segment to actually
 * buffer, assuming we have no compression */
	struct a12_channel* channel = &S->channels[S->in_channel];
	struct audio_frame* caf = &channel->unpack_state.aframe;
	struct arcan_shmif_cont* cont = channel->cont;

	if (!authdec_buffer(__func__, S, S->decode_pos)){
		fail_state(S);
		return;
	}
	else {
		a12int_trace(A12_TRACE_CRYPTO, "kind=frame_auth");
	}

	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM,
			"audio data on unmapped channel (%d)", (int) S->in_channel);
		reset_state(S);
		return;
	}

	if (channel->active == CHANNEL_RAW){
		if (!update_proxy_acont(channel, caf))
			return;
	}

/* passed the header stage, now it's the data block,
 * make sure the segment has registered that it can provide audio */
	if (!cont->audp){
		a12int_trace(A12_TRACE_AUDIO,
			"frame-resize, rate: %"PRIu32", channels: %"PRIu8,
			caf->rate, caf->channels
		);

/* a note with the extended resize here is that we always request a single
 * video buffer, which means the video part will be locked until we get an
 * ack from the consumer - this might need to be tunable to increase if we
 * detect that we stall on signalling video */
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

/* Flush out into abuffer, assuming that the context has been set to match the
 * defined source format in a previous stage. Resampling might be needed here,
 * both for rate and for drift/buffer */
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
			drain_audio(channel);
		}
	}

/* now we can subtract the number of SAMPLES from the audio stream packet, when
 * that reaches zero we reset state, this incorrectly assumes 2 channels. */
	caf->nsamples -= S->decode_pos >> 1;

/* drain if there is data left in the buffer, but no samples left */
	if (!caf->nsamples && cont->abufused){
		drain_audio(channel);
	}

	a12int_trace(A12_TRACE_TRANSFER,
		"audio packet over, samples left: %zu", (size_t) caf->nsamples);
	reset_state(S);
}

/* helper that just forwards to set-destination */
void a12_set_destination(
	struct a12_state* S, struct arcan_shmif_cont* wnd, uint8_t chid)
{
	if (!S){
		a12int_trace(A12_TRACE_DEBUG, "invalid set_destination call");
		return;
	}

	if (S->channels[chid].active == CHANNEL_RAW){
		free(S->channels[chid].cont);
		S->channels[chid].cont = NULL;
	}

	S->channels[chid].cont = wnd;
	S->channels[chid].active = wnd ? CHANNEL_SHMIF : CHANNEL_INACTIVE;
}

void a12_set_destination_raw(struct a12_state* S,
	uint8_t chid, struct a12_unpack_cfg cfg, size_t cfg_sz)
{
/* the reason for this rather odd design is that non-shmif based receiver was
 * an afterthought, and it was a much larger task refactoring it out versus
 * adding a proxy and tagging */
	size_t ct_sz = sizeof(struct arcan_shmif_cont);
	struct arcan_shmif_cont* fake = malloc(ct_sz);
	if (!fake)
		return;

	*fake = (struct arcan_shmif_cont){};
	S->channels[chid].cont = fake;
	S->channels[chid].raw = cfg;
	S->channels[chid].active = CHANNEL_RAW;
}

void
a12_unpack(struct a12_state* S, const uint8_t* buf,
	size_t buf_sz, void* tag, void (*on_event)
	(struct arcan_shmif_cont*, int chid, struct arcan_event*, void*))
{
	if (S->state == STATE_BROKEN){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:status=EINVAL:message=state machine broken");
		fail_state(S);
		return;
	}

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

/* do we need to buffer more? */
	if (S->left)
		return;

/* otherwise dispatch based on state */
	switch(S->state){
	case STATE_1STSRV_PACKET:
		process_srvfirst(S);
	break;
	case STATE_NOPACKET:
		process_nopacket(S);
	break;
	case STATE_CONTROL_PACKET:
		process_control(S, on_event, tag);
	break;
	case STATE_EVENT_PACKET:
		process_event(S, tag, on_event);
	break;
/* worth noting is that these (a,v,b) have different buffer sizes for their
 * respective packets, so the authentication and decryption steps are somewhat
 * different */
	case STATE_VIDEO_PACKET:
		process_video(S);
	break;
	case STATE_AUDIO_PACKET:
		process_audio(S);
	break;
	case STATE_BLOB_PACKET:
		process_blob(S);
	break;
	default:
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EINVAL:message=bad command");
		fail_state(S);
		return;
	break;
	}

/* slide window and tail- if needed */
	if (buf_sz)
		a12_unpack(S, &buf[ntr], buf_sz, tag, on_event);
}

/*
 * Several small issues that should be looked at here, one is that we don't
 * multiplex well with the source, risking a non-block 100% spin. Second is
 * that we don't have an intermediate buffer as part of the queue-node, meaning
 * that we risk sending very small blocks of data as part of the stream,
 * wasting bandwidth.
 */
static void* read_data(int fd, size_t cap, uint16_t* nts, bool* die)
{
	void* buf = malloc(65536);
	if (!buf){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=ENOMEM");
		*die = true;
		return NULL;
	}

	ssize_t nr = read(fd, buf, cap);

/* possibly non-fatal or no data present yet, keep stream alive - a bad stream
 * source with no timeout will block / preempt other binary transfers though so
 * might need to consider reordering in that case. */
	if (-1 == nr){
		if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
			*die = false;
		else
			*die = true;

		free(buf);
		return NULL;
	}

	*die = false;
	if (nr == 0){
		free(buf);
		return NULL;
	}

	*nts = nr;
	return buf;
}

static void unlink_node(struct a12_state* S, struct blob_out* node)
{
	/* find the owner of the node, redirect next */
	/* close the socket and other resources */
	struct blob_out* next = node->next;
	struct blob_out** dst = &S->pending;
	while (*dst != node && *dst){
		dst = &((*dst)->next);
	}

	if (*dst != node){
		a12int_trace(A12_TRACE_SYSTEM, "couldn't not unlink node");
		return;
	}

	a12int_trace(A12_TRACE_ALLOC, "unlinked:stream=%"PRIu64, node->streamid);
	S->active_blobs--;
	*dst = next;
	close(node->fd);
	free(node);
}

static size_t queue_node(struct a12_state* S, struct blob_out* node)
{
	uint16_t nts;
	size_t cap = node->left;
	if (cap == 0 || cap > 64096)
		cap = 64096;

	bool die;
	void* buf = read_data(node->fd, cap, &nts, &die);
	if (!buf){
		/* MISSING: SEND STREAM CANCEL */
		if (die){
			unlink_node(S, node);
		}
		return 0;
	}

/* not activated, so build a header first */
	if (!node->active){
		uint8_t outb[CONTROL_PACKET_SIZE] = {0};
		step_sequence(S, outb);
		S->out_stream++;
		outb[16] = node->chid;
		outb[17] = COMMAND_BINARYSTREAM;
		pack_u32(S->out_stream, &outb[18]); /* [18 .. 21] stream-id */
		pack_u64(node->left, &outb[22]); /* [22 .. 29] total-size */
		outb[30] = node->type;
		/* 31..34 : id-token, ignored for now */
		memcpy(&outb[35], node->checksum, 16);
		a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
		node->active = true;
		node->streamid = S->out_stream;
		a12int_trace(A12_TRACE_BTRANSFER,
			"kind=created:size=%zu:stream:%"PRIu64":ch=%d",
			node->left, node->streamid, node->chid
		);
	}

/* prepend the bstream header */
	uint8_t outb[1 + 4 + 2];
	outb[0] = node->chid;
	pack_u32(node->streamid, &outb[1]);
	pack_u16(nts, &outb[5]);

	a12int_append_out(S, STATE_BLOB_PACKET, buf, nts, outb, sizeof(outb));

	if (node->left){
		node->left -= nts;
		if (!node->left){

			unlink_node(S, node);
		}
		else {
			a12int_trace(A12_TRACE_BTRANSFER,
				"kind=block:stream=%"PRIu64":ch=%d:size=%"PRIu16":left=%zu",
				node->streamid, (int)node->chid, nts, node->left
			);
		}
	}
	else {
		a12int_trace(A12_TRACE_BTRANSFER,
			"kind=block:stream=%zu:ch=%d:streaming:size=%"PRIu16,
			(size_t) node->streamid, (int)node->chid, nts
		);
	}

	free(buf);
	return nts;
}

static size_t append_blob(struct a12_state* S, int mode)
{
/* find suitable blob */
	if (mode == A12_FLUSH_NOBLOB || !S->pending)
		return 0;
/* only current channel? */
	else if (mode == A12_FLUSH_CHONLY){
		struct blob_out* parent = S->pending;
		while (parent){
			if (parent->chid == S->out_channel)
				return queue_node(S, parent);
			parent = parent->next;
		}
		return 0;
	}
	return queue_node(S, S->pending);
}

size_t
a12_flush(struct a12_state* S, uint8_t** buf, int allow_blob)
{
	if (S->state == STATE_BROKEN || S->cookie != 0xfeedface)
		return 0;

/* nothing in the outgoing buffer? then we can pull in whatever data transfer
 * is pending, if there are any queued */
	if (S->buf_ofs == 0){
		if (allow_blob > A12_FLUSH_NOBLOB && append_blob(S, allow_blob)){}
		else
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

	return S->buf_ofs || S->pending ? 1 : 0;
}

int
a12_auth_state(struct a12_state* S)
{
	return S->authentic;
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
	if (!w || !h){
		a12int_trace(A12_TRACE_SYSTEM, "kind=einval:status=bad dimensions");
		return;
	}

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
	case VFRAME_METHOD_DZSTD:
		a12int_encode_dzstd(argstr);
	break;
	case VFRAME_METHOD_DPNG:
		a12int_encode_dpng(argstr);
	break;
	case VFRAME_METHOD_H264:
		a12int_encode_h264(argstr);
	break;
	case VFRAME_METHOD_TPACK:
		a12int_encode_tz(argstr);
	break;
	case VFRAME_METHOD_TPACK_ZSTD:
		a12int_encode_ztz(argstr);
	break;
	default:
		a12int_trace(A12_TRACE_SYSTEM, "unknown format: %d\n", opts.method);
	break;
	}
}

bool
a12_channel_enqueue(struct a12_state* S, struct arcan_event* ev)
{
	if (!S || S->cookie != 0xfeedface || !ev)
		return false;

/* descriptor passing events are another complex affair, those that require
 * the caller to provide data outwards should already have been handled at
 * this stage, so it is basically STORE and BCHUNK_OUT that are allowed to
 * be forwarded in order for the other side to a12_queue_bstream */
	if (arcan_shmif_descrevent(ev)){
		switch(ev->tgt.kind){
		case TARGET_COMMAND_STORE:
		case TARGET_COMMAND_BCHUNK_OUT:
/* we need to register a local store that tracks the descriptor here
 * and just replaces the [0].iv field with that key, the other side
 * will forward a bstream correctly then pair */
		break;

/* these events have a descriptor, just map them to the right type of
 * binary transfer event and the other side will synthesize and push
 * the rest */
		case TARGET_COMMAND_RESTORE:
			a12_enqueue_bstream(S,
				ev->tgt.ioevs[0].iv, A12_BTYPE_STATE, false, 0);
			return true;
		break;

/* let the bstream- side determine if the source is streaming or not */
		case TARGET_COMMAND_BCHUNK_IN:
			a12_enqueue_bstream(S,
				ev->tgt.ioevs[0].iv, A12_BTYPE_BLOB, false, 0);
				return true;
		break;

/* weird little detail with the fonthint is that the real fonthint event
 * sans descriptor will be transferred first, the other side will catch
 * it and merge */
		case TARGET_COMMAND_FONTHINT:
			a12_enqueue_bstream(S,
				ev->tgt.ioevs[0].iv, ev->tgt.ioevs[4].iv == 1 ?
				A12_BTYPE_FONT_SUPPL : A12_BTYPE_FONT, false, 0
			);
		break;
		default:
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=error:status=EINVAL:message=%s", arcan_shmif_eventstr(ev, NULL, 0));
			return true;
		}
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

void
a12_set_bhandler(struct a12_state* S,
	struct a12_bhandler_res (*on_bevent)(
		struct a12_state* S, struct a12_bhandler_meta, void* tag),
	void* tag)
{
	if (!S)
		return;

	S->binary_handler = on_bevent;
	S->binary_handler_tag = tag;
}

void* a12_sensitive_alloc(size_t nb)
{
	return arcan_alloc_mem(nb,
		ARCAN_MEM_EXTSTRUCT, ARCAN_MEM_SENSITIVE | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);
}

void a12_sensitive_free(void* ptr, size_t buf)
{
	volatile unsigned char* pos = ptr;
	for (size_t i = 0; i < buf; i++){
		pos[i] = 0;
	}
	arcan_mem_free(ptr);
}
