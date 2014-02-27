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
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <linux/input.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"

#define DEVPREFIX "/dev/input/event"

struct axis_opts {
/* none, avg, drop */ 
	enum ARCAN_ANALOGFILTER_KIND mode;
	enum ARCAN_ANALOGFILTER_KIND oldmode;

	int lower, upper, deadzone;

	int kernel_sz;
	int kernel_ofs;
	int32_t flt_kernel[64];
};

static struct {
	bool active;
	int mouseid;

	unsigned short n_devs;
	struct arcan_devnode* nodes;
} iodev = {0};

enum devnode_type {
	DEVNODE_SENSOR,
	DEVNODE_GAME,
	DEVNODE_CURSOR,
	DEVNODE_TOUCH
};

struct arcan_devnode {
/* identification and control */
	int handle;
	char label[256];
	unsigned long hashid;
	unsigned short devnum;

	enum devnode_type type;
	union {
		struct {
			struct axis_opts data;	
		} sensor;
		struct {
			unsigned short axes;
			unsigned short buttons;
			struct axis_opts* adata;
		} game;
		struct {
			uint16_t mx;
			uint16_t my;
			unsigned short buttons;
			struct axis_opts flt[2];
		} cursor;
		struct {
			bool incomplete;		
		} touch;
	};
};

/*
 * same in sdl/event.c
 */
static inline bool process_axis(arcan_evctx* ctx, 
	struct axis_opts* daxis, int16_t samplev, int16_t* outv)
{
	if (daxis->mode == ARCAN_ANALOGFILTER_NONE)
		return false;
	
	if (daxis->mode == ARCAN_ANALOGFILTER_PASS)
		goto accept_sample;

/* quickfilter deadzone */
	if (abs(samplev) < daxis->deadzone)
		return false;

/* quickfilter out controller edgenoise */
	if (samplev < daxis->lower ||
		samplev > daxis->upper)
		return false;

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

static inline void process_mousemotion(arcan_evctx* ctx,
	int16_t xv, int16_t xrel, int16_t yv, int16_t yrel)	
{
/*	int16_t dstv, dstv_r;
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

	if (process_axis(ctx, &iodev.mx, xv, &dstv) &&
		process_axis(ctx, &iodev.mx_r, xrel, &dstv_r)){
		nev.data.io.input.analog.subid = 0;
		nev.data.io.input.analog.axisval[0] = dstv;
		nev.data.io.input.analog.axisval[1] = dstv_r;
		arcan_event_enqueue(ctx, &nev);	
	}

	if (process_axis(ctx, &iodev.my, yev, &dstv) &&
		process_axis(ctx, &iodev.my_r, yrel, &dstv_r)){
		nev.data.io.input.analog.subid = 1;
		nev.data.io.input.analog.axisval[0] = dstv;
		nev.data.io.input.analog.axisval[1] = dstv_r;
		arcan_event_enqueue(ctx, &nev);	
	} */
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
/* special case, whatever device is permitted to 
 * emit cursor events at the moment */
	if (devid == -1){
		devid = iodev.mouseid;
	}

	if (devid < 0 || devid >= iodev.n_devs)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct arcan_devnode* node = &iodev.nodes[devid];
	switch(node->type){
	case DEVNODE_SENSOR:
		*mode = node->sensor.data.mode;
		*lower_bound = node->sensor.data.lower;
		*upper_bound = node->sensor.data.upper;
		*deadzone = node->sensor.data.deadzone;
		*kernel_size = node->sensor.data.kernel_sz;
	break;

	case DEVNODE_GAME:
/*		if (axisid >= iodev.joys[devid].axis) */
			return ARCAN_ERRC_BAD_RESOURCE;
	break;

	case DEVNODE_CURSOR:
		if (axisid != 0 && axisid != 1)
			return ARCAN_ERRC_NO_SUCH_OBJECT;

		struct axis_opts* src = &node->cursor.flt[axisid];
		*mode = src->mode;
		*lower_bound = src->lower;
		*upper_bound = src->upper;
		*deadzone = src->deadzone;
		*kernel_size = src->kernel_sz;
	break;
	
	case DEVNODE_TOUCH:
		return ARCAN_ERRC_BAD_RESOURCE;
	break;
	}	

	return ARCAN_OK;
}

void arcan_event_analogall(bool enable, bool mouse)
{
/*	if (mouse){
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
			} */
}

void arcan_event_analogfilter(int devid, 
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
/*	int kernel_lim = sizeof(opt.flt_kernel) / sizeof(opt.flt_kernel[0]);

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
		upper_bound, deadzone, buffer_sz, kind);*/
}

static unsigned long djb_hash(const char* str)
{
	unsigned long hash = 5381;
	int c;

	while ((c = *(str++)))
		hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

	return hash;
}

void platform_event_process(arcan_evctx* ctx)
{
/* poll all open FDs */
}

void platform_key_repeat(arcan_evctx* ctx, unsigned int rate)
{
/* ioctl for keyboard device */
}

void arcan_event_rescan_idev(arcan_evctx* ctx)
{
/* might just use a discover thread and sync when polled */
	char ibuf[sizeof(DEVPREFIX) + 4];
	char name[256];

	int i = 0;

/* aggressively open/lock devices */
	do{
		sprintf(ibuf, "%s%i", DEVPREFIX, i);

		int fd = open(ibuf, O_RDONLY);
		if (-1 == fd){
			if (errno == ENOENT)
				break;
			continue;
		}
		ioctl(fd, EVIOCGNAME(sizeof(name)), name);

		printf("found device( %s )\n", name);
		ioctl(fd, EVIOCGPROP(sizeof(name)), name);
		printf("prop: %s\n", name);

		close(fd);
	} while (++i);

/* for joyst:
 * 0 devs? drop_joytbl() then exit
 * n devs? allocate new array of arcan_stick, set it to 0
 * open each device, store label and hash
 * copy all existing into the new array
 * if device doesn't exist, try to open and if success add
 * drop old table, set iodev.n_joy to scanres and iodev.joys to tbl */
}

const char* arcan_event_devlabel(int devid)
{
	if (devid == -1)
		devid = iodev.mouseid;

	if (devid < 0 || devid >= iodev.n_devs)
		return "no device";

	return strlen(iodev.nodes[devid].label) == 0 ?
		"no identifier" : iodev.nodes[devid].label;
}

void platform_event_deinit(arcan_evctx* ctx)
{
	/* keep joystick table around, just close handles */
}

void platform_device_lock(int devind, bool state)
{
	/* doesn't make sense outside some window systems */
}

void platform_event_init(arcan_evctx* ctx)
{
	/*
	 * for keyboard -- use stdin but with a bunch of modes set,
	 * install signal handlers for ABURT, BUS, FPE, ILL, QUIT, etc.
	 * have an atexit handler to definitely reset keyboard states
	 *
	 * toggle unicode parsing of input keyboards,
	 * might possible patch _event to support longer (utf8 limit)
	 * resulting characters for real non-latin input
	 *
	 * set default repeat rate 
	 */

	arcan_event_rescan_idev(ctx);

	/* reset analog filter for mouse unless first init */
	/* flush pending device events? */
	/* rescan idev */
}

