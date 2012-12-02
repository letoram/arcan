/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
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

#include <SDL/SDL.h>
#include <apr_poll.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_frameserver_backend.h"

/* code is quite old and dodgy design at best.
 * The plan was initially to be able to get rid of SDL at some point,
 * and stop the stupid specialization of all these different device types,
 * just a bunch of digital inputs (aka buttons) and analog ones (aka axises)
 * as there's no stable and portable way of distingushing between mouse1..n, keyb1..n, joy1..n ...
 * all in all, this is still a small subsystem and deserves a rewrite .. */

const unsigned short arcan_joythresh  = 3200;
static int64_t arcan_last_frametime = 0;
static int64_t arcan_tickofset = 0;

/* possibly need different sample methods for different axis. especially as
 * the controls get increasingly "weird" */
struct axis_control;
typedef bool(*sample_cb)(struct axis_control*, int, int*, int, int*);
/* anything needed to rate-limit a specific axis,
 * smoothing buffers, threshold scaling etc. */
struct axis_control {
	enum ARCAN_EVENTFILTER_ANALOG mode;
	void* buffer;
	sample_cb samplefun;
};

struct arcan_stick {
	char label[256];
	unsigned long hashid;

	unsigned short devnum;
	unsigned short threshold;
	unsigned short axis;
	struct axis_control* axis_control;

/* these map to digital events */
	unsigned short buttons;
	unsigned short balls;

	unsigned* hattbls;
	unsigned short hats;

	SDL_Joystick* handle;
};

typedef struct queue_cell queue_cell;

static struct {
		unsigned short n_joy;
		struct arcan_stick* joys;
} joydev = {0};

static arcan_event eventbuf[ARCAN_EVENT_QUEUE_LIM];
static unsigned eventfront = 0, eventback = 0;

static struct arcan_evctx default_evctx = {
	.eventbuf = eventbuf,
	.n_eventbuf = ARCAN_EVENT_QUEUE_LIM,
	.front = &eventfront,
	.back  = &eventback,
	.local = true
};

arcan_evctx* arcan_event_defaultctx(){
	return &default_evctx;
}

static unsigned alloc_queuecell(arcan_evctx* ctx)
{
	unsigned rv = *(ctx->back);
	*(ctx->back) = ( *(ctx->back) + 1) % ctx->n_eventbuf;

	return rv;
}

static inline bool lock_local(arcan_evctx* ctx)
{
	SDL_LockMutex(ctx->synch.local);
	return true;
}

static inline bool lock_shared(arcan_evctx* ctx)
{
	if (ctx->synch.external.killswitch){
		if (-1 == arcan_sem_timedwait(ctx->synch.external.shared, DEFAULT_EVENT_TIMEOUT)){
			arcan_frameserver_free( (arcan_frameserver*) ctx->synch.external.killswitch, false );
			return false;
		}
	}
	else
		arcan_sem_timedwait(ctx->synch.external.shared, -1);
	return true;
}

static inline bool unlock_local(arcan_evctx* ctx)
{
	SDL_UnlockMutex(ctx->synch.local);
	return true;
}

static inline bool unlock_shared(arcan_evctx* ctx)
{
	arcan_sem_post(ctx->synch.external.shared);
	return true;
}

static inline bool LOCK(arcan_evctx* ctx)
{
	return ctx->local ? lock_local : lock_shared;
}

#define UNLOCK() if (ctx->local) unlock_local(ctx); else unlock_shared(ctx);

/* check queue for event, ignores mask */
arcan_event* arcan_event_poll(arcan_evctx* ctx)
{
	arcan_event* rv = NULL;

		if (*ctx->front != *ctx->back && LOCK(ctx)){

			rv = &ctx->eventbuf[ *ctx->front ];
			*ctx->front = (*ctx->front + 1) % ctx->n_eventbuf;

			UNLOCK();
		}

	return rv;
}

void arcan_event_maskall(arcan_evctx* ctx){
	if ( LOCK(ctx) ){
		ctx->mask_cat_inp = 0xffffffff;
		UNLOCK();
	}
}

