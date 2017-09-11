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
#include <dev/wscons/wsconsio.h>
#include <dev/wscons/wsksymdef.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"

#include "wskbdsdl.h"

/*
 * from easy experiments - there seem to be similar problems working with this
 * as on fbsd etc. a conflict between active tty and 'us'. The symbols from
 * wsksymdef are AFTER the map is applied - but we only get the raw values,
 * hence we need:
 * map -> code -> wsksym -> sdlsym -> onwards.
 * struct wscons_keymap mapdata[KS_NUMKEYCODES];
 * this, in turn, has (command, group1[2], group2[2]), where I tacitly
 * assume that group1/group2 are actually different modifiers.
 *
 * ioctl(fd, WSKBDIO_GETMAP, mapdata)
 */

static struct 
{
	struct {
		struct wscons_keymap mapdata[KS_NUMKEYCODES];
		struct termios tty;
		int mod;
		int fd;
	} kbd;
} evctx;

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

enum PLATFORM_EVENT_CAPABILITIES platform_input_capabilities()
{
	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH |
		ACAP_POSITION | ACAP_ORIENTATION;
}

void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

static void update_modifiers(int key, bool active)
{
	int xl = evctx.kbd.mapdata[key].group1[0];

	int mod = 0;
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
	if (evctx.kbd.mod & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)){
		val = evctx.kbd.mapdata[value].group1[1];
	}

	ev->io.input.translated.keysym = sym_lut[val];
	to_utf8(val, ev->io.input.translated.utf8);
}

void platform_event_process(arcan_evctx* ctx)
{
	struct wscons_event events[64];
	int type;
 	int blocked, n, i;

	if ((n = read(evctx.kbd.fd, events, sizeof(events))) > 0) {
		n /=  sizeof(struct wscons_event);
		for (i = 0; i < n; i++) {
			type = events[i].type;
			if (type == WSCONS_EVENT_KEY_UP || type == WSCONS_EVENT_KEY_DOWN) {
				update_modifiers(events[i].value, type == WSCONS_EVENT_KEY_DOWN);
				arcan_event outev = {
					.category = EVENT_IO,
						.io.kind = EVENT_IO_BUTTON,
						.io.devid = 0,
						.io.subid = events[i].value,
						.io.datatype = EVENT_IDATATYPE_TRANSLATED,
						.io.devkind = EVENT_IDEVKIND_KEYBOARD,
						.io.input.translated.scancode = events[i].value,
						.io.input.translated.modifiers = evctx.kbd.mod,
						.io.input.translated.active = type == WSCONS_EVENT_KEY_DOWN
				};
				apply_modifiers(events[i].value, &outev);
				arcan_event_enqueue(ctx, &outev);
			}
		}
	}
}

void platform_event_keyrepeat(arcan_evctx* ctx, int* rate, int* del)
{
	if (-1 == evctx.kbd.fd)
		return;
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

const char** platform_input_envopts()
{
	return (const char**) envopts;
}

void platform_event_deinit(arcan_evctx* ctx)
{
	if (-1 != evctx.kbd.fd){
		int option = WSKBD_TRANSLATED;
		ioctl(evctx.kbd.fd, WSKBDIO_SETMODE, &option);
		tcsetattr(evctx.kbd.fd, TCSANOW, &(evctx.kbd.tty));
		close(evctx.kbd.fd);
		evctx.kbd.fd = -1;
	}
}

void platform_event_reset(arcan_evctx* ctx)
{
	platform_event_deinit(ctx);
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_init(arcan_evctx* ctx)
{
	evctx.kbd.fd = open("/dev/wskbd", O_RDONLY | O_NONBLOCK | O_EXCL);
	if (-1 == evctx.kbd.fd){
		arcan_warning("couldn't open wskbd\n");
		return;
	}

	struct wskbd_map_data kbmap = { KS_NUMKEYCODES, evctx.kbd.mapdata };
	if (ioctl(evctx.kbd.fd, WSKBDIO_GETMAP, &kbmap) == -1){
		arcan_warning("couldn't get keymap\n");
	}

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

/* queue device discovered? */
}
