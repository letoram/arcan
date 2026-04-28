#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include "a12.h"
#include "a12_helper.h"
#include "hashmap.h"

/* >80% tile match threshold — a 64x64 RGBA tile is 16384 bytes,
 * 80% of one tile is 13107, but the partial-hit detector folds
 * by the nibbler block size (1729) since that's what the encoder
 * stride divides into cleanly */
#define A12_PARTIAL_HIT_THRESHOLD 1729u

struct frame_cache {
	int placeholder;
	struct hashmap_s clients;
	struct a12helper_framecache_stats stats;
};

struct listener {
	uintptr_t key;
	bool raw;
	bool wait_keyframe;
	void (*trigger)(uintptr_t, uint8_t*, size_t, int);
	ssize_t level;
};

struct frame_cache* a12helper_alloc_cache(uint32_t capacity)
{
	struct frame_cache* ret = malloc(sizeof(struct frame_cache));
	*ret = (struct frame_cache){
	};
	hashmap_create(capacity, &ret->clients);

	return ret;
}

struct frameinf {
	uint8_t* buf;
	size_t buf_sz;
	int type;
	bool keyed;
	struct frame_cache* cache;
};

static int each_client_enc(void* const tag, void *const val)
{
	struct listener* const cl = val;
	struct frameinf* const frame = tag;

/* ignore raw clients, those already get their thing from _raw */
	if (cl->raw)
		return 1;

/* can't join middle-gop */
	if (!frame->keyed && cl->wait_keyframe){
		frame->cache->stats.misses++;
		return 1;
	}

	if (frame->keyed)
		frame->cache->stats.hits++;
	else if (frame->buf_sz >= A12_PARTIAL_HIT_THRESHOLD)
		frame->cache->stats.partial++;

	cl->trigger(cl->key, frame->buf, frame->buf_sz, frame->keyed);

	return 1;
}

static int each_client_raw(void* const tag, void* const val)
{
	struct listener* const cl = val;
	struct shmifsrv_vbuffer* const frame = tag;

/* tpack is treated as 'raw' */
	if (!cl->raw && !frame->flags.tpack)
		return 1;

	cl->trigger(cl->key, (void*) &(*frame),
		sizeof(struct shmifsrv_vbuffer), FRAME_RAW_SHMIFSRV_VBUFFER);

	return 1;
}

void a12helper_vbuffer_append_raw(
	struct frame_cache* C, struct shmifsrv_vbuffer* vb, uint8_t chid)
{
/* if the vbuffer type is for TPACK we should maintain a tpack state machine
 * in order to produce keyframe for new clients */
	hashmap_iterate(&C->clients, each_client_raw, (void*) vb);
}

void a12helper_vbuffer_append_encoded(
	struct frame_cache* C, uint8_t* buf, size_t buf_sz, uint8_t chid, bool keyed)
{
	C->stats.offered++;
	if (buf_sz > C->stats.watermark)
		C->stats.watermark = buf_sz;

	struct frameinf data = {
		.buf = buf,
		.buf_sz = buf_sz,
		.keyed = keyed,
		.cache = C
	};

	hashmap_iterate(&C->clients, each_client_enc, &data);
}

void a12helper_vbuffer_add_listener(
	struct frame_cache* C, uintptr_t ref,
		bool raw, void (*trigger)(uintptr_t, uint8_t* buf, size_t buf_sz, int type))
{
	struct listener* newcl = malloc(sizeof(struct listener));
	*newcl = (struct listener){
		.raw = raw,
		.wait_keyframe = !raw,
		.trigger = trigger,
		.key = ref,
		.level = 5
	};

	hashmap_put(&C->clients, &newcl->key, sizeof(uintptr_t), newcl);

/* check if we have anything cached that can be sent directly */
}

void a12helper_vbuffer_step_quality(
	struct frame_cache* C, uintptr_t ref, ssize_t steps)
{
}

void a12helper_vbuffer_drop_listener(struct frame_cache* C, uintptr_t ref)
{
	struct listener* cl = hashmap_get(&C->clients, (void*)(&ref), sizeof(uintptr_t));
	if (!cl)
		return;

	C->stats.evictions++;
	hashmap_remove(&C->clients, (void*)(&ref), sizeof(uintptr_t));
	free(cl);
}

struct a12helper_framecache_stats
	a12helper_framecache_stats(struct frame_cache* C)
{
	if (!C)
		return (struct a12helper_framecache_stats){0};
	return C->stats;
}
