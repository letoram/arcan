/* Refactored version of chacha-simple, originally:
Copyright (C) 2014 insane coder (http://insanecoding.blogspot.com/,
http://chacha.insanecoding.org/)

Permission to use, copy, modify, and distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

This implementation is intended to be simple, many optimizations can be
performed.
*/

#include <stdbool.h>
#include <string.h>
#include <stdint.h>

#define ROTL32(v, n) ((v) << (n)) | ((v) >> (32 - (n)))
#define LE(p) \
	(((uint32_t)((p)[0])) | \
	((uint32_t)((p)[1]) << 8) | \
	((uint32_t)((p)[2]) << 16) | \
	((uint32_t)((p)[3]) << 24))

#define FROMLE(b, i) \
	(b)[0] = i & 0xFF; (b)[1] = (i >> 8) & 0xFF;\
	(b)[2] = (i >> 16) & 0xFF; \
	(b)[3] = (i >> 24) & 0xFF;

#define QUARTERROUND(x, a, b, c, d) \
	x[a] += x[b]; x[d] = ROTL32(x[d] ^ x[a], 16); \
	x[c] += x[d]; x[b] = ROTL32(x[b] ^ x[c], 12); \
	x[a] += x[b]; x[d] = ROTL32(x[d] ^ x[a], 8); \
	x[c] += x[d]; x[b] = ROTL32(x[b] ^ x[c], 7);

/* CTR location in keyschedule */
static const size_t counter_pos = 12;

struct chacha_ctx {
	uint32_t schedule[16];
	union {
		uint32_t u32[16];
		uint8_t u8[64];
	} keystream;
	int iterations;
	size_t pos;
	bool ready;
};

static void chacha_block(struct chacha_ctx* ctx, uint32_t output[16])
{
	uint32_t *const nonce = &ctx->schedule[counter_pos];
	int i = ctx->iterations;

	memcpy(output, ctx->schedule, sizeof(ctx->schedule));

	while (i--){
		QUARTERROUND(output, 0, 4, 8, 12)
		QUARTERROUND(output, 1, 5, 9, 13)
		QUARTERROUND(output, 2, 6, 10, 14)
		QUARTERROUND(output, 3, 7, 11, 15)
		QUARTERROUND(output, 0, 5, 10, 15)
		QUARTERROUND(output, 1, 6, 11, 12)
		QUARTERROUND(output, 2, 7, 8, 13)
		QUARTERROUND(output, 3, 4, 9, 14)
	}
	for (i = 0; i < 16; ++i){
		uint32_t result = output[i] + ctx->schedule[i];
		FROMLE((uint8_t *)(output+i), result);
	}

/*
 * Official specs calls for performing a 64 bit increment here, and limit usage
 * to 2^64 blocks.  However, recommendations for CTR mode in various papers
 * recommend including the nonce component for a 128 bit increment. This
 * implementation will remain compatible with the official up to 2^64 blocks,
 * and past that point, the official is not intended to be used. This
 * implementation with this change also allows this algorithm to become
 * compatible for a Fortuna-like construct.
*/
	if (!++nonce[0] && !++nonce[1] && !++nonce[2]){
		++nonce[3];
	}

	ctx->pos = 0;
}

static void chacha_setup(struct chacha_ctx* ctx, const uint8_t* key,
	size_t length, uint8_t nonce[8], uint64_t counter, uint8_t rounds)
{
	const char *constants =
		(length == 32) ? "expand 32-byte k" : "expand 16-byte k";

	ctx->iterations = rounds >> 1;
	ctx->schedule[0] = LE(constants + 0);
	ctx->schedule[1] = LE(constants + 4);
	ctx->schedule[2] = LE(constants + 8);
	ctx->schedule[3] = LE(constants + 12);
	ctx->schedule[4] = LE(key + 0);
	ctx->schedule[5] = LE(key + 4);
	ctx->schedule[6] = LE(key + 8);
	ctx->schedule[7] = LE(key + 12);
	ctx->schedule[8] = LE(key + 16 % length);
	ctx->schedule[9] = LE(key + 20 % length);
	ctx->schedule[10] = LE(key + 24 % length);
	ctx->schedule[11] = LE(key + 28 % length);
	ctx->schedule[12] = counter & UINT32_C(0xFFFFFFFF);
	ctx->schedule[13] = counter >> 32;
	ctx->schedule[14] = LE(nonce+0);
	ctx->schedule[15] = LE(nonce+4);
	chacha_block(ctx, ctx->keystream.u32);
	ctx->ready = true;
}

static void chacha_counter_set(
	struct chacha_ctx *ctx, uint64_t counter)
{
	ctx->schedule[12] = counter & UINT32_C(0xFFFFFFFF);
	ctx->schedule[13] = counter >> 32;
	chacha_block(ctx, ctx->keystream.u32);
}

static void chacha_apply(struct chacha_ctx *ctx,
	const uint8_t* in, uint8_t* out, size_t length)
{
	if (!length)
		return;

	size_t ofs = 0;
	while(ofs < length){
		if (ctx->pos == 64)
			chacha_block(ctx, ctx->keystream.u32);

		size_t nib = 64 - ctx->pos;
		while (nib && ofs < length){
			out[ofs] = in[ofs] ^ ctx->keystream.u8[ctx->pos++];
			nib--, ofs++;
		}
	}
}