void arcan_event_clearmask(arcan_evctx* ctx){
	if ( LOCK(ctx) ){
		ctx->mask_cat_inp = 0;
	UNLOCK();
	}
}

void arcan_event_setmask(arcan_evctx* ctx, uint32_t mask){
	if (LOCK(ctx)){
		ctx->mask_cat_inp = mask;
		UNLOCK();
	}
}

/* drop the specified index and compact everything to the right of it,
 * assumes the context is already locked, so for large event queues etc. this is subpar */
static void drop_event(arcan_evctx* ctx, unsigned index)
{
	unsigned current  = (index + 1) % ctx->n_eventbuf;
	unsigned previous = index;

/* compact left until we reach the end, back is actually one after the last cell in use */
	while (current != *(ctx->back)){
		memcpy( &ctx->eventbuf[ previous ], &ctx->eventbuf[ current ], sizeof(arcan_event) );
		previous = current;
		current  = (index + 1) % ctx->n_eventbuf;
	}

	*(ctx->back) = previous;
}

/* this implementation is pretty naive and expensive on a large/filled queue,
 * partly because this feature was added as an afterthought and the underlying datastructure
 * isn't optimal for the use, should have been linked or double-linked */
void arcan_event_erase_vobj(arcan_evctx* ctx, enum ARCAN_EVENT_CATEGORY category, arcan_vobj_id source)
{
	unsigned elem = *(ctx->front);

/* ignore unsupported categories */
	if ( !(category == EVENT_VIDEO || category == EVENT_FRAMESERVER) )
		return;

	if (LOCK(ctx)){

		while(elem != *(ctx->back)){
			bool match = false;

			switch (ctx->eventbuf[elem].category){
				case EVENT_VIDEO:       match = source == ctx->eventbuf[elem].data.video.source; break;
				case EVENT_FRAMESERVER: match = source == ctx->eventbuf[elem].data.frameserver.video; break;
			}

/* slide only if the cell shouldn't be deleted, otherwise it'll be replaced with the next one in line */
			if (match){
				drop_event(ctx, elem);
			}
			else
				elem = (elem + 1) % ctx->n_eventbuf;
		}

		UNLOCK();
	}
}

/* enqueue to current context considering input-masking,
 * unless label is set, assign one based on what kind of event it is */
void arcan_event_enqueue(arcan_evctx* ctx, const arcan_event* src)
{
/* early-out mask-filter */
	if (!src || (src->category & ctx->mask_cat_inp)){
		return;
	}
		
	if (LOCK(ctx)){
		unsigned ind = alloc_queuecell(ctx);
		arcan_event* dst = &ctx->eventbuf[ind];
		*dst = *src;
		dst->tickstamp = ctx->c_ticks;

		UNLOCK();
	}
}

static inline int queue_used(arcan_evctx* dq)
{
	int rv = *(dq->front) > *(dq->back) ? dq->n_eventbuf - *(dq->front) + *(dq->back) : *(dq->back) - *(dq->front);
	return rv;
}

void arcan_event_queuetransfer(arcan_evctx* dstqueue, arcan_evctx* srcqueue, enum ARCAN_EVENT_CATEGORY allowed, float saturation, arcan_vobj_id source)
{
	saturation = (saturation > 1.0 ? 1.0 : saturation < 0.5 ? 0.5 : saturation);

/* limited so a single frameserver can't storm the parent with events, DOSing others */
	while( *srcqueue->front != *srcqueue->back &&
		floor((float)dstqueue->n_eventbuf * saturation) > queue_used(dstqueue) ){
		arcan_event* ev = arcan_event_poll(srcqueue);

		if (ev && (ev->category & allowed) > 0 ){
			if (ev->category == EVENT_EXTERNAL)
				ev->data.external.source = source;

			else if (ev->category == EVENT_NET)
				ev->data.network.source = source;
			arcan_event_enqueue(dstqueue, ev);
		}
	}

}

