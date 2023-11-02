/*
 * Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the arcan source repository.
 * Reference: https://arcan-fe.com
 * Description: The conductor is responsible for figuring out what to synch
 * and what to do in the periods of time where one or many displays and GPUs
 * are busy synching. Since this is a task with many tradeoffs and context
 * specific heuristics, it exposes a user facing set of strategies to chose
 * from.
 */

#include "arcan_hmeta.h"

/* defined in platform.h, used in psep open, shared memory */
_Atomic uint64_t* volatile arcan_watchdog_ping = NULL;
static size_t gpu_lock_bitmap;
static int reset_counter;

void arcan_conductor_enable_watchdog()
{
	arcan_watchdog_ping = arcan_alloc_mem(system_page_size,
		ARCAN_MEM_SHARED, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	atomic_store(arcan_watchdog_ping, arcan_timemillis());
}

void arcan_conductor_toggle_watchdog()
{
	if (arcan_watchdog_ping){
		if (atomic_load(arcan_watchdog_ping)){
			atomic_store(arcan_watchdog_ping, 0);
		}
		else
			atomic_store(arcan_watchdog_ping, arcan_timemillis());
	}
}

/*
 * checklist:
 *  [ ] Actual setup to realtime- plot the different timings and stages. This can
 *      be done partially now in that the key sites are instrumented and can log
 *      into a buffer accessible from Lua, but for faster/better realtime the
 *      build should be patched to map those points to tracey.
 *
 *  [ ] dma-bufs are getting a sync_file API for better fencing which should be
 *      added to the compose- eval ("can we finish the current set within the
 *      time alotted"), and before that propagates, we should use the
 *      pending-set part along with POLLIN on the dma-buf set to determine if
 *      we should compose with the new set or the last-safe set.
 *
 *  [ ] parallelize PBO uploads
 *      (thought: test the systemic effects of not doing shm->gpu in process but
 *      rather have an 'uploader proxy' (like we'd do with wayland) and pass the
 *      descriptors around instead.
 *
 *  [x] perform resize- ack during synch period
 *      [ ] multi-thread resize-ack/evproc.
 *      right now we are 'blocking' on resize- still, though there aren't any
 *      GPU resources modified directly based on the resize stage as such, those
 *      are deferred until the actual frame commit. The later are still hard to
 *      multithread, but just ack-/verify- should be easier.
 *
 *  [ ] posix anon-semaphores on shmpage (OSX blocking)
 *      or drop the semaphores entirely (yes please) and switch to futexes, alas
 *      then we still have the problem of those not being a multiplexable primitives
 *      and needing a separate path for OSX.
 *
 *  [ ] defer GCs to low-load / embarassing pause in thread during synch etc.
 *      since we now 'know' when we are waiting for the GPU to unlock, this is a
 *      good spot to manually step the Lua GCing.
 *
 *  [ ] perform readbacks in possible delay periods might break some GPU drivers
 *
 *  [ ] thread rendertarget processing
 *      this would again be better for something like vulkan where we tie the
 *      rendertarget to a unique pipeline (they are much alike)
 */
static struct {
	uint64_t tick_count;
	int64_t set_deadline;
	double render_cost;
	double transfer_cost;
	uint8_t timestep;
	bool in_frame;
} conductor = {
	.render_cost = 4,
	.transfer_cost = 1,
	.timestep = 2
};

static ssize_t find_frameserver(struct arcan_frameserver* fsrv);

/*
 * To add new options here,
 *
 *  Add the corresponding lock- setting to setsynch then add preframe hook at
 *  preframe_synch and deadline adjustment in postframe_synch. Any 'during
 *  synch' yield specific options goes into conductor_yield. For strategies
 *  that work with a focus target, also handle arcan_conductor_focus.
 */
static char* synchopts[] = {
	"vsynch", "release clients on vsynch",
	"immediate", "release clients as soon as buffers are synched",
	"processing", "synch to ready displays, 100% CPU",
	"powersave", "synch to clock tick (~25Hz)",
	"adaptive", "defer composition",
	"tight", "defer composition, delay client-wake",
	NULL
};

static struct {
	struct arcan_frameserver** ref;
	size_t count;
	size_t used;
	struct arcan_frameserver* focus;
} frameservers;

enum synchopts {
/* wait for display, wake clients after vsynch */
	SYNCH_VSYNCH = 0,
/* wait for display, wake client after buffer ack */
	SYNCH_IMMEDIATE,
/* don't wait for display, wake client immediately */
	SYNCH_PROCESSING,
/* update display on slow clock (25Hz), wake clients after display */
	SYNCH_POWERSAVE,
/* defer composition, wake clients after vsynch */
	SYNCH_ADAPTIVE,
/* defer composition, wake clients after half-time */
	SYNCH_TIGHT
};

static int synchopt = SYNCH_IMMEDIATE;

/*
 * difference between step/unlock is that step performs a polling step
 * where transfers might occur, unlock simply awakes clients that did
 * contribute a frame last pass but has been locked since
 */
static void unlock_herd()
{
	for (size_t i = 0; i < frameservers.count; i++)
		if (frameservers.ref[i]){
			TRACE_MARK_ONESHOT("conductor", "synchronization",
				TRACE_SYS_DEFAULT, frameservers.ref[i]->vid, 0, "unlock-herd");
			arcan_frameserver_releaselock(frameservers.ref[i]);
		}
}

static void step_herd(int mode)
{
	uint64_t start = arcan_timemillis();

	TRACE_MARK_ENTER("conductor", "synchronization",
		TRACE_SYS_DEFAULT, mode, 0, "step-herd");

	arcan_frameserver_lock_buffers(0);
	arcan_video_pollfeed();
	arcan_frameserver_lock_buffers(mode);
	uint64_t stop = arcan_timemillis();

	conductor.transfer_cost =
		0.8 * (double)(stop - start) +
		0.2 * conductor.transfer_cost;

	TRACE_MARK_ENTER("conductor", "synchronization",
		TRACE_SYS_DEFAULT, mode, conductor.transfer_cost, "step-herd");
}

static void forward_vblank()
{
	for (size_t i = 0; i < frameservers.count; i++){
		struct arcan_frameserver* fsrv = frameservers.ref[i];
		if (fsrv && fsrv->clock.vblank){
			struct arcan_vobject* vobj = arcan_video_getobject(fsrv->vid);

			platform_fsrv_pushevent(fsrv, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_STEPFRAME,
					.tgt.ioevs[0].iv = 0,
					.tgt.ioevs[1].iv = 2,
					.tgt.ioevs[2].uiv = vobj->owner->msc,
				});
		}
	}
}

