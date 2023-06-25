/*
 * Copyright 2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: quick and dirty port of the SDL1.2 platform,
 * doesn't handle TEXTINPUT, incorrect handling of touch, joypad etc.
 * incorrect grabbing and repeat as well
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

#include <SDL.h>

#include <arcan_shmif.h>
#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_event.h>

#include "arcan_video.h"
#include "arcan_videoint.h"

#include "sdl2_12_lut.h"
#include "code_sc_evdev.h"

SDL_Window* sdl2_platform_activewnd();
static const char* envopts[] =
{
	NULL
};

static bool mouse_relative = false;
static bool filter_repeat = false;

const char** platform_event_envopts()
{
	return (const char**) envopts;
}

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
	struct axis_opts mx, my, mx_r, my_r;
	struct axis_opts wheel_x, wheel_y;

	bool sticks_init;
	unsigned short n_joy;
	struct arcan_stick* joys;
} iodev = {0};

struct arcan_stick {
/* if we can get a repeatable identifier to expose
 * to higher layers in order to retain / track settings
 * for a certain device, put that here */
	char label[256];
	bool tagged;

	SDL_Joystick* handle;
	SDL_JoystickID joyid;

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

static int find_devind(int devnum)
{
	for (int i = 0; i < iodev.n_joy; i++){
		if (iodev.joys[i].devnum == devnum){
			return i;
		}
	}
	return -1;
}

static int find_devind_from_joyid(SDL_JoystickID id)
{
	for (int i = 0; i < iodev.n_joy; i++) {
		if (iodev.joys[i].joyid == id) {
			return i;
		}
	}
	return -1;
}

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

static inline void process_axismotion(
	arcan_evctx* ctx, const SDL_JoyAxisEvent* const ev)
{
	int devind = find_devind_from_joyid(ev->which);

	if (devind == -1 || iodev.joys[devind].axis < ev->axis)
		return;

	struct axis_opts* daxis = &iodev.joys[devind].adata[ev->axis];
	int16_t dstv;

	if (process_axis(ctx, daxis, ev->value, &dstv)){
		arcan_event newevent = {
			.category = EVENT_IO,
			.io.kind = EVENT_IO_AXIS_MOVE,
			.io.devid = iodev.joys[devind].devnum,
			.io.subid = ev->axis,
			.io.datatype = EVENT_IDATATYPE_ANALOG,
			.io.devkind  = EVENT_IDEVKIND_GAMEDEV,
			.io.input.analog.gotrel = false,
			.io.input.analog.nvalues = 1,
			.io.input.analog.axisval[0] = dstv
		};
		arcan_event_enqueue(ctx, &newevent);
	}
}

void platform_event_samplebase(int devid, float xyz[3])
{
/*
	SDL2 FIXME
	if (0 == devid)
		SDL_WarpMouse(xyz[0], xyz[1]);
 */
}

int platform_event_translation(
	int devid, int action, const char** names, const char** err)
{
	*err = "Unsupported";
	return -1;
}

int platform_event_device_request(int space, const char* path)
{
	return -1;
}

