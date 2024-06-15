#include "arcan_shmif.h"
#include "arcan_shmif_server.h"
#include <errno.h>
#include <stdatomic.h>
#include <math.h>
#include <sys/wait.h>
#include <pthread.h>
#include <signal.h>

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
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_frameserver.h"
#include "platform/shmif_platform.h"

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

	char multipart[4096];
	size_t multipart_ofs;
	enum connstatus status;
	pid_t pid;
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

int shmifsrv_client_handle(struct shmifsrv_client* cl, int* pid)
{
	if (!cl || cl->status <= BROKEN)
		return -1;

	if (pid)
		*pid = cl->pid;

	return cl->con->dpipe;
}

enum ARCAN_SEGID shmifsrv_client_type(struct shmifsrv_client* cl)
{
	if (!cl || !cl->con)
		return SEGID_UNKNOWN;
	return cl->con->segid;
}

struct shmifsrv_client*
	shmifsrv_send_subsegment(struct shmifsrv_client* cl,
	int segid, int hints, size_t init_w, size_t init_h, int reqid, uint32_t idtok)
{
	if (!cl || cl->status < READY)
		return NULL;

	struct shmifsrv_client* res = alloc_client();
	if (!res)
		return NULL;

	res->con = platform_fsrv_spawn_subsegment(
		cl->con, segid, hints, init_w, init_h, reqid, idtok);
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

	res->con =
		platform_fsrv_listen_external(name, key, fd, permission, 32, 32, 0);

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

struct shmifsrv_client* shmifsrv_inherit_connection(int sockin, int* statuscode)
{
	if (-1 == sockin){
		if (statuscode)
			*statuscode = SHMIFSRV_INVALID_ARGUMENT;
		return NULL;
	}

	struct shmifsrv_client* res = alloc_client();
	if (!res){
		close(sockin);
		if (statuscode)
			*statuscode = SHMIFSRV_OUT_OF_MEMORY;
		return NULL;
	}

	res->con = platform_fsrv_preset_server(sockin, SEGID_UNKNOWN, 0, 0, 0);

	if (statuscode)
		*statuscode = SHMIFSRV_OK;

	res->cookie = arcan_shmif_cookie();
	res->status = AUTHENTICATING;

	return res;
}

struct shmifsrv_client* shmifsrv_spawn_client(
	struct shmifsrv_envp env, int* clsocket, int* statuscode, uint32_t idtok)
{
	if (!clsocket){
		if (statuscode)
			*statuscode = SHMIFSRV_INVALID_ARGUMENT;
		return NULL;
	}

	struct shmifsrv_client* res = alloc_client();

	if (!res){
		if (statuscode)
			*statuscode = SHMIFSRV_OUT_OF_MEMORY;
		return NULL;
	}

	int childend;
	res->con = platform_fsrv_spawn_server(
env.type ? env.type : SEGID_UNKNOWN, env.init_w, env.init_h, 0, &childend);

	if (!res){
		if (statuscode)
			*statuscode = SHMIFSRV_OUT_OF_MEMORY;
		shmifsrv_free(res, SHMIFSRV_FREE_FULL);
		return NULL;
	}

	*clsocket = childend;
	res->cookie = arcan_shmif_cookie();
	res->status = AUTHENTICATING;
	res->pid = -1;

	if (statuscode)
		*statuscode = SHMIFSRV_OK;

	int in = STDIN_FILENO;
	int out = STDOUT_FILENO;
	int err = STDERR_FILENO;

	int* fds[3] = {&in, &out, &err};

	if (env.detach & 2){
		env.detach &= ~(int)2;
		fds[0] = NULL;
	}

	if (env.detach & 4){
		env.detach &= ~(int)4;
		fds[1] = NULL;
	}

	if (env.detach & 8){
		env.detach &= ~(int)8;
		fds[2] = NULL;
	}

/* if path is provided we switch over to build/inherit mode */
	if (env.path){
		pid_t rpid = shmif_platform_execve(
			childend, res->con->shm.key,
			env.path, env.argv, env.envv, env.detach, fds, 3, NULL
		);
		close(childend);

		if (-1 == rpid){
			if (statuscode)
				*statuscode = SHMIFSRV_EXEC_FAILED;

			shmifsrv_free(res, SHMIFSRV_FREE_FULL);
			return NULL;
		}
		res->pid = rpid;
	}

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
			if (a || v)
				return
					(CLIENT_VBUFFER_READY * v) | (CLIENT_ABUFFER_READY * a);
			return CLIENT_IDLE;
		}
		else
			cl->status = BROKEN;
	break;
	default:
		return CLIENT_DEAD;
	}
	return CLIENT_NOT_READY;
}