void arcan_event_keyrepeat(arcan_evctx* ctx, unsigned int rate)
{
	if (LOCK(ctx)){
		ctx->kbdrepeat = rate;
		if (rate == 0)
			SDL_EnableKeyRepeat(0, SDL_DEFAULT_REPEAT_INTERVAL);
		else
			SDL_EnableKeyRepeat(10, ctx->kbdrepeat);
		UNLOCK();
	}
}

static void process_hatmotion(arcan_evctx* ctx, unsigned devid, unsigned hatid, unsigned value)
{
	arcan_event newevent = {
		.category = EVENT_IO,
		.kind = EVENT_IO_BUTTON_PRESS,
		.data.io.datatype = EVENT_IDATATYPE_DIGITAL,
		.data.io.devkind = EVENT_IDEVKIND_GAMEDEV,
		.data.io.input.digital.devid = ARCAN_JOYIDBASE + devid,
		.data.io.input.digital.subid = 128 + (hatid * 4)
	};

	static unsigned hattbl[4] = {SDL_HAT_UP, SDL_HAT_DOWN, SDL_HAT_LEFT, SDL_HAT_RIGHT};

	assert(joydev.n_joy > devid);
	assert(joydev.joys[devid].hats > hatid);

/* shouldn't really ever be the same, but not trusting SDL */
	if (joydev.joys[devid].hattbls[ hatid ] != value){
		unsigned oldtbl = joydev.joys[devid].hattbls[hatid];

		for (int i = 0; i < 4; i++){
			if ( (oldtbl & hattbl[i]) != (value & hattbl[i]) ){
				newevent.data.io.input.digital.subid  = ARCAN_HATBTNBASE + (hatid * 4) + i;
				newevent.data.io.input.digital.active = (value & hattbl[i]) > 0;
				arcan_event_enqueue(ctx, &newevent);
			}
		}

		joydev.joys[devid].hattbls[hatid] = value;
	}
}

static void process_axismotion(arcan_evctx* ctx, SDL_JoyAxisEvent ev)
{
	arcan_event newevent = {
		.kind = EVENT_IO_AXIS_MOVE,
		.category = EVENT_IO,
		.data.io.datatype = EVENT_IDATATYPE_ANALOG,
		.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV,
		.data.io.input.analog.gotrel = false,
		.data.io.input.analog.devid = ARCAN_JOYIDBASE + ev.which,
		.data.io.input.analog.subid = ev.axis,
		.data.io.input.analog.nvalues = 1
	};

	int ins = ev.value, outs;
	struct axis_control* ctrl =	&joydev.joys[ ev.which ].axis_control[ ev.which ];
	if ( ctrl->samplefun(ctrl, 1, &ins, 1, &outs) ){
		newevent.data.io.input.analog.axisval[0] = outs;
		newevent.data.io.input.analog.axisval[1] = 0;
		newevent.data.io.input.analog.axisval[2] = 0;
		newevent.data.io.input.analog.axisval[3] = 0;
		arcan_event_enqueue(ctx, &newevent);
	}
}
/* probe devices and generate mapping tables */
static void init_sdl_events(arcan_evctx* ctx)
{
	SDL_EnableUNICODE(1);
	arcan_event_keyrepeat(ctx, ctx->kbdrepeat);

/* OSX hack */
	SDL_ShowCursor(0);
	SDL_ShowCursor(1);
	SDL_ShowCursor(0);

	SDL_Event dummy[1];
/*	SDL_WM_GrabInput( SDL_GRAB_ON ); */
	while ( SDL_PeepEvents(dummy, 1, SDL_GETEVENT, SDL_EVENTMASK(SDL_MOUSEMOTION)) );
}

