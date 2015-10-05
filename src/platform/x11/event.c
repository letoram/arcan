/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Rather quick and dirty hack to get some kind of X11 input support. Missing
 * joysticks and similar devices, keyboard translation is only partially
 * working and so on. This is a very low priority platform, use the SDL layer
 * if possible.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

#include "util/xsymconv.h"

static const char* envopts[] = {
	NULL
};

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
	bool active;
	struct axis_opts mx, my, mx_r, my_r;
} iodev = {0};

static inline bool process_axis(struct arcan_evctx* ctx,
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

static inline void process_mousemotion(struct arcan_evctx* ctx,
	int16_t xv, int16_t xrel, int16_t yv, int16_t yrel)
{
	int16_t dstv, dstv_r;
	arcan_event nev = {
		.category = EVENT_IO,
		.io.label = "MOUSE\0",
		.io.kind = EVENT_IO_AXIS_MOVE,
		.io.datatype = EVENT_IDATATYPE_ANALOG,
		.io.devkind  = EVENT_IDEVKIND_MOUSE,
		.io.input.analog.devid  = 0,
		.io.input.analog.gotrel = true,
		.io.input.analog.nvalues = 2
	};

	snprintf(nev.io.label, sizeof(nev.io.label) - 1, "mouse");

	if (process_axis(ctx, &iodev.mx, xv, &dstv) &&
		process_axis(ctx, &iodev.mx_r, xrel, &dstv_r)){
		nev.io.input.analog.subid = 0;
		nev.io.input.analog.axisval[0] = dstv;
		nev.io.input.analog.axisval[1] = dstv_r;
		arcan_event_enqueue(ctx, &nev);
	}

	if (process_axis(ctx, &iodev.my, yv, &dstv) &&
		process_axis(ctx, &iodev.my_r, yrel, &dstv_r)){
		nev.io.input.analog.subid = 1;
		nev.io.input.analog.axisval[0] = dstv;
		nev.io.input.analog.axisval[1] = dstv_r;
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
/* special case, whatever device is permitted to
 * emit cursor events at the moment */
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

	return ARCAN_ERRC_NO_SUCH_OBJECT;
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
/*
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
			} */
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

	return;

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
}

Display* x11_get_display();
Window* x11_get_window();
static Cursor null_cursor;

void platform_event_samplebase(int devid, float xyz[3])
{
	if (0 == devid)
	XWarpPointer(x11_get_display(),
		None, x11_get_window(), 0, 0, 0, 0, xyz[0], xyz[1]);
}

void create_null_cursor()
{
	Pixmap cmask = XCreatePixmap(x11_get_display(), *x11_get_window(), 1, 1, 1);
	XGCValues xgc = {
		.function = GXclear
	};
	GC gc = XCreateGC(x11_get_display(), cmask, GCFunction, &xgc);
	XFillRectangle(x11_get_display(), cmask, gc, 0, 0, 1, 1);
	XColor ncol = {
		.flags = 04
	};
	null_cursor = XCreatePixmapCursor(x11_get_display(),
		cmask, cmask, &ncol, &ncol, 0, 0);
	XFreePixmap(x11_get_display(), cmask);
	XFreeGC(x11_get_display(), gc);
}

static void send_keyev(struct arcan_evctx* ctx, XKeyEvent key, bool state)
{
  char keybuf[4] = {0};
  XLookupString(&key, keybuf, 3, NULL, NULL);

	arcan_event ev = {
		.category = EVENT_IO,
		.io.kind = EVENT_IO_BUTTON,
		.io.datatype = EVENT_IDATATYPE_TRANSLATED,
		.io.devkind = EVENT_IDEVKIND_KEYBOARD,
		.io.input.translated.active = state,
		.io.input.translated.devid = key.keycode,
		.io.input.translated.subid = keybuf[1],
	};

/*
 * cheat here at the moment, need to track keysyms to separate mask
 */
	int mod = 0;
	if (key.state & ShiftMask)
		mod |= ARKMOD_LSHIFT;

	if (key.state & ControlMask)
		mod |= ARKMOD_LCTRL;

	if (key.state & Mod1Mask)
		mod |= ARKMOD_LALT;

	if (key.state & Mod5Mask)
		mod |= ARKMOD_RALT;

	int ind = XLookupKeysym(&key, key.state);
	ev.io.input.translated.keysym = symtbl_in[ind];
	ev.io.input.translated.modifiers = mod;

	arcan_event_enqueue(ctx, &ev);
}

static void send_buttonev(struct arcan_evctx* ctx, int button, bool state)
{
	arcan_event ev = {
		.category = EVENT_IO,
		.io.datatype = EVENT_IDATATYPE_DIGITAL,
		.io.devkind = EVENT_IDEVKIND_MOUSE,
		.io.input.digital.active = state,
		.io.input.digital.devid = 0,
		.io.input.digital.subid = button
	};

	arcan_event_enqueue(ctx, &ev);
}

void platform_event_process(struct arcan_evctx* ctx)
{
	static bool mouse_init;
	static int last_mx;
	static int last_my;
	Display* x11_display = x11_get_display();

	while (x11_display && XPending(x11_display)){
		XEvent xev;
		XNextEvent(x11_display, &xev);
		switch(xev.type){
		case MotionNotify:
			if (!mouse_init){
				last_mx = xev.xmotion.x;
				last_my = xev.xmotion.y;
				mouse_init = true;
			} else {
				process_mousemotion(ctx, xev.xmotion.x,
					xev.xmotion.x - last_mx, xev.xmotion.y,
					xev.xmotion.y - last_my
				);

				last_mx = xev.xmotion.x;
				last_my = xev.xmotion.y;
			}

		break;

		case ButtonPress:
			send_buttonev(ctx, xev.xbutton.button, true);
		break;

		case ButtonRelease:
			send_buttonev(ctx, xev.xbutton.button, false);
		break;

		case KeyPress:
			send_keyev(ctx, xev.xkey, true );
		break;

		case KeyRelease:
			send_keyev(ctx, xev.xkey, false );
		break;
		}
	}
}

const char** platform_input_envopts()
{
	return (const char**) envopts;
}

void platform_event_rescan_idev(struct arcan_evctx* ctx)
{
}

const char* platform_event_devlabel(int devid)
{
	if (devid == -1)
		return "mouse";

	return "no device";
}

void platform_event_keyrepeat(arcan_evctx* ctx, int* rate, int* delay)
{
}

void platform_event_deinit(struct arcan_evctx* ctx)
{
}

enum PLATFORM_EVENT_CAPABILITIES platform_input_capabilities()
{
	return ACAP_TRANSLATED | ACAP_MOUSE;
}

void platform_device_lock(int devind, bool state)
{
#ifndef WITH_HEADLESS_MAIN
	if (devind == 0){
		if (state){
			XGrabPointer(x11_get_display(), *x11_get_window(),
				true, PointerMotionMask, GrabModeAsync, GrabModeAsync,
				*x11_get_window(), null_cursor, CurrentTime
			);
		}
		else
			XUngrabPointer(x11_get_display(), CurrentTime);
	}
#endif
}

void platform_event_init(arcan_evctx* ctx)
{
	gen_symtbl();
	create_null_cursor();

	platform_event_analogfilter(-1, 0,
		-32768, 32767, 0, 1, ARCAN_ANALOGFILTER_AVG);
	platform_event_analogfilter(-1, 1,
		-32768, 32767, 0, 1, ARCAN_ANALOGFILTER_AVG);

	platform_event_rescan_idev(ctx);
}