static void* nanny_thread(void* arg)
{
	pid_t* pid = (pid_t*) arg;
	int counter = 10;
	while (counter--){
		int statusfl;
		int rv = waitpid(*pid, &statusfl, WNOHANG);
		if (rv > 0)
			break;
		else if (counter == 0){
			kill(*pid, SIGKILL);
			waitpid(*pid, &statusfl, 0);
			break;
		}
		sleep(1);
	}
	free(pid);
	return NULL;
}

void shmifsrv_free(struct shmifsrv_client* cl, int mode)
{
	if (!cl)
		return;

	if (cl->status == PENDING)
		cl->con->dpipe = BADFD;

	switch(mode){
	case SHMIFSRV_FREE_NO_DMS:
		cl->con->flags.no_dms_free = true;
	case SHMIFSRV_FREE_FULL:
		platform_fsrv_destroy(cl->con);
	break;
	case SHMIFSRV_FREE_LOCAL:
		platform_fsrv_destroy_local(cl->con);
	break;
	}

/* the same nanny-kill thread approach as used in platform-posix-frameserver */
	if (cl->pid){
		pid_t* pidptr = malloc(sizeof(pid_t));
		pthread_attr_t nanny_attr;
		pthread_attr_init(&nanny_attr);
		pthread_attr_setdetachstate(&nanny_attr, PTHREAD_CREATE_DETACHED);
		*pidptr = cl->pid;

		pthread_t nanny;
		if (0 != pthread_create(&nanny, &nanny_attr, nanny_thread, (void*) pidptr))
			kill(cl->pid, SIGKILL);
		pthread_attr_destroy(&nanny_attr);
	}

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

void shmifsrv_client_protomask(struct shmifsrv_client* cl, unsigned mask)
{
	if (!cl || !cl->con)
		return;

	cl->con->metamask = mask;
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
	res.flags.tpack = cl->con->desc.hints & SHMIF_RHINT_TPACK;
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

/* if we have negotiated compressed passthrough, set res.flags, copy /verify
 * framesize - if that fails, we need to propagate the bufferfail so the client
 * produces a new uncompressed one */
	if (cl->con->desc.aproto & SHMIF_META_VENC){
		if (cl->con->desc.aext.venc){
			memcpy(res.fourcc, cl->con->desc.aext.venc->fourcc, 4);
			res.buffer_sz = cl->con->desc.aext.venc->framesize;
		}
		res.flags.compressed = res.fourcc[0] != 0;
	}

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

	/* just fetch and wipe */
			int handle = arcan_fetchhandle(cl->con->dpipe, false);
			close(handle);

			return true;
		break;
/* need to track the type in order to be able to apply compression */
		case EVENT_EXTERNAL_REGISTER:
			if (cl->con->segid == SEGID_UNKNOWN){
				cl->con->segid = ev->ext.registr.kind;
				return false;
			}
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

bool shmifsrv_audio(struct shmifsrv_client* cl,
	void (*on_buffer)(shmif_asample* buf,
		size_t n_samples, unsigned channels, unsigned rate, void* tag), void* tag)
{
	struct arcan_shmif_page* src = cl->con->shm.ptr;
	volatile int ind = atomic_load(&src->aready) - 1;
	volatile int amask = atomic_load(&src->apending);

/* invalid indice, bad client */
	if (ind >= cl->con->abuf_cnt || ind < 0){
		return false;
	}

/* not readyy but signaled */
	if (0 == amask || ((1 << ind) & amask) == 0){
		atomic_store_explicit(&src->aready, 0, memory_order_release);
		arcan_sem_post(cl->con->async);
		return true;
	}

/* find oldest buffer */
	int i = ind, prev;
	do {
		prev = i;
		i--;
		if (i < 0)
			i = cl->con->abuf_cnt-1;
	} while (i != ind && ((1<<i)&amask) > 0);


/* forward to the callback */
	if (on_buffer && src->abufused[prev]){
		on_buffer(cl->con->abufs[prev], src->abufused[prev],
			cl->con->desc.channels, cl->con->desc.samplerate, tag);
	}

/* mark as consumed */
	atomic_store(&src->abufused[prev], 0);
	int last = atomic_fetch_and_explicit(
		&src->apending, ~(1 << prev), memory_order_release);

/* and release the client */
	atomic_store_explicit(&src->aready, 0, memory_order_release);
	arcan_sem_post(cl->con->async);
	return true;
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
#ifndef SHMIFSRV_EXTERNAL_CLOCK
static _Thread_local int64_t timebase;
static _Thread_local int64_t c_ticks;
#endif

int shmifsrv_monotonic_tick(int* left)
{
#ifndef SHMIFSRV_EXTERNAL_CLOCK
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
#else
	return 0;
#endif
}

void shmifsrv_monotonic_rebase()
{
#ifndef SHMIFSRV_EXTERNAL_CLOCK
	timebase = arcan_timemillis();
	c_ticks = 0;
#endif
}

#include "../frameserver/util/utf8.c"
bool shmifsrv_enqueue_multipart_message(struct shmifsrv_client* acon,
	struct arcan_event* base, const char* msg, size_t len)
{
	uint32_t state = 0, codepoint = 0;
	uint8_t* multipart;
	char* data;

/* different offsets for different categories, we need to be able to
 * handle both directions hence why _server works differently than _control.c */
	if (base->category == EVENT_TARGET){
		data = (char*)base->tgt.message;
		multipart = &base->tgt.ioevs[0].cv[0]; /* works because multipart is !0 */
	}
	else if (base->category == EVENT_EXTERNAL){
		multipart = &base->ext.message.multipart;
		data = (char*)base->ext.message.data;
	}
	else
		return false;

	_Static_assert(sizeof(base->ext.message.data) == 78, "broken header");
	size_t maxlen = 78;
	const char* outs = msg;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
			if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(msg[i])))
				lastok = i;

			if (i != lastok){
				if (0 == i)
					return false;
			}
		}

		memcpy(data, outs, lastok);
		data[lastok] = '\0';
		len -= lastok;
		outs += lastok;
		if (len)
			*multipart = 1;
		else
			*multipart = 0;

		platform_fsrv_pushevent(acon->con, base);
	}