void map_sdl_events(arcan_evctx* ctx)
{
	SDL_Event event;
	arcan_event newevent = {.category = EVENT_IO}; /* others will be set upon enqueue */

	while (SDL_PollEvent(&event)) {
		switch (event.type) {
			case SDL_MOUSEBUTTONDOWN:
				newevent.kind = EVENT_IO_BUTTON_PRESS;
				newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newevent.data.io.devkind  = EVENT_IDEVKIND_MOUSE;
				newevent.data.io.input.digital.devid = ARCAN_MOUSEIDBASE + event.motion.which; /* no multimouse.. */
				newevent.data.io.input.digital.subid = event.button.button;
				newevent.data.io.input.digital.active = true;
				snprintf(newevent.label, sizeof(newevent.label) - 1, "mouse%i", event.motion.which);
				arcan_event_enqueue(ctx, &newevent);
				break;

			case SDL_MOUSEBUTTONUP:
				newevent.kind = EVENT_IO_BUTTON_RELEASE;
				newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newevent.data.io.devkind  = EVENT_IDEVKIND_MOUSE;
				newevent.data.io.input.digital.devid = ARCAN_MOUSEIDBASE + event.motion.which; /* no multimouse.. */
				newevent.data.io.input.digital.subid = event.button.button;
				newevent.data.io.input.digital.active = false;
				snprintf(newevent.label, sizeof(newevent.label) - 1, "mouse%i", event.motion.which);
				arcan_event_enqueue(ctx, &newevent);
				break;

			case SDL_MOUSEMOTION: /* map to axis event */
				newevent.kind = EVENT_IO_AXIS_MOVE;
				newevent.data.io.datatype = EVENT_IDATATYPE_ANALOG;
				newevent.data.io.devkind  = EVENT_IDEVKIND_MOUSE;
				newevent.data.io.input.analog.devid = ARCAN_MOUSEIDBASE + event.motion.which;
				newevent.data.io.input.analog.nvalues = 2;
				newevent.data.io.input.analog.gotrel = true;
				snprintf(newevent.label, sizeof(newevent.label)-1, "mouse%i", event.motion.which);

/* split into two axis events, internal_launch targets might wish to merge again locally however */
				if (event.motion.xrel != 0){
					newevent.data.io.input.analog.subid = 0;
					newevent.data.io.input.analog.axisval[0] = event.motion.x;
					newevent.data.io.input.analog.axisval[1] = event.motion.xrel;
					arcan_event_enqueue(ctx, &newevent);
				}

				if (event.motion.yrel != 0){
					newevent.data.io.input.analog.subid = 1;
					newevent.data.io.input.analog.axisval[0] = event.motion.y;
					newevent.data.io.input.analog.axisval[1] = event.motion.yrel;
					arcan_event_enqueue(ctx, &newevent);
				}
				break;

			case SDL_JOYAXISMOTION:
				process_axismotion(ctx, event.jaxis);
			break;

			case SDL_KEYDOWN:
				newevent.kind  = EVENT_IO_KEYB_PRESS;
				newevent.data.io.datatype = EVENT_IDATATYPE_TRANSLATED;
				newevent.data.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
				newevent.data.io.input.translated.devid = event.key.which;
				newevent.data.io.input.translated.keysym = event.key.keysym.sym;
				newevent.data.io.input.translated.modifiers = event.key.keysym.mod;
				newevent.data.io.input.translated.scancode = event.key.keysym.scancode;
				newevent.data.io.input.translated.subid = event.key.keysym.unicode;
				arcan_event_enqueue(ctx, &newevent);
				break;

			case SDL_KEYUP: /* should check timer for keypress ... */
				newevent.kind  = EVENT_IO_KEYB_RELEASE;
				newevent.data.io.datatype = EVENT_IDATATYPE_TRANSLATED;
				newevent.data.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
				newevent.data.io.input.translated.devid = event.key.which;
				newevent.data.io.input.translated.keysym = event.key.keysym.sym;
				newevent.data.io.input.translated.modifiers = event.key.keysym.mod;
				newevent.data.io.input.translated.scancode = event.key.keysym.scancode;
				newevent.data.io.input.translated.subid = event.key.keysym.unicode;
				arcan_event_enqueue(ctx, &newevent);
				break;

			case SDL_JOYBUTTONDOWN:
				newevent.kind = EVENT_IO_BUTTON_PRESS;
				newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newevent.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
				newevent.data.io.input.digital.devid = ARCAN_JOYIDBASE + event.jbutton.which; /* no multimouse.. */
				newevent.data.io.input.digital.subid = event.jbutton.button;
				newevent.data.io.input.digital.active = true;
				snprintf(newevent.label, sizeof(newevent.label)-1, "joystick%i", event.jbutton.which);
				arcan_event_enqueue(ctx, &newevent);
				break;

			case SDL_JOYBUTTONUP:
				newevent.kind = EVENT_IO_BUTTON_RELEASE;
				newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newevent.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
				newevent.data.io.input.digital.devid = ARCAN_JOYIDBASE + event.jbutton.which; /* no multimouse.. */
				newevent.data.io.input.digital.subid = event.jbutton.button;
				newevent.data.io.input.digital.active = false;
				snprintf(newevent.label, sizeof(newevent.label)-1, "joystick%i", event.jbutton.which);
				arcan_event_enqueue(ctx, &newevent);
				break;

/* don't got any devices that actually use this to test with,
 * but should really just be translated into analog/digital events */
			case SDL_JOYBALLMOTION:
				break;

			case SDL_JOYHATMOTION:
				process_hatmotion(ctx, event.jhat.which, event.jhat.hat, event.jhat.value);
			break;

/* in theory, it should be fine to just manage window resizes by keeping track of a scale factor to the
 * grid size (window size) specified during launch) */
			case SDL_ACTIVEEVENT:
				//newevent.kind = (MOUSEFOCUS, INPUTFOCUS, APPACTIVE(0 = icon, 1 = restored)
				//if (event->active.state & SDL_APPINPUTFOCUS){
				//	SDL_SetModState(KMOD_NONE);
				break;

			case SDL_QUIT:
				newevent.category = EVENT_SYSTEM;
				newevent.kind = EVENT_SYSTEM_EXIT;
				arcan_event_enqueue(ctx, &newevent);
				break;

			case SDL_SYSWMEVENT:
				break;
				/*
				 * currently ignoring these events (and a resizeable window frame isn't
				 * yet supported, although the video- code is capable of handling a rebuild/reinit,
				 * the lua- scripts themselves all depend quite a bit on VRESH/VRESW, one option
				 * would be to just calculate a scale factor for the newvresh, newvresw and apply that
				 * as a translation step when passing the lua<->core border
					 case SDL_VIDEORESIZE:
					 break;

					 case SDL_VIDEOEXPOSE:
					 break;

					 case SDL_ACTIVEEVENT:
					 break;

					 case SDL_ */
		}
	}
}

