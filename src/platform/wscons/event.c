/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>
#include <assert.h>
#include <unistd.h>
#include <termios.h>
#include <time.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <errno.h>
#include <dev/wscons/wsconsio.h>
#include <dev/wscons/wsksymdef.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"

#include "wskbdsdl.h"

static struct
{
	struct {
		struct wscons_keymap mapdata[KS_NUMKEYCODES];
		struct wskbd_keyrepeat_data defrep;
		struct termios tty;
		int mod;
		int fd;
		int period;
		int delay;
		uint8_t reptrack[512];
	} kbd;
	struct {
		uint8_t bmask;
		int fd;
	} mouse;
} evctx = {
	.kbd = {
		.fd = -1,
		.period = 100, /* WSKBD_DEFAULT_REPEAT_DEL1 */
		.delay = 400, /* WSKBD_DEFAULT_REPEAT_DELN */
	},
	.mouse = {
		.fd = -1
	}
};

/*
 * same as in the FreeBSD driver
 */
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

void platform_event_samplebase(int devid, float xyz[3])
{
}

arcan_errc platform_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

void platform_event_analogall(bool enable, bool mouse)
{
}

enum PLATFORM_EVENT_CAPABILITIES platform_event_capabilities(const char** out)
{
	if (out)
		*out = "openbsd";

	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH |
		ACAP_POSITION | ACAP_ORIENTATION;
}

void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

static bool update_modifiers(int key, bool active)
{
	int xl = evctx.kbd.mapdata[key].group1[0];
	int mod = 0;
	bool res = (evctx.kbd.reptrack[
		key % sizeof(evctx.kbd.reptrack)] & active) * ARKMOD_REPEAT;
	evctx.kbd.reptrack[key % sizeof(evctx.kbd.reptrack)] = active;

	switch (xl){
	case KS_Shift_R: mod = ARKMOD_RSHIFT; break;
	case KS_Shift_L: mod = ARKMOD_LSHIFT; break;
	case KS_Caps_Lock: mod = ARKMOD_CAPS; break;
	case KS_Control_L: mod = ARKMOD_LCTRL; break;
	case KS_Control_R: mod = ARKMOD_RCTRL; break;
	case KS_Alt_R: mod = ARKMOD_RALT; break;
	case KS_Alt_L: mod = ARKMOD_LALT; break;
	case KS_Meta_L: mod = ARKMOD_LMETA; break;
	case KS_Meta_R: mod = ARKMOD_RMETA; break;
	default: break;
	}
	if (active)
		evctx.kbd.mod |= mod;
	else
		evctx.kbd.mod &= ~mod;
	return res;
}

/*
 * This is far from correct, but should at least be enough to be able to continue
 * development work from inside arcan rather than from a terminal
 */
static void apply_modifiers(int value, struct arcan_event* ev)
{
/* not at all sure how the 'group' is actually selected, or what 'command' stands for,
 * couldn't find any clear reference in the documentation - and the code is unusually
 * scattered */
	uint16_t val = evctx.kbd.mapdata[value].group1[0];
	ev->io.input.translated.keysym = sym_lut[val];
	if (evctx.kbd.mod & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)){
		val = evctx.kbd.mapdata[value].group1[1];
		to_utf8(val, ev->io.input.translated.utf8);
	}
	else if (evctx.kbd.mod & (ARKMOD_LCTRL | ARKMOD_RCTRL)){
/* quickhack to avoid ctrl+c etc. being assigned a sequence */
	}
	else
		to_utf8(val, ev->io.input.translated.utf8);
}

#define TS_MS(X) ((X).tv_sec * 1000 + (X).tv_nsec / 1.0e6)

