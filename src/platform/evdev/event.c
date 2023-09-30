/*
 * Copyright 2014-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <inttypes.h>
#include <stdio.h>
#include <errno.h>
#include <poll.h>
#include <glob.h>

#include <sys/types.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <linux/input.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_led.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "keycode_xlate.h"

#ifdef HAVE_XKBCOMMON
static struct xkb_context* xkb_context;
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-compose.h>
#endif

#ifndef __FreeBSD__
#include <sys/inotify.h>
#endif

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

#define debug_print(fmt, ...) \
            do { if (DEBUG) arcan_warning("[%lld]%s:%d:%s(): " fmt "\n", \
						arcan_timemillis(), "evdev:", __LINE__, __func__,##__VA_ARGS__); \
						} while (0)

#define verbose_print

/*
 * scan / probe a node- dir (ENVV overridable)
 */
#ifndef NOTIFY_SCAN_DIR
#define NOTIFY_SCAN_DIR "/dev/input"
#endif

static char* notify_scan_dir;

/*
 * In happy-fun everything is user-space land, we face the policy problem of
 * device nodes not being created with the desired permissions in an atomic
 * manner. Combine with inotify and we may beat some deaemon to the races and
 * there we go. For EACCES we go the 'retry a little later' route.
 */
static const int default_eacces_tries = 8;
static const int default_eacces_delay = 1000;

static struct {
	char* path;
	int tries;
	int64_t last_ts;
} pending[8];

static struct {
	bool mute, init;
	int tty, notify;
	int pending;
}
gstate = {

	.notify = -1,
};

static const char* envopts[] = {
	"scandir=path/to/folder", "Directory to monitor for device node hotplug "
		"(Default: "NOTIFY_SCAN_DIR")",
	"disable_ttyswap", "Disable tty- swapping signal handler",
	"[evdev_type=label]", "suffix evdev_type with _n for (n = 2, 3, ...)",
	"evdev_keyboard=label", "Force device matching 'label' as a keyboard",
	"evdev_game=label", "Force device matching 'label' as a game device",
	"evdev_mouse=label", "Force device matching 'label' as a mouse",
#ifdef HAVE_XKBCOMMON
	"", "",
	"[XKB db keys]", "(libkbcommon specific, no ARCAN_ env prefix)",
	"event_xkb_rules", "Ruleset (evdev)",
	"event_xkb_variant", "Variant within the keymap (intl,dvorak)",
	"event_xkb_model", "Keyboard model (pc105)",
	"event_xkb_layout", "Layout groups (fr,us)",
	"event_xkb_options", "Mapping options (ctrl:nocaps)",
	"[XKB-ENVVARS]", "(might be blocked by suid, libxkbcommon)",
	"XKB_DEFAULT_LAYOUT=lang", "enable XKB translation maps for keyboards",
	"XKB_DEFAULT_VARIANT=variant", "define XKB layout variant",
	"XKB_DEFAULT_MODEL=pc101", "define XKB keyboard model",
	"XKB_DEFAULT_RULES=evdev", "define XKB ruleset",
#endif
	NULL
};

/*
 * need a reasonable limit on the amount of allowed devices, should this become
 * a problem -- whitelist. See lookup_devnode for an explanation on the problem
 * with devid-.
 */
#define MAX_DEVICES 256

#define MAX_MT_SLOTS 5

struct devnode;
#include "device_db.h"

struct axis_opts {
/* none, avg, drop */
	enum ARCAN_ANALOGFILTER_KIND mode;
	enum ARCAN_ANALOGFILTER_KIND oldmode;

	int lower, upper, deadzone;

/* we won't get access to a good range distribution if we don't emit the first
 * / last sample that got into the drop range */
	bool inlzone, inuzone, indzone;

	int kernel_sz;
	int kernel_ofs;
	int32_t flt_kernel[64];
};

static struct {
	size_t n_devs, sz_nodes;

/* repeat is currently enforced uniformly across all keyboards, might be
 * usecases where this is not preferable but there is no higher-level api
 * that provides this granularity. */
	unsigned period, delay;

	unsigned short mouseid;
	struct devnode* nodes;

	struct pollfd* pollset;
} iodev = {0};

struct devnode {
	int handle;

/* NULL&size terminated, with chain-block set of the previous one could not
 * handle. This is to cover devices that could expose themselves as being
 * aggregated KEY/DEV/etc. */
	struct evhandler hnd;

	char label[256];
	char* path;
	unsigned short devnum;
	size_t button_count;

	enum devnode_type type;
	union {
		struct {
			struct axis_opts data;
		} sensor;
		struct {
			unsigned short axes;
			unsigned short buttons;
			unsigned short relofs;
			char hats[16];
			struct axis_opts* adata;
		} game;
		struct {
			uint16_t mx;
			uint16_t my;
			struct axis_opts flt[2];
		} cursor;
		struct {
			unsigned state;
#ifdef HAVE_XKBCOMMON
			struct xkb_keymap* xkb_layout;
			struct xkb_state* xkb_state;
#endif
		} keyboard;
	};
/* because in this universe, pretty much any normal input device can
 * also have a touch display. */
	struct {
		bool active;
		bool pending;
		int x[MAX_MT_SLOTS];
		int y[MAX_MT_SLOTS];
		int pressure;
		int size;
		int ind;
	} touch;

/* and also possible act as a LED controller */
	struct {
		bool gotled;
		int ctrlid;
		int ind;
		int fds[2];
	} led;
};

static void got_device(struct arcan_evctx* ctx, int fd, const char*);

/* for other platforms and legacy, devid used to be allocated sequentially
 * and swept linear, even though this platform do not work like that and we
 * have a dynamic set of devices. For this reason, we split the 16 bit space
 * into < MAX_DEVICES and >= MAX_DEVICES and a device a can be accessed by
 * either id */
static struct devnode* lookup_devnode(int devid)
{
	if (devid <= 0)
		devid = iodev.mouseid;

	if (devid < iodev.sz_nodes){
		verbose_print("lookup(%d) => %"PRIxPTR, devid, &iodev.nodes[devid]);
		return &iodev.nodes[devid];
	}

	for (size_t i = 0; i < iodev.sz_nodes; i++){
		if (iodev.nodes[i].devnum == devid){
			verbose_print("lookup(%d:%zu) => %"PRIxPTR, devid, i, &iodev.nodes[i]);
			return &iodev.nodes[i];
		}
	}

	verbose_print("%zu => %d", devid, -1);
	return NULL;
}

/* another option to this mess (as the hashing thing doesn't seem to work out
 * is to move identification/etc. to another level and just let whatever device
 * node generator is active populate with coherent names. and use a hash of that
 * name as the ID */
