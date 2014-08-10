/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

/*
 * a lot of the filtering here is copied of platform/sdl/event.c,
 * as it is scheduled for deprecation, we've not bothered designing
 * an interface for the axis bits to be shared. For future refactoring,
 * the basic signalling processing, e.g. determining device orientation
 * from 3-sensor + Kalman, user-configurable analog filters on noisy
 * devices etc. should be generalized and put in a shared directory,
 * and re-used for other input platforms.
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
#include <poll.h>
#include <glob.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <linux/input.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#include <sys/inotify.h>

/*
 * prever scanning device nodes as sysfs/procfs
 * and friends should not be needed to be mounted/exposed.
 */
#ifndef NOTIFY_SCAN_DIR
#define NOTIFY_SCAN_DIR "/dev/input"
#endif

/*
 * need a reasonable limit on the amount of allowed
 * devices, should this become a problem -- whitelist
 */
#define MAX_DEVICES 256

struct arcan_devnode;
#include "device_db.h"

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

	size_t n_devs, sz_nodes;

	unsigned short mouseid;
	struct arcan_devnode* nodes;

	struct pollfd* pollset;
} iodev = {0};

struct arcan_devnode {
	int handle;

/* NULL&size terminated, with chain-block set of the previous
 * one could not handle. This is to cover devices that could
 * expose themselves as being aggregated KEY/DEV/etc. */
	devnode_decode_cb handler;

	char label[256];
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
			struct axis_opts flt[2];
		} cursor;
		struct {
			bool incomplete;
		} touch;
	};
};

static int notify_fd;

static struct arcan_devnode* lookup_devnode(int devid)
{
	if (devid < 0)
		devid = iodev.mouseid;

/* some other parts of the engine still sweep
 * device IDs due to event/platform legacy,
 * we split the devid namespace in two so that
 * the devids we return are outside MAX_DEVICES */
	if (devid < iodev.n_devs)
		return &iodev.nodes[devid];

	for (size_t i = 0; i < iodev.n_devs; i++){
		if (iodev.nodes[i].devnum == devid)
			return &iodev.nodes[i];
	}

	return NULL;
}

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

static struct axis_opts* find_axis(int devid, int axisid)
{
	struct arcan_devnode* node = lookup_devnode(devid);
	axisid = abs(axisid);

	if (!node)
		return NULL;

	switch(node->type){
	case DEVNODE_SENSOR:
		return &node->sensor.data;
	break;

	case DEVNODE_GAME:
		if (axisid < node->game.axes)
			return &node->game.adata[axisid];
	break;

	case DEVNODE_MOUSE:
		if (axisid == 0)
			return &node->cursor.flt[0];
		else if (axisid == 1)
			return &node->cursor.flt[1];
	break;

	default:
	break;
	}

	return NULL;
}

arcan_errc arcan_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
	struct axis_opts* axis = find_axis(devid, axisid);

	if (!axis){
		struct arcan_devnode* node = lookup_devnode(devid);
		return node ? ARCAN_ERRC_BAD_RESOURCE : ARCAN_ERRC_NO_SUCH_OBJECT;
	}

	*lower_bound = axis->lower;
	*upper_bound = axis->upper;
	*deadzone = axis->deadzone;
	*kernel_size = axis->kernel_sz;
	*mode = axis->mode;

	return ARCAN_OK;
}

void arcan_event_analogall(bool enable, bool mouse)
{
	struct arcan_devnode* node = lookup_devnode(iodev.mouseid);
	if (!node)
		return;

/*
 * sweep all devices and all axes (or just mouseid)
 * if (enable) then set whatever the previous mode was,
 * else store current mode and set NONE
 */
}

void arcan_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
	struct axis_opts* axis = find_axis(devid, axisid);
	if (!axis)
		return;

	int kernel_lim = sizeof(axis->flt_kernel) / sizeof(axis->flt_kernel[0]);

	if (buffer_sz > kernel_lim)
		buffer_sz = kernel_lim;

	if (buffer_sz <= 0)
		buffer_sz = 1;

	set_analogstate(axis,lower_bound, upper_bound, deadzone, buffer_sz, kind);
}

