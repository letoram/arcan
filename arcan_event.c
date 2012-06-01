/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <errno.h>


#include <SDL/SDL.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_event.h"

#define LOCK() if (ctx->local) lock_local(ctx); else lock_shared(ctx); 
#define UNLOCK() if (ctx->local) unlock_local(ctx); else unlock_shared(ctx); 

/* code is quite old and dodgy design at best.
 * The plan was initially to be able to get rid of SDL at some point,
 * and stop the stupid specialization of all these different device types,
 * just a bunch of digital inputs (aka buttons) and analog ones (aka axises)
 * as there's no stable and portable way of distingushing between mouse1..n, keyb1..n, joy1..n ...
 * all in all, this is still a small subsystem and deserves a rewrite .. */

const unsigned short arcan_joythresh  = 3200;
static int64_t arcan_last_frametime = 0;
static int64_t arcan_tickofset = 0;

struct arcan_stick {
	unsigned long hashid;
	unsigned short devnum;
	unsigned short threshold;
	char label[256];
	unsigned short axis;
	unsigned short buttons;
	unsigned short balls;
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

static inline void lock_local(arcan_evctx* ctx)
{
	SDL_LockMutex(ctx->synch.local);
}

static inline void lock_shared(arcan_evctx* ctx)
{
	arcan_sem_timedwait(ctx->synch.shared, -1);
}

static inline void unlock_local(arcan_evctx* ctx)
{
	SDL_UnlockMutex(ctx->synch.local);
}

static inline void unlock_shared(arcan_evctx* ctx)
{
	arcan_sem_post(ctx->synch.shared);
}

/* no exotic protocol atm. as both parent / child are supposed to be 
 * built with the same compiler / alignment / structures so padding is 
 * quicker than the alternative, for more exotic purposes, here would be
 * a good place for protocolbuffers- style IDLs */
ssize_t arcan_event_tobytebuf(char* dst, size_t dstsize, arcan_event* src)
{
	if (NULL != src && dstsize >= sizeof(arcan_event)){
		memcpy(dst, src, sizeof(arcan_event));
		return sizeof(arcan_event);
	}

	return -1;
}

bool arcan_event_frombytebuf(arcan_event* dst, char* src, size_t dstsize)
{
	if (NULL != src &&
		NULL != dst && 
		dstsize >= sizeof(arcan_event)){
		memcpy(dst, src, dstsize);
		return true;
	}

	return false;
}

/* check queue for event, ignores mask */
arcan_event* arcan_event_poll(arcan_evctx* ctx)
{
	arcan_event* rv = NULL;

		if (*ctx->front != *ctx->back){
			LOCK();

			rv = &ctx->eventbuf[ *ctx->front ];
			*ctx->front = (*ctx->front + 1) % ctx->n_eventbuf;
		
			UNLOCK();
		}

	return rv;
}

void arcan_event_maskall(arcan_evctx* ctx){
	LOCK();
		ctx->mask_cat_inp = 0xffffffff;
	UNLOCK();
}

void arcan_event_clearmask(arcan_evctx* ctx){
	LOCK();
		ctx->mask_cat_inp = 0;
	UNLOCK();
}

void arcan_event_setmask(arcan_evctx* ctx, uint32_t mask){
	LOCK();
		ctx->mask_cat_inp = mask;
	UNLOCK();
}

/* enqueue to current context considering input-masking,
 * unless label is set, assign one based on what kind of event it is */
void arcan_event_enqueue(arcan_evctx* ctx, const arcan_event* src)
{
	/* early-out mask-filter */
	if (!src || (src->category & ctx->mask_cat_inp))
		return;

	LOCK();
		unsigned ind = alloc_queuecell(ctx);

		arcan_event* dst = &ctx->eventbuf[ind];
		*dst = *src;
		dst->tickstamp = ctx->c_ticks;

	UNLOCK();
}

void arcan_event_keyrepeat(arcan_evctx* ctx, unsigned int rate)
{
	LOCK();
		ctx->kbdrepeat = rate;
		if (rate == 0) 
			SDL_EnableKeyRepeat(ctx->kbdrepeat, SDL_DEFAULT_REPEAT_INTERVAL);
		else 
			SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_INTERVAL, ctx->kbdrepeat);
	UNLOCK();
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

			/* queue as two separate events, might need internal_launch workaround */
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
				newevent.kind = EVENT_IO_AXIS_MOVE;
				newevent.data.io.datatype = EVENT_IDATATYPE_ANALOG;
				newevent.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
				
			/* need to filter out "noise" */
				if (event.jaxis.value < (-1 * joydev.joys[ event.jaxis.which ].threshold) ||
				        event.jaxis.value > joydev.joys[ event.jaxis.which ].threshold) {
					newevent.data.io.input.analog.gotrel = false;
					newevent.data.io.input.analog.devid = ARCAN_JOYIDBASE + event.jaxis.which;
					newevent.data.io.input.analog.subid = event.jaxis.axis;
					newevent.data.io.input.analog.nvalues = 1;
					newevent.data.io.input.analog.axisval[0] = event.jaxis.value;
					arcan_event_enqueue(ctx, &newevent);
				}
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
				if (event.jhat.value & SDL_HAT_UP) {
					/* Do up stuff here */
				}
				/*              SDL_HAT_CENTERED
				                SDL_HAT_UP
				                SDL_HAT_RIGHT
				                SDL_HAT_DOWN
				                SDL_HAT_LEFT
				                SDL_HAT_RIGHTUP
				                SDL_HAT_RIGHTDOWN
				                SDL_HAT_LEFTUP
				                SDL_HAT_LEFTDOWN */
				break;

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
				 *  currently ignoring these events (and a resizeable window frame isn't 
				 *  yet supported, although the video- code is capable of handling a rebuild/reinit,
				 *  the lua- scripts themselves all depend quite a bit on VRESH/VRESW 
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
	if (!ctx->local){
		return;
	}
	
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
			joydev.joys[i].buttons = SDL_JoystickNumButtons(joydev.joys[i].handle);
			joydev.joys[i].balls = SDL_JoystickNumBalls(joydev.joys[i].handle);
			joydev.joys[i].hats = SDL_JoystickNumHats(joydev.joys[i].handle);
			joydev.joys[i].threshold = arcan_joythresh;
		}
	}
}
