/*
 * Copyright: Björn Ståhl
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
#include <assert.h>
#include <ctype.h>

#include "a12.h"
#include "a12_int.h"
#include "net/a12_helper.h"

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

#include "external/zstd/zstd.h"

int a12_trace_targets = 0;
FILE* a12_trace_dst = NULL;

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
	assert(kind < COUNT_OF(header_sizes));
	return header_sizes[kind];
}

static void unlink_node(struct a12_state*, struct blob_out*);
static void dirstate_item(struct a12_state* S, struct appl_meta* C);

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
		a12int_trace(A12_TRACE_SYSTEM, "error=grow_array:reason=limit");
		DYNAMIC_FREE(dst);
		*cur_sz = 0;
		return NULL;
	}

	new_sz = pow;

	a12int_trace(A12_TRACE_ALLOC,
		"grow=queue:%d:from=%zu:to=%zu", ind, *cur_sz, new_sz);
	uint8_t* res = DYNAMIC_REALLOC(dst, new_sz);
	if (!res){
		a12int_trace(A12_TRACE_SYSTEM, "error=grow_array:reason=malloc_fail");
		DYNAMIC_FREE(dst);
		*cur_sz = 0;
		return NULL;
	}

/* init the new region */
	memset(&res[*cur_sz], '\0', new_sz - *cur_sz);

	*cur_sz = new_sz;
	return res;
}

/* never permit this to be traced in a normal build */
static void trace_crypto_key(bool srv, const char* domain, uint8_t* buf, size_t sz)
{
#ifdef _DEBUG
	char conv[sz * 3 + 2];
	for (size_t i = 0; i < sz; i++){
		sprintf(&conv[i * 3], "%02X%s", buf[i], i == sz - 1 ? "" : "-");
	}
	a12int_trace(A12_TRACE_CRYPTO, "%s%s:key=%s", srv ? "server:" : "client:", domain, conv);
#endif
}

/* set the LAST SEEN sequence number in a CONTROL message */
static void step_sequence(struct a12_state* S, uint8_t* outb)
{
	pack_u64(S->last_seen_seqnr, outb);
}

static void build_control_header(struct a12_state* S, uint8_t* outb, uint8_t cmd)
{
	memset(outb, '\0', CONTROL_PACKET_SIZE);
	step_sequence(S, outb);
	arcan_random(&outb[8], 8);
	outb[16] = S->out_channel;
	outb[17] = cmd;
}

