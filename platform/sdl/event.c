#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

#include <SDL/SDL.h>

#include "../../arcan_math.h"
#include "../../arcan_general.h"
#include "../../arcan_event.h"

static struct {
		unsigned short n_joy;
		struct arcan_stick* joys;
} joydev = {0};

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

/* possibly need different sample methods for different axis.
 * especially as the controls get increasingly "weird" */
struct axis_control;
typedef bool(*sample_cb)(struct axis_control*, int, int*, int, int*);
/* anything needed to rate-limit a specific axis,
 * smoothing buffers, threshold scaling etc. */
struct axis_control {
	enum ARCAN_EVENTFILTER_ANALOG mode;
	void* buffer;
	sample_cb samplefun;
};

const unsigned short arcan_joythresh  = 3200;
static bool default_analogsample(struct axis_control* src, int srcsamples, 
	int* srcbuf, int dstsamples, int* dstbuf)
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

static unsigned long djb_hash(const char* str)
{
	unsigned long hash = 5381;
	int c;

	while ((c = *(str++)))
		hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

	return hash;
}

static void process_hatmotion(arcan_evctx* ctx, unsigned devid, 
	unsigned hatid, unsigned value)
{
	arcan_event newevent = {
		.category = EVENT_IO,
		.kind = EVENT_IO_BUTTON_PRESS,
		.data.io.datatype = EVENT_IDATATYPE_DIGITAL,
		.data.io.devkind = EVENT_IDEVKIND_GAMEDEV,
		.data.io.input.digital.devid = ARCAN_JOYIDBASE + devid,
		.data.io.input.digital.subid = 128 + (hatid * 4)
	};

	static unsigned hattbl[4] = {SDL_HAT_UP, SDL_HAT_DOWN, 
		SDL_HAT_LEFT, SDL_HAT_RIGHT};

	assert(joydev.n_joy > devid);
	assert(joydev.joys[devid].hats > hatid);

/* shouldn't really ever be the same, but not trusting SDL */
	if (joydev.joys[devid].hattbls[ hatid ] != value){
		unsigned oldtbl = joydev.joys[devid].hattbls[hatid];

		for (int i = 0; i < 4; i++){
			if ( (oldtbl & hattbl[i]) != (value & hattbl[i]) ){
				newevent.data.io.input.digital.subid  = ARCAN_HATBTNBASE +
					(hatid * 4) + i;
				newevent.data.io.input.digital.active = 
					(value & hattbl[i]) > 0;
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

void platform_event_process(arcan_evctx* ctx)
{
	SDL_Event event;
/* other fields will be set upon enqueue */
	arcan_event newevent = {.category = EVENT_IO}; 

	while (SDL_PollEvent(&event)) {
		switch (event.type) {
		case SDL_MOUSEBUTTONDOWN:
			newevent.kind = EVENT_IO_BUTTON_PRESS;
			newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newevent.data.io.devkind  = EVENT_IDEVKIND_MOUSE;
			newevent.data.io.input.digital.devid = ARCAN_MOUSEIDBASE +
				event.motion.which; 
			newevent.data.io.input.digital.subid = event.button.button;
			newevent.data.io.input.digital.active = true;
			snprintf(newevent.label, sizeof(newevent.label) - 1, "mouse%i",
				event.motion.which);
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_MOUSEBUTTONUP:
			newevent.kind = EVENT_IO_BUTTON_RELEASE;
			newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newevent.data.io.devkind  = EVENT_IDEVKIND_MOUSE;
			newevent.data.io.input.digital.devid = ARCAN_MOUSEIDBASE + 
				event.motion.which; 
			newevent.data.io.input.digital.subid = event.button.button;
			newevent.data.io.input.digital.active = false;
			snprintf(newevent.label, sizeof(newevent.label) - 1, "mouse%i", 
				event.motion.which);
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_MOUSEMOTION: /* map to axis event */
			newevent.kind = EVENT_IO_AXIS_MOVE;
			newevent.data.io.datatype = EVENT_IDATATYPE_ANALOG;
			newevent.data.io.devkind  = EVENT_IDEVKIND_MOUSE;
			newevent.data.io.input.analog.devid = ARCAN_MOUSEIDBASE 
				+ event.motion.which;
			newevent.data.io.input.analog.nvalues = 2;
			newevent.data.io.input.analog.gotrel = true;
			snprintf(newevent.label, sizeof(newevent.label)-1, "mouse%i",
				event.motion.which);

/* split into two axis events, internal_launch targets might wish
 * to merge again locally however */
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

		case SDL_KEYUP:
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
			newevent.data.io.input.digital.devid = ARCAN_JOYIDBASE +
				event.jbutton.which; /* no multimouse.. */
			newevent.data.io.input.digital.subid = event.jbutton.button;
			newevent.data.io.input.digital.active = true;
			snprintf(newevent.label, sizeof(newevent.label)-1, 
				"joystick%i", event.jbutton.which);
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_JOYBUTTONUP:
			newevent.kind = EVENT_IO_BUTTON_RELEASE;
			newevent.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newevent.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
			newevent.data.io.input.digital.devid = ARCAN_JOYIDBASE +
				event.jbutton.which; /* no multimouse.. */
			newevent.data.io.input.digital.subid = event.jbutton.button;
			newevent.data.io.input.digital.active = false;
			snprintf(newevent.label, sizeof(newevent.label)-1, "joystick%i",
				event.jbutton.which);
			arcan_event_enqueue(ctx, &newevent);
		break;

/* don't got any devices that actually use this to test with,
 * but should really just be translated into analog/digital events */
		case SDL_JOYBALLMOTION:
		break;

		case SDL_JOYHATMOTION:
			process_hatmotion(ctx, event.jhat.which, event.jhat.hat, event.jhat.value);
		break;

/* in theory, it should be fine to just manage window resizes by keeping 
 * track of a scale factor to the grid size (window size) specified 
 * during launch) */
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

void platform_key_repeat(arcan_evctx* ctx, unsigned int rate)
{
		ctx->kbdrepeat = rate;
		if (rate == 0)
			SDL_EnableKeyRepeat(0, SDL_DEFAULT_REPEAT_INTERVAL);
		else
			SDL_EnableKeyRepeat(10, ctx->kbdrepeat);
}

void platform_event_deinit(arcan_evctx* ctx)
{
	if (joydev.joys){
		free(joydev.joys);
		joydev.joys = 0;
	}

	SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
}

void platform_device_lock(int devind, bool state)
{
	SDL_WM_GrabInput( state ? SDL_GRAB_ON : SDL_GRAB_OFF );
}

void platform_event_init(arcan_evctx* ctx)
{
	SDL_EnableUNICODE(1);
	arcan_event_keyrepeat(ctx, ctx->kbdrepeat);

/* OSX hack */
	SDL_ShowCursor(0);
	SDL_ShowCursor(1);
	SDL_ShowCursor(0);

	SDL_Event dummy[1];
	while ( SDL_PeepEvents(dummy, 1, SDL_GETEVENT, 
		SDL_EVENTMASK(SDL_MOUSEMOTION)) );
			
	SDL_Init(SDL_INIT_JOYSTICK);

	SDL_JoystickEventState(SDL_ENABLE);
	joydev.n_joy = SDL_NumJoysticks();

/* 
 * enumerate joysticks, try to connect to those available and 
 * map their respective axises 
 */
	if (joydev.n_joy > 0) {
		joydev.joys = calloc(sizeof(struct arcan_stick), joydev.n_joy);

		for (int i = 0; i < joydev.n_joy; i++) {
			strncpy(joydev.joys[i].label, SDL_JoystickName(i), 255);
			joydev.joys[i].hashid = djb_hash(SDL_JoystickName(i));
			joydev.joys[i].handle = SDL_JoystickOpen(i);
			joydev.joys[i].devnum = i;
			joydev.joys[i].axis = SDL_JoystickNumAxes(joydev.joys[i].handle);
			joydev.joys[i].axis_control = malloc(joydev.joys[i].axis *
				sizeof(struct axis_control));

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
