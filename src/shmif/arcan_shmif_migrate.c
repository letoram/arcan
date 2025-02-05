#include <arcan_shmif.h>
#include "platform/shmif_platform.h"
#include "shmif_privint.h"
#include "shmif_privext.h"
#include <pthread.h>
#include <fcntl.h>
#include <sys/mman.h>

/* For fallback-migration, we don't want to initiate migrate on detecting DMS
 * if there is an EXIT event in the queue. This can happen in a situation like:
 *  DISPLAYHINT(resize) -> arcan_shmif_resize -> [liveness check failed] ->
 *  fallback_migrate.
 *
 * In that case we check if there is an EXIT pending and cancel the migration.
 */
/* this should be solved with kqueue on BSDs */
enum shmif_migrate_status arcan_shmif_migrate(
	struct arcan_shmif_cont* C, const char* newpath, const char* key)
{
	if (!C || !C->addr || !newpath)
		return SHMIF_MIGRATE_BADARG;

	struct shmif_hidden* P = C->priv;

	if (!pthread_equal(P->primary_id, pthread_self()))
		return SHMIF_MIGRATE_BAD_SOURCE;

	int dpipe;
	char* keyfile = NULL;

	if (-1 != shmif_platform_a12addr(newpath).len)
		keyfile = shmif_platform_a12spawn(C, newpath, &dpipe);
	else
		keyfile = arcan_shmif_connect(newpath, key, &dpipe);
	if (!keyfile)
		return SHMIF_MIGRATE_NOCON;

/* re-use tracked "old" credentials" */
	fcntl(dpipe, F_SETFD, FD_CLOEXEC);
	struct arcan_shmif_cont NEW =
		arcan_shmif_acquire(NULL, keyfile, P->type, P->flags);

	if (!NEW.addr){
		close(dpipe);
		return SHMIF_MIGRATE_NOCON;
	}
	NEW.epipe = dpipe;

/* all preconditions GO */
	P->in_migrate = true;
	shmif_platform_guard_resynch(C, -1, dpipe);

/* REGISTER is special, as GUID can be internally generated but should persist */
	if (P->flags & SHMIF_NOREGISTER){
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(REGISTER),
			.ext.registr.kind = P->type,
			.ext.registr.guid = {
				P->guid[0], P->guid[1]
			}
		};
		arcan_shmif_enqueue(&NEW, &ev);
	}

/* allow a reset-hook to release anything pending */
	if (P->reset_hook)
		P->reset_hook(SHMIF_RESET_REMAP, P->reset_hook_tag);

/* extract settings from the page and context, forward into the new struct -
 * possibly just actually cache this inside ext would be safer */
	size_t w = C->w;
	size_t h = C->h;

	struct shmif_resize_ext ext = {
		.abuf_sz = C->abufsize,
		.vbuf_cnt = P->vbuf_cnt,
		.abuf_cnt = P->abuf_cnt,
		.samplerate = C->samplerate,
		.meta = P->atype,
		.rows = atomic_load(&C->addr->rows),
		.cols = atomic_load(&C->addr->cols)
	};

/* Copy the drawing/formatting hints, this is particularly important in case of
 * certain extended features such as TPACK as the size calculations are
 * different, then remap / resize the new context accordingly */
	NEW.hints = C->hints;
	arcan_shmif_resize_ext(&NEW, w, h, ext);

/* and wake anything possibly blocking still as whatever was there is dead */
	arcan_sem_post(P->vsem);
	arcan_sem_post(P->asem);
	arcan_sem_post(P->esem);

/* Copy the audio/video contents of [cont] into [ret], if possible, a possible
 * workaround on failure is to check if we have VSIGNAL- state and inject one
 * of those, or delay-slot queue a RESET */
	size_t vbuf_sz_new =
		arcan_shmif_vbufsz(
			NEW.priv->atype, NEW.hints, NEW.w, NEW.h,
			atomic_load(&NEW.addr->rows),
			atomic_load(&NEW.addr->cols)
		);

	size_t vbuf_sz_old =
		arcan_shmif_vbufsz(
			P->atype, C->hints, C->w, C->h, ext.rows, ext.cols);

/* This might miss the bit where the new vs the old connection has the same
 * format but enforce different padding rules - but that edge case is better
 * off as accepting the buffer as lost */
	if (vbuf_sz_new == vbuf_sz_old){
		for (size_t i = 0; i < P->vbuf_cnt; i++)
			memcpy(NEW.priv->vbuf[i], P->vbuf[i], vbuf_sz_new);
	}
