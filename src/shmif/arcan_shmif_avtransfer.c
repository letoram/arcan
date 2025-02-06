#include <arcan_shmif.h>
#include <pthread.h>
#include "platform/shmif_platform.h"
#include "shmif_privint.h"
#include <inttypes.h>

static bool calc_dirty(
	struct arcan_shmif_cont* ctx, shmif_pixel* old, shmif_pixel* new)
{
	shmif_pixel diff = SHMIF_RGBA(0, 0, 0, 255);
	shmif_pixel ref = SHMIF_RGBA(0, 0, 0, 255);

/* find dirty y1, if this does not find anything, short-out */
	size_t cy = 0;
	for (; cy < ctx->h && diff == ref; cy++){
		for (size_t x = 0; x < ctx->w && diff == ref; x++)
			diff |= old[ctx->pitch * cy + x] ^ new[ctx->pitch * cy + x];
	}

	if (diff == ref)
		return false;

	ctx->dirty.y1 = cy - 1;

/* find dirty y2, since y1 is dirty there must be one */
	diff = ref;
	for (cy = ctx->h - 1; cy && diff == ref; cy--){
		for (size_t x = 0; x < ctx->w && diff == ref; x++)
			diff |= old[ctx->pitch * cy + x] ^ new[ctx->pitch * cy + x];
	}

/* dirty region starts at y1 and ends < y2 */
	ctx->dirty.y2 = cy + 1;

/* now do x in the same way, the order matters as the search space is hopefully
 * reduced with y, and the data access patterns are much more predictor
 * friendly */

	size_t cx;
	diff = ref;
	for (cx = 0; cx < ctx->w && diff == ref; cx++){
		for (cy = ctx->dirty.y1; cy < ctx->dirty.y2 && diff == ref; cy++)
			diff |= old[ctx->pitch * cy + cx] ^ new[ctx->pitch * cy + cx];
	}
	ctx->dirty.x1 = cx - 1;

	diff = ref;
	for (cx = ctx->w - 1; cx > 0 && diff == ref; cx--){
		for (cy = ctx->dirty.y1; cy < ctx->dirty.y2 && diff == ref; cy++)
			diff |= old[ctx->pitch * cy + cx] ^ new[ctx->pitch * cy + cx];
	}

	ctx->dirty.x2 = cx + 1;

	return true;
}

static bool step_v(struct arcan_shmif_cont* ctx, int sigv)
{
	struct shmif_hidden* priv = ctx->priv;
	bool lock = false;

/* store the current hint flags, could do away with this stage by
 * only changing hints at resize_ stage */
	atomic_store(&ctx->addr->hints, ctx->hints);
	priv->vframe_id++;

/* subregion is part of the shared block and not the video buffer
 * itself. this is a design flaw that should be moved into a
 * VBI- style post-buffer footer */
	if (ctx->hints & SHMIF_RHINT_SUBREGION){

/* set if we should trim the dirty region based on current ^ last buffer,
 * but it only works if we are >= double buffered and buffers are populated */
		if ((sigv & SHMIF_SIGVID_AUTO_DIRTY) &&
			priv->vbuf_nbuf_active && priv->vbuf_cnt > 1){
			shmif_pixel* old;
			if (priv->vbuf_ind == 0)
				old = priv->vbuf[priv->vbuf_cnt-1];
			else
				old = priv->vbuf[priv->vbuf_ind-1];

			if (!calc_dirty(ctx, ctx->vidp, old)){
				log_print("%lld: SIGVID (auto-region: no-op)", arcan_timemillis());
				return false;
			}
		}

		if (ctx->dirty.x2 <= ctx->dirty.x1 || ctx->dirty.y2 <= ctx->dirty.y1){
			log_print("%lld: SIGVID "
				"(id: %"PRIu64", force_full: dirty-inval-region: %zu,%zu-%zu,%zu)",
				arcan_timemillis(),
				priv->vframe_id,
				(size_t)ctx->dirty.x1, (size_t)ctx->dirty.y1,
				(size_t)ctx->dirty.x2, (size_t)ctx->dirty.y2
			);
			ctx->dirty.x1 = 0;
			ctx->dirty.y1 = 0;
			ctx->dirty.x2 = ctx->w;
			ctx->dirty.y2 = ctx->h;
		}

		if (priv->log_event){
			log_print("%lld: SIGVID (id: %"PRIu64", block: %d region: %zu,%zu-%zu,%zu)",
				arcan_timemillis(),
				priv->vframe_id,
				(sigv & SHMIF_SIGBLK_NONE) ? 0 : 1,
				(size_t)ctx->dirty.x1, (size_t)ctx->dirty.y1,
				(size_t)ctx->dirty.x2, (size_t)ctx->dirty.y2
			);
		}

		atomic_store(&ctx->addr->dirty, ctx->dirty);

/* set an invalid dirty region so any subsequent signals would be ignored until
 * they are updated (i.e. something has changed) */
		ctx->dirty.y2 = ctx->dirty.x2 = 0;
		ctx->dirty.y1 = ctx->h;
		ctx->dirty.x1 = ctx->w;
	}
	else {
		if (priv->log_event){
			log_print("%lld: SIGVID (id: %"PRIu64", block: %d full)",
				arcan_timemillis(),
				priv->vframe_id,
				(sigv & SHMIF_SIGBLK_NONE) ? 0 : 1
			);
		}
	}

/* mark the current buffer as pending, this is used when we have
 * non-subregion + (double, triple, quadruple buffer) rendering */
	int pending = atomic_fetch_or_explicit(
		&ctx->addr->vpending, 1 << priv->vbuf_ind, memory_order_release);
	atomic_store_explicit(&ctx->addr->vready,
		priv->vbuf_ind+1, memory_order_release);

/* let a latched support content analysis work through the buffer
 * while pending before we try to slide window or synch */
	if (priv->support_window_hook)
		priv->support_window_hook(ctx, SUPPORT_EVENT_VSIGNAL);

/* slide window so the caller don't have to care about which
 * buffer we are actually working against */
	priv->vbuf_ind++;
	priv->vbuf_nbuf_active = true;
	if (priv->vbuf_ind == priv->vbuf_cnt)
		priv->vbuf_ind = 0;

/* note if we need to wait for an ack before continuing */
	lock = priv->vbuf_cnt == 1 || (pending & (1 << priv->vbuf_ind));
	ctx->vidp = priv->vbuf[priv->vbuf_ind];

/* protect against reordering, like not needed after atomic- switch */
	FORCE_SYNCH();
	return lock;
}

