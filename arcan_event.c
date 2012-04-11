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

#define LOCK() ( SDL_LockMutex(current_context.event_sync) )
#define UNLOCK() ( SDL_UnlockMutex(current_context.event_sync) )

/* code is quite old and dodgy design at best.
 * The plan was initially to be able to get rid of SDL at some point,
 * and stop the stupid specialization of all these different device types,
 * just a bunch of digital inputs (aka buttons) and analog ones (aka axises)
 * as there's no stable and portable way of distingushing between mouse1..n, keyb1..n, joy1..n ...
 * all in all, this is still a small subsystem and deserves a rewrite .. */

const unsigned short arcan_joythresh  = 3200;
static int64_t arcan_last_frametime = 0;
static int64_t arcan_tickofset = 0;

struct queue_cell {
	arcan_event elem;
	arcan_event* ep;
	struct queue_cell* next;
	struct queue_cell* previous;
};

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

struct event_context {
	uint32_t seqn;
	uint32_t c_ticks;
	uint32_t c_leaks;
	uint32_t mask_cat_inp;
	uint32_t mask_cat_out;

	unsigned kbdrepeat;
	unsigned short nsticks;
	struct arcan_stick* sticks;

	queue_cell front;
	queue_cell* back;
	queue_cell cell_buffer[ARCAN_EVENT_QUEUE_LIM];
	uint32_t cell_aofs;
	SDL_mutex* event_sync;
};

static struct event_context current_context = {0};

queue_cell* alloc_queuecell()
{
	/* increment scan current context for avail-slot,
	 * if wraparound with no avail slot
	 * remove first from queue and inc. counter,
	 * but that's really a terminal condition for lots of cases */
	
	uint32_t ofs = current_context.cell_aofs;
	while (1) {
		ofs = (ofs + 1) % ARCAN_EVENT_QUEUE_LIM;

		if (current_context.cell_buffer[ofs].ep == NULL) {
			current_context.cell_aofs = (ofs + 1) % ARCAN_EVENT_QUEUE_LIM;
			current_context.cell_buffer[ofs].ep = &current_context.cell_buffer[ofs].elem;
			return &current_context.cell_buffer[ofs];
		}
		else
			if (ofs == current_context.cell_aofs) { /* happens at wraparound = no slots avail, dump first in queue */
				queue_cell* leak = current_context.front.next;
				current_context.front.next = leak->next;
				current_context.back->next = leak;
				current_context.back = leak;
				current_context.c_leaks++;
				leak->next = NULL;
				return leak;
			}
	}
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
arcan_event* arcan_event_poll()
{
	arcan_event* rv = NULL;

	LOCK();

	queue_cell* cell = current_context.front.next;
	/* dequeue */
	if (cell) {
		rv = cell->ep;
		if (cell == current_context.back)
			current_context.back = NULL;

		cell->ep = NULL; /* 'free' */
		cell->previous = NULL; /* detach */
		current_context.front.next = cell->next; /* forward front pointer */
	}

	UNLOCK();

	return rv;
}

void arcan_event_maskall(){
	current_context.mask_cat_inp = 0xffffffff;
}

void arcan_event_clearmask(){
	current_context.mask_cat_inp = 0;
}

void arcan_event_setmask(uint32_t mask){
		current_context.mask_cat_inp = mask;
}


arcan_event* arcan_event_poll_masked(uint32_t mask_cat, uint32_t mask_ev)
{
	arcan_event* rv = NULL;
	/* find matching */

	LOCK();

	queue_cell* cell = &current_context.front;
	while ((cell = cell->next) != NULL) {
		if (cell->ep && (cell->ep->category & mask_cat)
		        && (cell->ep->kind & mask_ev)) {
			/* match, dequeue and pop */
			rv = cell->ep;
			cell->ep = NULL; /* flag as avail */
			cell->previous->next = cell->next;
			break;
		}
	}

	UNLOCK();

	return rv;
}

/* enqueue to current context considering input-masking,
 * unless label is set, assign one based on what kind of event it is */
void arcan_event_enqueue(arcan_event* src)
{
	queue_cell* next;
	src->tickstamp = current_context.c_ticks;
	/* early-out mask-filter */
	if (!src || (src->category & current_context.mask_cat_inp))
		return;

	LOCK();
	next = alloc_queuecell();
	next->elem = *src;
	next->elem.seqn = current_context.seqn++;

	if (current_context.back) {
		current_context.back->next = next;
		current_context.back = next;
	}
	else {
		current_context.front.next = next;
		current_context.back = next;
	}
	UNLOCK();
}

void arcan_event_keyrepeat(unsigned int rate)
{
	current_context.kbdrepeat = rate;
	if (rate == 0) 
		SDL_EnableKeyRepeat(current_context.kbdrepeat, SDL_DEFAULT_REPEAT_INTERVAL);
	else 
		SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_INTERVAL, current_context.kbdrepeat);
}

/* probe devices and generate mapping tables */
void init_sdl_events()
{
	SDL_EnableUNICODE(1);
	arcan_event_keyrepeat(current_context.kbdrepeat);

/* OSX hack */
	SDL_ShowCursor(0);
	SDL_ShowCursor(1);
	SDL_ShowCursor(0);
	
	SDL_Event dummy[1];
/*	SDL_WM_GrabInput( SDL_GRAB_ON ); */
	while ( SDL_PeepEvents(dummy, 1, SDL_GETEVENT, SDL_EVENTMASK(SDL_MOUSEMOTION)) );
	
}

