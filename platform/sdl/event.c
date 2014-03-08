/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

#include <SDL/SDL.h>

#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_event.h>

struct axis_opts {
/* none, avg, drop */ 
	enum ARCAN_ANALOGFILTER_KIND mode;
	enum ARCAN_ANALOGFILTER_KIND oldmode;

	int lower, upper, deadzone;

/* we won't get access to a good range distribution
 * if we don't emit the first / last sample that got
 * into the drop range */
	bool inlzone, inuzone, indzone;

	int kernel_sz;
	int kernel_ofs;
	int32_t flt_kernel[64];
};

static struct {
		struct axis_opts mx, my, 
			mx_r, my_r;
	
		bool sticks_init;
		unsigned short n_joy;
		struct arcan_stick* joys;
} iodev = {0};

struct arcan_stick {
/* if we can get a repeatable identifier to expose
 * to higher layers in order to retain / track settings
 * for a certain device, put that here */
	char label[256];

	SDL_Joystick* handle;

	unsigned long hashid;

	unsigned short devnum;
	unsigned short axis;

/* these map to digital events */
	unsigned short buttons;
	unsigned short balls;

	unsigned* hattbls;
	unsigned short hats;

	struct axis_opts* adata;
};

static inline bool process_axis(arcan_evctx* ctx, 
	struct axis_opts* daxis, int16_t samplev, int16_t* outv)
{
	if (daxis->mode == ARCAN_ANALOGFILTER_NONE)
		return false;
	
	if (daxis->mode == ARCAN_ANALOGFILTER_PASS)
		goto accept_sample;

/* quickfilter deadzone */
	if (abs(samplev) < daxis->deadzone){
		if (!daxis->indzone){
			samplev = 0; 
			daxis->indzone = true;
		}
		else 
			return false;
	}
	else
		daxis->indzone = false;

/* quickfilter out controller edgenoise */
	if (samplev < daxis->lower){
		if (!daxis->inlzone){
			samplev = daxis->lower;
			daxis->inlzone = true;
			daxis->inuzone = false;
		}	
		else
			return false;
	}
	else if (samplev > daxis->upper){
		if (!daxis->inuzone){
			samplev = daxis->upper;
			daxis->inuzone = true;
			daxis->inlzone = false;
		}
		else
			return false;
	}
	else
		daxis->inlzone = daxis->inuzone = false;

	daxis->flt_kernel[ daxis->kernel_ofs++ ] = samplev;

/* don't proceed until the kernel is filled */ 
	if (daxis->kernel_ofs < daxis->kernel_sz)
		return false;

	if (daxis->kernel_sz > 1){
		int32_t tot = 0;

		if (daxis->mode == ARCAN_ANALOGFILTER_ALAST){
			samplev = daxis->flt_kernel[daxis->kernel_sz - 1];
		} 
		else {
			for (int i = 0; i < daxis->kernel_sz; i++)
				tot += daxis->flt_kernel[i];

			samplev = tot != 0 ? tot / daxis->kernel_sz : 0; 
		}

	} 
	else;
	daxis->kernel_ofs = 0;

accept_sample:
	*outv = samplev;
	return true;
}

static inline void process_axismotion(arcan_evctx* ctx,
	const SDL_JoyAxisEvent* const ev)
{
	int devid = ev->which;

	if (iodev.joys[devid].axis < ev->axis)
		return;
	
	struct axis_opts* daxis = &iodev.joys[devid].adata[ev->axis];
	int16_t dstv;
	
	if (process_axis(ctx, daxis, ev->value, &dstv)){
		arcan_event newevent = {
			.kind = EVENT_IO_AXIS_MOVE,
			.category = EVENT_IO,
			.data.io.datatype = EVENT_IDATATYPE_ANALOG,
			.data.io.devkind  = EVENT_IDEVKIND_GAMEDEV,
			.data.io.input.analog.gotrel = false,
			.data.io.input.analog.devid = ARCAN_JOYIDBASE + ev->which,
			.data.io.input.analog.subid = ev->axis,
			.data.io.input.analog.nvalues = 1,
			.data.io.input.analog.axisval[0] = dstv
		};
		arcan_event_enqueue(ctx, &newevent);
	}
}