void platform_event_process(struct arcan_evctx* ctx)
{
	bool more = false;

	if (notify_fd > 0){
		struct inotify_event ebuf[ 64 ];
		ssize_t nr = read(notify_fd, ebuf, sizeof(ebuf) );
		if (-1 != nr)
			for (size_t i = 0; i < nr / sizeof(struct inotify_event); i++){
				if (ebuf[i].mask & IN_DELETE){
/* FIXME: sweep existing devices for matching name,
 * disconnect handle (but remain last known data) */
				}
				if (ebuf[i].mask & IN_CREATE){
/* FIXME: sweep existing devices for matching name,
 * try adopt_device or got_device. Seems that name field isn't
 * always valid? */
				}
			}

		more = nr == sizeof(ebuf);
	}

	if (poll(iodev.pollset, iodev.n_devs, 0) > 0){
		for (size_t i = 0; i < iodev.n_devs; i++)
			if (iodev.pollset[i].revents & POLLIN)
				iodev.nodes[i].handler(ctx, &iodev.nodes[i]);
	}

	if (more)
		platform_event_process(ctx);
}

/*
 * poll all open FDs
 */
void platform_key_repeat(struct arcan_evctx* ctx, unsigned int rate)
{
/* FIXME: map repeat information,
 * this should be deprecated and moved to a script basis */
}

#define bit_longn(x) ( (x) / (sizeof(long)*8) )
#define bit_ofs(x) ( (x) % (sizeof(long)*8) )
#define bit_isset(ary, bit) (( ary[bit_longn(bit)] >> bit_ofs(bit)) & 1)
#define bit_count(x) ( ((x) - 1 ) / (sizeof(long) * 8 ) + 1 )

static size_t button_count(int fd, size_t bitn, bool* got_mouse, bool* got_joy)
{
	size_t count = 0;

	unsigned long bits[ bit_count(KEY_MAX) ];

	if (-1 == ioctl(fd, EVIOCGBIT(bitn, KEY_MAX), bits))
		return false;

	for (size_t i = 0; i < KEY_MAX; i++){
		if (bit_isset(bits, i)){
			count++;
		}
	}

	*got_mouse = (bit_isset(bits, BTN_MOUSE) || bit_isset(bits, BTN_LEFT) ||
		bit_isset(bits, BTN_RIGHT) || bit_isset(bits, BTN_MIDDLE));

	*got_joy = (bit_isset(bits, BTN_JOYSTICK) || bit_isset(bits, BTN_GAMEPAD) ||
		bit_isset(bits, BTN_WHEEL));

	return count;
}

static bool check_mouse_axis(int fd, size_t bitn)
{
	unsigned long bits[ bit_count(KEY_MAX) ];
	if (-1 == ioctl(fd, EVIOCGBIT(bitn, KEY_MAX), bits))
		return false;

/* uncertain if other (REL_Z, REL_RX,
 * REL_RY, REL_RZ, REL_DIAL, REL_MISC) should be used
 * as a failing criteria */
	return bit_isset(bits, REL_X) && bit_isset(bits, REL_Y);
}

static void map_axes(int fd, size_t bitn, struct arcan_devnode* node)
{
	unsigned long bits[ bit_count(ABS_MAX) ];

	if (-1 == ioctl(fd, EVIOCGBIT(bitn, ABS_MAX), bits))
		return;

	assert(node->type == DEVNODE_GAME);
	if (node->game.adata)
		return;

	node->game.axes = 0;

	for (size_t i = 0; i < ABS_MAX; i++){
		if (bit_isset(bits, i))
			node->game.axes++;
	}

	if (node->game.axes == 0)
		return;

	node->game.adata = malloc(sizeof(struct axis_opts) * node->game.axes);
	size_t ac = 0;

	for (size_t i = 0; i < ABS_MAX; i++)
		if (bit_isset(bits, i)){
			struct input_absinfo ainf;
			struct axis_opts* ax = &node->game.adata[ac++];

			memset(ax, '\0', sizeof(struct axis_opts));
			ax->mode = ax->oldmode = ARCAN_ANALOGFILTER_AVG;
			ax->lower = -32768;
			ax->upper = 32767;

			if (-1 == ioctl(fd, EVIOCGABS(i), &ainf))
				continue;

			ax->upper = ainf.maximum;
			ax->lower = ainf.minimum;
			assert(ainf.maximum != ainf.minimum && ainf.maximum > ainf.minimum);
		}
}