static inline void process_mousemotion(arcan_evctx* ctx,
	const SDL_MouseMotionEvent* const ev)
{
	arcan_event nev = {
		.category = EVENT_IO,
		.io.label = "MOUSE\0",
		.io.kind = EVENT_IO_AXIS_MOVE,
		.io.datatype = EVENT_IDATATYPE_ANALOG,
		.io.devkind = EVENT_IDEVKIND_MOUSE,
		.io.devid = 0,
		.io.input.analog.nvalues = 1
	};

	int16_t dstv, dstv_r;
	if (mouse_relative){
		nev.io.input.analog.gotrel = true;
		nev.io.input.analog.axisval[0] = ev->xrel;
		arcan_event_enqueue(ctx, &nev);
		nev.io.subid = 1;
		nev.io.input.analog.axisval[0] = ev->yrel;
		arcan_event_enqueue(ctx, &nev);
	}
	else {
		nev.io.input.analog.axisval[0] = ev->x;
		arcan_event_enqueue(ctx, &nev);
		nev.io.subid = 1;
		nev.io.input.analog.axisval[0] = ev->y;
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

arcan_errc platform_event_analogstate(int devid, int axisid,
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
		else if (axisid == 2){
			*mode = iodev.wheel_y.mode;
		}
		else if (axisid == 3){
			*mode = iodev.wheel_x.mode;
		}
		else
			return ARCAN_ERRC_BAD_RESOURCE;

		return true;
	}

	int jind = find_devind(devid);

	if (devid < 0 || -1 == jind)
		return ARCAN_ERRC_NO_SUCH_OBJECT;


	if (!iodev.joys || axisid >= iodev.joys[jind].axis)
		return ARCAN_ERRC_BAD_RESOURCE;

	struct axis_opts* daxis = &iodev.joys[jind].adata[axisid];
	*mode = daxis->mode;
	*lower_bound = daxis->lower;
	*upper_bound = daxis->upper;
	*deadzone = daxis->deadzone;
	*kernel_size = daxis->kernel_sz;

	return ARCAN_OK;
}

void platform_event_analogall(bool enable, bool mouse)
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

	if (iodev.joys){
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
}

void platform_event_analogfilter(int devid,
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

	int jind = find_devind(devid);

	if (devid < 0 || -1 == jind)
		return;

	if (axisid < 0 || axisid >= iodev.joys[jind].axis)
		return;

	struct axis_opts* daxis = &iodev.joys[jind].adata[axisid];

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
		else if (axisid == 2){
			iodev.wheel_y.mode = kind;
		}
		else if (axisid == 3){
			iodev.wheel_x.mode = kind;
		}
		return;
	}

	set_analogstate(daxis, lower_bound,
		upper_bound, deadzone, buffer_sz, kind);
}

static unsigned long djb_hash(const char* str, size_t n)
{
	unsigned long hash = 5381;
	int c;

	while (n--){
		c = *(str++);
		hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
	}

	return hash;
}

static inline void process_hatmotion(arcan_evctx* ctx, unsigned devid,
	unsigned hatid, unsigned value)
{
	int devind = find_devind_from_joyid(devid);
	if (devind == -1)
		return;

	static unsigned hattbl[4] = {SDL_HAT_UP, SDL_HAT_DOWN,
		SDL_HAT_LEFT, SDL_HAT_RIGHT};

	assert(iodev.n_joy > devind);
	assert(iodev.joys[devind].hats > hatid);

	arcan_event newevent = {
		.category = EVENT_IO,
		.io.kind = EVENT_IO_BUTTON,
		.io.datatype = EVENT_IDATATYPE_DIGITAL,
		.io.devkind = EVENT_IDEVKIND_GAMEDEV,
		.io.devid = iodev.joys[devind].devnum,
		.io.subid = 128 + (hatid * 4)
	};

/* shouldn't really ever be the same, but not trusting SDL */
	if (iodev.joys[devind].hattbls[ hatid ] != value){
		unsigned oldtbl = iodev.joys[devind].hattbls[hatid];

		for (int i = 0; i < 4; i++){
			if ( (oldtbl & hattbl[i]) != (value & hattbl[i]) ){
				newevent.io.subid  = (hatid * 4) + i;
				newevent.io.input.digital.active =
					(value & hattbl[i]) > 0;
				arcan_event_enqueue(ctx, &newevent);
			}
		}

		iodev.joys[devind].hattbls[hatid] = value;
	}
}

static void ucs4_to_utf8(uint32_t g, char *txt)
{
	if (g >= 0xd800 && g <= 0xdfff)
		return;
	if (g > 0x10ffff || (g & 0xffff) == 0xffff || (g & 0xffff) == 0xfffe)
		return;
	if (g >= 0xfdd0 && g <= 0xfdef)
		return;

	if (g < (1 << 7)) {
		txt[0] = g & 0x7f;
		return;
	} else if (g < (1 << (5 + 6))) {
		txt[0] = 0xc0 | ((g >> 6) & 0x1f);
		txt[1] = 0x80 | ((g     ) & 0x3f);
		return;
	} else if (g < (1 << (4 + 6 + 6))) {
		txt[0] = 0xe0 | ((g >> 12) & 0x0f);
		txt[1] = 0x80 | ((g >>  6) & 0x3f);
		txt[2] = 0x80 | ((g      ) & 0x3f);
		return;
	} else if (g < (1 << (3 + 6 + 6 + 6))) {
		txt[0] = 0xf0 | ((g >> 18) & 0x07);
		txt[1] = 0x80 | ((g >> 12) & 0x3f);
		txt[2] = 0x80 | ((g >>  6) & 0x3f);
		txt[3] = 0x80 | ((g      ) & 0x3f);
		return;
	} else {
		return;
	}
}