/* flush remaining */
	if (len){
		snprintf(data, maxlen, "%s", outs);
		*multipart = 0;
		platform_fsrv_pushevent(acon->con, base);
	}

	return true;
}

int shmifsrv_put_video(
	struct shmifsrv_client* C, struct shmifsrv_vbuffer* V)
{
/* incomplete - for passthrough the SHMIF_META_VENC subproto needs to
 * be enabled and fourCC carried in the extended block. This would be
 * in C->con->aext.venc.
 *
 * We'd also need to repack if dimensions mismatch, which also means
 * that ORIGO_LL can be stripped.
 */
	if (V->flags.compressed)
		return -2;

	if (shmifsrv_enter(C)){
		if (atomic_load(&C->con->shm.ptr->vready)){
			shmifsrv_leave(C);
			return 0;
		}

		size_t ntc = V->h * V->stride;
		int fflags = V->flags.origo_ll & SHMIF_RHINT_ORIGO_LL;
		memcpy(C->con->vbufs[0], V->buffer, ntc);

		atomic_store(&C->con->shm.ptr->hints, fflags);
    atomic_store(&C->con->shm.ptr->vready, 1);
		atomic_store(&C->con->shm.ptr->dirty, V->region);

		shmifsrv_enqueue_event(C, &(struct arcan_event){
			.tgt.kind = TARGET_COMMAND_STEPFRAME,
			.category = EVENT_TARGET
		}, -1);

		shmifsrv_leave(C);
		return 1;
	}
	else
		return -1;
}

bool shmifsrv_merge_multipart_message(
	struct shmifsrv_client* P, struct arcan_event* ev,
	char** out, bool* bad)
{
	if (!P || !ev || !out || !bad ||
		ev->category != EVENT_EXTERNAL || ev->ext.kind != EVENT_EXTERNAL_MESSAGE)
		return false;

	size_t msglen = strlen((char*)ev->ext.message.data);

	if (msglen + P->multipart_ofs >= sizeof(P->multipart)){
		*bad = true;
			return false;
	}
	else {
		memcpy(&P->multipart[P->multipart_ofs], ev->ext.message.data, msglen);
		P->multipart_ofs += msglen;
		P->multipart[P->multipart_ofs] = '\0';
		*out = P->multipart;
	}

	return !ev->ext.message.multipart;
}
