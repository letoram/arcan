/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <errno.h>
#include <math.h>
#include <assert.h>
#include <signal.h>

/* fixed limit of allowed events in queue before we need to
 * do something more aggressive (flush queue or start dropping
 * or even blacklisting noisy input device) */
#ifndef ARCAN_EVENT_QUEUE_LIM
#define ARCAN_EVENT_QUEUE_LIM 500
#endif

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"

#include "arcan_shmif.h"
#include "arcan_event.h"

#include "arcan_frameserver.h"

typedef struct queue_cell queue_cell;

static arcan_event eventbuf[ARCAN_EVENT_QUEUE_LIM];
static unsigned eventfront = 0, eventback = 0;
static int64_t epoch;

#ifndef FORCE_SYNCH
	#define FORCE_SYNCH() {\
		asm volatile("": : :"memory");\
		__sync_synchronize();\
	}
#endif

/* set through environment variable to ensure we can shut down
 * cleanly based on a certain keybinding */
static int panic_keysym = -1, panic_keymod = -1;

/* special cases, only enabled if the correct
 * environment has been set */
static FILE* record_out;
static map_region playback_in;
static size_t playback_ofs;

static void pack_rec_event(const struct arcan_event* const outev);

/*
 * By default, we only have a
 * single-producer,single-consumer,single-threaded approach
 * but some platforms may need different support, so allow
 * multiple-producers single-consumer at compile-time
 */
#ifdef EVENT_MULTITHREAD_SUPPORT
#include <pthread.h>
static pthread_mutex_t defctx_mutex = PTHREAD_MUTEX_INITIALIZER;
#define LOCK() pthread_mutex_lock(&defctx_mutex);
#define UNLOCK() pthread_mutex_unlock(&defctx_mutex);
#else
#define LOCK(X)
#define UNLOCK(X)
#endif

static struct arcan_evctx default_evctx = {
	.eventbuf = eventbuf,
	.eventbuf_sz = ARCAN_EVENT_QUEUE_LIM,
	.front = &eventfront,
	.back = &eventback,
	.local = true
};

arcan_evctx* arcan_event_defaultctx(){
	return &default_evctx;
}

/*
 * If the shmpage integrity is somehow compromised,
 * if semaphore use is out of order etc.
 */
static void pull_killswitch(arcan_evctx* ctx)
{
	arcan_frameserver* ks = (arcan_frameserver*) ctx->synch.killswitch;
	arcan_sem_post(ctx->synch.handle);
	arcan_warning("inconsistency while processing "
		"shmpage events, pulling killswitch.\n");
	arcan_frameserver_free(ks);
	ctx->synch.killswitch = NULL;
}

/* check queue for event, ignores mask */
int arcan_event_poll(arcan_evctx* ctx, struct arcan_event* dst)
{
	assert(dst);
	if (*ctx->front == *ctx->back)
		return 0;

	if (ctx->local == false){
		if ( *(ctx->front) > ARCAN_SHMPAGE_QUEUE_SZ )
			pull_killswitch(ctx);
		else {
			FORCE_SYNCH();
			*dst = ctx->eventbuf[ *(ctx->front) ];
			*(ctx->front) = (*(ctx->front) + 1) % ARCAN_SHMPAGE_QUEUE_SZ;
		}
	}
	else {
		LOCK();
			*dst = ctx->eventbuf[ *(ctx->front) ];
			*(ctx->front) = (*(ctx->front) + 1) % ctx->eventbuf_sz;
		UNLOCK();
	}

	return 1;
}


void arcan_event_repl(struct arcan_evctx* ctx, enum ARCAN_EVENT_CATEGORY cat,
	size_t r_ofs, size_t r_b, void* cmpbuf, size_t w_ofs, size_t w_b, void* w_buf)
{
	if (!ctx->local)
		return;

	LOCK();

	unsigned front = *ctx->front;

	while (front != *ctx->back){
		if (ctx->eventbuf[front].category == cat &&
			memcmp( (char*)(&ctx->eventbuf[front]) + r_ofs, cmpbuf, r_b) == 0){
				memcpy( (char*)(&ctx->eventbuf[front]) + w_ofs, w_buf, w_b );
		}

		front = (front + 1) % ctx->eventbuf_sz;
	}

	UNLOCK();
}