static inline void process_mousemotion(arcan_evctx* ctx, 
	const SDL_MouseMotionEvent* const ev)
{
	int16_t dstv, dstv_r;
	arcan_event nev = {
		.label = "MOUSE\0",
		.category = EVENT_IO,
		.kind = EVENT_IO_AXIS_MOVE,
		.data.io.datatype = EVENT_IDATATYPE_ANALOG,
		.data.io.devkind  = EVENT_IDEVKIND_MOUSE,
		.data.io.input.analog.devid  = ARCAN_MOUSEIDBASE,
		.data.io.input.analog.gotrel = true,
		.data.io.input.analog.nvalues = 2
	}; 

	snprintf(nev.label, 
		sizeof(nev.label) - 1, "mouse");

	if (process_axis(ctx, &iodev.mx, ev->x, &dstv) &&
		process_axis(ctx, &iodev.mx_r, ev->xrel, &dstv_r)){
		nev.data.io.input.analog.subid = 0;
		nev.data.io.input.analog.axisval[0] = dstv;
		nev.data.io.input.analog.axisval[1] = dstv_r;
		arcan_event_enqueue(ctx, &nev);	
	}

	if (process_axis(ctx, &iodev.my, ev->y, &dstv) &&
		process_axis(ctx, &iodev.my_r, ev->yrel, &dstv_r)){
		nev.data.io.input.analog.subid = 1;
		nev.data.io.input.analog.axisval[0] = dstv;
		nev.data.io.input.analog.axisval[1] = dstv_r;
		arcan_event_enqueue(ctx, &nev);	
	}
}

static void set_analogstate(struct axis_opts* dst,
	int lower_bound, int upper_bound, int deadzone,
	int kernel_size, enum ARCAN_ANALOGFILTER_KIND mode)
{	
	dst->lower = lower_bound;
	dst->upper = upper_bound;
	dst->deadzone = deadzone;
	dst->kernel_sz = kernel_size;
	dst->mode = mode;
	dst->kernel_ofs = 0;
}	

arcan_errc arcan_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
/* special case, mouse */
	if (devid == -1){
		if (axisid == 0){
			*lower_bound = iodev.mx.lower;
			*upper_bound = iodev.mx.upper;
			*deadzone    = iodev.mx.deadzone;
			*kernel_size = iodev.mx.kernel_sz;
			*mode        = iodev.mx.mode;
		}
		else if (axisid == 1){
			*lower_bound = iodev.my.lower;
			*upper_bound = iodev.my.upper;
			*deadzone    = iodev.my.deadzone;
			*kernel_size = iodev.my.kernel_sz;
			*mode        = iodev.my.mode;
		}
		else
			return ARCAN_ERRC_BAD_RESOURCE;

		return true;
	}

	devid -= ARCAN_JOYIDBASE;
	if (devid < 0 || devid >= iodev.n_joy)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (axisid >= iodev.joys[devid].axis)
		return ARCAN_ERRC_BAD_RESOURCE;

	struct axis_opts* daxis = &iodev.joys[devid].adata[axisid];
	*mode = daxis->mode;
	*lower_bound = daxis->lower;
	*upper_bound = daxis->upper;
	*deadzone = daxis->deadzone;
	*kernel_size = daxis->kernel_sz;

	return ARCAN_OK;
}

void arcan_event_analogall(bool enable, bool mouse)
{
	if (mouse){
		if (enable){
			iodev.mx.mode = iodev.mx.oldmode;
			iodev.my.mode = iodev.my.oldmode;
			iodev.mx_r.mode = iodev.mx_r.oldmode;
			iodev.my_r.mode = iodev.my_r.oldmode;
		} else {
			iodev.mx.oldmode = iodev.mx.mode;
			iodev.mx.mode = ARCAN_ANALOGFILTER_NONE;
			iodev.my.oldmode = iodev.mx.mode;
			iodev.my.mode = ARCAN_ANALOGFILTER_NONE;
			iodev.mx_r.oldmode = iodev.mx.mode;
			iodev.mx_r.mode = ARCAN_ANALOGFILTER_NONE;
			iodev.my_r.oldmode = iodev.mx.mode;
			iodev.my_r.mode = ARCAN_ANALOGFILTER_NONE;
		}
	}

	for (int i = 0; i < iodev.n_joy; i++)
		for (int j = 0; j < iodev.joys[i].axis; j++)
			if (enable){
				if (iodev.joys[i].adata[j].oldmode == ARCAN_ANALOGFILTER_NONE)
					iodev.joys[i].adata[j].mode = ARCAN_ANALOGFILTER_AVG;
				else
					iodev.joys[i].adata[j].mode = iodev.joys[i].adata[j].oldmode;
			}
			else {
				iodev.joys[i].adata[j].oldmode = iodev.joys[i].adata[j].mode;
				iodev.joys[i].adata[j].mode = ARCAN_ANALOGFILTER_NONE;
			}
}

