/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <pthread.h>
#include <assert.h>

#include <arcan_shmif.h>

#include "rwstat.h"

struct pattern {
	uint8_t* buf;
	size_t buf_sz;
	size_t buf_pos;
	uint8_t ind;
	uint32_t col;
};

struct rwstat_ch_priv {
	struct pattern* patterns;
	size_t n_patterns;
	size_t patterns_sz;

	size_t ind;

/* track write-offset for each row individually
 * to distinguish between synchronous options and not */
	size_t offsets[4];
	enum RWSTAT_CHOPTS opts;

	struct rwstat_ctx* parent;
};

struct rwstat_ctx {
	struct rwstat_ch** channels;
	size_t n_channels;
	size_t channels_sz;

	pthread_mutex_t th_sync;

	struct arcan_shmif_cont acon;
};

static void ch_signal(struct rwstat_ch* ch, uint32_t col, uint8_t ind)
{
	struct rwstat_ch_priv* chp = ch->priv;

	uint32_t* vidp = (uint32_t*) chp->parent->acon.vidp;
 	vidp += RW_SIGNAL * chp->parent->acon.addr->w;
	vidp[ind] = col;

	if (!(chp->opts & RWSTAT_CH_SYNCHRONOUS))
		arcan_shmif_signal(&chp->parent->acon, SHMIF_SIGVID);
}

static void ch_data(struct rwstat_ch* ch, uint8_t* buf, size_t buf_sz)
{
	ch->bytes_out += buf_sz;
	struct rwstat_ch_priv* chp = ch->priv;

/* need to stay locked the entire time so we don't get eaten by a resize */
	pthread_mutex_lock(&chp->parent->th_sync);

	size_t stride = chp->parent->acon.addr->w;
	uint32_t* base = (uint32_t*) chp->parent->acon.vidp;
	assert((uintptr_t)base % 4);

	base += stride * chp->ind;

/* should fold nicely, just adding here for convenience */
	uint32_t* vidps[4] = {0};
	vidps[RW_DATA_SZ  ] = base + RW_DATA_SZ   * stride;
	vidps[RW_HISTOGRAM] = base + RW_HISTOGRAM * stride;
	vidps[RW_SIGNAL   ] = base + RW_SIGNAL    * stride;
	vidps[RW_PATTERN  ] = base + RW_PATTERN   * stride;

/* pattern match */
	for (size_t j = 0; j < chp->n_patterns; j++)
		for (size_t i = 0; i < buf_sz; i++){
			if (buf[i] == chp->patterns[j].buf[chp->patterns[j].buf_pos]){
				chp->patterns[j].buf_pos++;

				if (chp->patterns[j].buf_sz == chp->patterns[j].buf_pos){
					vidps[RW_PATTERN][chp->patterns[j].ind] = chp->patterns[j].col;
					if (!(chp->opts & RWSTAT_CH_SYNCHRONOUS))
						chp->offsets[RW_PATTERN] = (chp->offsets[RW_PATTERN] + 1) % stride;
				}

			}
			else
				chp->patterns[j].buf_pos = 0;
		}

/* update histogram, should repack here
 * if native-endian vs color format doesn't match */
	for (size_t i = 0; i < buf_sz; i++)
		vidps[RW_HISTOGRAM][ buf[i] ]++;

/* update write-size */
	vidps[RW_DATA_SZ][ chp->offsets[RW_DATA_SZ] ] += buf_sz;

	if (!(chp->opts & RWSTAT_CH_SYNCHRONOUS))
		chp->offsets[RW_DATA_SZ] = (chp->offsets[RW_DATA_SZ] + 1) % stride;

/* if offset hits buffer width and we're not synchronous,
 * signal a video transfer on the shared memory page */
	if (!(chp->opts & RWSTAT_CH_SYNCHRONOUS))
		arcan_shmif_signal(&chp->parent->acon, SHMIF_SIGVID);

	pthread_mutex_unlock(&chp->parent->th_sync);
}

struct rwstat_ctx* rwstat_create(struct arcan_shmif_cont dst)
{
	struct rwstat_ctx* res = malloc(sizeof(struct rwstat_ctx));
	memset(res, '\0', sizeof(struct rwstat_ctx));

	res->channels = malloc(sizeof(struct rwstat_ch*) * 8);
	memset(res->channels, '\0', sizeof(struct rwstat_ch*) * 8);
	res->channels_sz = 8;
	res->acon = dst;
	pthread_mutex_init(&res->th_sync, NULL);

	return res;
}

struct rwstat_ch* rwstat_addch(struct rwstat_ctx* ctx, enum RWSTAT_CHOPTS opt)
{
	size_t ind = ctx->n_channels;
	struct rwstat_ch* res;

/* find available slot */
	for (size_t i = 0; i < ctx->channels_sz; i++){
		if (ctx->channels[i] == NULL)
			ind = i;
			goto add;
	}

	if (ctx->channels_sz == ctx->n_channels){
		ctx->channels_sz += 8;
		struct rwstat_ch* res = realloc(ctx->channels,
			sizeof(struct rwstat_ch*) * ctx->channels_sz);

		if (!res){
			ctx->channels_sz -= 8;
			return NULL;
		}

		memset(&res[ctx->channels_sz - 9], '\0', sizeof(struct rwstat_ch*) * 8);

		ctx->channels[ind] = res;

		if (!arcan_shmif_resize(&ctx->acon,
			ctx->acon.addr->w, ctx->channels_sz * rwstat_row_ch))
			return NULL;
	}
	ind = ctx->n_channels;
	ctx->n_channels++;

add:
	res = malloc(sizeof(struct rwstat_ch));
	res->bytes_in = res->bytes_out = 0;
	res->ch_data = ch_data;
	res->ch_signal = ch_signal;
	res->priv = malloc(sizeof(struct rwstat_ch_priv));
	memset(res->priv, '\0', sizeof(struct rwstat_ch_priv));
	res->priv->parent = ctx;
	ctx->channels[ind] = res;