void arcan_event_maskall(arcan_evctx* ctx)
{
	ctx->mask_cat_inp = 0xffffffff;
}

void arcan_event_clearmask(arcan_evctx* ctx)
{
	ctx->mask_cat_inp = 0;
}

void arcan_event_setmask(arcan_evctx* ctx, uint32_t mask)
{
	ctx->mask_cat_inp = mask;
}

/*
 * enqueue to current context considering input-masking,
 * unless label is set, assign one based on what kind of event it is
 * This function has a similar prototype to the enqueue defined in
 * the interop.h, but a different implementation to support waking up
 * the child, and that blocking behaviors in the main thread is always
 * forbidden.
 */
int arcan_event_enqueue(arcan_evctx* ctx, const struct arcan_event* const src)
{
/* early-out mask-filter, these are only ever used to silently
 * discard input / output (only operate on head and tail of ringbuffer) */
	if (!src || (src->category & ctx->mask_cat_inp)){
		return 1;
	}

/*
 * Note, we should add panic /warning hooks here as the internal event
 * subsystem is overloaded, which is a sign of something gone wrong.
 * The recover option would be to silently overwrite one of the lesser
 * important (typically, ANALOG INPUTS or frame counters) in the queue
 */
	if (((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		return 0;
	}

	if (panic_keysym != -1 && panic_keymod != -1 &&
		src->category == EVENT_IO &&
		src->io.kind == EVENT_IO_BUTTON &&
		src->io.devkind == EVENT_IDEVKIND_KEYBOARD &&
		src->io.input.translated.modifiers == panic_keymod &&
		src->io.input.translated.keysym == panic_keysym
	){

		arcan_event ev = {
			.category = EVENT_SYSTEM,
			.sys.kind = EVENT_SYSTEM_EXIT,
			.sys.errcode = EXIT_SUCCESS
		};

		return arcan_event_enqueue(ctx, &ev);
	}

	if (ctx->local){
		LOCK();
		if (src->category == EVENT_IO){
			pack_rec_event(src);
		}
	}

	ctx->eventbuf[(*ctx->back) % ctx->eventbuf_sz] = *src;
	ctx->eventbuf[(*ctx->back) % ctx->eventbuf_sz].timestamp = arcan_frametime();
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

/*
 * Currently, we just wake the sleeping frameserver up as soon as we get
 * an event (and it's actually sleeping), the better option would be
 * to somehow determine if we'll have more useful events coming in a little
 * while so that we don't get a sleep -> 1 event -> sleep -> 1 event scenario
 * for highly interactive frameservers
 */
	if (ctx->local){
		UNLOCK();
	}

	return 1;
}

static inline int queue_used(arcan_evctx* dq)
{
int rv = *(dq->front) > *(dq->back) ? dq->eventbuf_sz -
*(dq->front) + *(dq->back) : *(dq->back) - *(dq->front);
return rv;
}

void arcan_event_queuetransfer(arcan_evctx* dstqueue, arcan_evctx* srcqueue,
	enum ARCAN_EVENT_CATEGORY allowed, float saturation, arcan_vobj_id source)
{
	if (!srcqueue || !dstqueue || (srcqueue && !srcqueue->front)
		|| (srcqueue && !srcqueue->back))
		return;

	bool wake = false;

	arcan_frameserver* tgt = arcan_video_feedstate(source) ?
		arcan_video_feedstate(source)->ptr : NULL;

	saturation = (saturation > 1.0 ? 1.0 : saturation < 0.5 ? 0.5 : saturation);

	while ( srcqueue->front && *srcqueue->front != *srcqueue->back &&
			floor((float)dstqueue->eventbuf_sz * saturation) > queue_used(dstqueue)) {

		arcan_event inev;
		if (arcan_event_poll(srcqueue, &inev) == 0)
			break;

/*
 * update / translate to make sure the corresponding frameserver<->lua mapping
 * can be found and tracked, there are also a few events that should be handled
 * here rather than propagated (bufferstream for instance).
 */
		if ((inev.category & allowed) == 0 )
			continue;

		if (inev.category == EVENT_EXTERNAL){
			switch(inev.ext.kind){

/* to protect against scripts that would happily try to just allocate/respond
 * to what a the event says, clamp this here */
				case EVENT_EXTERNAL_SEGREQ:
					if (inev.ext.noticereq.width > PP_SHMPAGE_MAXW)
						inev.ext.noticereq.width = PP_SHMPAGE_MAXW;

					if (inev.ext.noticereq.height > PP_SHMPAGE_MAXH)
						inev.ext.noticereq.height = PP_SHMPAGE_MAXH;
				break;

#ifndef _WIN32
				case EVENT_EXTERNAL_BUFFERSTREAM:
/* this assumes that we are in non-blocking state and that a single
 * CSMG on a socket is sufficient for a non-blocking recvmsg */
					if (tgt->vstream.handle)
						close(tgt->vstream.handle);

					tgt->vstream.handle = arcan_fetchhandle(tgt->dpipe, false);
					tgt->vstream.stride = inev.ext.bstream.pitch;
					tgt->vstream.format = inev.ext.bstream.format;
				break;
#endif

/* note: one could manually enable EVENT_INPUT and use separate processes
 * as input sources (with all the risks that comes with it security wise)
 * if that ever becomes a concern, here would be a good place to consider
 * filtering the panic_key* */

/* client may need more fine grained control for audio transfers when it
 * comes to synchronized A/V playback */
				case EVENT_EXTERNAL_FLUSHAUD:
					if (tgt)
						arcan_frameserver_flush(tgt);
					continue;
				break;

				default:
				break;
			}
			inev.ext.source = source;
		}

		else if (inev.category == EVENT_NET){
			inev.net.source = source;
		}

		wake = true;
		arcan_event_enqueue(dstqueue, &inev);
	}

	if (wake)
		arcan_sem_post(srcqueue->synch.handle);
}

static long unpack_rec_event(char* bytep, size_t sz, arcan_event* tv,
	int32_t* tickv)
{
	size_t nb = sizeof(int32_t) * 11;

	if (sz < nb)
		return -1;

	int32_t buf[11];
	memcpy(buf, bytep, nb);
	*tickv = buf[0];

	tv->category = EVENT_IO;
	tv->io.kind = buf[1];

	switch (buf[1]){
	case EVENT_IO_TOUCH:
		tv->io.input.touch.devid = buf[2];
		tv->io.input.touch.subid = buf[3];
		tv->io.input.touch.pressure = buf[4];
		tv->io.input.touch.size = buf[5];
		tv->io.input.touch.x = buf[6];
		tv->io.input.touch.y = buf[7];
	break;
	case EVENT_IO_AXIS_MOVE:
		tv->io.input.analog.devid = buf[2];
		tv->io.input.analog.subid = buf[3];
		tv->io.input.analog.gotrel = buf[4];
		if (buf[5] < sizeof(buf) / sizeof(buf[0]) - 6){
			for (size_t i = 0; i < buf[5]; i++)
				tv->io.input.analog.axisval[i] = buf[6+i];
			tv->io.input.analog.nvalues = buf[5];
		}
		else
			buf[5] = 0;
	break;
	case EVENT_IO_BUTTON:
		if (buf[4] == EVENT_IDEVKIND_KEYBOARD){
			tv->io.input.translated.devid = buf[2];
			tv->io.input.translated.subid = buf[3];
			tv->io.devkind = EVENT_IDEVKIND_KEYBOARD;
			tv->io.input.translated.active = buf[5];
			tv->io.input.translated.scancode = buf[6];
			tv->io.input.translated.keysym = buf[7];
			tv->io.input.translated.modifiers = buf[8];
		}
		else if (buf[4] == EVENT_IDEVKIND_MOUSE||buf[4] == EVENT_IDEVKIND_GAMEDEV){
			tv->io.devkind = buf[4];
			tv->io.input.digital.devid = buf[2];
			tv->io.input.digital.subid = buf[3];
			tv->io.input.digital.active = buf[5];
		}
		else
			return -1;
	}

	return nb;
}

/*
 * no heavy serialization effort here, the format is intended
 * for debugging and testing. shmif- event serialization should
 * be used for other purposes.
 */
static void pack_rec_event(const struct arcan_event* const outev)
{
	if (!record_out)
		return;

	if (outev->category != EVENT_IO)
		return;

/* since this is a testing thing, we are not particularly considerate
 * in regards to compact representation */
	int32_t ioarr[11] = {0};
	ioarr[0] = arcan_frametime();
	size_t nmemb = sizeof(ioarr) / sizeof(ioarr[0]);
	ioarr[1] = outev->io.kind;

	switch(outev->io.kind){
	case EVENT_IO_TOUCH:
		ioarr[2] = outev->io.input.touch.devid;
		ioarr[3] = outev->io.input.touch.subid;
		ioarr[4] = outev->io.input.touch.pressure;
		ioarr[5] = outev->io.input.touch.size;
		ioarr[6] = outev->io.input.touch.x;
		ioarr[7] = outev->io.input.touch.y;
	break;
	case EVENT_IO_AXIS_MOVE:
		ioarr[2] = outev->io.input.analog.devid;
		ioarr[3] = outev->io.input.analog.subid;
		ioarr[4] = outev->io.input.analog.gotrel;
		for (size_t i = 0; i < nmemb - 6 &&
			i < outev->io.input.analog.nvalues; i++){
			ioarr[6+i] = outev->io.input.analog.axisval[i];
			ioarr[5]++;
		}
	break;
	case EVENT_IO_BUTTON:
		if (outev->io.devkind == EVENT_IDEVKIND_KEYBOARD){
			ioarr[2] = outev->io.input.translated.devid;
			ioarr[3] = outev->io.input.translated.subid;
			ioarr[4] = outev->io.devkind;
			ioarr[5] = outev->io.input.translated.active;
			ioarr[6] = outev->io.input.translated.scancode;
			ioarr[7] = outev->io.input.translated.keysym;
			ioarr[8] = outev->io.input.translated.modifiers;
		}
		else if (outev->io.devkind == EVENT_IDEVKIND_MOUSE ||
			outev->io.devkind == EVENT_IDEVKIND_GAMEDEV){
			ioarr[2] = outev->io.input.digital.devid;
			ioarr[3] = outev->io.input.digital.subid;
			ioarr[4] = outev->io.devkind;
			ioarr[5] = outev->io.input.digital.active;
		}
		else
			return;
	break;
	}

	if (1 != fwrite(ioarr, sizeof(int32_t) * nmemb, 1, record_out)){
		fclose(record_out);
		record_out = NULL;
	}
}

static void inject_scheduled(arcan_evctx* ctx)
{
	if (!playback_in.ptr)
		return;

	static arcan_event next_ev;
	static int32_t tickv = -1; /* -1 if no pending events */

step:
	if (tickv != -1){
		if (tickv <= arcan_frametime()){
			arcan_event_enqueue(ctx, &next_ev);
			tickv = -1;
		}
		else
			return;
	}

	ssize_t rv = unpack_rec_event(&playback_in.ptr[playback_ofs],
		playback_in.sz - playback_ofs, &next_ev, &tickv);

	if (-1 == rv){
		arcan_release_map(playback_in);
		memset(&playback_in, '\0', sizeof(playback_in));
		return;
	}

	playback_ofs += rv;
	goto step;
}

int64_t arcan_frametime()
{
	int64_t now = arcan_timemillis();
	if (now < epoch)
		epoch = now - (epoch - now);

	return now - epoch;
}

float arcan_event_process(arcan_evctx* ctx, arcan_tick_cb cb)
{
	int64_t base = ctx->c_ticks * ARCAN_TIMER_TICK;
	int64_t delta = arcan_frametime() - base;

	inject_scheduled(ctx);
	platform_event_process(ctx);

	if (delta > ARCAN_TIMER_TICK){
		int nticks = delta / ARCAN_TIMER_TICK;
		if (nticks > ARCAN_TICK_THRESHOLD){
			epoch += (nticks - 1) * ARCAN_TIMER_TICK;
			nticks = 1;
		}

		ctx->c_ticks += nticks;
		cb(nticks);
		arcan_bench_register_tick(nticks);
		return arcan_event_process(ctx, cb);
	}

	return (float)delta / (float)ARCAN_TIMER_TICK;
}

arcan_benchdata benchdata = {0};

/*
 * keep the time tracking separate from the other
 * timekeeping parts, discard non-monotonic values
 */
void arcan_bench_register_tick(unsigned nticks)
{
	static long long int lasttick = -1;
	if (benchdata.bench_enabled == false)
		return;

	while (nticks--){
		long long int ftime = arcan_timemillis();
		benchdata.tickcount++;

		if (lasttick > 0 && ftime > lasttick){
			unsigned delta = ftime - lasttick;
			benchdata.ticktime[(unsigned)benchdata.tickofs] = delta;
			benchdata.tickofs = (benchdata.tickofs + 1) %
				(sizeof(benchdata.ticktime) / sizeof(benchdata.ticktime[0]));
		}

		lasttick = ftime;
	}
}

void arcan_event_purge()
{
	LOCK();
	arcan_event meventbuf[ARCAN_EVENT_QUEUE_LIM];
	int ind = 0;

	for (int i = eventback; i != eventfront; i = (i + 1) % ARCAN_EVENT_QUEUE_LIM)
		if (eventbuf[i].category == EVENT_EXTERNAL)
			meventbuf[ind++] = eventbuf[i];

	memset(eventbuf, '\0', sizeof(arcan_event) * ARCAN_EVENT_QUEUE_LIM);
	memcpy(eventbuf, meventbuf, sizeof(arcan_event) * ind);
	eventfront = ind;
	eventback = 0;

	UNLOCK();
}

void arcan_bench_register_cost(unsigned cost)
{
	benchdata.framecost[(unsigned)benchdata.costofs] = cost;
	if (benchdata.bench_enabled == false)
		return;

	benchdata.costcount++;
	benchdata.costofs = (benchdata.costofs + 1) %
		(sizeof(benchdata.framecost) / sizeof(benchdata.framecost[0]));
}

void arcan_bench_register_frame()
{
	static long long int lastframe = -1;
	if (benchdata.bench_enabled == false)
		return;

	long long int ftime = arcan_timemillis();
	if (lastframe > 0 && ftime > lastframe){
		unsigned delta = ftime - lastframe;
		benchdata.frametime[(unsigned)benchdata.frameofs] = delta;
		benchdata.framecount++;
		benchdata.frameofs = (benchdata.frameofs + 1) %
			(sizeof(benchdata.frametime) / sizeof(benchdata.frametime[0]));
		}

	lastframe = ftime;
}

extern void platform_event_deinit(arcan_evctx* ctx);
void arcan_event_deinit(arcan_evctx* ctx)
{
	platform_event_deinit(ctx);

#ifdef EVENT_MULTITHREAD_SUPPORT
	pthread_mutex_destroy(&defctx_mutex);
#endif

	if (record_out){
		fclose(record_out);
		record_out = NULL;
	}

	if (playback_in.ptr){
		arcan_release_map(playback_in);
		memset(&playback_in, '\0', sizeof(playback_in));
		playback_ofs = 0;
	}

	eventfront = eventback = 0;
}

extern void platform_event_init(arcan_evctx* ctx);
void arcan_event_init(arcan_evctx* ctx)
{
/*
 * non-local (i.e. shmpage resident) event queues has a different
 * init approach (see frameserver_shmpage.c)
 */
	if (!ctx->local){
		return;
	}

	const char* panicbutton = getenv("ARCAN_EVENT_SHUTDOWN");
	char* cp;

	if (panicbutton){
		cp = strchr(panicbutton, ':');
		if (cp){
			*cp = '\0';
			panic_keysym = strtol(panicbutton, NULL, 10);
			panic_keymod = strtol(cp+1, NULL, 10);
			*cp = ':';
		}
		else
			arcan_warning("ARCAN_EVENT_SHUTDOWN=%s, malformed key "
				"expecting number:number (keysym:modifiers).\n", panicbutton);
	}

	const char* fn;
	if ((fn = getenv("ARCAN_EVENT_RECORD"))){
		record_out = fopen(fn, "w+");
		if (!record_out)
			arcan_warning("ARCAN_EVENT_RECORD=%s, couldn't open file "
				"for recording.\n", fn);
	}

	if ((fn = getenv("ARCAN_EVENT_REPLAY"))){
		data_source source = arcan_open_resource(fn);
		playback_in = arcan_map_resource(&source, false);
		arcan_release_resource(&source);
	}

#ifdef EVENT_MULTITHREAD_SUPPORT
	pthread_mutex_init(&defctx_mutex, NULL);
#endif

	platform_event_init(ctx);
	epoch = arcan_timemillis();
}

extern void platform_device_lock(int lockdev, bool lockstate);
void arcan_device_lock(int lockdev, bool lockstate)
{
    platform_device_lock(lockdev, lockstate);
}
