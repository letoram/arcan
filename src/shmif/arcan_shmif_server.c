#include "arcan_shmif.h"
#include "arcan_shmif_server.h"
#include <errno.h>

/*
 * basic checklist:
 *  [ ] resize / resynch
 *  [ ] video buffer transfers
 *  [ ] audio buffer transfers
 *  [ ] subsegment allocation
 *  [ ] configure flags
 *  [ ] spawn internal
 */

/*
 * This is needed in order to re-use some of the platform layer functions that
 * are rather heavy. This lib act as a replacement for the things that are in
 * engine/arcan_frameserver.c though.
 *
 * For that reason, we need to define some types that will actually never
 * really be used here, pending refactoring of the whole thing.
 */
typedef int shm_handle;
struct arcan_aobj;
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_frameserver.h"

/*
 * temporary workaround, this symbol should really have its visiblity lowered.
 */
bool platform_video_auth(int cardn, unsigned token)
{
	return false;
}

/*
 * wrap the normal structure as we need to pass it to the platform frameserver
 * functions, but may need to have some tracking of our own.
 */
enum connstatus {
	DEAD = -1,
	BROKEN = 0,
	PENDING = 1,
	AUTHENTICATING = 2,
	READY = 3
};

struct shmifsrv_client {
/* need a 'per client' eventqueue */
	struct arcan_frameserver* con;
	enum connstatus status;
	size_t errors;
	uint64_t cookie;
};

static struct shmifsrv_client* alloc_client()
{
	struct shmifsrv_client* res = malloc(sizeof(struct shmifsrv_client));
	if (!res)
		return NULL;

	*res = (struct shmifsrv_client){};
	res->status = BROKEN;
	res->cookie = arcan_shmif_cookie();

	return res;
}

int shmifsrv_client_handle(struct shmifsrv_client* cl)
{
	if (!cl || cl->status <= BROKEN)
		return -1;

	return cl->con->dpipe;
}

struct shmifsrv_client*
	shmifsrv_send_subsegment(struct shmifsrv_client* cl, int segid,
	size_t init_w, size_t init_h, int reqid, uint32_t idtok)
{
	if (!cl || cl->status < READY)
		return NULL;

	struct shmifsrv_client* res = alloc_client();
	if (!res)
		return NULL;

	res->con = platform_fsrv_spawn_subsegment(
		cl->con, segid, init_w, init_h, reqid, idtok);
	if (!res->con){
		free(res);
		return NULL;
	}
	res->cookie = arcan_shmif_cookie();
	res->status = READY;

	return res;
}

struct shmifsrv_client*
	shmifsrv_allocate_connpoint(const char* name, const char* key,
	mode_t permission, int* fd, int* statuscode, uint32_t idtok)
{
	int sc;
	struct shmifsrv_client* res = alloc_client();
	if (!res)
		return NULL;

	res->con = platform_fsrv_listen_external(
		name, key, fd ? *fd : -1, permission, 0, idtok);

	if (!res->con){
		free(res);
		return NULL;
	}

	res->cookie = arcan_shmif_cookie();
	res->status = PENDING;

	if (key)
		strncpy(res->con->clientkey, key, PP_SHMPAGE_SHMKEYLIM-1);

	return res;
}

struct shmifsrv_client* shmifsrv_spawn_client(
	struct shmifsrv_envp env, int* clsocket, int* statuscode, uint32_t idtok)
{
	if (!clsocket){
		*statuscode = SHMIFSRV_INVALID_ARGUMENT;
		return NULL;
	}

	struct shmifsrv_client* res = alloc_client();

	if (statuscode){
		*statuscode = SHMIFSRV_OUT_OF_MEMORY;
		return NULL;
	}

	res->con = platform_fsrv_spawn_server(
		SEGID_UNKNOWN, env.init_w, env.init_h, 0, clsocket, idtok);

	if (statuscode)
		*statuscode = SHMIFSRV_OK;

	return res;
}

bool shmifsrv_frameserver_tick(struct shmifsrv_client* cl)
{
/*
 * check:
 * shmifsrv_client_control_chld:
 *   sanity check:
 *    src->flags.alive, src->shm.ptr,
 *    src->shm.ptr->cookie == cookie
 * shmifsrv_client_validchild
 * shmifsrv_client_free on fail (though we just return false here)
 */
	return false;
}