static void got_device(int fd)
{
	struct arcan_devnode node = {
		.handle = fd
	};

	if (iodev.n_devs >= MAX_DEVICES)
		goto cleanup;

	if (-1 == ioctl(fd, EVIOCGNAME(sizeof(node.label)), node.label))
		goto cleanup;

	struct input_id nodeid;
	if (-1 == ioctl(fd, EVIOCGID, &nodeid))
		goto cleanup;

/* didn't find much on how unique eviocguniq actually was,
 * nor common lengths or what not so just mix them in a buffer,
 * hash and let unsigned overflow modulo take us down to 16bit */
	char buf[12] = {0};
	char bbuf[sizeof(buf)] = {0};

/* some test devices here answered to the ioctl and returned
 * full empty UNIQs, do something to lower the likelihood of
 * collisions */
	if (-1 == ioctl(fd, EVIOCGUNIQ(sizeof(buf)), buf) ||
		memcmp(buf, bbuf, sizeof(buf)) == 0){
		size_t len = strlen(node.label);

		len = len >= sizeof(buf) ? sizeof(buf)-1 : len;
		memcpy(buf, node.label, len);

	 	buf[0] ^= nodeid.vendor >> 8;
		buf[1] ^= nodeid.vendor;
		buf[2] ^= nodeid.product >> 8;
		buf[3] ^= nodeid.product;
		buf[4] ^= nodeid.version >> 8;
		buf[5] ^= nodeid.version;
	}

	unsigned long hash = 5381;
	for (size_t i = 0; i < sizeof(buf); i++)
		hash = ((hash << 5) + hash) + buf[i];

	node.devnum = hash;
	if (node.devnum < MAX_DEVICES)
		node.devnum += MAX_DEVICES;

/* figure out what kind of a device this is from the exposed
 * capabilities, heuristic nonsense rather than an interface
 * exposing what the driver already knows, fantastic.
 *
 * keyboards typically have longer key masks (and we can
 * check for a few common ones) no REL/ABS (don't know
 * if those built-in trackball ones expose as two devices
 * or not these days), but also a ton of .. keys
 */
	struct evhandler eh = lookup_dev_handler(node.label);

	/* we assume this by default since it covers a whole lot
	 * of buttons / axes / calibration */
	node.type = DEVNODE_GAME;

	size_t btn_count = 0;

	bool mouse_ax = false;
	bool mouse_btn = false;
	bool joystick_btn = false;

	if (!eh.handler){
		size_t bpl = sizeof(long) * 8;
		size_t nbits = ((EV_MAX)-1) / bpl + 1;
		long prop[ nbits ];

		if (-1 == ioctl(fd, EVIOCGBIT(0, EV_MAX), &prop))
			goto cleanup;

		for (size_t bit = 0; bit < EV_MAX; bit++)
			if ( 1ul & (prop[bit/bpl]) >> (bit & (bpl - 1)) )
			switch(bit){
			case EV_KEY:
				btn_count = button_count(fd, bit, &mouse_btn, &joystick_btn);
			break;

			case EV_REL:
				mouse_ax = check_mouse_axis(fd, bit);
			break;

			case EV_ABS:
				map_axes(fd, bit, &node);
			break;

/* useless for the time being */
			case EV_MSC:
			break;
			case EV_SYN:
			break;
			case EV_LED:
			break;
			case EV_SND:
			break;
			case EV_REP:
			break;
			case EV_PWR:
			break;
			case EV_FF:
			case EV_FF_STATUS:
			break;
			}

		if (mouse_ax && mouse_btn){
			node.type = DEVNODE_MOUSE;
			node.cursor.flt[0].mode = ARCAN_ANALOGFILTER_PASS;
			node.cursor.flt[1].mode = ARCAN_ANALOGFILTER_PASS;

			if (!iodev.mouseid)
				iodev.mouseid = node.devnum;
		}
/* not particularly pretty and rather arbitrary */
		else if (!mouse_btn && !joystick_btn && btn_count > 84)
			node.type = DEVNODE_KEYBOARD;
	}
	else
		node.type = eh.type;

	node.handler = defhandlers[node.type];
	iodev.n_devs++;

/* grow / allocate the first time */
	if (iodev.n_devs >= iodev.sz_nodes){
		size_t new_sz = iodev.sz_nodes + 8;
		char* buf = realloc(iodev.nodes,
			sizeof(struct arcan_devnode) * new_sz);

		iodev.nodes = (struct arcan_devnode*) buf;

		if (!buf)
			goto cleanup;

		buf = realloc(iodev.pollset,
			sizeof(struct pollfd) * new_sz);

		if (!buf)
			goto cleanup;

		iodev.pollset = (struct pollfd*) buf;

		iodev.sz_nodes = new_sz;
	}

	off_t ofs = iodev.n_devs - 1;

	memset(&iodev.nodes[ofs], '\0', sizeof(struct arcan_devnode));
	memset(&iodev.pollset[ofs], '\0', sizeof(struct pollfd));

	iodev.pollset[ofs].fd = fd;
	iodev.pollset[ofs].events = POLLIN;

	iodev.nodes[iodev.n_devs-1] = node;
	return;

cleanup:
	iodev.n_devs--;
	close(fd);
}