/* this dynamically buffers STDIN until statement termination ';' or newline.
 * this doesn't "really" match the lua syntax particularly well, and in lieu of a full
 * parser, this leads to the problem of (shell->partial_statement->event trigger(system_load()))->
 * parsing errors. Should be known when using the interactive mode (so dev purposes) */
char* nblk_readln(int fd)
{
	arcan_warning("(fixme) interactive mode not completed.\n");
	return NULL;
}

int64_t arcan_frametime()
{
	return arcan_last_frametime - arcan_tickofset;
}

/* the main usage case is simply to alternate
 * between process and poll after a scene has
 * been setup, kindof */
float arcan_event_process(arcan_evctx* ctx, unsigned* dtick)
{
	arcan_last_frametime = SDL_GetTicks();
	unsigned delta  = arcan_last_frametime - ctx->c_ticks;
	unsigned nticks = delta / ARCAN_TIMER_TICK;
	float fragment = ((float)(delta % ARCAN_TIMER_TICK) + 0.0001) / (float) ARCAN_TIMER_TICK;

	int rv = 0;

	/* the logic- clock is necessary, if we got the cycles to spare,
	 * process audio / video / io. */
	if (nticks){
		arcan_event newevent = {.category = EVENT_TIMER, .kind = 0, .data.timer.pulse_count = nticks};
		ctx->c_ticks += nticks * ARCAN_TIMER_TICK;
		arcan_event_enqueue(ctx, &newevent);
	}

	*dtick = nticks;
	map_sdl_events(ctx);

/* also assumes that fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK); is set on stdin and that complete LUA statements are parsed,
 * these would have to have its own parsing context or something to that effect so that the statements we get are fully terminated,
 * else we risk interleaving .. */
	if (ctx->interactive){
		char* resv = nblk_readln(STDIN_FILENO);
		if (resv){
			arcan_event sevent = {.category = EVENT_SYSTEM, .kind = EVENT_SYSTEM_EVALCMD, .data.system.data.mesg.dyneval_msg = resv};
			arcan_event_enqueue(ctx, &sevent);
/* FIXME: incomplete due to the reason stated above */
		}
	}

	return fragment;
}