void arcan_event_analogfilter(int devid, 
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
	struct axis_opts opt;
	int kernel_lim = sizeof(opt.flt_kernel) / sizeof(opt.flt_kernel[0]);

	if (buffer_sz > kernel_lim) 
		buffer_sz = kernel_lim;

	if (buffer_sz <= 0)
		buffer_sz = 1;

	if (devid == -1)
		goto setmouse;

	devid -= ARCAN_JOYIDBASE;
	if (devid < 0 || devid >= iodev.n_joy)
		return;

	if (axisid < 0 || axisid >= iodev.joys[devid].axis)
		return;
	
	struct axis_opts* daxis = &iodev.joys[devid].adata[axisid];

	if (0){
setmouse:
		if (axisid == 0){
			set_analogstate(&iodev.mx, lower_bound, 
				upper_bound, deadzone, buffer_sz, kind);
			set_analogstate(&iodev.mx_r, lower_bound, 
				upper_bound, deadzone, buffer_sz, kind);
		} 
		else if (axisid == 1){
			set_analogstate(&iodev.my, lower_bound, 
				upper_bound, deadzone, buffer_sz, kind);
			set_analogstate(&iodev.my_r, lower_bound, 
				upper_bound, deadzone, buffer_sz, kind);
		}
		return;	
	}

	set_analogstate(daxis, lower_bound, 
		upper_bound, deadzone, buffer_sz, kind);
}

static unsigned long djb_hash(const char* str)
{
	unsigned long hash = 5381;
	int c;

	while ((c = *(str++)))
		hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

	return hash;
}

static inline void process_hatmotion(arcan_evctx* ctx, unsigned devid, 
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

	assert(iodev.n_joy > devid);
	assert(iodev.joys[devid].hats > hatid);

/* shouldn't really ever be the same, but not trusting SDL */
	if (iodev.joys[devid].hattbls[ hatid ] != value){
		unsigned oldtbl = iodev.joys[devid].hattbls[hatid];

		for (int i = 0; i < 4; i++){
			if ( (oldtbl & hattbl[i]) != (value & hattbl[i]) ){
				newevent.data.io.input.digital.subid  = ARCAN_HATBTNBASE +
					(hatid * 4) + i;
				newevent.data.io.input.digital.active = 
					(value & hattbl[i]) > 0;
				arcan_event_enqueue(ctx, &newevent);
			}
		}

		iodev.joys[devid].hattbls[hatid] = value;
	}
}