#undef bit_isset
#undef bit_ofs
#undef bit_longn
#undef bit_count

void arcan_event_rescan_idev(struct arcan_evctx* ctx)
{
/* option is to add more namespaces here and have a
 * unique got_device for each of them to handle specific
 * APIs eg. old- style js0 (are they relevant anymore?) */
	char* namespaces[] = {
		"event",
		NULL
	};

/*
 * FIXME: doesn't implement repeated calls to rescan yet
 */

	char** cns = namespaces;

	while(*cns){
		char ibuf [strlen(*cns) + strlen(NOTIFY_SCAN_DIR) + sizeof("/*")];
		glob_t res = {0};
		snprintf(ibuf, sizeof(ibuf) / sizeof(ibuf[0]),
			"%s/%s*", NOTIFY_SCAN_DIR, *cns);

		if (glob(ibuf, 0, NULL, &res) == 0){
			char** beg = res.gl_pathv;

			while(*beg){
				int fd = open(*beg, O_NONBLOCK | O_RDONLY | O_CLOEXEC);
				if (-1 != fd)
					got_device(fd);
				beg++;
			}

			cns++;
		}
	}

}

static void defhandler_kbd(struct arcan_evctx* out,
	struct arcan_devnode* node)
{
	struct input_event inev[64];
	ssize_t evs = read(node->handle, &inev, sizeof(inev));
	if (evs < 0 || evs < sizeof(struct input_event))
		return;

	arcan_event newev = {
		.category = EVENT_IO,
		.data.io = {
			.datatype = EVENT_IDATATYPE_TRANSLATED,
			.devkind = EVENT_IDEVKIND_KEYBOARD,
			.input.translated = {
				.devid = node->devnum
			}
		}
	};

	for (size_t i = 0; i < evs / sizeof(struct input_event); i++){
		switch(inev[i].type){
		case EV_KEY:
		newev.data.io.input.translated.scancode = inev[i].code;
		newev.data.io.input.translated.keysym = inev[i].code;
		newev.kind = inev[i].value ? EVENT_IO_KEYB_PRESS : EVENT_IO_KEYB_RELEASE;

/* FIXME: try and fill out more fields (subid, ...) */
		arcan_event_enqueue(out, &newev);
		break;

		default:
		break;
		}

	}
}

static void defhandler_game(struct arcan_evctx* out,
	struct arcan_devnode* node)
{
	struct input_event inev[64];
	ssize_t evs = read(node->handle, &inev, sizeof(inev));
	if (evs < 0 || evs < sizeof(struct input_event))
		return;

/* FIXME: missing mapping to game device,
 * should be very similar to mouse code below */
}

static inline short code_to_mouse(int code)
{
	return (code < BTN_MOUSE || code >= BTN_JOYSTICK) ?
		-1 : (code - BTN_MOUSE + 1);
}

static void defhandler_mouse(struct arcan_evctx* ctx,
	struct arcan_devnode* node)
{
	struct input_event inev[64];

	ssize_t evs = read(node->handle, &inev, sizeof(inev));
	if (evs < 0 || evs < sizeof(struct input_event))
		return;

	arcan_event newev = {
		.category = EVENT_IO,
		.label = "mouse",
		.data.io = {
			.devkind = EVENT_IDEVKIND_MOUSE,
		}
	};

