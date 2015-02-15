/*
 * Copyright 2012-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <limits.h>
#include <math.h>
#include <assert.h>
#include <string.h>
#include <stdarg.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <pthread.h>

#include "arcan_shmif.h"
/*
 * The windows implementation here is rather broken in several ways:
 * 1. non-authoritative connections not accepted
 * 2. multiple- segments failed due to the hackish way that
 *    semaphores and shared memory handles are passed
 * 3. split- mode not implemented
 */
#if _WIN32
#define sleep(n) Sleep(1000 * n)

#define LOG(...) (fprintf(stderr, __VA_ARGS__))
extern sem_handle async, vsync, esync;
extern HANDLE parent;

#else
#include <signal.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#endif

/*
 * The guard-thread thing tries to get around all the insane edge conditions
 * that exist when you have a partial parent<->child circular dependency
 * with an untrusted child and a limited set of IPC primitives.
 *
 * Sleep a fixed amount of seconds, wake up and check if parent is alive.
 * If that's true, go back to sleep -- otherwise -- wake up, pop open
 * all semaphores set the disengage flag and go back to a longer sleep
 * that it shouldn't wake up from. Should this sleep be engaged anyhow,
 * shut down forcefully.
 */

struct shmif_hidden {
	shmif_trigger_hook video_hook;
	void* video_hook_data;

	shmif_trigger_hook audio_hook;
	void* audio_hook_data;

	bool output;

/*
 * as we currently don't serialize both events and descriptors
 * across the socket, we need to track and align the two
 */
	struct {
		bool gotev, consumed;
		arcan_event ev;
		file_handle fd;
	} pev;

	struct {
		int epipe;
		char key[256];
	} pseg;

	struct {
		bool active;
		sem_handle semset[3];
		process_handle parent;
		volatile uintptr_t* dms;
		pthread_mutex_t synch;
		void (*exitf)(int val);
	} guard;
};

static struct {
	struct arcan_shmif_cont* input, (* output);
} primary;

static void* guard_thread(void* gstruct);

static void spawn_guardthread(
	struct shmif_hidden gs, struct arcan_shmif_cont* d, bool nothread)
{
	struct shmif_hidden* hgs = malloc(sizeof(struct shmif_hidden));
	memset(hgs, '\0', sizeof(struct shmif_hidden));

	*hgs = gs;
	d->priv = hgs;

	if (!nothread){
		pthread_t pth;
		pthread_attr_t pthattr;
		pthread_attr_init(&pthattr);
		pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
		pthread_mutex_init(&hgs->guard.synch, NULL);

		hgs->guard.active = true;
		pthread_create(&pth, &pthattr, guard_thread, hgs);
		pthread_detach(pth);
	}
}

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

uint64_t arcan_shmif_cookie()
{
	uint64_t base = sizeof(struct arcan_event) + sizeof(struct arcan_shmif_page);
	base += (uint64_t)offsetof(struct arcan_shmif_page, cookie)  <<  8;
  base += (uint64_t)offsetof(struct arcan_shmif_page, resized) << 16;
	base += (uint64_t)offsetof(struct arcan_shmif_page, aready)  << 24;
  base += (uint64_t)offsetof(struct arcan_shmif_page, abufused)<< 32;
	base += (uint64_t)offsetof(struct arcan_shmif_page, childevq.front) << 40;
	base += (uint64_t)offsetof(struct arcan_shmif_page, childevq.back) << 48;
	base += (uint64_t)offsetof(struct arcan_shmif_page, parentevq.front) << 56;
	return base;
}

/*
 * Is populated and called whenever we get a descriptor or a
 * descriptor related event. Populates *dst and returns 1 if
 * we have a matching pair.
 */
static void fd_event(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	if (dst->category == EVENT_TARGET &&
		dst->tgt.kind == TARGET_COMMAND_NEWSEGMENT){
		c->priv->pseg.epipe = c->priv->pev.fd;
		c->priv->pev.fd = BADFD;
		memcpy(c->priv->pseg.key, dst->tgt.message, sizeof(dst->tgt.message));
	}
	else{
		dst->tgt.ioevs[0].iv = c->priv->pev.fd;
	}
	c->priv->pev.consumed = true;
}