/*
 * ugly hack to emulate normal us-keyboard behavior to reduce the need for
 * remapping everything at higher levels
 */
static void apply_mod(uint8_t ch[5], int mod)
{
	char oldch = ch[0];

/* unicode or unmodified? then leave it intact */
	if (oldch > 127 || ch[1] != 0 || !mod)
		return;

/* ctrl/alt ignored entirely and just reset */
	bool upper = mod & (ARKMOD_LSHIFT | ARKMOD_RSHIFT | KMOD_CAPS);
	if (!upper){
		ch[0] = 0;
		return;
	}

/* make sense to upcase? */
	if (isalpha(oldch)){
		ch[0] = toupper(oldch);
		return;
	}

	ch[0] = '\0';

	if (upper){
		if (isalpha(oldch)){
			ch[0] = toupper(oldch);
			return;
		}

/* don't shift+num workaround for caps-lock */
		if (mod & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)){
			switch(oldch){
			case '1': ch[0] = '!'; break;
			case '2': ch[0] = '"'; break;
			case '3': ch[0] = '#'; break;
			case '4': ch[0] = '$'; break;
			case '5': ch[0] = '%'; break;
			case '6': ch[0] = '^'; break;
			case '7': ch[0] = '&'; break;
			case '8': ch[0] = '*'; break;
			case '9': ch[0] = '('; break;
			case '0': ch[0] = ')'; break;
			case '-': ch[0] = '_'; break;
			case '=': ch[0] = '+'; break;
			case '[': ch[0] = '{'; break;
			case ']': ch[0] = '}'; break;
			case ';': ch[0] = ':'; break;
			case '\'': ch[0] = '"'; break;
			case '\\': ch[0] = '|'; break;
			case ',': ch[0] = '<'; break;
			case '.': ch[0] = '>'; break;
			case '/': ch[0] = '?'; break;
			case '~': ch[0] = '`'; break;
			}
		}
	}
	else if (mod == ARKMOD_RALT){
/* US international? */
	}
}

const char* platform_event_devlabel(int devid)
{
	if (devid == -1)
		return "mouse";

	devid = find_devind(devid);

	if (devid < 0 || devid >= iodev.n_joy)
		return "no device";

	return iodev.joys && strlen(iodev.joys[devid].label) == 0 ?
		"no identifier" : iodev.joys[devid].label;
}

uint16_t sdl2_sym_to_12sym(uint32_t insym)
{
	if (insym < COUNT_OF(lut))
		return lut[insym];
	return 0;
}