static void internal_yield()
{
	arcan_event_poll_sources(arcan_event_defaultctx(), conductor.timestep);
	TRACE_MARK_ONESHOT("conductor", "yield",
		TRACE_SYS_DEFAULT, 0, conductor.timestep, "step");
}

static void alloc_frameserver_struct()
{
	if (frameservers.ref)
		return;

	frameservers.count = 16;
	size_t buf_sz = sizeof(void*) * frameservers.count;
	frameservers.ref = arcan_alloc_mem(buf_sz,
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	memset(frameservers.ref, '\0', sizeof(void*) * frameservers.count);
}

void arcan_conductor_lock_gpu(
	size_t gpu_id, int fence, arcan_gpu_lockhandler lockh)
{
/*
 * this interface needs some more thinking, but the callback chain will
 * be that video_synch -> lock_gpu[gpu_id, fence_fd] and a process callback
 * when there's data on the fence_fd (which might potentially call unlock)
 */
	gpu_lock_bitmap |= 1 << gpu_id;
	TRACE_MARK_ENTER("conductor", "gpu", TRACE_SYS_DEFAULT, gpu_id, 0, "");
}

void arcan_conductor_release_gpu(size_t gpu_id)
{
	gpu_lock_bitmap &= ~(1 << gpu_id);
	TRACE_MARK_EXIT("conductor", "gpu", TRACE_SYS_DEFAULT, gpu_id, 0, "");
}

size_t arcan_conductor_gpus_locked()
{
	return gpu_lock_bitmap;
}

void arcan_conductor_register_display(size_t gpu_id,
		size_t disp_id, enum synch_method method, float rate, arcan_vobj_id obj)
{
/* need to know which display and which vobj is needed to be updated in order
 * to fulfill the requirement of the display synch so that we can schedule it
 * accordingly, later the full DAG- would also be calculated here to resolve
 * which agp- stores are involved and if they have an affinity on a locked
 * GPU or not so that we can MT GPU updates */
	char buf[48];
	snprintf(buf, 48, "register:%zu:%zu:%zu", gpu_id, disp_id, (size_t) obj);
	TRACE_MARK_ONESHOT("conductor", "display", TRACE_SYS_DEFAULT, gpu_id, 0, buf);
}

void arcan_conductor_release_display(size_t gpu_id, size_t disp_id)
{
/* remove from set of known displays so its rate doesn't come into account */
	char buf[24];
	snprintf(buf, 24, "release:%zu:%zu", gpu_id, disp_id);
	TRACE_MARK_ONESHOT("conductor", "display", TRACE_SYS_DEFAULT, gpu_id, 0, buf);
}

void arcan_conductor_register_frameserver(struct arcan_frameserver* fsrv)
{
	size_t dst_i = 0;
	alloc_frameserver_struct();
	fsrv->desc.recovery_tick = reset_counter;

/* safeguard */
	ssize_t src_i = find_frameserver(fsrv);
	if (-1 != src_i){
		TRACE_MARK_ONESHOT("conductor", "frameserver",
			TRACE_SYS_ERROR, fsrv->vid, 0, "add on known");
		return;

	}

/* check for a gap */
	if (frameservers.used < frameservers.count){
		for (size_t i = 0; i < frameservers.count; i++){
			if (!frameservers.ref[i]){
				dst_i = i;
				break;
			}
		}
	}
/* or grow and add */
	else {
		size_t nbuf_sz = frameservers.count * 2 * sizeof(void*);
		struct arcan_frameserver** newref = arcan_alloc_mem(
			nbuf_sz, ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		memcpy(newref, frameservers.ref, frameservers.count * sizeof(void*));
		arcan_mem_free(frameservers.ref);
		frameservers.ref = newref;
		dst_i = frameservers.count;
		frameservers.count *= 2;
	}

	frameservers.used++;
	frameservers.ref[dst_i] = fsrv;
	TRACE_MARK_ONESHOT("conductor", "frameserver",
		TRACE_SYS_DEFAULT, fsrv->vid, 0, "register");

/*
 * other approach is to run a monitor thread here that futexes on the flags
 * and responds immediately instead, moving the polling etc. details to the
 * other layers.
 *
 * what to keep in mind then is the whole 'events go from Lua, drain-function
 * from the threads isnt safe'
 */
}

int arcan_conductor_yield(struct conductor_display* disps, size_t pset_count)
{
	arcan_audio_refresh();

/* by returning false here we tell the platform to not even wait for synch
 * signal from screens but rather continue immediately */
	if (synchopt == SYNCH_PROCESSING){
		TRACE_MARK_ONESHOT("conductor", "display",
			TRACE_SYS_FAST, 0, frameservers.used, "synch-processing");
		return -1;
	}

	for (size_t i=0, j=frameservers.used; i < frameservers.count && j > 0; i++){
		if (frameservers.ref[i]){
			arcan_vint_pollfeed(frameservers.ref[i]->vid, false);
			j--;
		}
	}

/* same as other timesleep calls, should be replaced with poll and pollset */
	return conductor.timestep;
}

static ssize_t find_frameserver(struct arcan_frameserver* fsrv)
{
	for (size_t i = 0; i < frameservers.count; i++)
		if (frameservers.ref[i] == fsrv)
			return i;

	return -1;
}

const char** arcan_conductor_synchopts()
{
	return (const char**) synchopts;
}

void arcan_conductor_setsynch(const char* arg)
{
	int ind = 0;

	while(synchopts[ind]){
		if (strcmp(synchopts[ind], arg) == 0){
			synchopt = (ind > 0 ? ind / 2 : ind);
			break;
		}

		ind += 2;
	}

	TRACE_MARK_ONESHOT("conductor",
		"synchronization", TRACE_SYS_DEFAULT, 0, 0, arg);

/*
 * There might be small conflicts of unlock/lock behavior as the strategies
 * swap, solving the state transition graphics to get this entirely seamless is
 * probably not worth it.
 * 0: always, 1: no buffers, 2: allow buffers, manual release
 */
	switch (synchopt){
	case SYNCH_VSYNCH:
	case SYNCH_ADAPTIVE:
	case SYNCH_POWERSAVE:
		arcan_frameserver_lock_buffers(2);
	break;
	case SYNCH_TIGHT:
		arcan_frameserver_lock_buffers(2);
	break;
	case SYNCH_IMMEDIATE:
	case SYNCH_PROCESSING:
		arcan_frameserver_lock_buffers(0);
		unlock_herd();
	break;
	}
}

void arcan_conductor_focus(struct arcan_frameserver* fsrv)
{
/* Focus- based strategies might need to do special flag modification both
 * on set and remove. This table takes care of 'unset' */
	switch (synchopt){
	default:
	break;
	}

	ssize_t dst_i = fsrv ? find_frameserver(fsrv) : -1;
	if (-1 == dst_i)
		return;

	if (frameservers.focus)
		frameservers.focus->flags.locked = false;

	TRACE_MARK_ONESHOT("conductor", "synchronization",
		TRACE_SYS_DEFAULT, fsrv->vid, 0, "synch-focus");

/* And this is for 'set' */
	frameservers.focus = fsrv;

	switch(synchopt){
	default:
	break;
	}
}

void arcan_conductor_deregister_frameserver(struct arcan_frameserver* fsrv)
{
/* not all present frameservers will be registered with the conductor */
	ssize_t dst_i = find_frameserver(fsrv);
	if (!frameservers.used || -1 == dst_i){
		arcan_warning("deregister_frameserver() on unknown fsrv @ %zd\n", dst_i);
		return;
	}
	frameservers.ref[dst_i] = NULL;
	frameservers.used--;

	if (fsrv == frameservers.focus){
		TRACE_MARK_ONESHOT("conductor", "frameserver",
			TRACE_SYS_DEFAULT, fsrv->vid, 0, "lost-focus");

		frameservers.focus = NULL;
	}

	TRACE_MARK_ONESHOT("conductor", "frameserver",
		TRACE_SYS_DEFAULT, fsrv->vid, 0, "deregister");

/* the real work here comes when we do multithreaded processing */
}

extern struct arcan_luactx* main_lua_context;
static size_t event_count;
static bool process_event(arcan_event* ev, int drain)
{
/*
 * The event_counter here is used to determine if we should forward an
 * end-of-stream marker in order to let the lua scripts also have some buffer
 * window. It will trigger the '_input_end" event handler as a flush trigger.
 *
 * The cases where that is interesting and relevant is expensive actions where
 * there is buffer backpressure on something (mouse motion in drag-rz)
 * (buffer-bloat mitigation) and scenarios like:
 *
 *  (local event -> lua event -> displayhint -> [client resizes quickly] ->
 *  resize event -> next local event)
 *
 * to instead allow:
 *
 *  (local event -> lua event -> [accumulator])
 *  (end marker -> lua event end -> apply accumulator)
 */
	if (!ev){
		if (event_count){
			event_count = 0;
			arcan_lua_pushevent(main_lua_context, NULL);
		}

		return true;
	}

	event_count++;
	arcan_lua_pushevent(main_lua_context, ev);
	return true;
}

/*
 * The case for this one is slightly different to process_event (which is used
 * for flushing the master queue).
 *
 * Processing frameservers might cause a queue transfer that might block
 * if the master event queue is saturated above a safety threshold.
 *
 * It is possible to opt-in allow certain frameservers to exceed this
 * threshold, as well as process 'direct to drain' without being multiplexed on
 * the master queue, saving a copy/queue. This breaks ordering guarantees so
 * can only safely be enabled at the preroll synchpoint.
 *
 * This can also be used to force inject events when the video pipeline is
 * blocked due to scanout through arcan_event_denqueue. The main engine itself
 * has no problems with manipulating the video pipeline during scanout, but the
 * driver stack and agp layer (particularly GL) may be of an entirely different
 * opinion.
 *
 * Therefore there is a soft contract:
 *
 * (lua:input_raw) that will only be triggered if an input event sample is
 * received as a drain-enqueue while we are also locked to scanout. If the
 * entry point is implemented, the script 'promises' to not perform actions
 * that would manipulate GPU state (readbacks, rendertarget updates, ...).
 *
 * input_raw can also _defer_ input sample processing:
 *           denqueue:
 *             overflow_drain:
 *               lua:input_raw:
 *                 <- false (nak)
 *             <- false (nak)
 *           attempt normal enqueue <- this is problematic then as that
 *
 *
 */
static bool overflow_drain(arcan_event* ev, int drain)
{
	if (arcan_lua_pushevent(main_lua_context, ev)){
		event_count++;
		return true;
	}

	return false;
}

static int estimate_frame_cost()
{
	return conductor.render_cost + conductor.transfer_cost + conductor.timestep;
}

static bool preframe_synch(int next, int elapsed)
{
	switch(synchopt){
	case SYNCH_ADAPTIVE:{
		ssize_t margin = next - estimate_frame_cost();
		if (elapsed > margin){
			internal_yield();
			return false;
		}

		TRACE_MARK_ONESHOT("conductor", "synchronization",
			TRACE_SYS_DEFAULT, 0, elapsed - margin, "adaptive-deadline");
		return true;
	}
	break;
/* this is more complex, we behave like "ADAPTIVE" until half the deadline has passed,
 * then we release the herd and wait until the last safe moment and go with that */
	case SYNCH_TIGHT:{
		ssize_t deadline = (next >> 1) - estimate_frame_cost();
		ssize_t margin = next - estimate_frame_cost();

		if (elapsed < deadline){
			internal_yield();
			return false;
		}
		else if (elapsed < next - estimate_frame_cost()){
			if (!conductor.in_frame){
				conductor.in_frame = true;
				unlock_herd();
				internal_yield();
				return false;
			}
			internal_yield();
			return false;
		}

		TRACE_MARK_ONESHOT("conductor", "synchronization",
			TRACE_SYS_DEFAULT, 0, elapsed - margin, "tight-deadline");
		return true;
	}
	case SYNCH_VSYNCH:
	case SYNCH_PROCESSING:
	case SYNCH_IMMEDIATE:
	case SYNCH_POWERSAVE:
	break;
	}
	return true;
}

static uint64_t postframe_synch(uint64_t next)
{
	switch(synchopt){
	case SYNCH_VSYNCH:
	case SYNCH_ADAPTIVE:
	case SYNCH_POWERSAVE:
		unlock_herd();
	break;
	case SYNCH_PROCESSING:
	case SYNCH_IMMEDIATE:
	break;
	}

/* this is not the 'correct' time to do this for multiscreen settings, we would
 * need to let the platform expose that event per screen and bias to the one (if
 * any) the frameserver is actually mapped to the vblank on. */
	forward_vblank();

	conductor.in_frame = false;
	return next;
}

/* Reset when starting _run, and set to true after we have managed to pass a
 * full event-context flush and display scanout. This is to catch errors that
 * persist and re-introduce min the main event handler during warmup and make
 * sure we don't get stuck in an endless recover->main->flush->recover loop */
static bool valid_cycle;
bool arcan_conductor_valid_cycle()
{
	return valid_cycle;
}

int arcan_conductor_reset_count(bool step)
{
	if (step)
		reset_counter++;
	return reset_counter;
}

static int trigger_video_synch(float frag)
{
	conductor.set_deadline = -1;

	TRACE_MARK_ENTER("conductor", "platform-frame", TRACE_SYS_DEFAULT, conductor.tick_count, frag, "");
		arcan_lua_callvoidfun(main_lua_context, "preframe_pulse", false, NULL);
			platform_video_synch(conductor.tick_count, frag, NULL, NULL);

			#ifdef WITH_TRACY
			TracyCFrameMark
			#endif
		arcan_lua_callvoidfun(main_lua_context, "postframe_pulse", false, NULL);
	TRACE_MARK_EXIT("conductor", "platform-frame", TRACE_SYS_DEFAULT, conductor.tick_count, frag, "");

	arcan_bench_register_frame();
	arcan_benchdata* stats = arcan_bench_data();

/* exponential moving average */
	conductor.render_cost =
		0.8 * (double)stats->framecost[(uint8_t)stats->costofs] +
		0.2 * conductor.render_cost;

	TRACE_MARK_ONESHOT("conductor", "frame-over", TRACE_SYS_DEFAULT, 0, conductor.set_deadline, "");

	valid_cycle = true;
/* if the platform wants us to wait, it'll provide a new deadline at synch */
	return conductor.set_deadline > 0 ? conductor.set_deadline : 0;
}

static arcan_tick_cb outcb;
static void conductor_cycle();
int arcan_conductor_run(arcan_tick_cb tick)
{
	arcan_evctx* evctx = arcan_event_defaultctx();
	outcb = tick;
	int exit_code = EXIT_FAILURE;
	alloc_frameserver_struct();
	uint64_t last_tickcount;
	uint64_t last_synch = arcan_timemillis();
	uint64_t next_synch = 0;
	int sstate = -1;
	valid_cycle = false;

	arcan_event_setdrain(evctx, overflow_drain);

	for(;;){
/*
 * So this is not good enough to do attribution, and it is likely that the
 * cause of the context reset will simply repeat itself. Possible options for
 * deriving this is to trigger bufferfail for all external frameservers (or
 * pick them at random until figured out the sinner), and have an eval pass for
 * custom shaders (other likely suspect) - and after some 'n fails' trigger the
 * script kind of reset/rebuild.
 */
		if (!agp_status_ok(NULL)){
			TRACE_MARK_ONESHOT("conductor", "platform",
				TRACE_SYS_ERROR, 0, 0, "accelerated graphics failed");
			platform_video_reset(-1, false);
		}

/*
 * specific note here, we'd like to know about frameservers that have resized
 * and then actually dispatch / process these twice so that their old buffers
 * might get to be updated before we synch to display.
 */
		arcan_video_pollfeed();
		arcan_audio_refresh();

/* let the event-layer polling set interleave up to the next deadline. */
#ifdef ARCAN_LWA
		if (conductor.set_deadline > 0){
			int step = conductor.set_deadline - arcan_timemillis();
			if (step > 0)
				arcan_event_poll_sources(evctx, step);
		}
		else
#endif
			arcan_event_poll_sources(evctx, 0);

		last_tickcount = conductor.tick_count;

		TRACE_MARK_ENTER("conductor", "event",
			TRACE_SYS_DEFAULT, 0, last_tickcount, "process");

		float frag = arcan_event_process(evctx, conductor_cycle);
		uint64_t elapsed = arcan_timemillis() - last_synch;

		TRACE_MARK_EXIT("conductor", "event",
			TRACE_SYS_DEFAULT, 0, last_tickcount, "process");

/* This fails when the event recipient has queued a SHUTDOWN event */
		if (!arcan_event_feed(evctx, process_event, &exit_code))
			break;
		process_event(NULL, 0);

/* Chunk the time left until the next batch and yield in small steps. This
 * puts us about 25fps, could probably go a little lower than that, say 12 */
		if (synchopt == SYNCH_POWERSAVE && last_tickcount == conductor.tick_count){
			internal_yield();
			continue;
		}

/* Other processing modes deal with their poll/sleep synch inside video-synch
 * or based on another evaluation function */
		else if (next_synch <= 0 || preframe_synch(next_synch - last_synch, elapsed)){
/* A stall or other action caused us to miss the tight deadline and the herd
 * didn't get unlocked this pass, so perform one now to not block the clients
 * indefinitely */
			if (synchopt == SYNCH_TIGHT && !conductor.in_frame){
				conductor.in_frame = true;
				unlock_herd();
			}

			next_synch = postframe_synch( trigger_video_synch(frag) );
			last_synch = arcan_timemillis();
		}
	}

	outcb = NULL;
	return exit_code;
}

/* We arrive here when the video platform decides that the system should behave
 * like there is a synchronization period to respect, but leaves it up to us
 * to decide how to clock and interleave. Left sets the number of milliseconds
 * that should be 'burnt' for the synch signal to be complete. */
void arcan_conductor_fakesynch(uint8_t left)
{
	int real_left = left;
	int step;
	TRACE_MARK_ENTER("conductor", "synchronization",
		TRACE_SYS_SLOW, 0, left, "fake synch");

/* Some platforms have a high cost for sleep / yield operations and the overhead
 * alone might eat up what is actually left in the timing buffer */
	struct platform_timing timing = platform_hardware_clockcfg();
	size_t sleep_cost = !timing.tickless * (timing.cost_us / 1000);

	while ((step = arcan_conductor_yield(NULL, 0)) != -1 && left > step + sleep_cost){
		arcan_event_poll_sources(arcan_event_defaultctx(), step);
		left -= step;
	}

	TRACE_MARK_EXIT("conductor", "synchronization",
		TRACE_SYS_SLOW, 0, left, "fake synch");
}

void arcan_conductor_deadline(uint8_t deadline)
{
	if (conductor.set_deadline == -1 || deadline < conductor.set_deadline){
		conductor.set_deadline = arcan_timemillis() + deadline;
		TRACE_MARK_ONESHOT("conductor", "synchronization",
			TRACE_SYS_DEFAULT, 0, deadline, "deadline");
	}
}

static void conductor_cycle(int nticks)
{
	conductor.tick_count += nticks;
/* priority is always in maintaining logical clock and event processing */
	unsigned njobs;

	arcan_video_tick(nticks, &njobs);
	arcan_audio_tick(nticks);

/* the lua VM last after a/v pipe is to allow 1- tick schedulers, otherwise
 * you'd get the problem of:
 *
 * function clock_pulse() nudge_image(a, 10, 10, 1); end
 *
 * and tag transforms handlers being one tick off
 */
	if (arcan_watchdog_ping)
		atomic_store(arcan_watchdog_ping, arcan_timemillis());

	arcan_lua_tick(main_lua_context, nticks, conductor.tick_count);
	outcb(nticks);

	while(nticks--)
		arcan_mem_tick();
}