static bool identify(int fd, const char* path,
	char* label, size_t label_sz, unsigned short* dnum)
{
	if (-1 == ioctl(fd, EVIOCGNAME(label_sz), label)){
		debug_print("input/identify: bad EVIOCGNAME, setting unknown\n");
		snprintf(label, label_sz, "unknown");
	}
	else
		verbose_print(
			"input/identify(%d): %s name resolved to %s", fd, path, label);

	struct input_id nodeid;
	if (-1 == ioctl(fd, EVIOCGID, &nodeid)){
		debug_print(
			"input/identify(%d): no EVIOCGID, reason:%s", fd, strerror(errno));
		return false;
	}

/*
 * first, check if any other subsystem knows about this one and ignore if so
 */
	if (arcan_led_known(nodeid.vendor, nodeid.product)){
		debug_print(
			"led subsys know %d, %d\n", (int)nodeid.vendor, (int)nodeid.product);
		arcan_led_init();
		return false;
	}

/* didn't find much on how unique eviocguniq actually was, nor common lengths
 * or what not so just mix them in a buffer, hash and let unsigned overflow
 * modulo take us down to 16bit */
	size_t bpl = sizeof(long) * 8;
	size_t nbits = ((EV_MAX)-1) / bpl + 1;

	char buf[12 + nbits * sizeof(long)];
	char bbuf[sizeof(buf)];
	memset(buf, '\0', sizeof(buf));
	memset(bbuf, '\0', sizeof(bbuf));

/* some test devices here answered to the ioctl and returned full empty UNIQs,
 * do something to lower the likelihood of collisions */
	unsigned long hash = 5381;

	if (-1 == ioctl(fd, EVIOCGUNIQ(sizeof(buf)), buf) ||
		memcmp(buf, bbuf, sizeof(buf)) == 0){

		size_t llen = strlen(label);
		for (size_t i = 0; i < llen; i++)
			hash = ((hash << 5) + hash) + label[i];

		llen = strlen(path);
		for (size_t i = 0; i < llen; i++)
			hash  = ((hash << 5) + hash) + path[i];

		buf[11] ^= nodeid.vendor >> 8;
		buf[10] ^= nodeid.vendor;
		buf[9] ^= nodeid.product >> 8;
		buf[8] ^= nodeid.product;
		buf[7] ^= nodeid.version >> 8;
		buf[6] ^= nodeid.version;

/* even this point has a few collisions, particularly some keyboards and mice
 * that don't respond to CGUNIQ and expose multiple- subdevices but with
 * different button/axis count */
		ioctl(fd, EVIOCGBIT(0, sizeof(buf)), &buf);
	}

	for (size_t i = 0; i < sizeof(buf); i++)
		hash = ((hash << 5) + hash) + buf[i];

/* 16-bit clamp is legacy in the scripting layer, also leave the highest
 * bit unset as that is reserved for synthetic devices */
	hash &= 0xfffe;
	if (hash < MAX_DEVICES)
		hash += MAX_DEVICES;

/* scan for collisions, if there is one, random and repeat. We lose
 * repeatability but don't risk collision-disconnect spam */
	for (ssize_t i = 0; i < iodev.sz_nodes; i++){
		while (hash == iodev.nodes[i].devnum){
			uint16_t rv;
			arcan_random((uint8_t*)&rv, 2);
			hash = rv & (uint16_t) 0xfffe;
			if (hash < MAX_DEVICES)
				hash += MAX_DEVICES;
			if (i)
				i -= 1;
			continue;
		}
	}

	*dnum = hash;

	return true;
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

static struct axis_opts* find_axis(int devid, unsigned axisid, bool* outn)
{
	struct devnode* node = lookup_devnode(devid);
	*outn = node != NULL;

	if (!node)
		return NULL;

	switch(node->type){
	case DEVNODE_SENSOR:
		return axisid == 0 ? &node->sensor.data : NULL;
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

arcan_errc platform_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
	bool gotnode;
	struct axis_opts* axis = find_axis(devid, axisid, &gotnode);

	if (!axis)
		return gotnode ?
			ARCAN_ERRC_BAD_RESOURCE : ARCAN_ERRC_NO_SUCH_OBJECT;

	*lower_bound = axis->lower;
	*upper_bound = axis->upper;
	*deadzone = axis->deadzone;
	*kernel_size = axis->kernel_sz;
	*mode = axis->mode;

	return ARCAN_OK;
}

void platform_event_analogall(bool enable, bool mouse)
{
	struct devnode* node = lookup_devnode(iodev.mouseid);
	if (!node)
		return;

/*
 * FIXME sweep all devices and all axes (or just mouseid) if (enable) then set
 * whatever the previous mode was, else store current mode and set NONE
 */
}

static void disconnect(struct arcan_evctx* ctx, struct devnode* node);
void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
/* this was added here rather than a separate entry-point to deal with backward
 * and forward compatiblity from an API angle */
	if (kind == ARCAN_ANALOGFILTER_FORGET){
		struct devnode* node = lookup_devnode(devid);

/* this is also a piece of legacy, other functions operate on an explicit
 * context, but there is really only one */
		if (node)
			disconnect(arcan_event_defaultctx(), node);
		return;
	}

	bool node;
	struct axis_opts* axis = find_axis(devid, axisid, &node);
	if (!axis)
		return;

	int kernel_lim = sizeof(axis->flt_kernel) / sizeof(axis->flt_kernel[0]);

	if (buffer_sz > kernel_lim)
		buffer_sz = kernel_lim;

	if (buffer_sz <= 0)
		buffer_sz = 1;

	set_analogstate(axis,lower_bound, upper_bound, deadzone, buffer_sz, kind);
}

static bool discovered(struct arcan_evctx* ctx,
	const char* name, size_t name_len, bool nopending)
{
	char buffer[name_len+sizeof(notify_scan_dir)];
	char outbuffer[MAXPATHLEN];

/* need to resolve a symlink if there is one as the platform_device_open
 * has a whitelist that is rather picky about which devices it will open */
	snprintf(buffer, sizeof(buffer), "%s/%.*s", notify_scan_dir, (int)name_len, name);

	TRACE_MARK_ENTER("event", "open-device", TRACE_SYS_DEFAULT, 0, 0, name);

	int fd = platform_device_open(
		readlink(buffer, outbuffer, sizeof(outbuffer)) > 0 ?
			outbuffer : buffer, O_NONBLOCK| O_RDWR);

	TRACE_MARK_EXIT("event", "open-device", TRACE_SYS_DEFAULT, 0, fd, name);

	verbose_print("input: trying to add %s/%.*s",
		notify_scan_dir, (int)name_len, name);

	if (-1 == fd && errno == EACCES){
		if (gstate.pending >= COUNT_OF(pending)){
			debug_print(
				"input: pending queue limit exceeded, possibly something wrong"
				" with monitored folder (%s) and permissions.", notify_scan_dir
			);
			return false;
		}

/* already know about this one */
		if (nopending)
			return false;

/* sign that someone is impatient and plugging / unplugging while pending */
		size_t i;
		ssize_t j = -1;
		for (i = 0; i < COUNT_OF(pending); i++){
			if (!pending[i].path && j == -1)
				j = i;
			if (pending[i].path && strcmp(name, pending[i].path) == 0)
				return false;
		}
/* name comes from inotify which does not have to terminate */
		gstate.pending++;
		pending[j].path = malloc(name_len + 1);
		sprintf(pending[j].path, "%.*s", (int)name_len, name);
		pending[j].tries = default_eacces_tries;
		pending[j].last_ts = arcan_frametime();
		return false;
	}

/* even if we can access it and it is of the right type, it is not certain
 * that we can actually identify and use it according with evdev */
	if (-1 != fd){
		got_device(ctx, fd, name);
		return true;
	}
	else
		arcan_warning("input: couldn't open new device (%s), reason: %s\n",
			name, strerror(errno));
	return false;
}

static void process_pending(struct arcan_evctx* ctx)
{
	for (size_t i = 0; i < COUNT_OF(pending); i++){
		if (!pending[i].path)
			continue;

/* wait a little longer for each failed attempt */
		if (arcan_frametime() - pending[i].last_ts < (default_eacces_tries -
			pending[i].tries + 1) * default_eacces_delay)
			continue;

		pending[i].last_ts = arcan_frametime();

		if (discovered(ctx, pending[i].path, strlen(pending[i].path), true)){
			free(pending[i].path);
			pending[i].path = NULL;
			gstate.pending--;
		}
		else{
			pending[i].tries--;
			if (pending[i].tries <= 0){
				arcan_warning("input(eperm): device(%s) retry count"
					"exceeded\n", pending[i].path);
				free(pending[i].path);
				pending[i].path = NULL;
				gstate.pending--;
			}
		}
	}
}

static void disconnect(struct arcan_evctx* ctx, struct devnode* node)
{
	struct arcan_event addev = {
		.category = EVENT_IO,
		.io.kind = EVENT_IO_STATUS,
		.io.devid = node->devnum,
		.io.devkind = EVENT_IDEVKIND_STATUS,
		.io.input.status.devkind = node->type,
		.io.input.status.action = EVENT_IDEV_REMOVED
	};
	snprintf((char*) &addev.io.label, sizeof(addev.io.label) /
		sizeof(addev.io.label[0]), "%s", node->label);
	arcan_event_enqueue(ctx, &addev);

	for (size_t i = 0; i < iodev.sz_nodes; i++)
		if (node->devnum == iodev.nodes[i].devnum){
			close(node->handle);
			free(node->path);
			node->path = NULL;
			node->handle = -1;
			iodev.pollset[i].events = iodev.pollset[i].revents = 0;
			iodev.pollset[i].fd = -1;
			if (node->led.gotled){
				iodev.pollset[i+iodev.sz_nodes].fd = -1;
				iodev.pollset[i+iodev.sz_nodes].events =
					iodev.pollset[i+iodev.sz_nodes].revents = 0;
				node->led.gotled = false;
				arcan_led_remove(node->led.ctrlid);
				close(node->led.fds[0]);
				close(node->led.fds[1]);
				node->led.fds[0] = -1;
				node->led.fds[1] = -1;
			}
#ifdef HAVE_XKBCOMMON
			if (node->type == DEVNODE_KEYBOARD && node->keyboard.xkb_state){
				xkb_state_unref(node->keyboard.xkb_state);
				xkb_keymap_unref(node->keyboard.xkb_layout);
				node->keyboard.xkb_state = NULL;
				node->keyboard.xkb_layout = NULL;
			}
#endif
			iodev.n_devs--;
		}
}

static void do_led(struct devnode* node)
{
	if (!node->led.gotled){
		arcan_warning("evdev(), pollset corruption? POLLIN on node without LED\n");
		return;
	}

	uint8_t buf[2];
	bool set = false;

	while (2 == read(node->led.fds[0], buf, 2)){
		switch (tolower(buf[0])){
		case 'A': node->led.ind = -1; break;
		case 'a': node->led.ind = buf[1]; break;
/* not registered as a RGB led */
		case 'r': break;
		case 'g': break;
		case 'b': break;
		case 'i': set = buf[1] > 0; break;
		case 'c':
			if (node->led.ind == -1){
				for (size_t i = 0; i < LED_MAX; i++)
					if (-1 == write(node->handle, &(struct input_event){.type = EV_LED,
						.code = i, .value = set}, sizeof(struct input_event)))
						arcan_warning("platform/evdev: failed to write to led device\n");
			}
			else {
				if (-1 == write(node->handle, &(struct input_event){.type = EV_LED,
					.code = node->led.ind, .value = set}, sizeof(struct input_event)))
					arcan_warning("platform/evdev: failed to write to led device\n");
			}
		break;
		}
	}
}

void platform_event_process(struct arcan_evctx* ctx)
{
/* lovely little variable length field at end of struct here /sarcasm,
 * could get away with running the notify polling less often than once
 * every frame, somewhat excessive. */
#ifdef __FreeBSD__
#else
	if (-1 != gstate.notify){
		char inbuf[1024];
		ssize_t nr = read(gstate.notify, inbuf, sizeof(inbuf));
		off_t ofs = 0;

		if (-1 != nr)
			while (nr - ofs > sizeof(struct inotify_event)){
				struct inotify_event cur;
				memcpy(&cur, &inbuf[ofs], sizeof(struct inotify_event));
				ofs += sizeof(struct inotify_event);

				if ((cur.mask & IN_CREATE) && !(cur.mask & IN_ISDIR)){
					discovered(ctx, &inbuf[ofs], cur.len, false);
					ofs += cur.len;
				}
			}
	}
#endif
	TRACE_MARK_ENTER("event", "flush-pending-in", TRACE_SYS_DEFAULT, 0, 0, "flush-in");

	if (gstate.pending)
		process_pending(ctx);

	int nr = poll(iodev.pollset, iodev.sz_nodes * 2, 0);
	if (nr <= 0){
		TRACE_MARK_EXIT("event", "flush-pending-in", TRACE_SYS_FAST, 0, 0, "flush-in");
		return;
	}

	for (size_t i = 0; i < iodev.sz_nodes; i++){
/* recall, sz_nodes is half the count, i + sz_nodes = alt-dev index */
		if (iodev.pollset[i+iodev.sz_nodes].revents & POLLIN){
			do_led(&iodev.nodes[i]);
		}

		if (iodev.pollset[i].fd == -1 || 0 == iodev.pollset[i].revents)
			continue;

/* !POLLIN, then something is wrong, remove the node */
		if (0 == (iodev.pollset[i].revents & POLLIN)){
			disconnect(ctx, &iodev.nodes[i]);
			continue;
		}
/* some nodes may get a null handler temporarily or permanently assiged,
 * drain those for evdev structures */
		else {
			if (iodev.nodes[i].hnd.handler)
				iodev.nodes[i].hnd.handler(ctx, &iodev.nodes[i]);
			else{
				char dump[256];
				size_t nr __attribute__((unused));
				nr = read(iodev.nodes[i].handle, dump, 256);
			}
		}
	}
	TRACE_MARK_EXIT("event", "flush-pending-in", TRACE_SYS_DEFAULT, 0, 0, "flush-in");
}

void platform_event_samplebase(int devid, float xyz[3])
{
	struct devnode* node = lookup_devnode(devid);
	if (!node || node->type != DEVNODE_MOUSE)
		return;

	node->cursor.mx = xyz[0];
	node->cursor.my = xyz[1];
}

void platform_event_keyrepeat(struct arcan_evctx* ctx, int* period, int* delay)
{
	bool upd = false;

	if (*period < 0){
		*period = iodev.period;
	}
	else{
		int tmp = *period;
		*period = iodev.period;
		iodev.period = tmp;
		upd = true;
	}

	if (*delay < 0){
		*delay = iodev.delay;
	}
	else {
		int tmp = *delay;
		*delay = iodev.delay;
		iodev.delay = tmp;
		upd = true;
	}

	if (!upd)
		return;

	for (size_t i = 0; i < iodev.sz_nodes; i++)
		if (iodev.nodes[i].type == DEVNODE_KEYBOARD){
			struct input_event ev = {
				.type = EV_REP,
				.code = REP_DELAY,
				.value = *delay
			};
			if (-1 == write(iodev.nodes[i].handle,&ev,sizeof(struct input_event)))
				verbose_print("linux/event: keydelay fail (%s)\n", strerror(errno));

			ev.code = REP_PERIOD;
			ev.value = *period;
			if (-1 == write(iodev.nodes[i].handle,&ev,sizeof(struct input_event)))
				verbose_print("linux/event: keyrepeat fail (%s)\n", strerror(errno));
		}
}

static const char* lookup_type(int val)
{
	switch(val){
	case DEVNODE_GAME:
		return "game";
	case DEVNODE_MOUSE:
		return "mouse";
	case DEVNODE_SENSOR:
		return "sensor";
	case DEVNODE_KEYBOARD:
		return "keyboard";
	break;
	default:
	return "unknown";
	}
}

#define bit_longn(x) ( (x) / (sizeof(long)*8) )
#define bit_ofs(x) ( (x) % (sizeof(long)*8) )
#define bit_isset(ary, bit) (( ary[bit_longn(bit)] >> bit_ofs(bit)) & 1)
#define bit_count(x) ( ((x) - 1 ) / (sizeof(long) * 8 ) + 1 )

static size_t button_count(int fd, size_t bitn, bool* got_mouse, bool* got_joy)
{
	size_t count = 0;

	unsigned long bits[ bit_count(KEY_MAX) ];

	if (-1 == ioctl(fd, EVIOCGBIT(bitn, sizeof(bits)), bits))
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
	if (-1 == ioctl(fd, EVIOCGBIT(bitn, sizeof(bits)), bits))
		return false;

/* uncertain if other (REL_Z, REL_RX, REL_RY, REL_RZ, REL_DIAL, REL_MISC)
 * should be used as a failing criteria */
	return bit_isset(bits, REL_X) && bit_isset(bits, REL_Y);
}

static char* to_utf8(uint16_t utf16, uint8_t out[4])
{
	int count = 1, ofs = 0;
	uint32_t mask = 0x800;

	if (utf16 >= 0x80)
		count++;

	for(size_t i=0; i < 5; i++){
		if ( (uint32_t) utf16 >= mask )
			count++;

		mask <<= 5;
	}

	if (count == 1){
		out[0] = (char) utf16;
		out[1] = 0x00;
	}
	else {
		for (int i = (count-1 > 4 ? 4 : count - 1); i >= 0; i--){
			unsigned char ch = ( utf16 >> (6 * i)) & 0x3f;
			ch |= 0x80;
			if (i == count-1)
				ch |= 0xff << (8-count);
			out[ofs++] = ch;
		}
		out[ofs++] = 0x00;
	}

	return (char*) out;
}

static void map_axes(int fd, size_t bitn, struct devnode* node)
{
	unsigned long bits[ bit_count(ABS_MAX) ];
	unsigned long rel_bits[ bit_count(REL_MAX) ];

	assert(node->type == DEVNODE_GAME);
	if (node->game.adata)
		return;
	node->game.axes = 0;

	if (-1 != ioctl(fd, EVIOCGBIT(bitn, sizeof(bits)), bits)){
		for (size_t i = 0; i < ABS_MAX; i++){
			if (bit_isset(bits, i))
				node->game.axes++;
		}
	}

	node->game.relofs = node->game.axes;
	if (-1 != ioctl(fd, EVIOCGBIT(bitn, sizeof(rel_bits)), rel_bits)){
		for (size_t i = 0; i < REL_MAX; i++){
			if (bit_isset(bits, i)){
				node->game.axes++;
			}
		}
	}

	if (node->game.axes == 0)
		return;

	node->game.adata = arcan_alloc_mem(
		sizeof(struct axis_opts) * node->game.axes,
		ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

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
		}
}

/*
 * setup/register/prepare led- controller handler
 */
static void setup_led(struct devnode* dst, size_t bitn, int fd)
{
	unsigned long bits[ bit_count(LED_MAX) ];
	if (-1 == ioctl(fd, EVIOCGBIT(bitn, sizeof(bits)), bits))
		return;

	size_t count = 0;
	for (size_t i = 0; i < LED_MAX; i++){
		if (bit_isset(bits, i))
			count++;
	}

	if (!count)
		return;

	if (pipe(dst->led.fds) == -1)
		return;

	for (size_t i = 0; i < 2; i++){
		int flags = fcntl(dst->led.fds[i], F_GETFL);
		if (-1 != flags)
			fcntl(dst->led.fds[i], F_SETFL, flags | O_NONBLOCK);
		flags = fcntl(dst->led.fds[i], F_GETFD);
		if (-1 != flags)
			fcntl(dst->led.fds[i], F_SETFD, flags | FD_CLOEXEC);
	}

	char ledname[16];
	snprintf(ledname, 16, "%d_led", dst->devnum);
	dst->led.ctrlid = arcan_led_register(dst->led.fds[1], dst->devnum, ledname,
		(struct led_capabilities){ .nleds = LED_MAX,
			.variable_brightness = false, .rgb = false }
	);
	if (-1 == dst->led.ctrlid){
		close(dst->led.fds[0]);
		close(dst->led.fds[1]);
		dst->led.fds[0] = dst->led.fds[1] = -1;
		return;
	}
	dst->led.gotled = true;
/* reset */
	for (size_t i = 0; i < LED_MAX; i++){
		if (-1 == write(dst->handle, &(struct input_event){.type = EV_LED,
			.code = i, .value = 0}, sizeof(struct input_event)))
			arcan_warning("platform/evdev(), error sending reset to led device\n");
	}
}

static int xkb_layout_to_fd(struct xkb_keymap* layout, const char** err)
{
	if (!layout){
		*err = "no active map";
		return -1;
	}

	char* map = xkb_map_get_as_string(layout);
	if (!map){
		*err = "serialization request rejected";
		return -1;
	}

	int fd = arcan_strbuf_tempfile(map, strlen(map) + 1, err);
	return fd;
}

static int alloc_node_slot(const char* path)
{
/* pre-existing? close old node and replace with this one, happens
 * when we race and the device appears and reappears and we just need
 * to reference a new inode */
	int hole = -1;

	for (size_t i = 0; i < iodev.sz_nodes; i++){
		if (-1 == hole && iodev.nodes[i].handle < 0){
			hole = i;
			continue;
		}

/* or collision with existing? we use file-path for this. index
 * stays the same and got_device will still register so don't have
 * to consider leak for ledset */
		if (iodev.nodes[i].path && strcmp(iodev.nodes[i].path, path) == 0){
			close(iodev.nodes[i].handle);
			iodev.n_devs--;
			return i;
		}
	}

/* no empty slot, grow pollsets and node tracking */
	if (hole == -1){
		size_t new_cnt = iodev.sz_nodes + 8;
		struct devnode* nn = realloc(
			iodev.nodes, sizeof(struct devnode) * new_cnt);
		if (!nn)
			return -1;
		iodev.nodes = nn;
		memset(nn + iodev.sz_nodes, '\0', sizeof(struct devnode) * 8);
		for (size_t i = iodev.sz_nodes; i < new_cnt; i++){
			iodev.nodes[i].handle = BADFD;
			iodev.nodes[i].led.fds[0] = iodev.nodes[i].led.fds[1] = BADFD;
		}

/* pollset size is actually twice the number of nodes to allow a
 * 'mirror address' for a possible led- or other special device ref.
 * (say sound...) */
		struct pollfd* newset = malloc(2 * sizeof(struct pollfd) * new_cnt);
		if (!newset)
			return -1;

		free(iodev.pollset);
		for (size_t i = 0; i < new_cnt; i++){
			memset(&newset[i], '\0', sizeof(struct pollfd));
			memset(&newset[i+new_cnt], '\0', sizeof(struct pollfd));
			newset[i].events = POLLIN | POLLERR | POLLHUP;
			newset[i].fd = iodev.nodes[i].handle;
			newset[i+new_cnt].events = POLLIN;
			newset[i+new_cnt].fd = iodev.nodes[i].led.fds[0];
		}

/* update pointers, set hole to the first new entry */
		iodev.pollset = newset;
		hole = iodev.sz_nodes;
		iodev.sz_nodes = new_cnt;
	}

	return hole;
}

static void send_device_added(struct arcan_evctx* ctx, struct devnode* node)
{
	struct arcan_event addev = {
		.category = EVENT_IO,
		.io.kind = EVENT_IO_STATUS,
		.io.devkind = EVENT_IDEVKIND_STATUS,
		.io.devid = node->devnum,
		.io.input.status.devkind = node->type,
		.io.input.status.action = EVENT_IDEV_ADDED
	};
	snprintf((char*) &addev.io.label, sizeof(addev.io.label) /
		sizeof(addev.io.label[0]), "%s", node->label);
	arcan_event_enqueue(ctx, &addev);
}


int platform_event_translation(
	int devid, int action, const char** arg, const char** err)
{
	struct devnode* node = NULL;

/* find the n'th device on a negative id */
	if (devid < 0){
		devid *= -1;

		for (size_t i = 0; i < iodev.sz_nodes; i++){
			if (iodev.nodes[i].type == DEVNODE_KEYBOARD){
				devid--;
				if (!devid){
					node = &iodev.nodes[i];
					break;
				}
			}
		}
	}
	else
		node = lookup_devnode(devid);

	if (!node || node->type != DEVNODE_KEYBOARD){
		*err = "No such device";
		return false;
	}

#ifdef HAVE_XKBCOMMON
	char* rules = NULL;
	char* model = NULL;
	char* variant = NULL;
	char* options = NULL;
	char* layout = NULL;

	struct xkb_rule_names names = {0};

	if (!xkb_context){
		*err = "Missing XKB context";
		return false;
	}

/* Config takes priority - Then explicitly fill with environment,
 *
 * An omitted path here is to incrementally index keyboards and allow multiple
 * slots so different keyboards can get different layouts from the start. The
 * problem with this is the usual one of persistant IDs across instances as
 * anyone with a multiple keyboard setup that calls for different layouts
 * already have very .. exotic tastes.
 */
	if (action == EVENT_TRANSLATION_CLEAR){
		uintptr_t tag;
		cfg_lookup_fun get_config = platform_config_lookup(&tag);
		get_config("event_xkb_rules", 0, &rules, tag);
		get_config("event_xkb_variant", 0, &variant, tag);
		get_config("event_xkb_model", 0, &model, tag);
		get_config("event_xkb_options", 0, &options, tag);
		get_config("event_xkb_layout", 0, &layout, tag);

		names.rules = rules ? rules : getenv("XKB_DEFAULT_RULES");
		names.model = model ? model : getenv("XKB_DEFAULT_MODEL");
		names.variant = variant ? variant : getenv("XKB_DEFAULT_VARIANT");
		names.options = options ? options : getenv("XKB_DEFAULT_OPTIONS");
		names.layout = layout ? options : getenv("XKB_DEFAULT_LAYOUT");
	}
/* just fill struct from arg */
	else if (action == EVENT_TRANSLATION_SET ||
		action == EVENT_TRANSLATION_SERIALIZE_SPEC){
		names.layout = arg[0];
		if (names.layout)
			names.model = arg[1];
		if (names.model)
			names.variant = arg[2];
		if (names.variant)
			names.options = arg[3];
	}
	else if (action == EVENT_TRANSLATION_SERIALIZE_CURRENT){
		return xkb_layout_to_fd(node->keyboard.xkb_layout, err);
	}
	else {
		*err = "Unsupported action";
		return false;
	}

/* build the map and depending on if we should serialize or not, create a tmp
 * file, write the string to it, seek back and return the descriptor */
	struct xkb_keymap* map =
		xkb_keymap_new_from_names(xkb_context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);

	if (action == EVENT_TRANSLATION_SERIALIZE_SPEC){
		int fd = xkb_layout_to_fd(map, err);
		xkb_keymap_unref(map);
		return fd;
	}

	if (node->keyboard.xkb_layout){
		if (node->keyboard.xkb_state)
			xkb_state_unref(node->keyboard.xkb_state);
		xkb_keymap_unref(node->keyboard.xkb_layout);
		node->keyboard.xkb_state = NULL;
		node->keyboard.xkb_layout = NULL;
	}

	node->keyboard.xkb_layout = map;

/* Disable xkb translation entirely */
	if (!names.rules && !names.model &&
		!names.variant && !names.options && !names.layout)
		return false;

	if (node->keyboard.xkb_layout)
		node->keyboard.xkb_state = xkb_state_new(node->keyboard.xkb_layout);

	free(rules);
	free(model);
	free(variant);
	free(options);

	return true;
#endif

	*err = "Engine built without libxkbcommon support";
	return false;
}

int platform_event_device_request(int space, const char* path)
{
	return -EINVAL;
}

static void got_device(struct arcan_evctx* ctx, int fd, const char* path)
{
	struct devnode node = {
		.handle = fd,
		.led.fds = {BADFD, BADFD}
	};

	struct stat fdstat;
	if (-1 == fstat(fd, &fdstat)){
			verbose_print(
				"input: couldn't stat node to identify (%s)", strerror(errno));
		return;
	}

	if ((fdstat.st_mode & (S_IFCHR | S_IFBLK)) == 0){
			verbose_print(
				"input: ignoring %s, not a character or block device", path);
		return;
	}

	if (!identify(fd, path, node.label, sizeof(node.label), &node.devnum)){
			verbose_print(
				"input: identify failed on %s, ignoring unknown.", path);
		close(fd);
		return;
	}

	if (iodev.n_devs >= MAX_DEVICES){
		arcan_warning("input: device limit reached, ignoring %s.", path);
		close(fd);
	}

/* figure out what kind of a device this is from the exposed capabilities,
 * heuristic nonsense rather than an interface exposing what the driver should
 * know or decide, fantastic.
 *
 * keyboards typically have longer key masks (and we can check for a few common
 * ones) no REL/ABS (don't know if those built-in trackball ones expose as two
 * devices or not these days), but also a ton of .. keys
 */
	struct evhandler eh = lookup_dev_handler(node.label);

/* [eh] may contain overrides, but we still need to probe the driver state for
 * axes etc. and allocate accordingly */
	node.type = DEVNODE_GAME;

	bool mouse_ax = false;
	bool mouse_btn = false;
	bool joystick_btn = false;
	int add_led = -1;

	size_t bpl = sizeof(long) * 8;
	size_t nbits = ((EV_MAX)-1) / bpl + 1;
	long prop[ nbits ];

	if (-1 == ioctl(fd, EVIOCGBIT(0, sizeof(prop)), &prop)){
		verbose_print(
			"input: probing %s failed, %s", path, strerror(errno));
		close(fd);
		return;
	}

	for (size_t bit = 0; bit < EV_MAX; bit++)
		if ( 1ul & (prop[bit/bpl]) >> (bit & (bpl - 1)) )
		switch(bit){
		case EV_KEY:
			node.button_count = button_count(fd, bit, &mouse_btn, &joystick_btn);
		break;

		case EV_REL:
			mouse_ax = check_mouse_axis(fd, bit);
		break;

		case EV_ABS:
			map_axes(fd, bit, &node);
		break;

		case EV_SW:
		break;

/* useless for the time being */
		case EV_MSC:
		break;
		case EV_SYN:
		break;
		case EV_LED:
			add_led = bit;
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

	if (!eh.handler){
		if (mouse_ax && mouse_btn){
			node.type = DEVNODE_MOUSE;
			node.cursor.flt[0].mode = ARCAN_ANALOGFILTER_PASS;
			node.cursor.flt[1].mode = ARCAN_ANALOGFILTER_PASS;

			if (!iodev.mouseid)
				iodev.mouseid = node.devnum;
		}
/* not particularly pretty and rather arbitrary */
		else if (!mouse_btn && !joystick_btn && node.button_count > 84){
			node.type = DEVNODE_KEYBOARD;
			node.keyboard.state = 0;

/* FIX: query current LED states and set corresponding states in the devnode,
 * this does not save / restore the built-in repeats */
			unsigned rep[2] = {0, 0};
			ioctl(node.handle, EVIOCSREP, rep);
		}

		node.hnd.handler = defhandlers[node.type];
	}
	else{
		node.hnd = eh;
		node.type = eh.type;
	}

/* finally added */
	int hole = alloc_node_slot(path);
	if (-1 == hole){
		verbose_print(
			"input: dropped %s due to errors during scan.", path);
		close(fd);
		return;
	}

	iodev.n_devs++;
	node.path = strdup(path);
	iodev.pollset[hole].fd = fd;
	iodev.pollset[hole].events = POLLIN | POLLERR | POLLHUP;
	iodev.pollset[hole + iodev.sz_nodes].fd = BADFD;
	send_device_added(ctx, &node);

/* had to defer led device creation until now because we didn't
 * know if there's a slot for it or not, the pollset actually is
 * twice the expected size, one for the main device and one for
 * the possible led controller */
	if (add_led != -1){
		setup_led(&node, add_led, fd);
		if (node.led.gotled){
			iodev.pollset[hole+iodev.sz_nodes].fd = node.led.fds[0];
		}
	}
	iodev.nodes[hole] = node;

	if (node.type == DEVNODE_KEYBOARD){
		const char* err;
		platform_event_translation(node.devnum, EVENT_TRANSLATION_CLEAR, NULL, &err);
	}

	verbose_print("input: (%s:%s) added as type: %s",
		path, node.label, lookup_type(node.type));

	return;
}

#undef bit_isset
#undef bit_ofs
#undef bit_longn
#undef bit_count

void platform_event_rescan_idev(struct arcan_evctx* ctx)
{
	char ibuf [strlen(notify_scan_dir) + sizeof("/*")];
	glob_t res = {0};
	snprintf(ibuf, sizeof(ibuf), "%s/*", notify_scan_dir);

	if (glob(ibuf, 0, NULL, &res) == 0){
		char** beg = res.gl_pathv;

		while(*beg){
			int fd = platform_device_open(*beg, O_NONBLOCK | O_RDWR);
			if (-1 != fd)
				got_device(ctx, fd, *beg);
			beg++;
		}

		globfree(&res);
	}

	verbose_print("input: couldn't scan %s", notify_scan_dir);
}

static void update_state(int code, bool state, unsigned* statev)
{
	int modifier = 0;

	switch (klut[code]){
	case K_LSHIFT:
		modifier = ARKMOD_LSHIFT;
	break;
	case K_RSHIFT:
		modifier = ARKMOD_RSHIFT;
	break;
	case K_LALT:
		modifier = ARKMOD_LALT;
	break;
	case K_RALT:
		modifier = ARKMOD_RALT;
	break;
	case K_LCTRL:
		modifier = ARKMOD_LCTRL;
	break;
	case K_RCTRL:
		modifier = ARKMOD_RCTRL;
	break;
	case K_LMETA:
		modifier = ARKMOD_LMETA;
	break;
	case K_RMETA:
		modifier = ARKMOD_RMETA;
	break;
	case K_CAPSLOCK:
		modifier = ARKMOD_CAPS;
	break;
	case K_COMPOSE:
		modifier = ARKMOD_MODE;
	break;
	default:
		return;
	}

	if (state)
		*statev |= modifier;
	else
		*statev &= ~modifier;
}

static void defhandler_kbd(
	struct arcan_evctx* out, struct devnode* node)
{
	struct input_event inev[64];
	ssize_t evs = read(node->handle, &inev, sizeof(inev));

	if (-1 == evs){
		if (errno != EINTR && errno != EAGAIN)
			disconnect(out, node);
	}

	if (evs < 0 || evs < sizeof(struct input_event))
		return;

	arcan_event newev = {
		.category = EVENT_IO,
		.io = {
			.kind = EVENT_IO_BUTTON,
			.devid = node->devnum,
			.datatype = EVENT_IDATATYPE_TRANSLATED,
			.devkind = EVENT_IDEVKIND_KEYBOARD,
		}
	};

	for (size_t i = 0; i < evs / sizeof(struct input_event); i++){
		switch(inev[i].type){
		case EV_KEY:
		newev.io.input.translated.scancode = inev[i].code;
		newev.io.input.translated.keysym = lookup_keycode(inev[i].code);
		newev.io.input.translated.modifiers = node->keyboard.state;
		update_state(inev[i].code, inev[i].value != 0, &node->keyboard.state);
/* possible checkpoint for adding other keyboard layout support here */
		newev.io.subid = inev[i].code;

/* default 'fallback' translation */
		uint16_t code = lookup_character(inev[i].code, node->keyboard.state, true);
		if (code)
			to_utf8(code, newev.io.input.translated.utf8);

/* virtual terminal switching for press on LCTRL+LALT+Fn. should possibly have
 * more advanced config here to limit # of eligible devices and change
 * combination, and option to disable the thing entirely because it is
 * just terrible */
		if ((node->keyboard.state == (ARKMOD_LALT | ARKMOD_LCTRL)) &&
			inev[i].code >= KEY_F1 && inev[i].code <= KEY_F10 && inev[i].value != 0){
			platform_device_release("TTY", inev[i].code - KEY_F1 + 1);
		}

/* Feed layout statemachine, try to get a translation out of it. Since we
 * don't have support for xkeyboard symbols, we either make due with the normal
 * kernel keycode to SDL keysym or go with the keyboard layout and try to
 * translate that into SDL. */
#ifdef HAVE_XKBCOMMON
		if (node->keyboard.xkb_state){
			memset(newev.io.input.translated.utf8, '\0', 5);
			if (inev[i].value == 0){
				xkb_state_update_key(
					node->keyboard.xkb_state, inev[i].code + 8, XKB_KEY_UP);
			}
			else if (inev[i].value == 1 || (inev[i].value == 2 && xkb_keymap_key_repeats(
				node->keyboard.xkb_layout, inev[i].code+8))){
				xkb_state_key_get_utf8(node->keyboard.xkb_state,
					inev[i].code + 8, (char*) newev.io.input.translated.utf8, 5);
				xkb_state_update_key(
					node->keyboard.xkb_state, inev[i].code + 8, XKB_KEY_DOWN);
			}
		}
#endif

/* auto-repeat, may get even if we are not in this state because of broken
 * drivers or failed mode-setting. */
		if (inev[i].value == 2){
			if (iodev.period){
				newev.io.input.translated.modifiers |= ARKMOD_REPEAT;
				newev.io.input.translated.active = false;
				arcan_event_enqueue(out, &newev);
				newev.io.input.translated.active = true;
				arcan_event_enqueue(out, &newev);
			}
		}
		else{
			newev.io.input.translated.active = inev[i].value != 0;
			arcan_event_enqueue(out, &newev);
		}

		break;

		default:
		break;
		}

	}
}

static void flush_pending(
	struct arcan_evctx* ctx, struct devnode* node)
{
	arcan_event newev = {
		.category = EVENT_IO,
		.io = {
		.label = "touch",
		.devid = node->devnum,
		.subid = node->touch.ind + 128,
		.kind = EVENT_IO_TOUCH,
		.devkind = EVENT_IDEVKIND_TOUCHDISP,
		.datatype = EVENT_IDATATYPE_TOUCH
		}
	};

	verbose_print("kind=touch:device=%d:base=%d", node->devnum, node->touch.ind);

	newev.io.input.touch.active = node->touch.active;
	newev.io.input.touch.x = node->touch.x[MIN(MAX_MT_SLOTS-1, node->touch.ind)];
	newev.io.input.touch.y = node->touch.y[MIN(MAX_MT_SLOTS-1, node->touch.ind)];
	newev.io.input.touch.pressure = node->touch.pressure;
	newev.io.input.touch.size = node->touch.size;

	arcan_event_enqueue(ctx, &newev);
	node->touch.pending = false;
	node->touch.active = true;
}

static void decode_mt(struct arcan_evctx* ctx,
	struct devnode* node, int code, int val)
{
/* there are multiple protocols and mappings for this that we don't
 * account for here, move it to a toch event with the basic information
 * and let higher layers deal with it */
	switch(code){
	case ABS_X:
		if (node->touch.ind != 0 && node->touch.pending)
			flush_pending(ctx, node);

		node->touch.ind = 0;
		node->touch.x[0] = val;
		node->touch.pending = true;
	break;
	case ABS_Y:
		if (node->touch.ind != 0 && node->touch.pending)
			flush_pending(ctx, node);

		node->touch.ind = 0;
		node->touch.y[0] = val;
		node->touch.pending = true;
	break;
	case ABS_MT_PRESSURE:
		node->touch.pressure = val;
	break;
	case ABS_MT_POSITION_X:
		node->touch.x[MIN(MAX_MT_SLOTS-1, node->touch.ind)] = val;
		node->touch.pending = true;
	break;
	case ABS_MT_POSITION_Y:
		node->touch.y[MIN(MAX_MT_SLOTS-1, node->touch.ind)] = val;
		node->touch.pending = true;
	break;
	case ABS_DISTANCE:
		node->touch.pressure = val;
	break;
	case ABS_MT_TRACKING_ID:
		if (-1 == val){
			node->touch.active = false;
			node->touch.pending = true;
			flush_pending(ctx, node);
		}
		else
			; /* we don't distingush between IDs, only SLOTs */
	break;
	case ABS_MT_SLOT:
		if (node->touch.pending && node->touch.ind != val)
			flush_pending(ctx, node);
		node->touch.ind = val;
	break;
	default:
		verbose_print("dev=%d:type=multitouch:code=%d"
			":status=unknown", (int) node->devnum, code);
	break;
	}
}

static void decode_hat(struct arcan_evctx* ctx,
	struct devnode* node, int ind, int val)
{
	arcan_event newev = {
		.category = EVENT_IO,
		.io = {
			.label = "gamepad",
			.kind = EVENT_IO_BUTTON,
			.devkind = EVENT_IDEVKIND_GAMEDEV,
			.datatype = EVENT_IDATATYPE_DIGITAL
		}
	};

	ind *= 2;
	const int base = 64;

	newev.io.devid = node->devnum;

/* clamp */
	if (val < 0)
		val = -1;
	else if (val > 0)
		val = 1;
	else {
/* which of the two possibilities was released? */
		newev.io.input.digital.active = false;

		if (node->game.hats[ind] != 0){
			newev.io.subid = base + ind;
			node->game.hats[ind] = 0;
			arcan_event_enqueue(ctx, &newev);
		}

		if (node->game.hats[ind+1] != 0){
			newev.io.subid = base + ind + 1;
			node->game.hats[ind+1] = 0;
			arcan_event_enqueue(ctx, &newev);
		}

		return;
	}

	if (val > 0)
		ind++;

	node->game.hats[ind] = val;
	newev.io.input.digital.active = true;
	newev.io.subid = base + ind;
	arcan_event_enqueue(ctx, &newev);
}

static void defhandler_game(struct arcan_evctx* ctx, struct devnode* node)
{
	struct input_event inev[64];
	ssize_t evs = read(node->handle, &inev, sizeof(inev));

	if (-1 == evs){
		if (errno != EINTR && errno != EAGAIN)
			disconnect(ctx, node);
	}

	if (evs < 0 || evs < sizeof(struct input_event))
		return;

	arcan_event newev = {
		.category = EVENT_IO,
		.io = {
			.label = "gamepad",
			.devkind = EVENT_IDEVKIND_GAMEDEV
		}
	};

	short samplev;

	for (size_t i = 0; i < evs / sizeof(struct input_event); i++){
		switch(inev[i].type){
		case EV_KEY:
			if (inev[i].code >= BTN_TOUCH)
				inev[i].code -= BTN_TOUCH;
			else if (inev[i].code >= BTN_JOYSTICK)
				inev[i].code -= BTN_JOYSTICK;
			else if (inev[i].code >= BTN_MOUSE)
				inev[i].code -= BTN_MOUSE - 1;
			if (node->hnd.button_mask && inev[i].code <= 64 &&
				( (node->hnd.button_mask >> inev[i].code) & 1) )
				continue;

			newev.io.kind = EVENT_IO_BUTTON;
			newev.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newev.io.input.digital.active = inev[i].value;
			newev.io.subid = inev[i].code;
			newev.io.devid = node->devnum;
			arcan_event_enqueue(ctx, &newev);
		break;

		case EV_SW:
			newev.io.kind = EVENT_IO_BUTTON;
			newev.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newev.io.input.digital.active = inev[i].value;
			newev.io.subid = inev[i].code;
			newev.io.devid = node->devnum;
			arcan_event_enqueue(ctx, &newev);
		break;

		case EV_REL:
		case EV_ABS:
/* is the axis currently masked? */
			if (node->hnd.axis_mask && inev[i].code <= 64 &&
				( (node->hnd.axis_mask >> inev[i].code) & 1) ){
				continue;
			}
			verbose_print("rel? %d - %d\n", inev[i].type, inev[i].code);

			if (inev[i].code >= ABS_HAT0X && inev[i].code <= ABS_HAT3Y){
				decode_hat(ctx, node, inev[i].code - ABS_HAT0X, inev[i].value);
			}
			else if (inev[i].code < node->game.axes &&
				process_axis(ctx,
				&node->game.adata[inev[i].code], inev[i].value, &samplev)){
				newev.io.kind = EVENT_IO_AXIS_MOVE;
				newev.io.datatype = EVENT_IDATATYPE_ANALOG;
				newev.io.input.analog.gotrel = inev[i].type == EV_REL;
				newev.io.subid = inev[i].code;
				newev.io.devid = node->devnum;
				newev.io.input.analog.axisval[0] = samplev;
				newev.io.input.analog.nvalues = 2;
				arcan_event_enqueue(ctx, &newev);
			}
			else if ((inev[i].code >= ABS_X && inev[i].code <= ABS_Y) ||
				(inev[i].code >= ABS_MT_SLOT && inev[i].code <= ABS_MT_TOOL_Y)){
				decode_mt(ctx, node, inev[i].code, inev[i].value);
			}
/* though we do reserve axis slots for the relative bits, there is no actual
 * filter set to them other than the the mask used above */
			else if (
				inev[i].code == REL_X ||
				inev[i].code == REL_Y ||
				inev[i].code == REL_DIAL ||
				inev[i].code == REL_Z ||
				inev[i].code == REL_RZ ||
				inev[i].code == REL_RX ||
				inev[i].code == REL_RY)
			{
				newev.io.kind = EVENT_IO_AXIS_MOVE;
				newev.io.datatype = EVENT_IDATATYPE_ANALOG;
				newev.io.input.analog.gotrel = true;
				newev.io.subid = inev[i].code;
				newev.io.devid = node->devnum;
				newev.io.input.analog.axisval[0] = inev[i].value;
				newev.io.input.analog.nvalues = 1;
				arcan_event_enqueue(ctx, &newev);
			}
			else {
				verbose_print("kind=game:device=%d:rel:code=%d:status=unknown", node->devnum, inev[i].code);
			}
		break;

		case EV_SYN:
		case EV_REP:
			if (node->touch.pending)
				flush_pending(ctx, node);
		break;

		default:
			verbose_print("kind=game:device=%d:type=%d:status=unknown", node->devnum, inev[i].type);
		break;
		}
	}

}

static inline short code_to_mouse(int code)
{
	return (code < BTN_MOUSE || code >= BTN_JOYSTICK) ?
		-1 : (code - BTN_MOUSE + 1);
}

static void defhandler_mouse(struct arcan_evctx* ctx,
	struct devnode* node)
{
	struct input_event inev[64];

	ssize_t evs = read(node->handle, &inev, sizeof(inev));

	if (-1 == evs){
		if (errno != EINTR && errno != EAGAIN)
			disconnect(ctx, node);
	}

	if (evs < 0 || evs < sizeof(struct input_event))
		return;

	arcan_event newev = {
		.category = EVENT_IO,
		.io = {
			.label = "mouse",
			.devkind = EVENT_IDEVKIND_MOUSE,
		}
	};

	short samplev;
	newev.io.devid = node->devnum;

	for (size_t i = 0; i < evs / sizeof(struct input_event); i++){
		int vofs = 0;

		switch(inev[i].type){
		case EV_KEY:
			samplev = code_to_mouse(inev[i].code);
			if (samplev < 0)
				continue;

			newev.io.kind = EVENT_IO_BUTTON;
			newev.io.datatype = EVENT_IDATATYPE_DIGITAL;
			newev.io.input.digital.active = inev[i].value;
			newev.io.subid = samplev;

			arcan_event_enqueue(ctx, &newev);
		break;
		case EV_REL:
			switch (inev[i].code){
			case REL_HWHEEL:
				vofs += 2;
			case REL_WHEEL:
				newev.io.kind = EVENT_IO_BUTTON;
				newev.io.datatype = EVENT_IDATATYPE_DIGITAL;
				newev.io.input.digital.active = 1;
				newev.io.subid = vofs + (inev[i].value > 0 ? 256 : 257);
				arcan_event_enqueue(ctx, &newev);
				newev.io.input.digital.active = 0;
				arcan_event_enqueue(ctx, &newev);
			break;

			case REL_X:
				if (process_axis(ctx, &node->cursor.flt[0], inev[i].value, &samplev)){
					samplev = inev[i].value;

					node->cursor.mx = ((int)node->cursor.mx + samplev < 0) ?
						0 : node->cursor.mx + samplev;

					newev.io.kind = EVENT_IO_AXIS_MOVE;
					newev.io.datatype = EVENT_IDATATYPE_ANALOG;
					newev.io.input.analog.gotrel = true;
					newev.io.subid = 0;
					newev.io.input.analog.axisval[0] = samplev;
					newev.io.input.analog.axisval[1] = node->cursor.mx;
					newev.io.input.analog.nvalues = 2;

					arcan_event_enqueue(ctx, &newev);
				}
			break;
			case REL_Y:
				if (process_axis(ctx, &node->cursor.flt[1], inev[i].value, &samplev)){
					node->cursor.my = ((int)node->cursor.my + samplev < 0) ?
						0 : node->cursor.my + samplev;

					newev.io.kind = EVENT_IO_AXIS_MOVE;
					newev.io.datatype = EVENT_IDATATYPE_ANALOG;
					newev.io.input.analog.gotrel = true;
					newev.io.subid = 1;
					newev.io.input.analog.axisval[0] = samplev;
					newev.io.input.analog.axisval[1] = node->cursor.my;
					newev.io.input.analog.nvalues = 2;

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
	struct devnode* node)
{
	char nbuf[256];
	ssize_t evs = read(node->handle, nbuf, sizeof(nbuf));
	if (-1 == evs){
		if (errno != EINTR && errno != EAGAIN)
			disconnect(out, node);
	}
}

const char* platform_event_devlabel(int devid)
{
	struct devnode* node = lookup_devnode(devid);
	if (!node)
		return NULL;

	return node->label;
}

/*
 * note, this do not currently save/restore individual options between
 * init/deinit sessions, which is needed for virtual terminal switching
 * and external_launch.
 */
void platform_event_reset(struct arcan_evctx* ctx)
{

}

void platform_event_deinit(struct arcan_evctx* ctx)
{
	platform_device_release("TTY", -1);

/* note, we purposely leak (let it disappear on close) to avoid the races and
 * interactions that come from TTY switching -> deinit -> signal -> init */

	if (gstate.notify != -1){
		close(gstate.notify);
		gstate.notify = -1;
	}

/* note, for VT switching this means that the state of devices when it comes
 * to filtering etc. do not persist between external launches, should rework
 * this */
	for (size_t i = 0; i < iodev.n_devs; i++){
		if (iodev.nodes[i].handle > 0){
			verbose_print("closing %zu:%d", i, iodev.nodes[i].handle);
			close(iodev.nodes[i].handle);
			memset(&iodev.nodes[i], '\0', sizeof(struct devnode));
			iodev.nodes[i].handle = -1;
		}
	}

	iodev.n_devs = 0;
	gstate.init = false;
}

void platform_device_lock(int devind, bool state)
{
	struct devnode* node = lookup_devnode(devind);
	if (!node || !node->handle)
		return;

	ioctl(node->handle, EVIOCGRAB, state? 1 : 0);

/*
 * doesn't make sense outside some window systems, might be useful to propagate
 * further to device locking on systems that are less forgiving.
 */
}

enum PLATFORM_EVENT_CAPABILITIES platform_event_capabilities(const char** out)
{
	enum PLATFORM_EVENT_CAPABILITIES rv = 0;
	if (out)
		*out = "evdev";

	for (size_t i = 0; i < iodev.n_devs; i++){
		if (iodev.nodes[i].handle)
			switch(iodev.nodes[i].type){
/* don't have better granularity in this step at the moment */
			case DEVNODE_SENSOR:
				rv |= ACAP_POSITION | ACAP_ORIENTATION;
			break;
			case DEVNODE_MOUSE:
				rv |= ACAP_MOUSE;
			break;
			case DEVNODE_GAME:
				rv |= ACAP_GAMING;
			break;
			case DEVNODE_KEYBOARD:
				rv |= ACAP_TRANSLATED;
			break;
			case DEVNODE_TOUCH:
				rv |= ACAP_TOUCH;
			break;
			default:
			break;
		}
	}

	return rv;
}

const char** platform_event_envopts()
{
	return (const char**) envopts;
}

/*
 * most of this is done priv-side, it is just the actual tty device to use and
 * control that is of importance as the privilege side keeps track of the first
 * TTY marked device that was opened as use that for the special 'TTY' name
 * later on release requests.
 */
static void find_tty()
{
/* first, check if the env. defines a specific TTY device to use and try that */
	const char* newtty = NULL;
	int tty = -1;
	bool scantty = true;

	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	char* ttydev;
	if (get_config("event_tty_override", 0, &ttydev, tag) && ttydev){
		int fd = platform_device_open(ttydev, O_RDWR);
		scantty = false;
		if (-1 == fd)
			arcan_warning("couldn't open TTYOVERRIDE %s, reason: %s\n",
				newtty, strerror(errno));
		else
			tty = fd;
		free(ttydev);
	}

/* Failing that, try and find what tty we might be on -- some might redirect
 * stdin to something else and then it is not a valid tty to work on. Which,
 * of course, brings us back to the special kid in the class, sysfs. */
	if (!isatty(tty) && scantty){
		FILE* fpek = fopen("/sys/class/tty/tty0/active", "r");
		if (fpek){
			char line[32] = "/dev/";
			if (fgets(line+5, 32-5, fpek)){
				char* endl = strrchr(line, '\n');
				if (endl)
					*endl = '\0';
				tty = platform_device_open(line, O_RDWR);
			}
			fclose(fpek);
		}
	}
}

void platform_event_preinit()
{
}

void platform_event_init(arcan_evctx* ctx)
{
	uintptr_t tag;

	cfg_lookup_fun get_config = platform_config_lookup(&tag);

#ifdef __LINUX
	gstate.notify = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
#endif

	init_keyblut();
#ifdef HAVE_XKBCOMMON
	xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
#endif

	if (!notify_scan_dir)
		notify_scan_dir = strdup(NOTIFY_SCAN_DIR);

	find_tty();

	char* newsd;
	if (get_config("event_scandir", 0, &newsd, tag) && newsd){
		free(notify_scan_dir);
		notify_scan_dir = newsd;
	}

/* chances are the CREATE events are actually racey, but with the
 * _device_open refactor this won't really matter as the suid part
 * allows us access anyway */
#ifdef __LINUX
	if (-1 == gstate.notify || inotify_add_watch(
		gstate.notify, notify_scan_dir, IN_CREATE) == -1){
		arcan_warning("inotify initialization failure (%s),"
			"	device discovery disabled.", strerror(errno));

		if (-1 != gstate.notify){
			close(gstate.notify);
			gstate.notify = -1;
		}
	}
#elif __FreeBSD__
/* there is a way to get devd to cooperate */
#else
#endif

	platform_event_rescan_idev(ctx);
}