static bool step_a(struct arcan_shmif_cont* ctx)
{
	struct shmif_hidden* priv = ctx->priv;
	bool lock = false;

	if (ctx->abufpos)
		ctx->abufused = ctx->abufpos * sizeof(shmif_asample);

	if (ctx->abufused == 0)
		return false;

/* atomic, set [pending, used] -> flag */
	int pending = atomic_fetch_or_explicit(&ctx->addr->apending,
		1 << priv->abuf_ind, memory_order_release);
	atomic_store_explicit(&ctx->addr->abufused[priv->abuf_ind],
		ctx->abufused, memory_order_release);
	atomic_store_explicit(&ctx->addr->aready,
		priv->abuf_ind+1, memory_order_release);

/* now it is safe to slide local references */
	pending |= 1 << priv->abuf_ind;
	priv->abuf_ind++;
	if (priv->abuf_ind == priv->abuf_cnt)
		priv->abuf_ind = 0;
	ctx->abufused = ctx->abufpos = 0;
	ctx->audp = priv->abuf[priv->abuf_ind];
	lock = priv->abuf_cnt == 1 || (pending & (1 << priv->abuf_ind));

	FORCE_SYNCH();
	return lock;
}

unsigned arcan_shmif_signal(struct arcan_shmif_cont* C, int mask)
{
	if (!C || !C->addr || !C->vidp)
		return 0;

	struct shmif_hidden* P = C->priv;
	if (!P)
		return 0;

/* sematics for output segments are easier, no chunked buffers
 * or hooks to account for */
	if (is_output_segment(P->type)){
		if (mask & SHMIF_SIGVID)
			atomic_store(&C->addr->vready, 0);
		if (mask & SHMIF_SIGAUD)
			atomic_store(&C->addr->aready, 0);
		return 0;
	}

/* if we are in migration there is no reason to go into signal until that
 * has been dealt with */
	if (P->in_migrate)
		return 0;

/* and if we are in signal, migration will need to unlock semaphores so we
 * leave signal and any held mutex on the context will be released until NEXT
 * signal that would then let migration continue on other thread. */
	P->in_signal = true;

/*
 * To protect against some callers being stuck in a 'just signal as a means of
 * draining buffers'. We can only initiate fallback recovery here if the
 * context is not unlocked, the current thread is holding the lock and there
 * is no on-going migration
 */
	if (!shmif_platform_check_alive(C)){
		C->abufused = C->abufpos = 0;
		shmif_platform_fallback(C, P->alt_conn, true);
		P->in_signal = false;
		return 0;
	}

	unsigned startt = arcan_timemillis();
	if ( (mask & SHMIF_SIGVID) && P->video_hook)
		mask = P->video_hook(C);

	if ( (mask & SHMIF_SIGAUD) && P->audio_hook)
		mask = P->audio_hook(C);

	if ( mask & SHMIF_SIGAUD ){
		bool lock = step_a(C);

/* watchdog will pull this for us */
		if (lock && !(mask & SHMIF_SIGBLK_NONE))
			arcan_sem_wait(P->asem);
		else
			arcan_sem_trywait(P->asem);
	}
/* for sub-region multi-buffer synch, we currently need to
 * check before running the step_v */
	if (mask & SHMIF_SIGVID){
		while ((C->hints & SHMIF_RHINT_SUBREGION)
			&& C->addr->vready && shmif_platform_check_alive(C))
			arcan_sem_wait(P->vsem);

		bool lock = step_v(C, mask);

		if (lock && !(mask & SHMIF_SIGBLK_NONE)){
			while (C->addr->vready && shmif_platform_check_alive(C))
				arcan_sem_wait(P->vsem);
		}
		else
			arcan_sem_trywait(P->vsem);
	}

	P->in_signal = false;
	return arcan_timemillis() - startt;
}

unsigned arcan_shmif_signalhandle(struct arcan_shmif_cont* ctx,
	int mask, int handle, size_t stride, int format, ...)
{
	if (!shmif_platform_pushfd(handle, ctx->epipe))
		return 0;

	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_BUFFERSTREAM,
		.ext.bstream.width = ctx->w,
		.ext.bstream.height = ctx->h,
		.ext.bstream.stride = stride,
		.ext.bstream.format = format
	};
	arcan_shmif_enqueue(ctx, &ev);
	return arcan_shmif_signal(ctx, mask);
}