static void consume(struct arcan_shmif_cont* c, bool newseg)
{
	if (c->priv->pev.consumed){
		if (!newseg)
			close(c->priv->pev.fd);

		c->priv->pev.fd = BADFD;
		c->priv->pev.gotev = false;
		c->priv->pev.consumed = false;
	}
}

int process_events(struct arcan_shmif_cont* c,
	struct arcan_event* dst, bool blocking)
{
	assert(dst);
	assert(c);
	if (!c->addr)
		return 0;

	int rv = 0;
	struct arcan_evctx* ctx = &c->inev;
	volatile int* ks = (volatile int*) ctx->synch.killswitch;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

/* clean up any pending descriptors, ... */
	consume(c, false);

checkfd:
/* got a descriptor dependent event, descriptor is on its way */
	do {
		if (-1 == c->priv->pev.fd){
			c->priv->pev.fd = arcan_fetchhandle(c->epipe, blocking);
		}

		if (c->priv->pev.gotev){
			if (c->priv->pev.fd > 0){
				fd_event(c, dst);
				rv = 1;
			}
			goto done;
		}
	} while (c->priv->pev.gotev && *ks);

/* event ready, if it is descriptor dependent - wait for that one */
	if (*ctx->front != *ctx->back){
		*dst = ctx->eventbuf[ *ctx->front ];
		*ctx->front = (*ctx->front + 1) % ctx->eventbuf_sz;

/* descriptor dependent events need to be flagged and tracked */
		if (dst->category == EVENT_TARGET)
			switch (dst->tgt.kind){
			case TARGET_COMMAND_STORE:
			case TARGET_COMMAND_RESTORE:
			case TARGET_COMMAND_BCHUNK_IN:
			case TARGET_COMMAND_BCHUNK_OUT:
			case TARGET_COMMAND_NEWSEGMENT:
				c->priv->pev.gotev = true;
				goto checkfd;
			default:
			break;
			}

		rv = 1;
	}
	else if (c->addr->dms == 0)
		return -1;
	else if (blocking && *ks)
		goto checkfd;

done:
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return *ks ? rv : -1;
}

int arcan_shmif_poll(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	return process_events(c, dst, false);
}

int arcan_shmif_wait(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	return process_events(c, dst, true);
}