const char* arcan_event_devlabel(int devid)
{
	if (devid == -1)
		return "mouse";

	devid -= ARCAN_JOYIDBASE;
	if (devid < 0 || devid >= iodev.n_joy)
		return "no device";

	return strlen(iodev.joys[devid].label) == 0 ?
		"no identifier" : iodev.joys[devid].label;
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

		case SDL_MOUSEMOTION:
			process_mousemotion(ctx, &event.motion);
		break; 

		case SDL_JOYAXISMOTION:
			process_axismotion(ctx, &event.jaxis);
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

void drop_joytbl()
{
	for(int i=0; i < iodev.n_joy; i++){
		free(iodev.joys[i].adata);
		free(iodev.joys[i].hattbls);
	}

	free(iodev.joys);
	iodev.joys = NULL;
	iodev.n_joy = 0;
}

void arcan_event_rescan_idev(arcan_evctx* ctx)
{
	if (iodev.sticks_init)
		SDL_QuitSubSystem(SDL_INIT_JOYSTICK);

	SDL_Init(SDL_INIT_JOYSTICK);
	iodev.sticks_init = true;
	SDL_JoystickEventState(SDL_ENABLE);

	int n_joys = SDL_NumJoysticks();

	if (n_joys == 0){
		drop_joytbl();
		return;
	}

/*
 * (Re) scan/open all joysticks, 
 * look for matching / already present devices
 * and copy their settings.
 */
	size_t jsz = sizeof(struct arcan_stick) * n_joys;
	struct arcan_stick* joys = malloc(jsz);
	memset(joys, '\0', jsz);

	for (int i = 0; i < n_joys; i++) {
		struct arcan_stick* dj = &joys[i];
		struct arcan_stick* sj = NULL;
		unsigned long hashid = djb_hash(SDL_JoystickName(i));

/* find existing */
		if (iodev.joys){
			for (int j = 0; j < iodev.n_joy; j++){ 
				if (iodev.joys[j].hashid == hashid){
					arcan_warning("found matching\n");
					sj = &iodev.joys[j];
					break;
				}
				else
					arcan_warning("didn't match %d, %d\n", iodev.joys[j].hashid, hashid);
			}

			if (sj){
				memcpy(dj, sj, sizeof(struct arcan_stick));
				if (dj->hats){
					dj->hattbls = malloc(dj->hats * sizeof(unsigned));
					memcpy(dj->hattbls, sj->hattbls, sizeof(unsigned) * sj->hats);
				}

				if (dj->axis){
					dj->adata = malloc(dj->axis * sizeof(struct axis_opts));
					memcpy(dj->adata, sj->adata, sizeof(struct axis_opts) * sj->axis);
				}

				dj->handle = SDL_JoystickOpen(i);
				continue;
			}
		}

/* new entry */
		strncpy(dj->label, SDL_JoystickName(i), 255);
		dj->hashid = djb_hash(SDL_JoystickName(i));
		dj->handle = SDL_JoystickOpen(i);
		dj->devnum = i;

		dj->axis    = SDL_JoystickNumAxes(joys[i].handle);
		dj->buttons = SDL_JoystickNumButtons(joys[i].handle);
		dj->balls   = SDL_JoystickNumBalls(joys[i].handle);
		dj->hats    = SDL_JoystickNumHats(joys[i].handle);

		if (dj->hats > 0){
			size_t dst_sz = joys[i].hats * sizeof(unsigned);
			dj->hattbls = malloc(dst_sz);
			memset(joys[i].hattbls, 0, dst_sz);
		}

		if (dj->axis > 0){
			size_t ad_sz = sizeof(struct axis_opts) * dj->axis;
			dj->adata = malloc(ad_sz);
			memset(dj->adata, '\0', ad_sz); 
			for (int i = 0; i < dj->axis; i++){
				dj->adata[i].mode = ARCAN_ANALOGFILTER_AVG;
/* these values are sortof set 
 * based on the SixAxis (common enough, and noisy enough) */
				dj->adata[i].lower    = -32765;
				dj->adata[i].deadzone = 5000;
				dj->adata[i].upper    = 32768;
				dj->adata[i].kernel_sz = 1;
			}
		}
	}

	drop_joytbl();
	iodev.n_joy = n_joys; 
	iodev.joys = joys;
}

void platform_key_repeat(arcan_evctx* ctx, unsigned int rate)
{
	static int kbdrepeat;

		if (rate == 0)
			SDL_EnableKeyRepeat(0, SDL_DEFAULT_REPEAT_INTERVAL);
		else{
			kbdrepeat = rate;
			SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY, kbdrepeat); 
		}
}

void platform_event_deinit(arcan_evctx* ctx)
{
	if (iodev.sticks_init){
		SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
		iodev.sticks_init = false;
	}
}

void platform_device_lock(int devind, bool state)
{
	SDL_WM_GrabInput( state ? SDL_GRAB_ON : SDL_GRAB_OFF );
}

void platform_event_init(arcan_evctx* ctx)
{
	static bool first_init;

	SDL_EnableUNICODE(1);
	arcan_event_keyrepeat(ctx, SDL_DEFAULT_REPEAT_INTERVAL);

/* OSX hack */
	SDL_ShowCursor(0);
	SDL_ShowCursor(1);
	SDL_ShowCursor(0);

	if (!first_init){
		arcan_event_analogfilter(-1, 0, 
			-32768, 32767, 0, 1, ARCAN_ANALOGFILTER_AVG); 
		arcan_event_analogfilter(-1, 1, 
			-32768, 32767, 0, 1, ARCAN_ANALOGFILTER_AVG); 
		first_init = true;
	}
/* flush out initial storm */
	SDL_Event dummy[1];
	while ( SDL_PeepEvents(dummy, 1, SDL_GETEVENT, 
		SDL_EVENTMASK(SDL_MOUSEMOTION)) );

	arcan_event_rescan_idev(ctx);
}