void
a12int_request_dirlist(struct a12_state* S, bool notify)
{
	if (!S || S->cookie != 0xfeedface){
		return;
	}

	uint8_t outb[CONTROL_PACKET_SIZE];
	build_control_header(S, outb, COMMAND_DIRLIST);
	outb[18] = notify;

	a12int_trace(A12_TRACE_DIRECTORY, "request_list");
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

struct appl_meta* a12int_get_directory(struct a12_state* S, uint64_t* clk)
{
	if (clk)
		*clk = S->directory_clk;
	return S->directory;
}

/* linear search, set_directory is low N and infrequent so O^2 is ok */
static struct appl_meta* find_entry(struct a12_state* S, struct appl_meta* tgt)
{
	struct appl_meta* cur = S->directory;

	while (cur){
		if (cur->identifier == tgt->identifier){
			return cur;
		}
		cur = cur->next;
	}

	return NULL;
}

/* swapping out an existing directory is ok, the only 'requirement' is that
 * identifiers for applname are retained without collision */
void a12int_set_directory(struct a12_state* S, struct appl_meta* M)
{
/* first synch the ones that have changed */
	struct appl_meta* cur = M;
	bool updated = false;

	while (cur && S->directory){
		struct appl_meta* C = find_entry(S, cur);
		if (!C){
			updated = true;
			dirstate_item(S, cur);
		}
		else if (memcmp(C->hash, cur->hash, 4) != 0){
			updated = true;
			dirstate_item(S, cur);
		}

		cur = cur->next;
	}

	if (updated){
		uint8_t outb[CONTROL_PACKET_SIZE] = {0};
		memset(outb, '\0', CONTROL_PACKET_SIZE);
		build_control_header(S, outb, COMMAND_DIRSTATE);
		a12int_append_out(S,
			STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
	}

/* now free the old */
	struct appl_meta* C = S->directory;
	while (C){
		struct appl_meta* old = C;
		free(C->buf);

		C = C->next;
		DYNAMIC_FREE(old);
	}

	S->directory = M;
}

static void fail_state(struct a12_state* S)
{
#ifndef _DEBUG
/* overwrite all relevant state, dealloc mac/chacha - mark n random bytes for
 * continuous transfer before shutting down to be even less useful as an oracle */
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

	if (S->opts->local_role == ROLE_SOURCE){
		outb[54] = 1;
	}
	else if (S->opts->local_role == ROLE_SINK){
		outb[54] = 2;
	}
	else if (S->opts->local_role == ROLE_PROBE){
		outb[54] = 3;
	}
	else if (S->opts->local_role == ROLE_DIR){
		outb[54] = 4;
	}
	else {
		fail_state(S);
		a12int_trace(A12_TRACE_SYSTEM, "unknown_role");
		return;
	}

/* channel-id is empty */
	outb[17] = COMMAND_HELLO;
	outb[18] = ASHMIF_VERSION_MAJOR;
	outb[19] = ASHMIF_VERSION_MINOR;

/* mode indicates if we have an ephemeral-Kp exchange first or if we go
 * straight to the real one, it is also reserved as a migration path if
 * a new ciphersuite will need to be added */
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
	const uint8_t* const out, size_t out_sz, uint8_t* prepend, size_t prepend_sz)
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
		fail_state(S);
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

/*
 * If we are the client and haven't sent the first authentication request
 * yet, setup the nonce part of the cipher to random and shorten the MAC.
 *
 * Thus the first packet has a half-length MAC and use the other half to
 * provide the nonce. This is mainly to reduce code complexity somewhat
 * and not have a different pre-header length for the first packet.
 */
	size_t mac_sz = MAC_BLOCK_SZ;
	if (S->authentic != AUTH_FULL_PK && !S->server && !S->cl_firstout){
		mac_sz >>= 1;
		arcan_random(&dst[mac_sz], mac_sz);
		S->cl_firstout = true;

		chacha_set_nonce(S->dec_state, &dst[mac_sz]);
		chacha_set_nonce(S->enc_state, &dst[mac_sz]);
		a12int_trace(A12_TRACE_CRYPTO, "kind=cipher:status=init_nonce");

		trace_crypto_key(S->server, "nonce", &dst[mac_sz], mac_sz);
/* don't forget to add the nonce to the first message MAC */
		blake3_hasher_update(&S->out_mac, &dst[mac_sz], mac_sz);
	}

/* apply stream-cipher to buffer contents - ETM */
	chacha_apply(S->enc_state, &dst[data_pos], used);

/* update MAC with encrypted contents */
	blake3_hasher_update(&S->out_mac, &dst[data_pos], used);

/* sample MAC and write to buffer pos, remember it for debugging - no need to
 * chain separately as 'finalize' is not really finalized */
	blake3_hasher_finalize(&S->out_mac, &dst[mac_pos], mac_sz);
	a12int_trace(A12_TRACE_CRYPTO, "kind=mac_enc:position=%zu", S->out_mac.counter);
	trace_crypto_key(S->server, "mac_enc", &dst[mac_pos], mac_sz);

	S->stats.b_out += out_sz + prepend_sz;

/* if we have set a function that will get the buffer immediately then we set
 * the internal buffering state, this is a short-path that can be used
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
	S->left = header_sizes[STATE_NOPACKET];
	if (S->state != STATE_1STSRV_PACKET && S->state != STATE_BROKEN)
		S->state = STATE_NOPACKET;
	S->decode_pos = 0;
	S->in_channel = -1;
}

static void derive_encdec_key(
	const char* ssecret, size_t secret_len,
	uint8_t out_mac[static BLAKE3_KEY_LEN],
	uint8_t out_srv[static BLAKE3_KEY_LEN],
	uint8_t  out_cl[static BLAKE3_KEY_LEN],
	uint8_t* nonce)
{
	blake3_hasher temp;
	blake3_hasher_init_derive_key(&temp, "arcan-a12 init-packet");
	blake3_hasher_update(&temp, ssecret, secret_len);

	if (nonce){
		blake3_hasher_update(&temp, nonce, NONCE_SIZE);
	}

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
	_Static_assert(BLAKE3_KEY_LEN == 16 || BLAKE3_KEY_LEN == 32, "misconfigured blake3 size");

/* the secret is only used for the first packet */
	derive_encdec_key(secret, len, mac_key, srv_key, cl_key, nonce);

	blake3_hasher_init_keyed(&S->out_mac, mac_key);
	blake3_hasher_init_keyed(&S->in_mac,  mac_key);

	if (!S->dec_state){
		S->dec_state = DYNAMIC_MALLOC(sizeof(struct chacha_ctx));
		if (!S->dec_state){
			fail_state(S);
			return;
		}
	}

	S->enc_state = DYNAMIC_MALLOC(sizeof(struct chacha_ctx));
	if (!S->enc_state){
		DYNAMIC_FREE(S->dec_state);
		fail_state(S);
		return;
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
	if (S->server){
		trace_crypto_key(S->server, "enc_key", srv_key, BLAKE3_KEY_LEN);
		trace_crypto_key(S->server, "dec_key", cl_key, BLAKE3_KEY_LEN);

		chacha_setup(S->dec_state, cl_key, BLAKE3_KEY_LEN, 0, CIPHER_ROUNDS);
		chacha_setup(S->enc_state, srv_key, BLAKE3_KEY_LEN, 0, CIPHER_ROUNDS);
	}
	else {
		trace_crypto_key(S->server, "dec_key", srv_key, BLAKE3_KEY_LEN);
		trace_crypto_key(S->server, "enc_key", cl_key, BLAKE3_KEY_LEN);

		chacha_setup(S->enc_state, cl_key, BLAKE3_KEY_LEN, 0, CIPHER_ROUNDS);
		chacha_setup(S->dec_state, srv_key, BLAKE3_KEY_LEN, 0, CIPHER_ROUNDS);
	}

/* First setup won't have a nonce until one has been received. For that case,
 * the key-dance is only to setup MAC - just reusing the same codepath for all
 * keymanagement */
	if (nonce){
		trace_crypto_key(S->server, "state=set_nonce", nonce, NONCE_SIZE);
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

	res->shutdown_id = -1;
	for (size_t i = 0; i <= 255; i++){
		res->channels[i].unpack_state.bframe.tmp_fd = -1;
	}

	size_t len = 0;
	res->opts = DYNAMIC_MALLOC(sizeof(struct a12_context_options));
	if (!res->opts){
		DYNAMIC_FREE(res);
		return NULL;
	}
	memcpy(res->opts, opt, sizeof(struct a12_context_options));

	if (!res->opts->secret[0]){
		sprintf(res->opts->secret, "SETECASTRONOMY");
	}

	len = strlen(res->opts->secret);
	update_keymaterial(res, res->opts->secret, len, NULL);

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
	res->out_stream = 1;
	res->notify_dynamic = true;

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

	struct a12_state* S = a12_setup(opt, false);
	if (!S)
		return NULL;

/* use x25519? - pull out the public key from the supplied private and set
 * one or two rounds of exchange state, otherwise just mark the connection
 * as preauthenticated should the server reply use the correct PSK */
	uint8_t empty[32] = {0};
	uint8_t outpk[32];

/* client didn't provide an outbound key, generate one at random */
	if (memcmp(empty, opt->priv_key, 32) == 0){
		a12int_trace(A12_TRACE_SECURITY, "no_private_key:generating");
		x25519_private_key(opt->priv_key);
	}

	memcpy(S->keys.real_priv, opt->priv_key, 32);

/* single round, use correct key immediately - drop the priv-key from the input
 * arguments, keep it temporarily here until the shared secret can be
 * calculated */
	if (opt->disable_ephemeral_k){
		mode = HELLO_MODE_REALPK;
		S->authentic = AUTH_REAL_HELLO_SENT;
		memset(opt->priv_key, '\0', 32);
		x25519_public_key(S->keys.real_priv, outpk);
		trace_crypto_key(S->server, "cl-priv", S->keys.real_priv, 32);
	}

/* double-round, start by generating ephemeral key */
	else {
		mode = HELLO_MODE_EPHEMPK;
		x25519_private_key(S->keys.ephem_priv);
		x25519_public_key(S->keys.ephem_priv, outpk);
		S->authentic = AUTH_POLITE_HELLO_SENT;
	}

/* the nonce in the outbound won't be used, but it should look random still */
	uint8_t nonce[8];
	arcan_random(nonce, 8);
	trace_crypto_key(S->server, "hello-pub", outpk, 32);
	send_hello_packet(S, mode, outpk, nonce);

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

	struct a12_channel* ch = &S->channels[S->out_channel];

	a12int_encode_drop(S, S->out_channel, false);
	a12int_decode_drop(S, S->out_channel, false);

	if (ch->unpack_state.bframe.zstd){
		ZSTD_freeDCtx(ch->unpack_state.bframe.zstd);
		ch->unpack_state.bframe.zstd = NULL;
	}

	if (ch->active){
		ch->cont = NULL;
		ch->active = false;
	}

/* closing the primary channel means no more operations are permitted */
	if (S->out_channel == 0){
		fail_state(S);
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

	a12int_set_directory(S, NULL);

	if (S->prepend_unpack){
		DYNAMIC_FREE(S->prepend_unpack);
		S->prepend_unpack = NULL;
		S->prepend_unpack_sz = 0;
	}

	a12int_trace(A12_TRACE_ALLOC, "a12-state machine freed");
	DYNAMIC_FREE(S->bufs[0]);
	DYNAMIC_FREE(S->bufs[1]);
	DYNAMIC_FREE(S->opts);

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
	if (S->last_seen_seqnr <= S->current_seqnr)
		S->stats.packets_pending = S->last_seen_seqnr - S->current_seqnr;

/* and finally the actual type in the inner block */
	int state_id = S->decode[MAC_BLOCK_SZ + 8];

	if (state_id >= STATE_BROKEN){
		a12int_trace(A12_TRACE_SYSTEM, "state=broken:unknown_command=%"PRIu8, S->state);
		fail_state(S);
		return;
	}

/* transition to state based on type, from there we know how many bytes more
 * we need to process before the MAC can be checked */
	S->state = state_id;
	a12int_trace(A12_TRACE_TRANSFER, "seq=%"PRIu64
		":left=%"PRIu16":state=%"PRIu8, S->last_seen_seqnr, S->left, S->state);
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
	if (S->authentic > AUTH_REAL_HELLO_SENT){
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

	if (!S->dec_state){
		a12int_trace(A12_TRACE_SECURITY, "srvfirst:no_decode");
		fail_state(S);
		return;
	}

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

static void fill_diropened(struct a12_state* S, struct a12_dynreq r)
{
	uint8_t outb[CONTROL_PACKET_SIZE];

	build_control_header(S, outb, COMMAND_DIROPENED);
	outb[18] = r.proto;
	memcpy(&outb[19], r.host, 46);
	pack_u16(r.port, &outb[65]);
	memcpy(&outb[67], r.authk, 12);
	memcpy(&outb[79], r.pubk, 32);

	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

static void command_diropened(struct a12_state* S)
{
/* local- copy the members so the closure is allowed to queue a new one */
	void(* oc)(struct a12_state*, struct a12_dynreq, void* tag) = S->pending_dynamic.closure;
	void* tag = S->pending_dynamic.tag;

	S->pending_dynamic.closure = NULL;
	S->pending_dynamic.tag = NULL;
	S->pending_dynamic.active = false;

	struct a12_dynreq rep = {
		.proto = S->decode[18]
	};

	memcpy(rep.host, &S->decode[19], 46);
	unpack_u16(&rep.port, &S->decode[65]);
	memcpy(rep.authk, &S->decode[67], 12);

/* this is used both for source and sink, for sink swap in the pubk of the request */
	uint8_t nullk[32] = {0};
	if (memcmp(nullk, &S->decode[79], 32) == 0)
		memcpy(rep.pubk, S->pending_dynamic.req_key, 32);
	else
		memcpy(rep.pubk, &S->decode[79], 32);

	oc(S, rep, tag);
}

static void command_diropen(
	struct a12_state* S, uint8_t mode, uint8_t kpub_tgt[static 32])
{
/* a12.h misuse */
	struct a12_unpack_cfg* C = &S->channels[0].raw;
	if (!C->directory_open){
		a12int_trace(A12_TRACE_SECURITY, "kind=warning:diropen_no_handler");
		return;
	}

/* forward the request */
	struct a12_dynreq out = {0};
	uint8_t outb[CONTROL_PACKET_SIZE];

/* the implementation is expected to set the authk as it might be outsourced
 * to an external oracle that coordinates with the partner in question */
	if (C->directory_open(S, kpub_tgt, mode, &out, C->tag)){
		fill_diropened(S, out);
	}
/* failure is just an empty command */
	else {
		build_control_header(S, outb, COMMAND_DIROPENED);
		a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
	}
}

static void command_cancelstream(
	struct a12_state* S, uint32_t streamid, uint8_t reason, uint8_t stype)
{
	struct blob_out* node = S->pending;
	a12int_trace(A12_TRACE_SYSTEM, "stream_cancel:%"PRIu32":%"PRIu8, streamid, reason);

/* the other end indicated that the current codec or data source is broken,
 * propagate the error to the client (if in direct passing mode) otherwise just
 * switch the encoder for next frame - any recoverable decode error should
 * really be in h264 et al. now so assume that. There might also be a point
 * in force-inserting a RESET/STEPFRAME */
	if (stype == 0){
		if (reason == STREAM_CANCEL_DECODE_ERROR){
			a12int_trace(A12_TRACE_VIDEO,
				"kind=decode_degrade:codec=h264:reason=sink rejected format");
			S->advenc_broken = true;
		}

/* other reasons means that the image contents is already known or too dated,
 * currently just ignore that - when we implement proper image hashing and can
 * use that for known types (cursor, ...) then reconsider */
		return;
	}
	else if (stype == 1){
		return;
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

	if (S->decode[52] == 1){
		bframe->zstd = ZSTD_createDCtx();
		if (!bframe->zstd){
			a12_stream_cancel(S, channel);
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=error:source=binarystream:kind=zstd_fail:ch=%d", (int) channel);
			return;
		}
	}

	uint32_t streamid;
	unpack_u32(&streamid, &S->decode[18]);
	bframe->streamid = streamid;
	unpack_u64(&bframe->size, &S->decode[22]);
	bframe->type = S->decode[30];
	unpack_u32(&bframe->identifier, &S->decode[31]);
	memcpy(bframe->checksum, &S->decode[35], 16);
	bframe->tmp_fd = -1;
	memcpy(bframe->extid, &S->decode[53], 16);

	bframe->active = true;
	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=header:stream=%"PRId64":left=%"PRIu64":ch=%d:compressed=%d",
		bframe->streamid, bframe->size, channel, (int) S->decode[52]
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
		.identifier = bframe->identifier,
		.type = bframe->type,
		.dcont = S->channels[channel].cont,
		.fd = -1
	};
	memcpy(bm.extid, bframe->extid, 16);
	memcpy(bm.checksum, bframe->checksum, 16);

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

/* note that the cancel itself does not affect the congestion stats, it is when
 * we get a frame ack that is within the frame_window that the pending set is
 * decreased */
	outb[16] = channel;
	outb[17] = COMMAND_CANCELSTREAM;
	pack_u32(1, &outb[18]);
	outb[22] = reason;
	outb[23] = STREAM_TYPE_VIDEO;

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
	outb[23] = STREAM_TYPE_BINARY;
	bframe->active = false;
	bframe->streamid = -1;
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);

	if (bframe->zstd){
		ZSTD_freeDCtx(bframe->zstd);
		bframe->zstd = NULL;
	}

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

	unpack_u32(&aframe->id, &S->decode[18]);
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
	uint8_t outb[CONTROL_PACKET_SIZE];
	build_control_header(S, outb, COMMAND_CANCELSTREAM);

	outb[16] = ch;
	pack_u32(id, &outb[18]);
	outb[22] = (uint8_t) fail; /* user-cancel, can't handle, already cached */

	a12int_append_out(S,
		STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

/*
static void dump_window(struct a12_state* S)
{
	printf("[%zu] -", S->congestion_stats.pending);
	for (size_t i = 0; i < VIDEO_FRAME_DRIFT_WINDOW; i++){
		printf(" %"PRIu32, S->congestion_stats.frame_window[i]);
	}
}
*/

void a12int_stream_ack(struct a12_state* S, uint8_t ch, uint32_t id)
{
	uint8_t outb[CONTROL_PACKET_SIZE];
	build_control_header(S, outb, COMMAND_PING);

	outb[16] = ch;
	pack_u32(id, &outb[18]);

	a12int_trace(A12_TRACE_DEBUG, "ack=%"PRIu32, id);

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
	unpack_u32(&vframe->id, &S->decode[18]);
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

	if (S->decode[35] ^ (!!(cont->hints & SHMIF_RHINT_ORIGO_LL))){
		if (S->decode[35])
			cont->hints = cont->hints | SHMIF_RHINT_ORIGO_LL;
		else
			cont->hints = cont->hints & (~SHMIF_RHINT_ORIGO_LL);
		hints_changed = true;
	}

	if (vframe->postprocess == POSTPROCESS_VIDEO_TZSTD &&
		!(cont->hints & SHMIF_RHINT_TPACK)){
		cont->hints |= SHMIF_RHINT_TPACK;
		hints_changed = true;
	}
	else if ((cont->hints & SHMIF_RHINT_TPACK) &&
		 vframe->postprocess != POSTPROCESS_VIDEO_TZSTD){
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
		vframe->inbuf = DYNAMIC_MALLOC(vframe->inbuf_sz);
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

static struct blob_out** alloc_attach_blob(struct a12_state* S)
{
	struct blob_out* next = DYNAMIC_MALLOC(sizeof(struct blob_out));
	if (!next){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=ENOMEM");
		return NULL;
	}

	*next = (struct blob_out){
		.type = A12_BTYPE_BLOB,
		.streaming = true,
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
	}
	*parent = next;

	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=reserve:queue=%zu:total=%zu", n_streaming, n_known);

	return parent;
}

void a12_set_session(
	struct pk_response* dst, uint8_t pubk[static 32], uint8_t privk[static 32])
{
	x25519_public_key(privk, dst->key_pub);
	x25519_shared_secret(dst->key_session, privk, pubk);
}

/*
 * Simplified form of enqueue bstream below, we already have the buffer
 * in memory so just build a different blob-out node with a copy
 */
void a12_enqueue_blob(struct a12_state* S, const char* const buf,
	size_t buf_sz, uint32_t id, int type, const char extid[static 16])
{
	struct blob_out** next = alloc_attach_blob(S);
	if (!next)
		return;

	char* nbuf = DYNAMIC_MALLOC(buf_sz);
	if (!buf){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=ENOMEM");
		DYNAMIC_FREE(*next);
		*next = NULL;
		return;
	}

	memcpy(nbuf, buf, buf_sz);
	(*next)->buf = nbuf;
	(*next)->buf_sz = buf_sz;
	(*next)->left = buf_sz;
	(*next)->identifier = id;
	(*next)->type = type;
	memcpy((*next)->extid, extid, 16);

	blake3_hasher hash;
	blake3_hasher_init(&hash);
	blake3_hasher_update(&hash, nbuf, buf_sz);
	blake3_hasher_finalize(&hash, (*next)->checksum, 16);

	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=added:type=fixed_blob:stream=no:size=%zu", buf_sz);

	S->active_blobs++;
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
void a12_enqueue_bstream(struct a12_state* S,
	int fd, int type, uint32_t id, bool streaming, size_t sz,
	const char extid[static 16])
{
	struct blob_out** parent = alloc_attach_blob(S);
	if (!parent)
		return;

	struct blob_out* next = *parent;
	next->type = type;
	next->identifier = id;

	if (type == A12_BTYPE_APPL || type == A12_BTYPE_APPL_RESOURCE){
		snprintf(next->extid, 16, "%s", extid);
	}

	if (type == A12_BTYPE_FONT_SUPPL || type == A12_BTYPE_FONT)
		next->rampup_seqnr = S->current_seqnr + 1;

/* [MISSING]
 * Insertion priority sort goes here, be wary of channel-id in heuristic
 * though, and try to prioritize channel that has focus over those that
 * don't - and if not appending, the unlink at the fail-state need to
 * preserve forward integrity
 **/
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
		next->left = sz;
		return;
	}

	off_t fend = lseek(fd, 0, SEEK_END);
	if (fend == 0){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EEMPTY");
		*parent = NULL;
		DYNAMIC_FREE(next);
		return;
	}

	if (-1 == fend){
/* force streaming if the host system can't manage */
		switch(errno){
		case ESPIPE:
		case EOVERFLOW:
			next->streaming = true;
			a12int_trace(A12_TRACE_BTRANSFER,
				"kind=added:type=%d:stream=yes:size=%zu", type, next->left);
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
	DYNAMIC_FREE(next);
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
	uint8_t remote_pubk[32];

	uint8_t nonce[8];
	int cfl = S->decode[20];

	memcpy(remote_pubk, &S->decode[21], 32);
	a12int_trace(A12_TRACE_CRYPTO, "state=complete:method=%d", cfl);

	/* here is a spot for having more authentication modes if needed (version bump) */
	if (cfl != HELLO_MODE_EPHEMPK && cfl != HELLO_MODE_REALPK){
		a12int_trace(A12_TRACE_SECURITY, "unknown_hello");
		fail_state(S);
		return;
	}

/* public key is ephemeral, generate new pair, send a hello out with the new
 * one THEN derive new keys for authentication and so on. After this the
 * connection flows just like if the ephem mode wasn't used - the client
 * will send its real Pk and we respond in kind. The protection this affords us
 * is that you need an active MiM to gather Pks for tracking. */
	if (cfl == HELLO_MODE_EPHEMPK){
		uint8_t ek[32];
		x25519_private_key(ek);
		x25519_public_key(ek, pubk);
		arcan_random(nonce, 8);
		send_hello_packet(S, HELLO_MODE_EPHEMPK, pubk, nonce);

		x25519_shared_secret((uint8_t*)S->opts->secret, ek, remote_pubk);
		trace_crypto_key(S->server, "ephem_pub", pubk, 32);
		update_keymaterial(S, S->opts->secret, 32, nonce);
		S->authentic = AUTH_EPHEMERAL_PK;
		return;
	}

/* public key is the real one, use an external lookup function for mapping
 * to keystores defined by the api user */
	if (!S->opts->pk_lookup){
		a12int_trace(A12_TRACE_CRYPTO, "state=eimpl:kind=x25519-no-lookup");
		fail_state(S);
		return;
	}

/* the lookup function returns the key that should be used in the reply
 * and to calculate the shared secret */
	trace_crypto_key(S->server, "state=client_pk", remote_pubk, 32);
	struct pk_response res = S->opts->pk_lookup(remote_pubk, S->opts->pk_lookup_tag);
	if (!res.authentic){
		a12int_trace(A12_TRACE_CRYPTO, "state=eperm:kind=x25519-pk-fail");
		fail_state(S);
		return;
	}

	memcpy((uint8_t*)S->opts->secret, res.key_session, 32);
	memcpy(pubk, res.key_pub, 32);

/* hello packet here will still use the keystate from the process_srvfirst
 * which will use the client provided nonce, KDF on preshare-pw */
	arcan_random(nonce, 8);
	send_hello_packet(S, HELLO_MODE_REALPK, pubk, nonce);
	memcpy(S->keys.remote_pub, &S->decode[21], 32);
	trace_crypto_key(S->server, "state=client_pk_ok:respond_pk", pubk, 32);

/* now we can switch keys, note that the new nonce applies for both enc and dec
 * states regardless of the nonce the client provided in the first message */
	trace_crypto_key(S->server, "state=server_ssecret", (uint8_t*)S->opts->secret, 32);
	update_keymaterial(S, S->opts->secret, 32, nonce);

/* and done, mark latched so a12_unpack saves buffer and returns */
	S->authentic = AUTH_FULL_PK;
	S->auth_latched = true;

	if (S->on_auth)
		S->on_auth(S, S->auth_tag);
}

static void hello_auth_client_hello(struct a12_state* S)
{
	if (!S->opts->pk_lookup){
		a12int_trace(A12_TRACE_CRYPTO, "state=eimpl:kind=x25519-no-lookup");
		fail_state(S);
		return;
	}

	trace_crypto_key(S->server, "server_pk", &S->decode[21], 32);
	struct pk_response res = S->opts->pk_lookup(&S->decode[21], S->opts->pk_lookup_tag);
	if (!res.authentic){
		a12int_trace(A12_TRACE_CRYPTO, "state=eperm:kind=25519-pk-fail");
		fail_state(S);
		return;
	}

/* now we can calculate the x25519 shared secret, overwrite the preshared
 * secret slot in the initial configuration and repeat the key derivation
 * process to get new enc/dec/mac keys. */
	x25519_shared_secret((uint8_t*)S->opts->secret, S->keys.real_priv, &S->decode[21]);
	trace_crypto_key(S->server, "state=client_ssecret", (uint8_t*)S->opts->secret, 32);
	update_keymaterial(S, S->opts->secret, 32, &S->decode[8]);

	S->authentic = AUTH_FULL_PK;
	S->auth_latched = true;
	S->remote_mode = S->decode[54];
	memcpy(S->keys.remote_pub, &S->decode[21], 32);
	a12int_trace(A12_TRACE_SYSTEM, "remote_mode=%d", S->remote_mode);

	if (S->on_auth)
		S->on_auth(S, S->auth_tag);
}

static void process_hello_auth(struct a12_state* S)
{
	/*
- [18]      Version major : uint8 (shmif-version until 1.0)
- [19]      Version minor : uint8 (shmif-version until 1.0)
- [20]      Flags         : uint8
- [21+ 32]  x25519 Pk     : blob,
- [54]      Source/Sink
	 */

	if (S->decode[54]){
		S->remote_mode = ROLE_PROBE;
		if ((S->opts->local_role == ROLE_SOURCE && S->decode[54] == ROLE_SINK)){
			a12int_trace(A12_TRACE_SYSTEM, "kind=match:local=source:remote=sink");
			S->remote_mode = ROLE_SINK;
		}
		else if(S->opts->local_role == ROLE_SINK && S->decode[54] == ROLE_SOURCE){
			a12int_trace(A12_TRACE_SYSTEM, "kind=match:local=sink:remote=source");
			S->remote_mode = ROLE_SOURCE;
		}
		else if (S->opts->local_role == ROLE_SINK && S->decode[54] == ROLE_SINK){
			a12int_trace(A12_TRACE_SYSTEM, "kind=mismatch:local=sink:remote=sink");
			fail_state(S);
			return;
		}
/* client: we might just be probing, if so continue without matching */
		else if (S->opts->local_role == ROLE_PROBE){
		}
/* server: client is just probing, continue with normal auth */
		else if (S->decode[54] == ROLE_PROBE){
			if (S->opts->local_role != ROLE_PROBE){
/* both sides probing is fishy */
			}
			else {
				a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EINVAL:probe");
				fail_state(S);
				return;
			}
		}
		else if (S->decode[54] == ROLE_DIR){
			S->remote_mode = ROLE_DIR;
			if (S->opts->local_role != ROLE_SINK && S->opts->local_role != ROLE_SOURCE){
				a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EIMPL:dir2dir");
				fail_state(S);
				return;
			}
			else {
				a12int_trace(A12_TRACE_SYSTEM, "kind=match:local=source:remote=dir");
			}
		}
/* we are directory, the other can be directory, source or sink */
		else if (S->opts->local_role == ROLE_DIR){
			S->remote_mode = S->decode[54];
			if (S->remote_mode != ROLE_SOURCE &&
				S->remote_mode != ROLE_DIR && S->remote_mode != ROLE_SINK){
				fail_state(S);
				a12int_trace(A12_TRACE_SYSTEM,
					"kind=error:status=EINVALID:local=dir:remote=unknown");
				return;
			}
		}
		else {
			fail_state(S);
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=error:status=EINVALID:hello_kind=%"PRIu8, S->decode[64]);
			return;
		}
	}
/* ignore any mismatch for the time being in order to retain backwards compat. */
	else
		;

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

		uint8_t realpk[32];
		x25519_public_key(S->keys.real_priv, realpk);

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

static void command_pingpacket(struct a12_state* S, uint32_t sid)
{
/* might get empty pings, ignore those as they only update last_seen_seq */
	if (!sid)
		return;

	if (sid == S->shutdown_id){
		S->state = STATE_BROKEN;
		a12int_trace(A12_TRACE_SYSTEM, "terminal_ping=%"PRIu32, sid);
		return;
	}

	size_t i;
	size_t wnd_sz = VIDEO_FRAME_DRIFT_WINDOW;
	for (i = 0; i < wnd_sz; i++){
		uint32_t cid = S->congestion_stats.frame_window[i];

		if (!cid){
			a12int_trace(A12_TRACE_DEBUG, "ack-sid %"PRIu32" not in wnd", sid);
			return;
		}

		if (cid == sid)
			break;
	}

/* the ID might be bad (after the last sent) or truncated or outdated.
 * Truncation / outdating can happen if the source continues to push frames
 * while fully congested. It is the user of the implementation that needs to
 * determine actions on congestion/backpressure. */
	if (i >= wnd_sz - 1){
		uint32_t latest =
			S->congestion_stats.frame_window[wnd_sz-1];

		if (sid >= latest){
			a12int_trace(A12_TRACE_DEBUG, "ack-sid %"PRIu32" after wnd", sid);
			S->congestion_stats.pending = 0;
			for (size_t i = 0; i < wnd_sz; i++){
				S->congestion_stats.frame_window[i] = 0;
			}
			return;
		}

/* in the truncation case, we only retain the last 'sent' and slide
 * the rest of the window */
		if (i < latest)
			i = wnd_sz - 2;
	}

	size_t i_start = i + 1;
	size_t to_move = 0;

/* shrink the moveset to only cover non-0 */
	while (i_start + to_move < wnd_sz &&
		S->congestion_stats.frame_window[i_start+to_move]){
		to_move++;
	}
	S->congestion_stats.pending = to_move;

	memmove(
		S->congestion_stats.frame_window,
		&S->congestion_stats.frame_window[i_start],
		to_move * sizeof(uint32_t)
	);

	S->stats.vframe_backpressure = to_move +
		(S->congestion_stats.frame_window[0] - sid);

	for (i = to_move; i < wnd_sz; i++)
		S->congestion_stats.frame_window[i] = 0;
}

static void dirstate_item(struct a12_state* S, struct appl_meta* C)
{
	uint8_t outb[CONTROL_PACKET_SIZE];
	build_control_header(S, outb, COMMAND_DIRSTATE);

	pack_u16(C->identifier, &outb[18]);
	pack_u16(C->categories, &outb[20]);
	pack_u16(C->permissions, &outb[22]);
	memcpy(&outb[24], C->hash, 4);
	pack_u64(C->buf_sz, &outb[28]);
	memcpy(&outb[36], C->appl.name, 18);
	memcpy(&outb[55], C->appl.short_descr, 69);
	a12int_append_out(S,
		STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
	a12int_trace(A12_TRACE_DIRECTORY, "send:name=%s", C->appl.name);
}

static void send_dirlist(struct a12_state* S)
{
	uint8_t outb[CONTROL_PACKET_SIZE];
	struct appl_meta* C = S->directory;

	while (C){
		dirstate_item(S, C);
		C = C->next;
	}

/* empty to terminate */
	memset(outb, '\0', CONTROL_PACKET_SIZE);
	build_control_header(S, outb, COMMAND_DIRSTATE);
	a12int_append_out(S,
		STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

/* just unpack and forward to the event handler, arcan proper can deal with the
 * event as it is mostly verbatim when it passes through afsrv_net and
 * arcan-net has the same structures available */
static void command_dirdiscover(struct a12_state* S)
{
	if (!S->on_discover)
		return;

	uint8_t type = S->decode[18];
	bool added = S->decode[19];

/* grab petname, sanitize to 7-bit alnum + _ */
	char petname[17] = {0};
	memcpy(petname, &S->decode[20], 16);
	for (size_t i = 0; petname[i]; i++){
		if (!isalnum(petname[i]) && petname[i] != '_'){
			a12int_trace(A12_TRACE_SECURITY, "discover:malformed_petname=%s", petname);
			return;
		}
	}

	uint8_t pubk[32];
	memcpy(pubk, &S->decode[36], 32);
	S->on_discover(S, type, petname, added, pubk, S->discover_tag);
}

static void add_dirent(struct a12_state* S)
{
/* end of update is marked with an empty entry */
	if (S->decode[36] == '\0'){
		S->directory_clk++;
		return;
	}

	struct appl_meta* new = malloc(sizeof(struct appl_meta));
	if (!new)
		return;

/* buf / buf_sz are left empty until we request / retrieve it as a
 * file based on the current server id */
	*new = (struct appl_meta){0};

	unpack_u16(&new->identifier, &S->decode[18]);
	unpack_u16(&new->categories, &S->decode[20]);
	unpack_u16(&new->permissions, &S->decode[22]);
	memcpy(new->hash, &S->decode[24], 4);
	unpack_u64(&new->buf_sz, &S->decode[28]);
	memcpy(new->appl.name, &S->decode[36], 18);
	memcpy(new->appl.short_descr, &S->decode[55], 69);
	new->update_ts = arcan_timemillis();

	if (!S->directory){
		S->directory = new;
		return;
	}

	struct appl_meta* cur = S->directory;
	struct appl_meta* prev = NULL;

	while (cur){
/* override / update? */
		if (cur->identifier == new->identifier){
			new->next = cur->next;
			if (prev)
				prev->next = new;
			else
				S->directory = new;
			DYNAMIC_FREE(cur);
			return;
		}

/* or attach to end */
		if (!cur->next){
			cur->next = new;
			return;
		}

/* or step */
		prev = cur;
		cur = cur->next;
	}

/* shouldn't be reached */
	DYNAMIC_FREE(new);
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

	a12int_trace(A12_TRACE_DEBUG, "cmd=%"PRIu8, command);

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
		command_cancelstream(S, streamid, S->decode[22], S->decode[23]);
	}
	break;
	case COMMAND_DIROPEN:{
		if (S->opts->local_role == ROLE_DIR){
			command_diropen(S, S->decode[18], &S->decode[19]);
		}
		else
			a12int_trace(A12_TRACE_SECURITY, "diropen:wrong_role");
	}
	case COMMAND_DIROPENED:{
		if (S->pending_dynamic.active)
			command_diropened(S);
		else
			a12int_trace(A12_TRACE_SECURITY, "diropened:no_pending_request");
	}
	break;
	case COMMAND_PING:{
		uint32_t streamid;
		unpack_u32(&streamid, &S->decode[18]);
		a12int_trace(A12_TRACE_DEBUG, "ping=%"PRIu32, streamid);
		command_pingpacket(S, streamid);
	}
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
	case COMMAND_DIRLIST:
/* force- synch dynamic entries */
		S->notify_dynamic = S->decode[18];
		a12int_trace(A12_TRACE_DIRECTORY, "dirlist:notify=%d", (int) S->notify_dynamic);
		send_dirlist(S);
/* notify the directory side that this action occurred */
		on_event(NULL, 0, &(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_MESSAGE,
			.ext.message.data = "a12:dirlist"
		}, tag);
	break;
	case COMMAND_DIRDISCOVER:
		command_dirdiscover(S);
	break;

/* Security notice: this allows the remote end to update / populate the
 * local directory list for the ongoing session. If we are operating in
 * 'directory to directory' this might end up being important yet desired.
 *
 * Allowing the local list to be updated, and it being shared with a server
 * instance becomes a building block for relaying appl transfers dynamically.
 */
	case COMMAND_DIRSTATE:
		add_dirent(S);
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
	if (!cont && !S->binary_handler && !cbf->tunnel){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:status=EINVAL:"
			"ch=%d:message=no segment or bhandler mapped", S->in_channel);
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

/* compression enabled? */
	size_t ntw = S->decode_pos;
	uint8_t* buf = S->decode;
	bool free_buf = false;

/* for now each zstd transfer is self-contained and thus capped to a ~64k
 * output per message and should be determinable from each received message.
 * This is hardly the best / most efficient use of zstd here (similar applies
 * to video, but there the output size is always determinable and can be
 * calculated independently and compared) and will need to be reworked */
	if (cbf->zstd){
		uint64_t content_sz = ZSTD_getFrameContentSize(S->decode, S->decode_pos);
		if (ZSTD_CONTENTSIZE_UNKNOWN == content_sz ||
		    ZSTD_CONTENTSIZE_ERROR == content_sz){
			a12int_trace(A12_TRACE_SYSTEM, "kind=zstd_bad:unknown_size");
			a12_stream_cancel(S, S->in_channel);
			reset_state(S);
			return;
		}

		buf = DYNAMIC_MALLOC(content_sz);
		ntw = content_sz;

		if (!buf){
			a12int_trace(A12_TRACE_ALLOC,
				"kind=zstd_buffer_fail:size=%zu", (size_t) content_sz);
			a12_stream_cancel(S, S->in_channel);
			reset_state(S);
			return;
		}

		uint64_t decode =
			ZSTD_decompressDCtx(cbf->zstd, buf, content_sz, S->decode, S->decode_pos);
		S->decode_pos = 0;

		if (ZSTD_isError(decode)){
			a12int_trace(A12_TRACE_SYSTEM, "kind=zstd_fail:code=%zu", (size_t) decode);
			a12_stream_cancel(S, S->in_channel);
			reset_state(S);
			return;
		}
		else
			a12int_trace(A12_TRACE_BTRANSFER, "kind=zstd_state:size=%"PRIu64, decode);

		free_buf = true;
	}

/* Flush it out to the assigned descriptor, this is currently likely to be
 * blocking and can cascade quite far down the chain, consider a drag and drop
 * that routes via a pipe onwards to another client. Normal splice etc.
 * operations won't work so we are left with this. To not block video/audio
 * processing we would have to buffer / flush this separately, with a big
 * complexity leap. */
	if (-1 != cbf->tmp_fd){
		size_t pos = 0;

		while(pos < ntw){
			ssize_t status = write(cbf->tmp_fd, &buf[pos], ntw - pos);
			if (-1 == status){
				if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
					continue;

/* so there was a problem writing (dead pipe, out of space etc). send a cancel
 * on the stream,this will also forward the status change to the event handler
 * itself who is responsible for closing the tmp_fd */
				a12_stream_cancel(S, S->in_channel);
				reset_state(S);
				if (free_buf)
					DYNAMIC_FREE(buf);
				return;
			}
			else
				pos += status;
		}
	}

	if (free_buf)
		DYNAMIC_FREE(buf);

	if (!S->binary_handler || cbf->tunnel)
		return;

/* is it a streaming transfer or a known size? */
	if (cbf->size){
		if (ntw > cbf->size){
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=btransfer_overflow:size=%zu:ch=%d:stream=%"PRId64,
				(size_t)(ntw - cbf->size), S->in_channel, cbf->streamid
			);
			cbf->size = 0;
		}
		else
			cbf->size -= ntw;

		if (!cbf->size){
			a12int_trace(A12_TRACE_BTRANSFER,
				"kind=completed:ch=%d:stream=%"PRId64, S->in_channel, cbf->streamid);
			cbf->active = false;

/* finally forward all the metadata to the handler and let the recipient
 * pack it into the proper event structure and so on. */
			struct a12_bhandler_meta bm = {
				.type = cbf->type,
				.streamid = cbf->streamid,
				.channel = S->in_channel,
				.identifier = cbf->identifier,
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

/* send that we ack:ed the transfer so the other side gets a chance to react
 * even if they have nothing else queued */
			a12int_stream_ack(S, S->in_channel, cbf->identifier);
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

		a12int_stream_ack(S, S->in_channel, cvf->id);
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
		DYNAMIC_FREE(S->channels[chid].cont);
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
	struct arcan_shmif_cont* fake = DYNAMIC_MALLOC(ct_sz);
	if (!fake)
		return;

	*fake = (struct arcan_shmif_cont){};
	S->channels[chid].cont = fake;
	S->channels[chid].raw = cfg;
	S->channels[chid].active = CHANNEL_RAW;

/* these are tracked per context and not per channel */
	S->on_discover = cfg.on_discover;
	S->discover_tag = cfg.on_discover_tag;
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

/* flush any prequeued buffer, see comment at the end of the function */
	if (S->prepend_unpack){
		uint8_t* tmp_buf = S->prepend_unpack;
		size_t tmp_sz = S->prepend_unpack_sz;
		a12int_trace(A12_TRACE_SYSTEM, "kind=prebuf:size=%zu", tmp_sz);
		S->prepend_unpack_sz = 0;
		S->prepend_unpack = NULL;
		a12_unpack(S, tmp_buf, tmp_sz, tag, on_event);
		DYNAMIC_FREE(tmp_buf);
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
	S->stats.b_in += ntr;

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

/* This is an ugly thing - so a buffer can contain a completed authentication
 * sequence and subsequent data. An API consumer may well need to do additional
 * work in between completed authentication and proper use or data might get
 * lost. The easiest way to solve this after the fact was to add a latched
 * buffer stage.
 *
 *  on_authentication_completed:
 *   - set latched state
 *   - if data remaining: save a copy and return
 *
 *  next unpack:
 *   - check if buffered data exist
 *   - process first, then move on to submitted buffer
 */
	if (buf_sz){
		if (!S->auth_latched){
			a12_unpack(S, &buf[ntr], buf_sz, tag, on_event);
			return;
		}

		S->auth_latched = false;
		S->prepend_unpack = DYNAMIC_MALLOC(buf_sz);

		if (!S->prepend_unpack){
			a12int_trace(A12_TRACE_ALLOC, "kind=error:latch_buffer_sz=%zu", buf_sz);
			fail_state(S);
			return;
		}

		a12int_trace(A12_TRACE_SYSTEM, "kind=auth_latch:size=%zu", buf_sz);
		memcpy(S->prepend_unpack, &buf[ntr], buf_sz);
		S->prepend_unpack_sz = buf_sz;
		return;
	}
	if (S->auth_latched)
		S->auth_latched = false;
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
	void* buf = DYNAMIC_MALLOC(65536);
	*nts = 0;

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

		DYNAMIC_FREE(buf);
		return NULL;
	}

	*die = false;
	if (nr == 0){
		DYNAMIC_FREE(buf);
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
	if (node->zstd){
		ZSTD_freeCCtx(node->zstd);
		node->zstd = NULL;
	}

	DYNAMIC_FREE(node);
}

/*
 * tail-recurse back into queue_node until the
 */
static size_t queue_node(struct a12_state* S, struct blob_out* node);
static bool flush_compressed(
	struct a12_state* S, struct blob_out* node, char* buf, size_t nts)
{
	uint8_t outb[1 + 4 + 2];
	outb[0] = node->chid;
	pack_u32(node->streamid, &outb[1]);

	if (!node->left && !nts){
		a12int_trace(A12_TRACE_BTRANSFER,
			"kind=compressed_stream_over:stream=%zu:ch=%d",
			(size_t)node->streamid, (int) node->chid
		);
		return false;
	}

/* Nts and buffer size comes from the read function and its static upper buffer
 * bound, this is mainly to balance between interleaving (higher prio data) and
 * throughput. An external oracle should be allowed to influence this using
 * transport information on bandwidth and MTUs. There are better (?) ways of
 * using ZSTD here, but all are quite complicated. The problem is the normal of
 * chunking+metadata and the discrepancy between bytes in vs bytes out. A
 * trivially compressible input set might just yield a byte or two for a full
 * input buffer, yet we will 'terminate' compression and send of a chunk with
 * header regardless - reducing efficiency.
 *
 * The flow here might be unintuitive but -
 *  - a12_flush checks if there is space to interleave binary data
 *  - if so, append_blob will check if there is a binary transfer queued
 *    it picks this in first come first server order, but could be reordered
 *  - it enters queue_node which reads up to a cap of bytes into a buffer
 *  - this buffer is forwarded to flush_compressed or uncompressed depending
 *    on the zstd- context availability which should be setup when the stream
 *    is initialised.
 *  - we arrive here, compress and flush whatever is provided, and return if
 *    there is more data to be processed (the nts for the blob stream)
 *    and if there isn't, queue_node will unlink and free us.
 *  - otherwise a12int_append_out will increase the outgoing buffer that
 *    a12_flush checks, and the cycle repeats itself.
 * */

	size_t max = ZSTD_compressBound(nts);
	if (max >= 65536){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=compressed_stream_overflow:cap=64k:size=%zu", max);
		return false;
	}

	void* compressed = DYNAMIC_MALLOC(max);
	size_t out = ZSTD_compressCCtx(node->zstd, compressed, max, buf, nts, 3);
	pack_u16(out, &outb[5]);

	a12int_append_out(S,
		STATE_BLOB_PACKET, (uint8_t*) compressed, out, outb, sizeof(outb));

	DYNAMIC_FREE(compressed);

	if (node->left){
		a12int_trace(A12_TRACE_BTRANSFER, "kind=compressed_block:"
			"stream=%"PRIu64":ch=%d:size=%zu:base=%zu:left=%zu",
			(uint64_t)node->streamid, (int) node->chid, out, nts, node->left
		);
		node->left -= nts;
		return node->left != 0;
	}

	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=compressed_stream=%zu:ch=%d:size=%zu:base=%zu",
		(size_t)node->streamid, (int) node->chid, out, nts
	);

	return true;
}

static bool flush_uncompressed(
	struct a12_state* S, struct blob_out* node, char* buf, size_t nts)
{
	uint8_t outb[1 + 4 + 2];
	outb[0] = node->chid;
	pack_u32(node->streamid, &outb[1]);
	pack_u16(nts, &outb[5]);
	a12int_append_out(S, STATE_BLOB_PACKET, (uint8_t*) buf, nts, outb, sizeof(outb));

/* if we have a fixed known size .. */
	if (node->left){
		node->left -= nts;
		a12int_trace(A12_TRACE_BTRANSFER,
			"kind=block:stream=%"PRIu64":ch=%d:size=%zu:left=%zu",
			node->streamid, (int)node->chid, nts, node->left
			);
		return node->left != 0;
	}

	a12int_trace(A12_TRACE_BTRANSFER,
		"kind=block:stream=%zu:ch=%d:streaming:size=%zu",
		(size_t) node->streamid, (int)node->chid, nts
	);

/* otherwise we are streaming from an unknown source and the EOB determines */
	return nts != 0;
}

static size_t begin_bstream(struct a12_state* S, struct blob_out* node)
{
	uint8_t outb[CONTROL_PACKET_SIZE];

	build_control_header(S, outb, COMMAND_BINARYSTREAM);
	outb[16] = node->chid;

	S->out_stream++;
	pack_u32(S->out_stream, &outb[18]);      /* [18 .. 21] stream-id */
	pack_u64(node->left, &outb[22]);         /* [22 .. 29] total-size */
	outb[30] = node->type;
	pack_u32(node->identifier, &outb[31]);   /* 31..34 : id-token */
	memcpy(&outb[35], node->checksum, 16);

/* enable compression if possible - zstd has a decent entropy estimator so even
 * for precompressed source material the overhead isn't that substantial, still
 * could be added as an option for the bstream creation function but just let
 * it be the default for now */
	node->zstd = ZSTD_createCCtx();
	if (node->zstd){
		ZSTD_CCtx_setParameter(node->zstd, ZSTD_c_nbWorkers, 4);
		outb[52] = 1;
	}

/* only used for two subtypes but will be set to 0 otherwise */
	memcpy(&outb[53], node->extid, 16);
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);

	node->active = true;
	node->streamid = S->out_stream;
	a12int_trace(
		A12_TRACE_BTRANSFER, "kind=created:size=%zu:stream:%"PRIu64":ch=%d",
		node->left, node->streamid, node->chid
	);

/* set a small cap for the first packet, and defer the next queue node until
 * the ack:ed serial has advanced a bit to let the other end cancel before we
 * push too much so that we don't just burst - better rampup is needed here */
	return 16384;
}

static size_t queue_node(struct a12_state* S, struct blob_out* node)
{
	uint16_t nts;
	size_t cap = node->left;
	if (cap == 0 || cap > 64096)
		cap = 64096;

	bool die;
	bool free_buf;
	char* buf;

/* not activated, so build a header first */
	if (!node->active){
		size_t rampup = begin_bstream(S, node);
		if (rampup < cap)
			cap = rampup;
	}

/* if we have a non-streaming pre-allocated source, just slice off and keep */
	if (node->buf){
		buf = &node->buf[node->buf_sz - node->left];
		nts = cap;
		die = false;
		free_buf = false;
	}
	else {
		buf = read_data(node->fd, cap, &nts, &die);
	}

/* streaming or file source that broke before we finished sending it all */
	if (!buf && (die || !node->zstd)){
		a12_stream_cancel(S, S->in_channel);
		if (die){
			unlink_node(S, node);
		}
		return 0;
	}

/* might not have data to send yet */
	if (!nts)
		return nts;

/* keep it around and referenced for being able to revert / disable compression
 * should some edge case need arise */
	if (node->zstd)
		die = !flush_compressed(S, node, buf, nts);
	else
		die = !flush_uncompressed(S, node, buf, nts);

	if (free_buf)
		DYNAMIC_FREE(buf);

	if (die)
		unlink_node(S, node);

	return nts;
}

static size_t append_blob(struct a12_state* S, int mode)
{
/* find suitable blob */
	if (mode == A12_FLUSH_NOBLOB || !S->pending)
		return 0;

/* The last seen seqnr shows how big the window drift is between us and the
 * other side. Control packets contain sequence numbers, and the last one
 * seen. When a binary transfer that is likely to be rejected due to being
 * cached - transfer is delayed until the other end has had enough time to
 * cancel the stream. */
	if (
		S->pending->rampup_seqnr &&
		S->last_seen_seqnr < S->pending->rampup_seqnr)
	{
		return 0;
	}

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

/* Nothing in the outgoing buffer? then we can pull in whatever data transfer
 * is pending, if there are any queued. Repeat the append- until we have an
 * outgoing buffer of a certain size. */
	if (S->buf_ofs == 0){
		while (allow_blob > A12_FLUSH_NOBLOB &&
			append_blob(S, allow_blob) && S->buf_ofs < BLOB_QUEUE_CAP){}

		if (!S->buf_ofs)
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
	uint8_t outb[CONTROL_PACKET_SIZE];
	build_control_header(S, outb, COMMAND_NEWCH);

	outb[18] = chid;
	outb[19] = segkind;
	outb[20] = 0;
	pack_u32(cookie, &outb[21]);

	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

void
a12_set_channel(struct a12_state* S, uint8_t chid)
{
	if (chid != S->out_channel)
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
	uint32_t sid = S->out_stream;

	a12int_trace(A12_TRACE_VIDEO,
		"out vframe: %zu*%zu @%zu,%zu+%zu,%zu", vb->w, vb->h, w, h, x, y);
#define argstr S, vb, opts, sid, x, y, w, h, chunk_sz, S->out_channel

	size_t now = arcan_timemillis();

/* we have a pre-compressed passthrough - send it with the FOURCC stored
 * in place of expanded length and just send the buffer as is */
	if (vb->flags.compressed)
		a12int_encode_passthrough(argstr);
	else
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
/* these are the same, the encoder will pick which based on ref. frame */
	case VFRAME_METHOD_ZSTD:
	case VFRAME_METHOD_DZSTD:
		a12int_encode_dzstd(argstr);
	break;
	case VFRAME_METHOD_H264:
		if (S->advenc_broken)
			a12int_encode_dzstd(argstr);
		else
			a12int_encode_h264(argstr);
	break;
	case VFRAME_METHOD_TPACK_ZSTD:
		a12int_encode_ztz(argstr);
	break;
	default:
		a12int_trace(A12_TRACE_SYSTEM, "unknown format: %d\n", opts.method);
		return;
	break;
	}

	size_t then = arcan_timemillis();
	if (then > now){
		S->stats.ms_vframe = then - now;
		S->stats.ms_vframe_px = (float)(then - now) / (float)(w * h);
	}
}

bool
a12_channel_enqueue(struct a12_state* S, struct arcan_event* ev)
{
	if (!S || S->cookie != 0xfeedface || !ev)
		return false;

	char empty_ext[16] = {0};

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
				ev->tgt.ioevs[0].iv, A12_BTYPE_STATE, false, 0, 0, empty_ext);
			return true;
		break;

/* let the bstream- side determine if the source is streaming or not */
		case TARGET_COMMAND_BCHUNK_IN:
			a12_enqueue_bstream(S,
				ev->tgt.ioevs[0].iv, A12_BTYPE_BLOB, false, 0, 0, empty_ext);
				return true;
		break;

/* weird little detail with the fonthint is that the real fonthint event
 * sans descriptor will be transferred first, the other side will catch
 * it and merge */
		case TARGET_COMMAND_FONTHINT:
			a12_enqueue_bstream(S,
				ev->tgt.ioevs[0].iv, ev->tgt.ioevs[4].iv == 1 ?
				A12_BTYPE_FONT_SUPPL : A12_BTYPE_FONT, false, 0, 0, empty_ext
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
	"btransfer",
	"security",
	"directory"
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
	if (ind >= sizeof(groups)/sizeof(groups[0]))
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

struct a12_iostat a12_state_iostat(struct a12_state* S)
{
/* just an accessor, values are updated continously */
	return S->stats;
}

void* a12_sensitive_alloc(size_t nb)
{
	return arcan_alloc_mem(nb,
		ARCAN_MEM_EXTSTRUCT, ARCAN_MEM_SENSITIVE | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);
}

void a12int_step_vstream(struct a12_state* S, uint32_t id)
{
	size_t slot = S->congestion_stats.pending;

/* clamp so that sz-1 compared to sz-2 can indicate how reckless the api
 * user is with regards to backpressure */
	if (S->congestion_stats.pending < VIDEO_FRAME_DRIFT_WINDOW - 1)
		S->congestion_stats.pending++;

	S->congestion_stats.frame_window[slot] = S->out_stream++;
}

bool a12_ok(struct a12_state* S)
{
	return S->state != STATE_BROKEN;
}

void a12_sensitive_free(void* ptr, size_t buf)
{
	arcan_random(ptr, buf);
	arcan_mem_free(ptr);
}

int a12_remote_mode(struct a12_state* S)
{
	return S->remote_mode;
}

void a12int_notify_dynamic_resource(struct a12_state* S,
		const char* petname, uint8_t kpub[static 32], uint8_t role, bool added)
{
	if (!S->notify_dynamic){
		a12int_trace(A12_TRACE_DIRECTORY, "ignore_no_dynamic");
		return;
	}

	a12int_trace(A12_TRACE_DIRECTORY,
		"dynamic:forward:name=%s:role=%d:added=%d", petname,(int)role,(int)added);

	uint8_t outb[CONTROL_PACKET_SIZE];
	build_control_header(S, outb, COMMAND_DIRDISCOVER);
	outb[18] = role;
	outb[19] = added;
/* note: this does not align on unicode codepoints or utf8- encoding,
 * petname is expected to have been shortened / aligned before */
	snprintf((char*)&outb[20], 16, "%s", petname);
	memcpy(&outb[36], kpub, 32);
	a12int_append_out(S,
		STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);
}

bool a12_request_dynamic_resource(struct a12_state* S,
	uint8_t ident_pubk[static 32],
	bool prefer_tunnel,
	void(*request_reply)(struct a12_state*, struct a12_dynreq, void* tag),
	void* tag)
{
	if (S->pending_dynamic.active || S->remote_mode != ROLE_DIR){
		return false;
	}

/* role source just need the closure tagged actually */
	S->pending_dynamic.active = true;
	S->pending_dynamic.closure = request_reply;
	S->pending_dynamic.tag = tag;
	memcpy(S->pending_dynamic.req_key, ident_pubk, 32);

	if (S->opts->local_role != ROLE_SINK)
		return true;

/* this key isn't as sensitive as it will only be used to authenticate the
 * mediated nested connections ephemeral layer not added to the keystore. */
	uint8_t outb[CONTROL_PACKET_SIZE];
	build_control_header(S, outb, COMMAND_DIROPEN);
	arcan_random(S->pending_dynamic.priv_key, 32);
	memcpy(&outb[19], ident_pubk, 32);
	outb[18] = prefer_tunnel ? 4 : 2;
	x25519_public_key(S->pending_dynamic.priv_key, &outb[52]);
	a12int_append_out(S, STATE_CONTROL_PACKET, outb, CONTROL_PACKET_SIZE, NULL, 0);

	return true;
}

void a12_set_endpoint(struct a12_state* S, const char* ep)
{
	free(S->endpoint);
	S->endpoint = ep ? strdup(ep) : NULL;
}

const char* a12_get_endpoint(struct a12_state* S)
{
	return S->endpoint;
}

void a12_supply_dynamic_resource(struct a12_state* S, struct a12_dynreq r)
{
	fill_diropened(S, r);
}

bool
	a12_write_tunnel(struct a12_state* S,
		uint8_t chid, const uint8_t* const buf, size_t buf_sz)
{
	if (!buf_sz)
		return false;

	if (!S->channels[chid].active){
		a12int_trace(A12_TRACE_BTRANSFER, "write_tunnel:bad_channel=%"PRIu8, chid);
		return false;
	}

/* tunnel packet is a simpler form of binary stream with no rampup,
 * multiplexing, checksum, compression, cancellation, ... just straight into
 * channel */
	uint8_t outb[1 + 4 + 2] = {0};
	outb[0] = chid;
	pack_u16(buf_sz, &outb[5]);
	a12int_append_out(S, STATE_BLOB_PACKET, buf, buf_sz, outb, sizeof(outb));

	a12int_trace(
		A12_TRACE_BTRANSFER, "write_tunnel:ch=%"PRIu8":nb=%zu", chid, buf_sz);
	return true;
}

int
	a12_tunnel_descriptor(struct a12_state* S, uint8_t chid)
{
	if (S->channels[chid].active){
		return S->channels[chid].unpack_state.bframe.tmp_fd;
	}
	else
		return -1;
}

bool
	a12_set_tunnel_sink(struct a12_state* S, uint8_t chid, int fd)
{
	if (S->channels[chid].active){
		a12int_trace(A12_TRACE_DIRECTORY, "swap_sink:chid=%"PRIu8, chid);
		if (0 < S->channels[chid].unpack_state.bframe.tmp_fd)
			close(S->channels[chid].unpack_state.bframe.tmp_fd);
		return false;
	}

	if (-1 == fd){
		S->channels[chid].active = false;
		S->channels[chid].unpack_state.bframe.tunnel = false;
		S->channels[chid].unpack_state.bframe.tmp_fd = -1;
		return true;
	}

	S->channels[chid].active = true;
	S->channels[chid].unpack_state.bframe = (struct binary_frame){
		.tmp_fd = fd,
		.tunnel = true,
		.active = true
	};
	return true;
}

void a12_shutdown_id(struct a12_state* S, uint32_t id)
{
	S->shutdown_id = id;
}