int arcan_shmif_enqueue(struct arcan_shmif_cont* c,
	const struct arcan_event* const src)
{
	assert(c);
	if (!c->addr || !c->addr->dms)
		return 0;

	struct arcan_evctx* ctx = &c->outev;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	while ( ((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		LOG("arcan_event_enqueue(), going to sleep, eventqueue full\n");
		arcan_sem_wait(ctx->synch.handle);
	}

	ctx->eventbuf[*ctx->back] = *src;
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return 1;
}

int arcan_shmif_tryenqueue(
	struct arcan_shmif_cont* c, const arcan_event* const src)
{
	assert(c);
	if (!c->addr || !c->addr->dms)
		return 0;

	struct arcan_evctx* ctx = &c->outev;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	if (((*ctx->front + 1) % ctx->eventbuf_sz) == *ctx->back){
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

		return 0;
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return arcan_shmif_enqueue(c, src);
}

#if _WIN32
static inline bool parent_alive()
{
	return IsWindow(parent);
}

/* force_unlink isn't used here as the semaphores are
 * passed as inherited handles */
static void map_shared(const char* shmkey,
	char force_unlink, struct arcan_shmif_cont* res)
{
	assert(shmkey);
	HANDLE shmh = (HANDLE) strtoul(shmkey, NULL, 10);

	res->addr = MapViewOfFile(shmh,
		FILE_MAP_ALL_ACCESS, 0, 0, ARCAN_SHMPAGE_MAX_SZ);

	res->asem = async;
	res->vsem = vsync;
	res->esem = esync;

	if ( res->addr == NULL ) {
		LOG("fatal: Couldn't map the allocated shared "
			"memory buffer (%i) => error: %i\n", shmkey, GetLastError());
		CloseHandle(shmh);
	}

/*
 * note: this works "poorly" for multiple segments,
 * we should mimic the posix approach where we push a base-key,
 * and then use that to lookup handles for shared memory and semaphores
 */
	parent = res->addr->parent;
}

/*
 * No implementation on windows currently
 */
char* arcan_shmif_connect(const char* connpath, const char* connkey,
	file_handle* conn_ch)
{
	return NULL;
}

#else
static void map_shared(const char* shmkey, char force_unlink,
	struct arcan_shmif_cont* dst)
{
	assert(shmkey);
	assert(strlen(shmkey) > 0);

	int fd = -1;
	fd = shm_open(shmkey, O_RDWR, 0700);

	if (-1 == fd){
		LOG("arcan_frameserver(getshm) -- couldn't open "
			"keyfile (%s), reason: %s\n", shmkey, strerror(errno));
		return;
	}

	dst->addr = mmap(NULL, ARCAN_SHMPAGE_START_SZ,
		PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	dst->shmh = fd;

	if (force_unlink)
		shm_unlink(shmkey);

	if (MAP_FAILED == dst->addr){
map_fail:
		LOG("arcan_frameserver(getshm) -- couldn't map keyfile"
			"	(%s), reason: %s\n", shmkey, strerror(errno));
		dst->addr = NULL;
		return;
	}

	/* parent suggested that we work with a different
   * size from the start, need to remap */
	if (dst->addr->segment_size != ARCAN_SHMPAGE_START_SZ){
		LOG("arcan_frameserver(getshm) -- different initial size, remapping.\n");
		size_t sz = dst->addr->segment_size;
		munmap(dst->addr, ARCAN_SHMPAGE_START_SZ);
		dst->addr = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		if (MAP_FAILED == dst->addr)
			goto map_fail;
	}

	LOG("arcan_frameserver(getshm) -- mapped to %" PRIxPTR
		" \n", (uintptr_t) dst->addr);

/* step 2, semaphore handles */
	char* work = strdup(shmkey);
	work[strlen(work) - 1] = 'v';
	dst->vsem = sem_open(work, 0);
	if (force_unlink)
		sem_unlink(work);

	work[strlen(work) - 1] = 'a';
	dst->asem = sem_open(work, 0);
	if (force_unlink)
		sem_unlink(work);

	work[strlen(work) - 1] = 'e';
	dst->esem = sem_open(work, 0);
	if (force_unlink)
		sem_unlink(work);
	free(work);

	if (dst->asem == 0x0 || dst->esem == 0x0 || dst->vsem == 0x0){
		LOG("arcan_shmif_control(getshm) -- couldn't "
			"map semaphores (basekey: %s), giving up.\n", shmkey);
		free(dst->addr);
		dst->addr = NULL;
		return;
	}
}

char* arcan_shmif_connect(const char* connpath, const char* connkey,
	file_handle* conn_ch)
{
	if (!connpath){
		LOG("arcan_shmif_connect(), missing connpath, giving up.\n");
		return NULL;
	}

	char* res = NULL;
	char* workbuf = NULL;
	size_t conn_sz;

/* the rules for resolving the connection socket namespace are
 * somewhat complex, i.e. on linux we have the atrocious \0 prefix
 * that defines a separate socket namespace, if we don't specify
 * an absolute path, the key will resolve to be relative your
 * HOME environment (BUT we also have an odd size limitation to
 * sun_path to take into consideration). */
#ifdef __linux
	if (ARCAN_SHM_PREFIX[0] == '\0'){
		conn_sz = strlen(connpath) + sizeof(ARCAN_SHM_PREFIX);
		workbuf = malloc(conn_sz);
		snprintf(workbuf+1, conn_sz-1, "%s%s", &ARCAN_SHM_PREFIX[1], connpath);
		workbuf[0] = '\0';
	}
	else
#endif
	if (ARCAN_SHM_PREFIX[0] != '/'){
		const char* auxp = getenv("HOME");
		conn_sz = strlen(connpath) + strlen(auxp) + sizeof(ARCAN_SHM_PREFIX) + 1;
		workbuf = malloc(conn_sz);
		snprintf(workbuf, conn_sz, "%s/%s%s", auxp, ARCAN_SHM_PREFIX, connpath);
	}
	else {
		conn_sz = strlen(connpath) + sizeof(ARCAN_SHM_PREFIX);
		workbuf = malloc(conn_sz);
		snprintf(workbuf, conn_sz, "%s%s", ARCAN_SHM_PREFIX, connpath);
	}

/* 1. treat connpath as socket and connect */
	int sock = socket(AF_UNIX, SOCK_STREAM, 0);

#ifdef __APPLE__
	int val = 1;
	setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif

	struct sockaddr_un dst = {
		.sun_family = AF_UNIX
	};

	if (-1 == sock){
		LOG("arcan_shmif_connect(), "
			"couldn't allocate socket, reason: %s\n", strerror(errno));
		goto end;
	}

	size_t lim = sizeof(dst.sun_path) / sizeof(dst.sun_path[0]);
	if (lim < conn_sz){
		LOG("arcan_shmif_connect(), "
			"specified connection path exceeds limits (%zu)\n", lim);
		goto end;
	}
	memcpy(dst.sun_path, workbuf, conn_sz);

/* connection or not, unlink the connection path */
	if (connect(sock, (struct sockaddr*) &dst, sizeof(struct sockaddr_un)) < 0){
		LOG("arcan_shmif_connect(%s), "
			"couldn't connect to server, reason: %s.\n",
			dst.sun_path, strerror(errno)
		);
		close(sock);
		unlink(workbuf);
		goto end;
	}
	unlink(workbuf);

/* 2. send (optional) connection key, we send that first (keylen + linefeed) */
	char wbuf[PP_SHMPAGE_SHMKEYLIM+1];
	if (connkey){
		ssize_t nw = snprintf(wbuf, PP_SHMPAGE_SHMKEYLIM, "%s\n", connkey);
		if (nw >= PP_SHMPAGE_SHMKEYLIM){
			LOG("arcan_shmif_connect(%s), "
				"ident string (%s) exceeds limit (%d).\n",
				workbuf, connkey, PP_SHMPAGE_SHMKEYLIM
			);
			close(sock);
			goto end;
		}

		if (write(sock, wbuf, nw) < nw){
			LOG("arcan_shmif_connect(%s), "
				"error sending connection string, reason: %s\n",
				workbuf, strerror(errno)
			);
			close(sock);
			goto end;
		}
	}

/* 3. wait for key response (or broken socket) */
	size_t ofs = 0;
	do {
		if (-1 == read(sock, wbuf + ofs, 1)){
			LOG("arcan_shmif_connect(%s), "
				"invalid response received during shmpage negotiation.\n", workbuf);
			close(sock);
			goto end;
		}
	}
	while(wbuf[ofs++] != '\n' && ofs < PP_SHMPAGE_SHMKEYLIM);
	wbuf[ofs-1] = '\0';

/* 4. omitted, just return a copy of the key and let someoneddelse
 * perform the arcan_shmif_acquire call. Just set the env. */
	res = strdup(wbuf);

	*conn_ch = sock;

end:
	free(workbuf);
	return res;
}

static inline bool parent_alive(struct shmif_hidden* gs)
{
/* based on the idea that init inherits an orphaned process,
 * return getppid() != 1; won't work for hijack targets that fork() fork() */
	return kill(gs->guard.parent, 0) != -1;
}
#endif

struct arcan_shmif_cont arcan_shmif_acquire(
	struct arcan_shmif_cont* parent,
	const char* shmkey,
	enum ARCAN_SEGID type,
	enum SHMIF_FLAGS flags, ...)
{
	struct arcan_shmif_cont res = {
		.vidp = NULL
	};

	if (!shmkey && (!parent || !parent->priv))
		return res;

	bool privps = false;

/* different path based on an acquire from a NEWSEGMENT event or if it
 * comes from a _connect (via _open) call */
	if (!shmkey){
		struct shmif_hidden* gs = parent->priv;
		map_shared(gs->pseg.key, !(flags & SHMIF_DONT_UNLINK), &res);
		if (!res.addr){
			close(gs->pseg.epipe);
			gs->pseg.epipe = BADFD;
		}
		privps = true; /* can't set d/e fields yet */
	}
	else
		map_shared(shmkey, !(flags & SHMIF_DONT_UNLINK), &res);

	if (!res.addr){
		LOG("(arcan_shmif) Couldn't acquire connection through (%s)\n", shmkey);

		if (flags & SHMIF_ACQUIRE_FATALFAIL)
			exit(EXIT_FAILURE);
		else
			return res;
	}

	void (*exitf)(int) = exit;
	if (flags & SHMIF_FATALFAIL_FUNC){
		va_list funarg;

		va_start(funarg, flags);
			exitf = va_arg(funarg, void(*)(int));
		va_end(funarg);
	}

	struct shmif_hidden gs = {
		.guard = {
			.dms = (uintptr_t*) &res.addr->dms,
			.semset = { res.asem, res.vsem, res.esem },
			.parent = res.addr->parent,
			.exitf = exitf
		},
		.pev = {.fd = BADFD},
		.pseg = {.epipe = BADFD},
	};

/* will also set up and popuplate -> priv */
	spawn_guardthread(gs, &res, flags & SHMIF_DISABLE_GUARD);

	if (privps){
		struct shmif_hidden* pp = parent->priv;

		res.epipe = pp->pseg.epipe;
#ifdef __APPLE__
		int val = 1;
		setsockopt(res.epipe, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif

		pp->pseg.epipe = BADFD;
		memset(pp->pseg.key, '\0', sizeof(pp->pseg.key));
		consume(parent, true);
	}

	arcan_shmif_setevqs(res.addr, res.esem, &res.inev, &res.outev, false);
	arcan_shmif_calcofs(res.addr, &res.vidp, &res.audp);

	res.shmsize = res.addr->segment_size;
	res.cookie = arcan_shmif_cookie();

	if (type == SEGID_ENCODER){
		((struct shmif_hidden*)res.priv)->output = true;
	}

	if (0 != type) {
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_REGISTER,
			.ext.registr.kind = type
		};

		arcan_shmif_enqueue(&res, &ev);
	}

	return res;
}

static void* guard_thread(void* gs)
{
	struct shmif_hidden* gstr = gs;
	*(gstr->guard.dms) = true;

	while (gstr->guard.active){
		if (!parent_alive(gstr)){
			pthread_mutex_lock(&gstr->guard.synch);
			*(gstr->guard.dms) = false;

			for (size_t i = 0; i < sizeof(gstr->guard.semset) /
					sizeof(gstr->guard.semset[0]); i++)
				if (gstr->guard.semset[i])
					arcan_sem_post(gstr->guard.semset[i]);

			pthread_mutex_unlock(&gstr->guard.synch);
			sleep(5);
			LOG("frameserver::guard_thread -- couldn't shut"
				"	down gracefully, exiting.\n");

			if (gstr->guard.exitf)
				gstr->guard.exitf(EXIT_FAILURE);
			goto done;
		}

		sleep(5);
	}

done:
	free(gstr);
	return NULL;
}

bool arcan_shmif_integrity_check(struct arcan_shmif_cont* cont)
{
	struct arcan_shmif_page* shmp = cont->addr;
	if (!cont)
		return false;

	if (shmp->major != ARCAN_VERSION_MAJOR ||
		shmp->minor != ARCAN_VERSION_MINOR){
		LOG("frameserver::shmif integrity check failed, version mismatch\n");
		return false;
	}

	if (shmp->cookie != cont->cookie)
	{
		LOG("frameserver::shmif integrity check failed, non-matching cookies"
			"(%llu) vs (%llu), this is a serious issue indicating either "
			"data-corruption or compiler / interface version mismatch.\n",
			(long long unsigned) shmp->cookie, (long long unsigned) cont->cookie);

		return false;
	}

	return true;
}

void arcan_shmif_setevqs(struct arcan_shmif_page* dst,
	sem_handle esem, arcan_evctx* inq, arcan_evctx* outq, bool parent)
{
	if (parent){
		arcan_evctx* tmp = inq;
		inq = outq;
		outq = tmp;

		outq->synch.handle = esem;
		inq->synch.handle = esem;

		inq->synch.killswitch = NULL;
		outq->synch.killswitch = NULL;
	}
	else {
		inq->synch.handle = esem;
		inq->synch.killswitch = &dst->dms;
		outq->synch.handle = esem;
		outq->synch.killswitch = &dst->dms;
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	if (!inq->synch.init){
		inq->synch.init = true;
		pthread_mutex_init(&inq->synch.lock, NULL);
	}
	if (!outq->synch.init){
		outq->synch.init = true;
		pthread_mutex_init(&outq->synch.lock, NULL);
	}
#endif

	inq->local = false;
	inq->eventbuf = dst->childevq.evqueue;
	inq->front = &dst->childevq.front;
	inq->back  = &dst->childevq.back;
	inq->eventbuf_sz = ARCAN_SHMPAGE_QUEUE_SZ;

	outq->local =false;
	outq->eventbuf = dst->parentevq.evqueue;
	outq->front = &dst->parentevq.front;
	outq->back  = &dst->parentevq.back;
	outq->eventbuf_sz = ARCAN_SHMPAGE_QUEUE_SZ;
}

#if _WIN32
void arcan_shmif_signalhandle(struct arcan_shmif_cont* ctx, int mask,
	int handle, size_t stride, int format, ...)
{
}

#else
void arcan_shmif_signalhandle(struct arcan_shmif_cont* ctx, int mask,
	int handle, size_t stride, int format, ...)
{
	if (!arcan_pushhandle(handle, ctx->epipe))
		return;

	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_BUFFERSTREAM,
		.ext.bstream.pitch = stride,
		.ext.bstream.format = format
	};
	arcan_shmif_enqueue(ctx, &ev);
	arcan_shmif_signal(ctx, mask);
}
#endif

void arcan_shmif_signal(struct arcan_shmif_cont* ctx, int mask)
{
	struct shmif_hidden* priv = ctx->priv;
	if (!ctx->addr->dms)
		return;

/*
 * possible misuse point (need to verify in kernel source for this)
 * who OWNS this descriptor after a push when it comes to descriptor
 * limits etc.? The misuse here would be a number of pushes that
 * are not aligned with a corresponding event. The parent can
 * detect this by attempting to read from the socket and if it gets
 * one without a pending event, alert + KILL.
 */
	if ( (mask & SHMIF_SIGVID) && priv->video_hook)
		mask = priv->video_hook(ctx);

	if ( (mask & SHMIF_SIGAUD) && priv->audio_hook)
		mask = priv->audio_hook(ctx);

	if ( (mask & SHMIF_SIGVID) && !(mask & SHMIF_SIGAUD)){
		ctx->addr->vready = true;
		arcan_sem_wait(ctx->vsem);
	}
	else if ( (mask & SHMIF_SIGAUD) && !(mask & SHMIF_SIGVID)){
		ctx->addr->aready = true;
		arcan_sem_wait(ctx->asem);
	}
	else if (mask & (SHMIF_SIGVID | SHMIF_SIGAUD)){
		ctx->addr->vready = true;
    if (ctx->addr->abufused > 0){
			ctx->addr->aready = true;
			arcan_sem_wait(ctx->asem);
    }
		arcan_sem_wait(ctx->vsem);
	}
	else
		;
}

void arcan_shmif_forceofs(struct arcan_shmif_page* shmp,
	uint32_t** dstvidptr, int16_t** dstaudptr, unsigned width,
	unsigned height, unsigned bpp)
{
	uint8_t* base = (uint8_t*) shmp;
	uint8_t* vidaddr = base + sizeof(struct arcan_shmif_page);
	uint8_t* audaddr;

	const int memalign = 64;

	if ( (uintptr_t)vidaddr % memalign != 0)
		vidaddr += memalign - ( (uintptr_t)vidaddr % memalign);

	audaddr = vidaddr + width * height * bpp;
	if ( (uintptr_t) audaddr % memalign != 0)
		audaddr += memalign - ( (uintptr_t) audaddr % memalign);

	if (audaddr < base || vidaddr < base){
		*dstvidptr = NULL;
		*dstaudptr = NULL;
	}
/* we guarantee the alignment, hence the cast */
	else {
		*dstvidptr = (uint32_t*) vidaddr;
		*dstaudptr = (int16_t*) audaddr;
	}
}

void arcan_shmif_calcofs(struct arcan_shmif_page* shmp,
	uint32_t** dstvidptr, int16_t** dstaudptr)
{
	arcan_shmif_forceofs(shmp, dstvidptr, dstaudptr,
		shmp->w, shmp->h, ARCAN_SHMPAGE_VCHANNELS);
}

void arcan_shmif_drop(struct arcan_shmif_cont* inctx)
{
	if (!inctx || !inctx->priv)
		return;

	if (inctx->addr)
		inctx->addr->dms = false;

	struct shmif_hidden* gstr = inctx->priv;

	close(inctx->epipe);

/* guard thread will clean up on its own */
	if (gstr->guard.active){
		gstr->guard.active = false;
	}
/* no guard thread for this context */
	else
		free(inctx->priv);

#if _WIN32
#else
	munmap(inctx->addr, inctx->shmsize);
#endif
	memset(inctx, '\0', sizeof(struct arcan_shmif_cont));
}

size_t arcan_shmif_getsize(unsigned width, unsigned height)
{
	return width * height * ARCAN_SHMPAGE_VCHANNELS +
		sizeof(struct arcan_shmif_page) + ARCAN_SHMPAGE_AUDIOBUF_SZ;
}

bool arcan_shmif_resize(struct arcan_shmif_cont* arg,
	unsigned width, unsigned height)
{
	if (!arg->addr || !arcan_shmif_integrity_check(arg))
		return false;

	arg->addr->w = width;
	arg->addr->h = height;
	arg->addr->resized = true;

	LOG("request resize to (%d:%d) approx ~%zu bytes (currently: %zu).\n",
		width, height, arcan_shmif_getsize(width, height), arg->shmsize);

/*
 * spin until acknowledged,
 * re-using the "wait on sync-fd" approach might
 * be worthwile (test latency to be sure).
 */
	while(arg->addr->resized && arg->addr->dms)
		;

	if (!arg->addr->dms){
		LOG("dead man switch pulled during resize, giving up.\n");
		return false;
	}

	if (arg->shmsize != arg->addr->segment_size){
/*
 * the guard struct, if present, has another thread running that may
 * trigger the dms. BUT now the dms may be relocated so we must lock
 * guard and update and recalculate everything.
 */
		size_t new_sz = arg->addr->segment_size;
		struct shmif_hidden* gs = arg->priv;
		if (gs)
			pthread_mutex_lock(&gs->guard.synch);

/* win32 is built with overcommit as we don't support dynamically
 * resizing shared memory pages there */
#if _WIN32
#else
		munmap(arg->addr, arg->shmsize);
		arg->shmsize = new_sz;
		arg->addr = mmap(NULL, arg->shmsize,
			PROT_READ | PROT_WRITE, MAP_SHARED, arg->shmh, 0);
#endif
		if (!arg->addr){
			LOG("arcan_shmif_resize() failed on segment remapping.\n");
			return false;
		}

		arcan_shmif_setevqs(arg->addr, arg->esem, &arg->inev, &arg->outev, false);

		if (gs){
			gs->guard.dms = &arg->addr->dms;
			pthread_mutex_unlock(&gs->guard.synch);
		}
	}

/* free, mmap again --
 * parent has ftruncated and copied contents */

	arcan_shmif_calcofs(arg->addr, &arg->vidp, &arg->audp);
	return true;
}

shmif_trigger_hook arcan_shmif_signalhook(struct arcan_shmif_cont* cont,
	enum arcan_shmif_sigmask mask, shmif_trigger_hook hook, void* data)
{
	struct shmif_hidden* priv = cont->priv;
	shmif_trigger_hook rv = NULL;

	if (mask == (SHMIF_SIGVID | SHMIF_SIGAUD))
	;
	else if (mask == SHMIF_SIGVID){
		rv = priv->video_hook;
		priv->video_hook = hook;
		priv->video_hook_data = data;
	}
	else if (mask == SHMIF_SIGAUD){
		rv = priv->audio_hook;
		priv->audio_hook = hook;
		priv->audio_hook_data = data;
	}
	else;

	return rv;
}

struct arcan_shmif_cont* arcan_shmif_primary(enum arcan_shmif_type type)
{
	if (type == SHMIF_INPUT)
		return primary.input;
	else
		return primary.output;
}

void arcan_shmif_setprimary(enum arcan_shmif_type type,
	struct arcan_shmif_cont* seg)
{
	if (type == SHMIF_INPUT)
		primary.input = seg;
	else
		primary.output = seg;
}

static char* strrep(char* dst, char key, char repl)
{
	char* src = dst;

	if (dst)
		while (*dst){
			if (*dst == key)
				*dst = repl;
			dst++;
		}

		return src;
}

struct arg_arr* arg_unpack(const char* resource)
{
	int argc = 1;
	const char* rsstr = resource;

/* unless an empty string, we'll always have 1 */
	if (!resource)
		return NULL;

/* figure out the number of additional arguments we have */
	do{
		if (rsstr[argc] == ':')
			argc++;
		rsstr++;
	} while(*rsstr);

/* prepare space */
	struct arg_arr* argv = malloc( (argc+1) * sizeof(struct arg_arr) );
	if (!argv)
		return NULL;

	int curarg = 0;
	argv[argc].key = argv[argc].value = NULL;

	char* base    = strdup(resource);
	char* workstr = base;

/* sweep for key=val:key:key style packed arguments,
 * since this is used in such a limited fashion (RFC 3986 at worst),
 * we use a replacement token rather than an escape one,
 * so \t becomes : post-process
 */
	while (curarg < argc){
		char* endp  = workstr;
		argv[curarg].key = argv[curarg].value = NULL;

		while (*endp && *endp != ':'){
/* a==:=a=:a=dd= are disallowed */
			if (*endp == '='){
				if (!argv[curarg].key){
					*endp = 0;
					argv[curarg].key = strrep(strdup(workstr), '\t', ':');
					argv[curarg].value = NULL;
					workstr = endp + 1;
				}
				else{
					free(argv);
					argv = NULL;
					goto cleanup;
				}
			}

			endp++;
		}

		if (*endp == ':')
			*endp = '\0';

		if (argv[curarg].key)
			argv[curarg].value = strrep(strdup( workstr ), '\t', ':');
		else
			argv[curarg].key = strrep(strdup( workstr ), '\t', ':');

		workstr = (++endp);
		curarg++;
	}

cleanup:
	free(base);

	return argv;
}

void arg_cleanup(struct arg_arr* arr)
{
	if (!arr)
		return;

	while (arr->key){
		free(arr->key);
		free(arr->value);
		arr++;
	}
}

bool arg_lookup(struct arg_arr* arr, const char* val,
	unsigned short ind, const char** found)
{
	int pos = 0;
	if (!arr)
		return false;

	while (arr[pos].key != NULL){
/* return only the 'ind'th match */
		if (strcmp(arr[pos].key, val) == 0)
			if (ind-- == 0){
				if (found)
					*found = arr[pos].value;

				return true;
			}

		pos++;
	}

	return false;
}

struct arcan_shmif_cont arcan_shmif_open(
	enum ARCAN_SEGID type, enum SHMIF_FLAGS flags, struct arg_arr** outarg)
{
	struct arcan_shmif_cont ret = {0};
	file_handle dpipe;

	char* resource = getenv("ARCAN_ARG");
	char* keyfile = NULL;

	if (getenv("ARCAN_SHMKEY") && getenv("ARCAN_SOCKIN_FD")){
		keyfile = getenv("ARCAN_SHMKEY");
		dpipe = (int) strtol(getenv("ARCAN_SOCKIN_FD"), NULL, 10);
	}
	else if (getenv("ARCAN_CONNPATH")){
		do {
			keyfile = arcan_shmif_connect(
				getenv("ARCAN_CONNPATH"), getenv("ARCAN_CONNKEY"), &dpipe);
		} while (keyfile == NULL &&
			(flags & SHMIF_CONNECT_LOOP) > 0 && (sleep(1), 1));
	}
	else {
		LOG("shmif_open() - No arcan-shmif connection, "
			"check ARCAN_CONNPATH environment.\n\n");
		goto fail;
	}

	if (!keyfile){
		LOG("shmif_open() - No valid connection key found, giving up.\n");
		goto fail;
	}

	ret = arcan_shmif_acquire(NULL, keyfile, type, flags);
	if (resource)
		*outarg = arg_unpack(resource);
	else
		*outarg = NULL;

	ret.epipe = dpipe;
	if (-1 == ret.epipe)
		LOG("shmif_open() - Could not retrieve event- pipe from parent.\n");

	return ret;

fail:
	if (flags & SHMIF_ACQUIRE_FATALFAIL)
		exit(EXIT_FAILURE);
	return ret;
}