size_t shmifsrv_dequeue_events(
	struct shmifsrv_client* cl, struct arcan_event* newev, size_t limit)
{
	if (!cl || cl->status < READY)
		return 0;

	if (shmifsrv_enter(cl)){
		size_t count = 0;
		uint8_t front = cl->con->shm.ptr->parentevq.front;
		uint8_t back = cl->con->shm.ptr->parentevq.back;
		if (front > PP_QUEUE_SZ || back > PP_QUEUE_SZ){
			cl->errors++;
			shmifsrv_leave();
			return 0;
		}

		while (count < limit && front != back){
			newev[count++] = cl->con->shm.ptr->parentevq.evqueue[front];
			front = (front + 1) % PP_QUEUE_SZ;
		}
		asm volatile("": : :"memory");
		__sync_synchronize();
		cl->con->shm.ptr->parentevq.front = front;
		shmifsrv_leave();
		return count;
	}
	else{
		cl->errors++;
		return 0;
	}
}

static void autoclock_frame(arcan_frameserver* tgt)
{
	if (!tgt->clock.left)
		return;

/*
	if (!tgt->clock.frametime)
		tgt->clock.frametime = arcan_frametime();

	int64_t delta = arcan_frametime() - tgt->clock.frametime;
	if (delta < 0){

	}
	else if (delta == 0)
		return;

	if (tgt->clock.left <= delta){
		tgt->clock.left = tgt->clock.start;
		tgt->clock.frametime = arcan_frametime();
		arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_STEPFRAME,
			.tgt.ioevs[0].iv = delta / tgt->clock.start,
			.tgt.ioevs[1].iv = 1
		};
		platform_fsrv_pushevent(tgt, &ev);
	}
	else
		tgt->clock.left -= delta;
	*/
}


bool shmifsrv_enqueue_event(
	struct shmifsrv_client* cl, struct arcan_event* ev, int fd)
{
	if (!cl || cl->status < READY || !ev)
		return false;

	if (fd != -1)
		return platform_fsrv_pushfd(cl->con, ev, fd) == ARCAN_OK;
	else
		return platform_fsrv_pushevent(cl->con, ev) == ARCAN_OK;
}

int shmifsrv_poll(struct shmifsrv_client* cl)
{
	if (!cl || cl->status <= BROKEN){
		cl->status = BROKEN;
		return CLIENT_DEAD;
	}

/* we go from PENDING -> BROKEN || AUTHENTICATING -> BROKEN || READY */
	switch (cl->status){
	case PENDING:{
		int sc = platform_fsrv_socketpoll(cl->con);
		if (-1 == sc){
			if (errno == EBADF){
				cl->status = BROKEN;
				return CLIENT_DEAD;
			}
			return CLIENT_NOT_READY;
		}
		cl->status = AUTHENTICATING;
	}
/* consumed one character at a time up to a fixed limit */
	case AUTHENTICATING:
		while (-1 == platform_fsrv_socketauth(cl->con)){
			if (errno == EBADF){
				cl->status = BROKEN;
				return CLIENT_DEAD;
			}
			else if (errno == EWOULDBLOCK){
				return CLIENT_NOT_READY;
			}
		}
		cl->status = READY;
	case READY:
/* check if resynch, else check if aready or vready */
		if (shmifsrv_enter(cl)){
			if (cl->con->shm.ptr->resized){
				if (-1 == platform_fsrv_resynch(cl->con)){
					cl->status = BROKEN;
					shmifsrv_leave();
					return CLIENT_DEAD;
				}
				return CLIENT_NOT_READY;
			}
			int a = atomic_load(&cl->con->shm.ptr->aready);
			int v = atomic_load(&cl->con->shm.ptr->vready);
			shmifsrv_leave();
			return (a * 1) | (v * 1);
		}
		else
			cl->status = BROKEN;
	break;
	default:
		return CLIENT_DEAD;
	}
	return CLIENT_NOT_READY;
}

void shmifsrv_free(struct shmifsrv_client* cl)
{
	if (!cl)
		return;

	if (cl->status == PENDING)
		cl->con->dpipe = BADFD;

	platform_fsrv_destroy(cl->con);
	cl->status = DEAD;
	free(cl);
}

bool shmifsrv_enter(struct shmifsrv_client* cl)
{
	jmp_buf tramp;
	if (0 != setjmp(tramp))
		return false;

	platform_fsrv_enter(cl->con, tramp);
	return true;
}

void shmifsrv_leave()
{
	platform_fsrv_leave();
}