void platform_event_process(arcan_evctx* ctx)
{
	struct wscons_event events[64];
	int type;
 	int blocked, n, i;

	if ((n = read(evctx.mouse.fd, events, sizeof(events))) > 0) {
		n /= sizeof(struct wscons_event);
		for (i = 0; i < n; i++) {
			int aind = 0;
			bool aev = false, arel = false;

			switch(events[i].type){
			case WSCONS_EVENT_MOUSE_UP:
				if (evctx.mouse.bmask & (1 << events[i].value)){
					evctx.mouse.bmask &= ~(1 << events[i].value);
					arcan_event_enqueue(ctx, &(struct arcan_event){
						.category = EVENT_IO,
						.io.label = "MOUSE\0",
						.io.pts = TS_MS(events[i].time),
						.io.kind = EVENT_IO_BUTTON,
						.io.devkind = EVENT_IDEVKIND_MOUSE,
						.io.datatype = EVENT_IDATATYPE_DIGITAL,
						.io.subid = events[i].value + 1
					});
				}
			break;
			case WSCONS_EVENT_MOUSE_DOWN:
				if (!(evctx.mouse.bmask & (1 << events[i].value))){
					evctx.mouse.bmask |= 1 << events[i].value;
					arcan_event_enqueue(ctx, &(struct arcan_event){
						.category = EVENT_IO,
						.io.label = "MOUSE\0",
						.io.pts = TS_MS(events[i].time),
						.io.kind = EVENT_IO_BUTTON,
						.io.devkind = EVENT_IDEVKIND_MOUSE,
						.io.datatype = EVENT_IDATATYPE_DIGITAL,
						.io.subid = events[i].value + 1,
						.io.input.digital.active = true
					});
				}
			break;
			case WSCONS_EVENT_MOUSE_DELTA_X:
				aev = arel = true;
			break;
			case WSCONS_EVENT_MOUSE_DELTA_Y:
				aev = arel = true;
				aind = 1;
				events[i].value *= -1;
			break;
			case WSCONS_EVENT_MOUSE_ABSOLUTE_X:
				aev = true;
			break;
			case WSCONS_EVENT_MOUSE_ABSOLUTE_Y:
				aev = true; aind = 1;
			break;
/* ignored for now */
			case WSCONS_EVENT_MOUSE_DELTA_Z:
			case WSCONS_EVENT_MOUSE_ABSOLUTE_Z:
			case WSCONS_EVENT_MOUSE_DELTA_W:
			case WSCONS_EVENT_MOUSE_ABSOLUTE_W:
			break;
			default:
			break;
			}
			if (aev){
				arcan_event_enqueue(ctx, &(struct arcan_event){
				.category = EVENT_IO,
				.io.label = "MOUSE\0",
				.io.subid = aind,
				.io.kind = EVENT_IO_AXIS_MOVE,
				.io.datatype = EVENT_IDATATYPE_ANALOG,
				.io.devkind = EVENT_IDEVKIND_MOUSE,
				.io.input.analog.gotrel = arel,
				.io.input.analog.nvalues = 1,
				.io.input.analog.axisval[0] = events[i].value
				});
			}
		}
	}

	if ((n = read(evctx.kbd.fd, events, sizeof(events))) > 0) {
		n /=  sizeof(struct wscons_event);
		for (i = 0; i < n; i++) {
			type = events[i].type;
			if (type == WSCONS_EVENT_KEY_UP || type == WSCONS_EVENT_KEY_DOWN) {
				bool rep = update_modifiers(events[i].value, type == WSCONS_EVENT_KEY_DOWN);
				if (rep && evctx.kbd.period == 0)
					continue;

				arcan_event outev = {
					.category = EVENT_IO,
						.io.kind = EVENT_IO_BUTTON,
						.io.pts = TS_MS(events[i].time),
						.io.devid = 0,
						.io.subid = events[i].value,
						.io.datatype = EVENT_IDATATYPE_TRANSLATED,
						.io.devkind = EVENT_IDEVKIND_KEYBOARD,
						.io.input.translated.scancode = events[i].value,
						.io.input.translated.modifiers = evctx.kbd.mod | (rep * ARKMOD_REPEAT),
						.io.input.translated.active = type == WSCONS_EVENT_KEY_DOWN
				};
				apply_modifiers(events[i].value, &outev);
				arcan_event_enqueue(ctx, &outev);
			}
		}
	}
}