void map_sdl_events()
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
				arcan_event_enqueue(&newevent);
				break;

			case SDL_MOUSEBUTTONUP:
				newevent.kind = EVENT_IO_BUTTON_RELEASE;
				newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newevent.data.io.devkind  = EVENT_IDEVKIND_MOUSE;
				newevent.data.io.input.digital.devid = ARCAN_MOUSEIDBASE + event.motion.which; /* no multimouse.. */
				newevent.data.io.input.digital.subid = event.button.button;
				newevent.data.io.input.digital.active = false;
				snprintf(newevent.label, sizeof(newevent.label) - 1, "mouse%i", event.motion.which);
				arcan_event_enqueue(&newevent);
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
					arcan_event_enqueue(&newevent);
				}
				
				if (event.motion.yrel != 0){
					newevent.data.io.input.analog.subid = 1;
					newevent.data.io.input.analog.axisval[0] = event.motion.y;
					newevent.data.io.input.analog.axisval[1] = event.motion.yrel;
					arcan_event_enqueue(&newevent);
				}
				break;
				
			case SDL_JOYAXISMOTION:
				newevent.kind = EVENT_IO_AXIS_MOVE;
				newevent.data.io.datatype = EVENT_IDATATYPE_ANALOG;
				newevent.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
				
			/* need to filter out "noise" */
				if (event.jaxis.value < (-1 * current_context.sticks[ event.jaxis.which ].threshold) ||
				        event.jaxis.value > current_context.sticks[ event.jaxis.which ].threshold) {
					newevent.data.io.input.analog.gotrel = false;
					newevent.data.io.input.analog.devid = ARCAN_JOYIDBASE + event.jaxis.which;
					newevent.data.io.input.analog.subid = event.jaxis.axis;
					newevent.data.io.input.analog.nvalues = 1;
					newevent.data.io.input.analog.axisval[0] = event.jaxis.value;
					arcan_event_enqueue(&newevent);
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
				arcan_event_enqueue(&newevent);
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
				arcan_event_enqueue(&newevent);
				break;

			case SDL_JOYBUTTONDOWN:
				newevent.kind = EVENT_IO_BUTTON_PRESS;
				newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newevent.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
				newevent.data.io.input.digital.devid = ARCAN_JOYIDBASE + event.jbutton.which; /* no multimouse.. */
				newevent.data.io.input.digital.subid = event.jbutton.button;
				newevent.data.io.input.digital.active = true;
				snprintf(newevent.label, sizeof(newevent.label)-1, "joystick%i", event.jbutton.which);
				arcan_event_enqueue(&newevent);
				break;

			case SDL_JOYBUTTONUP:
				newevent.kind = EVENT_IO_BUTTON_RELEASE;
				newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newevent.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
				newevent.data.io.input.digital.devid = ARCAN_JOYIDBASE + event.jbutton.which; /* no multimouse.. */
				newevent.data.io.input.digital.subid = event.jbutton.button;
				newevent.data.io.input.digital.active = false;
				snprintf(newevent.label, sizeof(newevent.label)-1, "joystick%i", event.jbutton.which);
				arcan_event_enqueue(&newevent);
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
				arcan_event_enqueue(&newevent);
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
float arcan_process(unsigned* dtick)
{
	arcan_last_frametime = SDL_GetTicks();
	unsigned delta  = arcan_last_frametime - current_context.c_ticks;
	unsigned nticks = delta / ARCAN_TIMER_TICK;
	float fragment = ((float)(delta % ARCAN_TIMER_TICK) + 0.0001) / (float) ARCAN_TIMER_TICK; 
	
	int rv = 0;
	
	/* the logic- clock is necessary, if we got the cycles to spare,
	 * process audio / video / io. */
	if (nticks){
		arcan_event newevent = {.category = EVENT_TIMER, .kind = 0, .data.timer.pulse_count = nticks};
		current_context.c_ticks += nticks * ARCAN_TIMER_TICK;
		arcan_event_enqueue(&newevent);
	}
	
	*dtick = nticks;
	map_sdl_events();
	return fragment;
}

void arcan_event_dumpqueue()
{
	queue_cell* current = &current_context.front;

	LOCK();
	while ((current = current->next) != NULL) {
		printf("cat: %i kind: %i seq: %i tick#: %i\n", current->elem.category, current->elem.kind, current->elem.seqn, current->elem.tickstamp);
	}
	UNLOCK();
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

void arcan_event_deinit()
{
	if (current_context.sticks){
		free(current_context.sticks);
		current_context.sticks = 0;
	}

	SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
}

void arcan_event_init()
{
	init_sdl_events();
    
	current_context.event_sync = SDL_CreateMutex();
 	arcan_tickofset = SDL_GetTicks();
    
	SDL_Init(SDL_INIT_JOYSTICK);
	/* enumerate joysticks, try to connect to those available and map their respective axises */
	SDL_JoystickEventState(SDL_ENABLE);
	current_context.nsticks = SDL_NumJoysticks();

	if (current_context.nsticks > 0) {
		current_context.sticks = (struct arcan_stick*) calloc(sizeof(struct arcan_stick), current_context.nsticks);
		for (int i = 0; i < current_context.nsticks; i++) {
			strncpy(current_context.sticks[i].label, SDL_JoystickName(i), 255);
			current_context.sticks[i].hashid = djb_hash(SDL_JoystickName(i));
			current_context.sticks[i].handle = SDL_JoystickOpen(i);
			current_context.sticks[i].devnum = i;
			current_context.sticks[i].axis = SDL_JoystickNumAxes(current_context.sticks[i].handle);
			current_context.sticks[i].buttons = SDL_JoystickNumButtons(current_context.sticks[i].handle);
			current_context.sticks[i].balls = SDL_JoystickNumBalls(current_context.sticks[i].handle);
			current_context.sticks[i].hats = SDL_JoystickNumHats(current_context.sticks[i].handle);
			current_context.sticks[i].threshold = arcan_joythresh;
		}
	}
}