	return res;
}

bool rwstat_addpattern(struct rwstat_ch* ch,
	uint8_t signal, uint32_t col, void* buf, size_t buf_sz)
{
	void* buf_cp = malloc(buf_sz);
	if (!buf_cp)
		return false;

	struct rwstat_ch_priv* chp = ch->priv;
	if (chp->n_patterns+1 > chp->patterns_sz){
		void* buf = realloc(chp->patterns, chp->patterns_sz + 8);
		if (!buf){
			free(buf_cp);
			return false;
		}

		chp->patterns = buf;
		memset(&chp->patterns[chp->n_patterns], '\0', sizeof(struct pattern) * 8);
		chp->patterns_sz += 8;
	}

	struct pattern* newp = &chp->patterns[chp->n_patterns];
	chp->n_patterns++;
	memcpy(buf_cp, buf, buf_sz);

	newp->buf = buf_cp;
	newp->buf_sz = buf_sz;
	newp->col = col;
	newp->ind = signal;

	return true;
}

void rwstat_dropch(struct rwstat_ctx* ctx, struct rwstat_ch** src_ch)
{
	for (size_t i = 0; i < ctx->n_channels; i++){
		if (ctx->channels[i] == *src_ch){
			ctx->channels[i] = NULL;
			break;
		}
	}

	free((*src_ch)->priv);
	free(src_ch);
	*src_ch = NULL;
}

void rwstat_free(struct rwstat_ctx** ctx, bool shmif_dealloc)
{
	pthread_mutex_lock(&(*ctx)->th_sync);

	for (size_t i = 0; i < (*ctx)->n_channels; i++)
		if ( (*ctx)->channels[i])
			rwstat_dropch(*ctx, &((*ctx)->channels[i]));

	if (shmif_dealloc)
		arcan_shmif_drop(&(*ctx)->acon);

	pthread_mutex_destroy(&(*ctx)->th_sync);

	free(*ctx);
	*ctx = NULL;
}

void rwstat_tick(struct rwstat_ctx* ctx)
{
	bool sync = false;

	pthread_mutex_lock(&ctx->th_sync);

	size_t stride = ctx->acon.addr->w;

	for (size_t i = 0; i < ctx->n_channels; i++){
		struct rwstat_ch* ch = ctx->channels[i];
		if (!ch || !(ch->priv->opts & RWSTAT_CH_SYNCHRONOUS))
			continue;

		sync = true;

		struct rwstat_ch_priv* chp = ch->priv;

		uint32_t* base = (uint32_t*) ctx->acon.vidp;
		assert((uintptr_t)base % 4);
		base += stride * ch->priv->ind;

		uint32_t* vidps[4] = {0};

		vidps[RW_DATA_SZ  ] = base + RW_DATA_SZ   * stride;
		vidps[RW_HISTOGRAM] = base + RW_HISTOGRAM * stride;
		vidps[RW_SIGNAL   ] = base + RW_SIGNAL    * stride;
		vidps[RW_PATTERN  ] = base + RW_PATTERN   * stride;

		chp->offsets[RW_DATA_SZ]++;
		chp->offsets[RW_SIGNAL]++;
		chp->offsets[RW_PATTERN]++;

/* scroll remove and replace offsets with % stride to
 * get classic "L/R overwrite behavior */
		if (chp->offsets[RW_DATA_SZ] >= stride){
			chp->offsets[RW_DATA_SZ] = stride - 1;
			memmove(&vidps[RW_DATA_SZ],
				&vidps[RW_DATA_SZ] + 4, (stride - 1) * 4);
		}

		vidps[RW_DATA_SZ][chp->offsets[RW_DATA_SZ]] = 0;

		if (chp->offsets[RW_SIGNAL] >= stride){
			chp->offsets[RW_SIGNAL] = stride - 1;
			memmove(&vidps[RW_SIGNAL],
				&vidps[RW_SIGNAL] + 4, (stride - 1) * 4);
		}

		vidps[RW_SIGNAL][chp->offsets[RW_SIGNAL]] = 0;

		if (chp->offsets[RW_PATTERN] >= stride){
			chp->offsets[RW_PATTERN] = stride - 1;
			memmove(&vidps[RW_PATTERN], &vidps[RW_PATTERN] + 4, (stride - 1) * 4);
		}

		vidps[RW_SIGNAL][chp->offsets[RW_SIGNAL]] = 0;
	}

/*
 * if we have synchronous channels,
 * slide offsets and signal
 */

	if (sync)
		arcan_shmif_signal(&ctx->acon, SHMIF_SIGVID);

	for (size_t i = 0; i < ctx->n_channels; i++){
		struct rwstat_ch* ch = ctx->channels[i];
		if (!ch || !(ch->priv->opts & RWSTAT_CH_HISTOGRAM_GLOBAL))
			continue;

		uint32_t* base = (uint32_t*) ctx->acon.vidp;
		assert((uintptr_t)base % 4);
		base += stride * (ch->priv->ind + RW_HISTOGRAM);
		memset(base, '\0', 256 * 4);
	}

	pthread_mutex_unlock(&ctx->th_sync);
}