void platform_event_keyrepeat(arcan_evctx* ctx, int* period, int* delay)
{
	bool upd = false;

	if (-1 == evctx.kbd.fd)
		return;

	if (*period < 0){
		*period = evctx.kbd.period;
	}
	else {
		int tmp = *period;
		*period = evctx.kbd.period;
		evctx.kbd.period = tmp;
		upd = true;
	}

	if (*delay < 0){
		*delay = evctx.kbd.delay;
	}
	else {
		int tmp = *delay;
		*delay = evctx.kbd.delay;
		evctx.kbd.delay = tmp;
		upd = true;
	}

	if (!upd)
		return;

	if (-1 == ioctl(evctx.kbd.fd, WSKBDIO_SETKEYREPEAT,
		&(struct wskbd_keyrepeat_data){
		.which = WSKBD_KEYREPEAT_DOALL,
		.del1 = (evctx.kbd.delay == 0 ? UINT_MAX : evctx.kbd.delay),
		.delN = (evctx.kbd.period == 0 ? UINT_MAX : evctx.kbd.period)
	})){
		arcan_warning("couldn't set repeat(%d:%d), %s\n",
			evctx.kbd.delay, evctx.kbd.period, strerror(errno));
	}
}

int platform_event_translation(
	int devid, int action, const char** names, const char** err)
{
	*err = "Unsupported";
	return false;
}

int platform_event_device_request(int space, const char* path)
{
	return -1;
}

void platform_event_rescan_idev(arcan_evctx* ctx)
{
}

const char* platform_event_devlabel(int devid)
{
	return NULL;
}

static char* envopts[] = {
	NULL
};

const char** platform_event_envopts()
{
	return (const char**) envopts;
}

void platform_event_deinit(arcan_evctx* ctx)
{
	if (-1 != evctx.kbd.fd){
		int option = WSKBD_TRANSLATED;
		ioctl(evctx.kbd.fd, WSKBDIO_SETKEYREPEAT, &evctx.kbd.defrep);
		ioctl(evctx.kbd.fd, WSKBDIO_SETMODE, &option);
		tcsetattr(evctx.kbd.fd, TCSANOW, &(evctx.kbd.tty));
		close(evctx.kbd.fd);
		evctx.kbd.fd = -1;
	}
	if (-1 != evctx.mouse.fd){
		close(evctx.mouse.fd);
		evctx.mouse.fd = -1;
	}
}

void platform_event_reset(arcan_evctx* ctx)
{
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_preinit()
{
/* drop privileges dance that might be needed on some video platforms */
	if (setgid(getgid()) == -1){
		fprintf(stderr, "event_preinit() - couldn't setgid(drop on suid)\n");
		exit(EXIT_FAILURE);
	}
	if (setuid(getuid()) == -1){
		fprintf(stderr, "event_preinit() - couldn't setuid(drop on suid)\n");
	}
}

void platform_event_init(arcan_evctx* ctx)
{
	evctx.kbd.fd =
		platform_device_open("/dev/wskbd", O_RDONLY | O_NONBLOCK | O_EXCL);
	if (-1 == evctx.kbd.fd){
		arcan_warning("couldn't open wskbd\n");
		return;
	}

	struct wskbd_map_data kbmap = { KS_NUMKEYCODES, evctx.kbd.mapdata };
	if (ioctl(evctx.kbd.fd, WSKBDIO_GETMAP, &kbmap) == -1){
		arcan_warning("couldn't get keymap\n");
	}

	ioctl(evctx.kbd.fd, WSKBDIO_GETKEYREPEAT, &evctx.kbd.defrep);

/* not needed?
	int opt = WSKBD_RAW;
	if (ioctl(evctx.kbd.fd, WSKBDIO_SETMODE, &opt) == -1){
		arcan_warning("couldn't set raw mode on keyboard\n");
	}

	tcgetattr(evctx.kbd.fd,	&(evctx.kbd.tty));
	evctx.kbd.tty.c_iflag = IGNPAR | IGNBRK;
	evctx.kbd.tty.c_oflag = 0;
	evctx.kbd.tty.c_cflag = CREAD | CS8;
	evctx.kbd.tty.c_lflag = 0;
	evctx.kbd.tty.c_cc[VTIME] = 0;
	evctx.kbd.tty.c_cc[VMIN] = 1;
	cfsetispeed(&evctx.kbd.tty, 9600);
	cfsetospeed(&evctx.kbd.tty, 9600);
	if (tcsetattr(evctx.kbd.fd, TCSANOW, &evctx.kbd.tty) < 0){
		arcan_warning("couldn't setattr on tty\n");
	}
*/

	evctx.mouse.fd =
		platform_device_open("/dev/wsmouse", O_RDONLY | O_NONBLOCK);
	if (-1 == evctx.mouse.fd){
		arcan_warning("couldn't open mouse device, %s\n", strerror(errno));
	}

/* queue device discovered? */
}