void shmifsrv_set_protomask(struct shmifsrv_client* cl, unsigned mask)
{
	if (!cl || !cl->con)
		return;

	cl->con->metamask = mask;
}

struct shmifsrv_vbuffer shmifsrv_video(struct shmifsrv_client* cl, bool step)
{
	struct shmifsrv_vbuffer res = {0};
	if (!cl || cl->status != READY)
		return res;

	res.flags.origo_ll = cl->con->desc.hints & SHMIF_RHINT_ORIGO_LL;
	res.flags.ignore_alpha = cl->con->desc.hints & SHMIF_RHINT_IGNORE_ALPHA;
	res.flags.subregion = cl->con->desc.hints & SHMIF_RHINT_SUBREGION;
	res.flags.srgb = cl->con->desc.hints & SHMIF_RHINT_CSPACE_SRGB;
	res.vpts = atomic_load(&cl->con->shm.ptr->vpts);
	res.w = cl->con->desc.width;
	res.h = cl->con->desc.height;

/* samplerate, channels, vfthresh */

	if (step){
/* signal that we're done with the buffer */
		atomic_store_explicit(&cl->con->shm.ptr->vready, 0, memory_order_release);
		arcan_sem_post(cl->con->vsync);

/* If the frameserver has indicated that it wants a frame callback every time
 * we consume. This is primarily for cases where a client needs to I/O mplex
 * and the semaphores doesn't provide that */
		if (cl->con->desc.hints & SHMIF_RHINT_VSIGNAL_EV){
			platform_fsrv_pushevent(cl->con, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.tgt.ioevs[0].iv = 1
			});
		}
		return res;
	}

/*
 * copy the flags..
 * struct arcan_shmif_region dirty = atomic_load(&shmpage->dirty);
 *
 */
	return res;
}

bool shmifsrv_process_event(struct shmifsrv_client* cl, struct arcan_event* ev)
{
	if (!cl || !ev || cl->status != READY)
		return false;

	if (ev->category == EVENT_EXTERNAL){
		switch (ev->ext.kind){
		case EVENT_EXTERNAL_BUFFERSTREAM:
/* FIXME: used for handle passing, accumulate, grab descriptor,
 * use ext.bstream.* */
			return true;
		break;
		case EVENT_EXTERNAL_CLOCKREQ:
			if (cl->con->flags.autoclock && !ev->ext.clock.once){
				cl->con->clock.frame = ev->ext.clock.dynamic;
				cl->con->clock.left = cl->con->clock.start = ev->ext.clock.rate;
				return true;
			}
		break;
		default:
		break;
		}
	}
	return false;
}

struct shmifsrv_abuffer shmifsrv_audio(
	struct shmifsrv_client* cl, shmif_asample* buf, size_t buf_sz)
{
	struct shmifsrv_abuffer res = {0};
	volatile int ind = atomic_load(&cl->con->shm.ptr->aready) - 1;
	volatile int amask = atomic_load(&cl->con->shm.ptr->apending);
/* missing, copy buffer, re-use buf if possible, release if we're out
 * of buffers */
	atomic_store_explicit(&cl->con->shm.ptr->aready, 0, memory_order_release);
	arcan_sem_post(cl->con->async);
	return res;
}

void shmifsrv_tick(struct shmifsrv_client* cl)
{
/* want the event to be queued after resize so the possible reaction (i.e.
	bool alive = src->flags.alive && src->shm.ptr &&
		src->shm.ptr->cookie == arcan_shmif_cookie() &&
		platform_fsrv_validchild(src);

	if (!fail && tick){
		if (0 >= --src->clock.left){
			src->clock.left = src->clock.start;
			platform_fsrv_pushevent(src, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.tgt.ioevs[0].iv = 1,
				.tgt.ioevs[1].iv = 1
			});
		}
	}
 */
}

static int64_t timebase, c_ticks;
int shmifsrv_monotonic_tick(int* left)
{
	int64_t now = arcan_timemillis();
	int64_t base = c_ticks * ARCAN_TIMER_TICK;
	if (now < timebase)
		timebase = now - (timebase - now);
	int64_t delta = now - timebase - base;

	if (left){
		*left = (c_ticks+1) * ARCAN_TIMER_TICK - now - base;
	}

	return (float) delta / (float) ARCAN_TIMER_TICK;
}

void shmifsrv_monotonic_rebase()
{
	timebase = arcan_timemillis();
}