	short samplev;

	for (size_t i = 0; i < evs / sizeof(struct input_event); i++){
		switch(inev[i].type){
		case EV_KEY:
			samplev = code_to_mouse(inev[i].code);
			if (samplev < 0)
				continue;

			newev.kind = EVENT_IO_BUTTON_PRESS;
			newev.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newev.data.io.input.digital.active = inev[i].value;
			newev.data.io.input.digital.subid = samplev;
			newev.data.io.input.digital.devid = node->devnum;

			arcan_event_enqueue(ctx, &newev);
		break;
		case EV_REL:
			switch (inev[i].code){
			case REL_X:
				if (process_axis(ctx, &node->cursor.flt[0], inev[i].value, &samplev)){
					samplev = inev[i].value;

					node->cursor.mx = ((int)node->cursor.mx + samplev < 0) ?
						0 : node->cursor.mx + samplev;
					node->cursor.mx = node->cursor.mx > arcan_video_display.width ?
						arcan_video_display.width : node->cursor.mx;

					newev.kind = EVENT_IO_AXIS_MOVE;
					newev.data.io.datatype = EVENT_IDATATYPE_ANALOG;
					newev.data.io.input.analog.gotrel = true;
					newev.data.io.input.analog.subid = 0;
					newev.data.io.input.analog.devid = node->devnum;
					newev.data.io.input.analog.axisval[0] = node->cursor.mx;
					newev.data.io.input.analog.axisval[1] = samplev;
					newev.data.io.input.analog.nvalues = 2;

					arcan_event_enqueue(ctx, &newev);
				}
			break;
			case REL_Y:
				if (process_axis(ctx, &node->cursor.flt[1], inev[i].value, &samplev)){
					node->cursor.my = ((int)node->cursor.my + samplev < 0) ?
						0 : node->cursor.my + samplev;
					node->cursor.my = node->cursor.my > arcan_video_display.width ?
						arcan_video_display.width : node->cursor.my;

					newev.kind = EVENT_IO_AXIS_MOVE;
					newev.data.io.datatype = EVENT_IDATATYPE_ANALOG;
					newev.data.io.input.analog.gotrel = true;
					newev.data.io.input.analog.subid = 1;
					newev.data.io.input.analog.devid = node->devnum;
					newev.data.io.input.analog.axisval[0] = node->cursor.my;
					newev.data.io.input.analog.axisval[1] = samplev;
					newev.data.io.input.analog.nvalues = 2;

					arcan_event_enqueue(ctx, &newev);
				}
			break;
			default:
			break;
			}
		break;
		case EV_ABS:
		break;
		}
	}
}

static void defhandler_null(struct arcan_evctx* out,
	struct arcan_devnode* node)
{
	char nbuf[256];
	read(node->handle, nbuf, sizeof(nbuf));
}

const char* arcan_event_devlabel(int devid)
{
	if (devid == -1)
		return "mouse";

	if (devid < 0 || devid >= iodev.n_devs)
		return "no device";

	return strlen(iodev.nodes[devid].label) == 0 ?
		"no identifier" : iodev.nodes[devid].label;
}

void platform_event_deinit(struct arcan_evctx* ctx)
{
	/*
	 * kill descriptors and pollset
	 * keep source paths in order to rebuild (adopt style),
	 * as the primary purpose for this call is to free- up
	 * locks before switching to external control
	 */
}

void platform_device_lock(int devind, bool state)
{
	struct arcan_devnode* node = lookup_devnode(devind);
	if (!node || !node->handle)
		return;

	ioctl(node->handle, EVIOCGRAB, state? 1 : 0);

/*
 * doesn't make sense outside some window systems,
 * might be useful to propagate further to device locking
 * on systems that are less forgiving.
 */
}

void platform_event_init(arcan_evctx* ctx)
{
	notify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);

	if (-1 == notify_fd || inotify_add_watch(
		notify_fd, NOTIFY_SCAN_DIR, IN_CREATE | IN_DELETE) == -1){
		arcan_warning("inotify initialization failure (%s),"
			"	device discovery disabled.", strerror(errno));

		if (notify_fd > 0){
			close(notify_fd);
			notify_fd = 0;
		}
	}

	arcan_event_rescan_idev(ctx);
}

