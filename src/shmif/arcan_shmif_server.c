#include "arcan_shmif.h"
#include "arcan_shmif_server.h"
#include <errno.h>
#include <stdatomic.h>
#include <math.h>

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
 * really be used here, pending refactoring of the whole thing. In that refact.
 * we should share all the code between the engine- side and the server lib -
 * no reason for the two implementations.
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

enum ARCAN_SEGID shmifsrv_client_type(struct shmifsrv_client* cl)
{
	if (!cl || !cl->con)
		return SEGID_UNKNOWN;
	return cl->con->segid;
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

struct shmifsrv_client* shmifsrv_allocate_connpoint(
	const char* name, const char* key, mode_t permission, int fd)
{
	shmifsrv_monotonic_tick(NULL);
	struct shmifsrv_client* res = alloc_client();
	if (!res)
		return NULL;

	res->con = platform_fsrv_listen_external(name, key, fd, permission, 0);

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
		SEGID_UNKNOWN, env.init_w, env.init_h, 0, clsocket);

	if (statuscode)
		*statuscode = SHMIFSRV_OK;

	return res;
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
		arcan_sem_post(cl->con->esync);
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
			int a = !!(atomic_load(&cl->con->shm.ptr->aready));
			int v = !!(atomic_load(&cl->con->shm.ptr->vready));
			shmifsrv_leave();
			return
				(CLIENT_VBUFFER_READY * v) | (CLIENT_ABUFFER_READY * a);
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

void shmifsrv_audio_step(struct shmifsrv_client* cl)
{

}

void shmifsrv_video_step(struct shmifsrv_client* cl)
{
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
}

/*
 * The reference implementation for this is really in engine/arcan_frameserver
 * with the vframe and push_buffer implementations in particular. Some of the
 * changes is that we need to manage fewer states, like the rz_ack control.
 */
struct shmifsrv_vbuffer shmifsrv_video(struct shmifsrv_client* cl)
{
	struct shmifsrv_vbuffer res = {0};
	if (!cl || cl->status != READY)
		return res;

	cl->con->desc.hints = cl->con->desc.pending_hints;
	res.flags.origo_ll = cl->con->desc.hints & SHMIF_RHINT_ORIGO_LL;
	res.flags.ignore_alpha = cl->con->desc.hints & SHMIF_RHINT_IGNORE_ALPHA;
	res.flags.subregion = cl->con->desc.hints & SHMIF_RHINT_SUBREGION;
	res.flags.srgb = cl->con->desc.hints & SHMIF_RHINT_CSPACE_SRGB;
	res.vpts = atomic_load(&cl->con->shm.ptr->vpts);
	res.w = cl->con->desc.width;
	res.h = cl->con->desc.height;

/*
 * should have a better way of calculating this taking all the possible fmts
 * into account, becomes more relevant when we have different vchannel types.
 */
	res.stride = res.w * ARCAN_SHMPAGE_VCHANNELS;
	res.pitch = res.w;

/* vpending contains the latest region that was synched, so extract the ~vready
 * mask to figure out which is the most recent buffer to work with in the case
 * of 'n' buffering */
	int vready = atomic_load_explicit(
		&cl->con->shm.ptr->vready, memory_order_consume);
	vready = (vready <= 0 || vready > cl->con->vbuf_cnt) ? 0 : vready - 1;

	int vmask = ~atomic_load_explicit(
		&cl->con->shm.ptr->vpending, memory_order_consume);

	res.buffer = cl->con->vbufs[vready];
	res.region = atomic_load(&cl->con->shm.ptr->dirty);

	return res;
}

bool shmifsrv_process_event(struct shmifsrv_client* cl, struct arcan_event* ev)
{
	if (!cl || !ev || cl->status != READY)
		return false;

	if (ev->category == EVENT_EXTERNAL){
		switch (ev->ext.kind){

/* default behavior for bufferstream is to simply send the reject, we can look
 * into other options later but for now the main client is the network setup
 * and accelerated buffer management is far on the list there */
		case EVENT_EXTERNAL_BUFFERSTREAM:
			shmifsrv_enqueue_event(cl, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_BUFFER_FAIL
			}, -1);
			if (cl->con->vstream.handle > 0){
				close(cl->con->vstream.handle);
				cl->con->vstream.handle = -1;
			}
			cl->con->vstream.handle = arcan_fetchhandle(cl->con->dpipe, false);
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

void shmifsrv_audio(struct shmifsrv_client* cl,
	void (*on_buffer)(shmif_asample* buf,
		size_t n_samples, unsigned channels, unsigned rate, void* tag), void* tag)
{
	volatile int ind = atomic_load(&cl->con->shm.ptr->aready) - 1;
	volatile int amask = atomic_load(&cl->con->shm.ptr->apending);

/* sanity check, untrusted source
	if (ind >= src->abuf_cnt || ind < 0){
		platform_fsrv_leave(src);
		return ARCAN_ERRC_NOTREADY;
	}

	int i = ind, prev;
	do {
		prev = i;
		i--;
		if (i < 0)
			i = src->abuf_cnt-1;
	} while (i != ind && ((1<<i)&amask) > 0);

  sweep from oldest buffer (prev) up to i, yield to on_buffer, mask as consumed

	atomic_store(&src->shm.ptr->abufused[prev], 0);
	int last = atomic_fetch_and_explicit(&src->shm.ptr->apending,
		~(1 << prev), memory_order_release);
*/

	atomic_store_explicit(&cl->con->shm.ptr->aready, 0, memory_order_release);
	arcan_sem_post(cl->con->async);
}

bool shmifsrv_tick(struct shmifsrv_client* cl)
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
	return true;
}

static int64_t timebase, c_ticks;
int shmifsrv_monotonic_tick(int* left)
{
	int64_t now = arcan_timemillis();
	int n_ticks = 0;

	if (now < timebase)
		timebase = now - (timebase - now);
	int64_t frametime = now - timebase;

	int64_t base = c_ticks * ARCAN_TIMER_TICK;
	int64_t delta = frametime - base;

	if (delta > ARCAN_TIMER_TICK){
		n_ticks = delta / ARCAN_TIMER_TICK;

/* safeguard against stalls or clock issues */
		if (n_ticks > ARCAN_TICK_THRESHOLD){
			shmifsrv_monotonic_rebase();
			return shmifsrv_monotonic_tick(left);
		}

		c_ticks += n_ticks;
	}

	if (left)
		*left = ARCAN_TIMER_TICK - delta;

	return n_ticks;
}

void shmifsrv_monotonic_rebase()
{
	timebase = arcan_timemillis();
	c_ticks = 0;
}