void platform_event_process(arcan_evctx* ctx)
{
	int canary = 0xf00f;
	SDL_Event event;
	SDL_StopTextInput();

/* other fields will be set upon enqueue */
	while (SDL_PollEvent(&event)) {
		arcan_event newevent = {.category = EVENT_IO};
		switch (event.type) {
		case SDL_MOUSEBUTTONDOWN:
			newevent.io.kind = EVENT_IO_BUTTON;
			newevent.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newevent.io.devkind  = EVENT_IDEVKIND_MOUSE;
			switch(event.button.button){
			case SDL_BUTTON_LEFT: newevent.io.subid = 1; break;
			case SDL_BUTTON_MIDDLE: newevent.io.subid = 3; break;
			case SDL_BUTTON_RIGHT: newevent.io.subid = 2; break;
			default:
				newevent.io.subid = event.button.button;
			break;
			}
			newevent.io.devid = event.button.which;
			newevent.io.input.digital.active = true;
			snprintf(newevent.io.label, sizeof(newevent.io.label) - 1, "mouse%i",
				event.motion.which);
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_MOUSEBUTTONUP:
			newevent.io.kind = EVENT_IO_BUTTON;
			newevent.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newevent.io.devkind  = EVENT_IDEVKIND_MOUSE;
			newevent.io.devid = event.button.which;
			switch(event.button.button){
			case SDL_BUTTON_LEFT: newevent.io.subid = 1; break;
			case SDL_BUTTON_MIDDLE: newevent.io.subid = 3; break;
			case SDL_BUTTON_RIGHT: newevent.io.subid = 2; break;
			default:
				newevent.io.subid = event.button.button;
			break;
			}
			newevent.io.input.digital.active = false;
			snprintf(newevent.io.label, sizeof(newevent.io.label) - 1, "mouse%i",
				event.motion.which);
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_MOUSEMOTION:
			process_mousemotion(ctx, &event.motion);
		break;

/* there are two modes of operation here, one is where the wheel is simulated
 * as a button press (which is the only coherent tactic across all OSes, but
 * suboptimal for those with analog wheels), the other is where the wheel is
 * treated fully analog. If a filter has been set for the context (all mice)
 * then we emit 'raw' analog values */
		case SDL_MOUSEWHEEL:
			snprintf(newevent.io.label,
				sizeof(newevent.io.label) - 1, "mouse%i", event.motion.which);
			newevent.io.devid = event.wheel.which;
			newevent.io.devkind = EVENT_IDEVKIND_MOUSE;

			if (event.wheel.y != 0){
				bool isdigit = iodev.wheel_y.mode == ARCAN_ANALOGFILTER_NONE;
				if (isdigit){
					newevent.io.subid = (event.wheel.y > 0) ? 4 : 5;
					newevent.io.input.digital.active = true;
					arcan_event_enqueue(ctx, &newevent);
					newevent.io.input.digital.active = false;
					arcan_event_enqueue(ctx, &newevent);
				}
				else {
					newevent.io.subid = 2;
					newevent.io.datatype = EVENT_IDATATYPE_ANALOG;
					newevent.io.input.analog.gotrel = true;
					newevent.io.input.analog.nvalues = 1;
					newevent.io.input.analog.axisval[0] = event.wheel.y;
					arcan_event_enqueue(ctx, &newevent);
				}
			}
			else if (event.wheel.x != 0){
				bool isdigit = iodev.wheel_y.mode == ARCAN_ANALOGFILTER_NONE;
				if (isdigit){
					newevent.io.subid = (event.wheel.x > 0) ? 6 : 7;
					newevent.io.input.digital.active = true;
					arcan_event_enqueue(ctx, &newevent);
					newevent.io.input.digital.active = false;
					arcan_event_enqueue(ctx, &newevent);
				}
				else {
					newevent.io.subid = 3;
					newevent.io.datatype = EVENT_IDATATYPE_ANALOG;
					newevent.io.input.analog.gotrel = true;
					newevent.io.input.analog.nvalues = 1;
					newevent.io.input.analog.axisval[0] = event.wheel.y;
					arcan_event_enqueue(ctx, &newevent);
				}
			}
		break;

		case SDL_JOYAXISMOTION:
			process_axismotion(ctx, &event.jaxis);
		break;

		case SDL_KEYDOWN:
			newevent.io.datatype = EVENT_IDATATYPE_TRANSLATED;
			newevent.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
			newevent.io.pts = event.key.timestamp;
			newevent.io.input.translated.active = true;

/*
 * Keysym / keycodes have changed since the SDL1.2 days, but a lot of scripts
 * rely on the old format, so convert back and keep the code as sub.
 *
 * A note here is that on x11 we don't get access to the native (typically
 * linux) sym. This means that for clients that expect OS representation for
 * keypresses and apply their own translation tables, most notably
 * arcan-wayland and qemu, the information necessary for correct input is lost
 * in transit. The only real option is to have some kind of generator go from
 * the SDL tables back to x11 ones. The one used here (sdl_sc_evdev) comes from
 * reverse-mapping the sdl2/src/events/scancodes_linux header.
 */
			newevent.io.input.translated.keysym =
				sdl2_sym_to_12sym(event.key.keysym.scancode);
			newevent.io.input.translated.modifiers = event.key.keysym.mod;
			newevent.io.input.translated.scancode = event.key.keysym.scancode;
			newevent.io.subid = event.key.keysym.sym;

/* and if we can't reliably translate, patch it in there anyhow and hope the
 * scripting layer can do someting more, would have been nice if SDL2 actually
 * provided this as part of their compat - there is some 1.2 wrapper lib in
 * development so it might happen */
			if (!newevent.io.input.translated.keysym)
				newevent.io.input.translated.keysym = newevent.io.subid;

			if (event.key.keysym.scancode < SDL_NUM_SCANCODES &&
				sdl_sc_evdev[event.key.keysym.scancode]){
				newevent.io.subid = sdl_sc_evdev[event.key.keysym.scancode];
			}

/* there's no having old .unicode behavior back unfortunately, so the SDL2
 * users will need a keymap on the scripting level */
			if (!(event.key.keysym.scancode & 0x8000000)){
				ucs4_to_utf8(event.key.keysym.sym,
					(char*)newevent.io.input.translated.utf8);

				if (event.key.keysym.mod & ~(KMOD_NUM)){
					apply_mod(newevent.io.input.translated.utf8, event.key.keysym.mod);
				}
/* some hacks to make more of the translated table work, use special modifier
 * rules */
			}

			if (event.key.repeat && filter_repeat)
				continue;

			newevent.io.input.translated.modifiers |=
				ARKMOD_REPEAT * event.key.repeat != 0;
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_KEYUP:
			newevent.io.datatype = EVENT_IDATATYPE_TRANSLATED;
			newevent.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
			newevent.io.pts = event.key.timestamp;
			newevent.io.input.translated.active = false;
			newevent.io.input.translated.keysym =
				sdl2_sym_to_12sym(event.key.keysym.scancode);
			newevent.io.input.translated.modifiers = event.key.keysym.mod;
			newevent.io.input.translated.scancode = event.key.keysym.scancode;
			newevent.io.subid = event.key.keysym.sym;

			if (!newevent.io.input.translated.keysym)
				newevent.io.input.translated.keysym = newevent.io.subid;

			if (
				event.key.keysym.scancode < SDL_NUM_SCANCODES &&
				sdl_sc_evdev[event.key.keysym.scancode])
				newevent.io.subid = sdl_sc_evdev[event.key.keysym.scancode];

			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_JOYBUTTONDOWN:
			newevent.io.kind = EVENT_IO_BUTTON;
			newevent.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newevent.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
			newevent.io.devid = iodev.joys[event.jbutton.which].devnum;
			newevent.io.subid = event.jbutton.button;
			newevent.io.input.digital.active = true;
			snprintf(newevent.io.label, sizeof(newevent.io.label)-1,
				"joystick%i", event.jbutton.which);
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_JOYBUTTONUP:
			newevent.io.kind = EVENT_IO_BUTTON;
			newevent.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newevent.io.devkind  = EVENT_IDEVKIND_GAMEDEV;
			newevent.io.devid = iodev.joys[event.jbutton.which].devnum;
			newevent.io.subid = event.jbutton.button;
			newevent.io.input.digital.active = false;
			snprintf(newevent.io.label, sizeof(newevent.io.label)-1, "joystick%i",
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

/*		case SDL_ACTIVEEVENT:
newevent.io.kind = (MOUSEFOCUS, INPUTFOCUS, APPACTIVE(0 = icon, 1 = restored)
if (event->active.state & SDL_APPINPUTFOCUS){
SDL_SetModState(KMOD_NONE);
		break;
*/
		case SDL_QUIT:
			newevent.category = EVENT_SYSTEM;
			newevent.sys.kind = EVENT_SYSTEM_EXIT;
			arcan_event_enqueue(ctx, &newevent);
		break;

		case SDL_APP_WILLENTERBACKGROUND:
/* FIXME: need to stop rendering or iOS will be cranky - and we can't really
 * do it here, we need an explicit callback trigger via the SDL_AddEventWatch */
		break;
		case SDL_WINDOWEVENT:
			if (event.window.event == SDL_WINDOWEVENT_RESIZED ||
				event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED){
				int w, h;
				SDL_GL_GetDrawableSize(sdl2_platform_activewnd(), &w, &h);
				arcan_event_enqueue(ctx, &(arcan_event){
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_RESET,
					.vid.source = -1,
					.vid.displayid = 0,
					.vid.width = w,
					.vid.height = h
				});
			}
			else if (event.window.event == SDL_WINDOWEVENT_EXPOSED){
				arcan_video_display.ignore_dirty = 2;
			}
		break;
	}
	}
}

/* just separate chain on hid until no collision */
static unsigned gen_devid(unsigned hid)
{
	for (int i = 0; i < iodev.n_joy; i++){
		if (iodev.joys[i].devnum == hid){
			hid += 257;
			i = 0;
		}
	}
	return hid;
}

void drop_joytbl(struct arcan_evctx* ctx)
{
	for(int i=0; i < iodev.n_joy; i++){
		if (!iodev.joys[i].tagged){
			struct arcan_event remev = {
				.category = EVENT_IO,
				.io.kind = EVENT_IO_STATUS,
				.io.devid = iodev.joys[i].devnum,
				.io.devkind = EVENT_IDEVKIND_STATUS,
				.io.input.status.devkind = EVENT_IDEVKIND_GAMEDEV,
				.io.input.status.action = EVENT_IDEV_REMOVED
			};

			snprintf((char*) &remev.io.label, sizeof(remev.io.label) /
				sizeof(remev.io.label[0]), "%s", iodev.joys[i].label);
			arcan_event_enqueue(ctx, &remev);

			free(iodev.joys[i].adata);
			free(iodev.joys[i].hattbls);
		}
		else
			iodev.joys[i].tagged = false;

		free(iodev.joys);
		iodev.joys = NULL;
		iodev.n_joy = 0;
	}
}

enum PLATFORM_EVENT_CAPABILITIES platform_event_capabilities(const char** out)
{
	if (out)
		*out = "sdl2";

	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_GAMING;
}

void platform_event_rescan_idev(arcan_evctx* ctx)
{
	if (iodev.sticks_init)
		SDL_QuitSubSystem(SDL_INIT_JOYSTICK);

	SDL_Init(SDL_INIT_JOYSTICK);
	SDL_JoystickEventState(SDL_ENABLE);

	int n_joys = SDL_NumJoysticks();
	iodev.sticks_init = true;

	if (n_joys == 0){
		drop_joytbl(ctx);
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
		unsigned long hashid = djb_hash((char*)SDL_JoystickGetDeviceGUID(i).data, 16);

/* find existing */
		if (iodev.joys){
			for (int j = 0; j < iodev.n_joy; j++){
				if (iodev.joys[j].hashid == hashid){
					sj = &iodev.joys[j];
					break;
				}
			}

/* if found, copy to new table */
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
				dj->joyid = SDL_JoystickInstanceID(dj->handle);
				continue;
			}
		}

/* otherwise add as new entry */
		strncpy(dj->label, SDL_JoystickNameForIndex(i), 255);
		dj->hashid = djb_hash((char*)SDL_JoystickGetDeviceGUID(i).data, 16);
		dj->handle = SDL_JoystickOpen(i);
		dj->joyid = SDL_JoystickInstanceID(dj->handle);
		dj->devnum = gen_devid(dj->hashid);

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

/* notify the rest of the system about the added device */
		struct arcan_event addev = {
			.category = EVENT_IO,
			.io.kind = EVENT_IO_STATUS,
			.io.devkind = EVENT_IDEVKIND_STATUS,
			.io.devid = dj->devnum,
			.io.input.status.devkind = EVENT_IDEVKIND_GAMEDEV,
			.io.input.status.action = EVENT_IDEV_ADDED
		};
		snprintf((char*) &addev.io.label, sizeof(addev.io.label) /
			sizeof(addev.io.label[0]), "%s", dj->label);
		arcan_event_enqueue(ctx, &addev);
	}

	iodev.n_joy = n_joys;
	iodev.joys = joys;
}