/* Set some indicator color so this can be detected visually */
	else{
		log_print("[shmif::recovery] vbuf_sz "
			"mismatch (%zu, %zu)", vbuf_sz_new, vbuf_sz_old);
		shmif_pixel color = SHMIF_RGBA(90, 60, 60, 255);
		for (size_t row = 0; row < NEW.h; row++){
			shmif_pixel* cr = NEW.vidp + row * NEW.pitch;
			for (size_t col = 0; col < NEW.w; col++)
				cr[col] = color;
			}
	}

/* The audio buffering parameters >should< be simpler as the negotiation
 * there does not have hint- or subprotocol- dependent constraints, though
 * again we could just delay-slot queue a FLUSH */
	if (NEW.abuf_cnt == P->abuf_cnt && NEW.abufsize == C->abufsize){
		for (size_t i = 0; i < P->abuf_cnt && i < NEW.priv->abuf_cnt; i++)
			memcpy(NEW.priv->abuf[i], P->abuf[i], C->abufsize);
	}
	else {
		log_print("[shmif::recovery] couldn't restore audio parameters"
			" , want=(%zu * %zu) got=(%zu * %zu)",
			(size_t)C->abufsize, (size_t) P->abuf_cnt,
			(size_t)NEW.priv->abuf_cnt, (size_t)NEW.abufsize);
	}

/* now we can free cont and update the video state of the new connection */
	void* old_page = C->addr;
	void* old_user = C->user;
	void* old_hook = P->reset_hook;
	void* old_hook_tag = P->reset_hook_tag;
	int old_hints = C->hints;
	struct arcan_shmif_region old_dirty = C->dirty;

/* But not before transferring privext or accel would be lost, no platform has
 * any back-refs inside of the privext so that's fine - chances are that we
 * should switch render device though. That can't be done here as there is
 * state in the outer client that needs to come with, so when we have delay
 * slots, another one of those is needed for DEVICEHINT */
	NEW.privext = C->privext;
	C->privext = malloc(sizeof(struct shmif_ext_hidden));
	*C->privext = (struct shmif_ext_hidden){
		.cleanup = NULL,
		.active_fd = -1,
		.pending_fd = -1,
	};

/* This would terminate any existing guard-thread and a new one have spawned
 * through the inherited flags */
	P->in_migrate = false;
	arcan_shmif_drop(C);

/* last step, replace the relevant members of cont with the values from ret */
/* first try and just re-use the mapping so any aliasing issues from the
 * caller can be masked */
	void* alias = mmap(old_page, NEW.shmsize,
		PROT_READ | PROT_WRITE, MAP_SHARED, NEW.shmh, 0);

	if (alias != old_page){
		munmap(alias, NEW.shmsize);
		debug_print(INFO, cont, "remapped base changed, beware of aliasing clients");
	}
/* we did manage to retain our old mapping, so switch the pointers, including
 * synchronization with the guard thread */
	else {
		munmap(NEW.addr, NEW.shmsize);
		NEW.addr = alias;

		shmif_platform_guard_lock(&NEW);
			shmif_platform_guard_resynch(&NEW, NEW.addr->parent, NEW.epipe);
		shmif_platform_guard_unlock(&NEW);

/* need to recalculate the buffer pointers */
		arcan_shmif_mapav(NEW.addr,
			NEW.priv->vbuf, NEW.priv->vbuf_cnt,
			NEW.w * NEW.h * sizeof(shmif_pixel),
			NEW.priv->abuf, NEW.priv->abuf_cnt, NEW.abufsize
		);

		shmif_platform_setevqs(
			NEW.addr, NEW.priv->esem, &NEW.priv->inev, &NEW.priv->outev);

		NEW.vidp = NEW.priv->vbuf[0];
		NEW.audp = NEW.priv->abuf[0];
	}
	NEW.priv->reset_hook = old_hook;
	NEW.priv->reset_hook_tag = old_hook_tag;

/* and map our copies and the prepared context unto the user- tracked one */
	memcpy(C, &NEW, sizeof(struct arcan_shmif_cont));

	C->hints = old_hints;
	C->dirty = old_dirty;
	C->user = old_user;

/* and signal the reset hook listener that the contents have now been
 * remapped and can be filled with new data */
	if (C->priv->reset_hook){
		C->priv->reset_hook(SHMIF_RESET_REMAP, C->priv->reset_hook_tag);
	}

/* This does not currently handle subsegment remapping as they typically
 * depend on more state "server-side" and there are not that many safe
 * options. The current approach is simply to kill tracked subsegments,
 * although we could "in theory" repeat the process for each subsegment */
	return SHMIF_MIGRATE_OK;
}