/* afaik, this function has been placed in the public domain by daniel bernstein */
static unsigned long djb_hash(const char* str)
{
	unsigned long hash = 5381;
	int c;

	while ((c = *(str++)))
		hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

	return hash;
}

static bool default_analogsample(struct axis_control* src, int srcsamples, int* srcbuf, int dstsamples, int* dstbuf)
{
	if (src->mode == EVENT_FILTER_ANALOG_ALL)
		return false;

/* first call, initialize cb- specific storage (not needed here) */
	if (src->buffer == NULL){
	}
	if (srcsamples > 0 && dstsamples > 0){
		if (srcbuf[0] > -32768 &&
			((srcbuf[0] < -arcan_joythresh || srcbuf[0] > arcan_joythresh))){
			dstbuf[0] = srcbuf[0];
			return true;
		}
	}

	return false;
}

void arcan_event_deinit(arcan_evctx* ctx)
{
	if (joydev.joys){
		free(joydev.joys);
		joydev.joys = 0;
	}

	SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
}

void arcan_event_init(arcan_evctx* ctx)
{
/* non-local (i.e. shmpage resident) event queues has a different init approach (see frameserver_shmpage.c) */
	if (!ctx->local){
		return;
	}

/* SIGUSR1 is only used to signal compliant frameservers, starts masked and is inherited that way. */
	struct sigaction sa;
	sa.sa_flags   = 0;
	sa.sa_handler = SIG_IGN;
	sigaction(SIGUSR1, &sa, NULL);
	
	init_sdl_events(ctx);

	ctx->synch.local = SDL_CreateMutex();
 	arcan_tickofset = SDL_GetTicks();

	SDL_Init(SDL_INIT_JOYSTICK);
	/* enumerate joysticks, try to connect to those available and map their respective axises */
	SDL_JoystickEventState(SDL_ENABLE);
	joydev.n_joy = SDL_NumJoysticks();

	if (joydev.n_joy > 0) {
		joydev.joys = (struct arcan_stick*) calloc(sizeof(struct arcan_stick), joydev.n_joy);
		for (int i = 0; i < joydev.n_joy; i++) {
			strncpy(joydev.joys[i].label, SDL_JoystickName(i), 255);
			joydev.joys[i].hashid = djb_hash(SDL_JoystickName(i));
			joydev.joys[i].handle = SDL_JoystickOpen(i);
			joydev.joys[i].devnum = i;
			joydev.joys[i].axis = SDL_JoystickNumAxes(joydev.joys[i].handle);
			joydev.joys[i].axis_control = malloc(joydev.joys[i].axis * sizeof(struct axis_control));

			for (int j = 0; j < joydev.joys[i].axis; j++){
					struct axis_control defctrl = {
						.buffer = NULL,
						.mode = EVENT_FILTER_ANALOG_NONE,
						.samplefun = default_analogsample
					};

					joydev.joys[i].axis_control[j] = defctrl;
			}

			joydev.joys[i].buttons = SDL_JoystickNumButtons(joydev.joys[i].handle);
			joydev.joys[i].balls = SDL_JoystickNumBalls(joydev.joys[i].handle);
			joydev.joys[i].hats = SDL_JoystickNumHats(joydev.joys[i].handle);

			if (joydev.joys[i].hats > 0){
				size_t dst_sz = joydev.joys[i].hats * sizeof(unsigned);

				joydev.joys[i].hattbls = malloc(dst_sz);
				memset(joydev.joys[i].hattbls, 0, dst_sz);
			}
		}
	}
}