void platform_event_keyrepeat(arcan_evctx* ctx, int* rate, int* delay)
{
/* sdl repeat start disabled */
	static int cur_rep, cur_del;
	bool upd = false;

/* we would need to implement an oscillator to get anywhere with this,
 * so treat this as binary for the time being */
	if (*rate < 0){
		*rate = cur_rep;
	}
	else{
		int tmp = *rate;
		*rate = cur_rep;
		cur_rep = tmp;
		upd = true;
	}

	if (*delay < 0){
		*delay = cur_del;
	}
	else{
		int tmp = *delay;
		*delay = cur_del;
		cur_del = tmp;
		upd = true;
	}

	if (upd){
		filter_repeat = cur_rep == 0;
	}
}

void platform_event_deinit(arcan_evctx* ctx)
{
	if (iodev.sticks_init){
		SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
		iodev.sticks_init = false;
	}
}

void platform_event_reset(arcan_evctx* ctx)
{
	platform_event_deinit(ctx);
}

void platform_device_lock(int devind, bool state)
{
	SDL_SetWindowGrab(sdl2_platform_activewnd(), state);
	SDL_SetRelativeMouseMode(state);
	mouse_relative = state;
}

void platform_event_preinit()
{
}

void platform_event_init(arcan_evctx* ctx)
{
	static bool first_init;

	if (!first_init){
		init_lut();
		init_sdl_sc_evdev();

		platform_event_analogfilter(-1, 0,
			-32768, 32767, 0, 1, ARCAN_ANALOGFILTER_PASS);
		platform_event_analogfilter(-1, 1,
			-32768, 32767, 0, 1, ARCAN_ANALOGFILTER_PASS);
		first_init = true;
		int r = 0, d = 0;
		platform_event_keyrepeat(ctx, &r, &d);
	}

	platform_event_rescan_idev(ctx);
}
