/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://arcan-fe.com
 */
#include <stdlib.h>
#include <limits.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <poll.h>

#include <sys/consio.h>
#include <sys/mouse.h>
#include <sys/kbio.h>
#include <sys/select.h>
#include <sys/time.h>

#include <termios.h>
#include <ctype.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"

/*
 * TODO:
 * 1. handle multiple keyboards with individual maps
 *  . keyboard repeat tracking (emit release), modifier subtable
 * 2. mouse devices
 * 3. trackpad / touch devices (synaptic?)
 * 4. joystick devices w/ analog filtering
 * 5. device hotplug detection
 * 6. vtswitching (can be copied from evdev)
 */

enum devtype {
/* use the TTY from /dev/console, user-specific device-node on rescan
 * like /dev/kbd*) or the kbdmux abstraction. We run this in K_CODE mode
 * and load the keymaps ourselves since there seem to be no mechanism for
 * getting both from the same device at the same time.
 * Expected to emit:
 * datatype: EVENT_IDATATYPE_TRANSLATED,
 * kind: EVENT_IDEVKIND_KEYBOPARD,
 * with the input.translated.active set on press/release
 * devid set to some unique index per device
 * scancode/subid to scancode
 * keysym to an SDL1.2 compatible SYM (if available)
 * and utf8 to a textual representation (if available)
 */
	keyboard = 0,

/*
 * expected to emit:
 *  label : MOUSE,
 *  kind  : EVENT_IO_AXIS_MOVE, EVENT_IO_BUTTON,
 *  datatype : EVENT_IDATATYPE_ANALOG, EVENT_IDATATYPE_DIGITAL
 *  with the reserved devid(-1) for mouse, subid for axis or button index.
 * Analog values should ideally respect lower_bound, upper_bound, deadzone,
 * kernel_size and mode (see sdl platform) and allow rebase ("warp") absolute
 * sample values.
 */
	mouse = 1,
	gamedev = 2,
	touchdev = 3,
	toggle = 4
};

struct bsdkey {
	uint8_t u8[5];
	uint16_t sym;
	uint16_t modmask;
};

struct devnode {
	enum devtype type;
	int fd;
	const char* nodepath;

	union {
		struct {
/* go from scancode to */
			struct bsdkey lut[8][128];
			uint16_t mods;
		} keyb;
		struct {
			int base[2];
			int mode;
		} mouse;
	};
};

static struct {
	struct termios ttystate;
	struct devnode keyb, mouse;
	int tty;
} evctx;

static char* accents[] = {
	"dgra", "dacu", "dcir", "dtil", "dmac", "dbre", "ddot", "duml",
	"ddia", "dsla", "drin", "dced", "dapo", "ddac", "dogo", "dcar",
	NULL
};

static bool next_tok(char* str, char** tok, size_t* cofs, size_t* out)
{
/* scan for beginning */
	while(str[*cofs] && isspace(str[*cofs]))
		(*cofs)++;

	if (!str[*cofs] || str[*cofs] == '#')
		return false;
	*tok = &str[*cofs];

/* scan for end */
	if (str[*cofs] == '\''){
		(*cofs)++;
		while (str[*cofs] && str[*cofs] != '\'')
			(*cofs)++;
		(*cofs)++;
	}
	else {
		while (str[*cofs] && !isspace(str[*cofs]))
			(*cofs)++;
	}

	*out = (uintptr_t)&str[*cofs] - (uintptr_t)*tok;
	return true;
}

struct bsdk_ent {
	uint8_t key;
	uint16_t sym;
	uint16_t mask;
	char tok[8];
};

static struct bsdk_ent bsdk_lut[] = {
	{.tok = "nop"},
	{.key =  0, .tok = "nul"}, {.key =  1, .tok = "soh"}, {.key =  2, .tok = "stx"},
	{.key =  3, .tok = "etx"}, {.key =  4, .tok = "eot"}, {.key =  5, .tok = "enq"},
	{.key =  6, .tok = "ack"}, {.key =  7, .tok = "bel"}, {.key =  8, .tok =  "bs"},
	{.key =  9, .tok = "tab"}, {.key = 10, .tok =  "lf"}, {.key = 11, .tok =  "vt"},
	{.key = 12, .tok =  "ff"}, {.key = 13, .tok =  "cr"}, {.key = 14, .tok =  "so"},
	{.key = 15, .tok =  "si"}, {.key = 16, .tok = "dle"}, {.key = 17, .tok = "dc1"},
	{.key = 18, .tok = "dc2"}, {.key = 19, .tok = "dc3"}, {.key = 20, .tok = "dc4"},
	{.key = 21, .tok = "nak"}, {.key = 22, .tok = "syn"}, {.key = 23, .tok = "etb"},
	{.key = 24, .tok = "can"}, {.key = 25, .tok =  "em"}, {.key = 26, .tok = "sub"},
	{.key = 27, .tok = "esc"}, {.key = 28, .tok =  "fs"}, {.key = 29, .tok =  "gs"},
	{.key = 30, .tok =  "rs"}, {.key = 31, .tok =  "us"},
	{.tok = "lshift", .mask = ARKMOD_LSHIFT, .sym = 304},
	{.tok = "rshift", .mask = ARKMOD_RSHIFT, .sym = 303},
	{.tok = "lctrl",  .mask = ARKMOD_LCTRL,  .sym = 306},
	{.tok = "rctrl",  .mask = ARKMOD_RCTRL,  .sym = 305},
	{.tok = "lalt",   .mask = ARKMOD_LALT,   .sym = 308},
	{.tok = "ralt",   .mask = ARKMOD_RALT,   .sym = 307},
	{.tok = "clock",  .mask = ARKMOD_CAPS,   .sym = 301},
	{.tok = "nlock",  .mask = ARKMOD_NUM,    .sym = 300},
	{.tok = "meta",   .mask = ARKMOD_LMETA,  .sym = 309},
	{.tok = "fkey64", .mask = ARKMOD_RMETA,  .sym = 319},
	{.tok = "slock",  .sym = 302}, {.tok = "fkey01", .sym = 282},
	{.tok = "fkey02", .sym = 283}, {.tok = "fkey03", .sym = 284},
	{.tok = "fkey04", .sym = 285}, {.tok = "fkey05", .sym = 286},
	{.tok = "fkey06", .sym = 287}, {.tok = "fkey07", .sym = 288},
	{.tok = "fkey08", .sym = 289}, {.tok = "fkey09", .sym = 290},
	{.tok = "fkey10", .sym = 291}, {.tok = "fkey11", .sym = 292},
	{.tok = "fkey12", .sym = 293}, {.tok = "fkey49", .sym = 278},
	{.tok = "fkey50", .sym = 273}, {.tok = "fkey51", .sym = 280},
	{.tok = "fkey52", .sym = 269}, {.tok = "fkey53", .sym = 276},
	{.tok = "fkey54", .sym = 261}, {.tok = "fkey55", .sym = 275},
	{.tok = "fkey56", .sym = 270}, {.tok = "fkey57", .sym = 279},
	{.tok = "fkey58", .sym = 274}, {.tok = "fkey59", .sym = 281},
	{.tok = "fkey60", .sym = 277}, {.tok = "fkey61", .sym = 127},
	{.tok = "fkey62", .sym = 311}, {.tok = "fkey63", .sym = 312}
};

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

static struct bsdkey decode_tok(char* tok)
{
	struct bsdkey res = {.sym = 0};

	if (tok[0] == '\''){
		res.u8[0] = tok[1];
		res.sym = res.u8[0];
	}
/* the manpage says unicode or unicode as hex, but nothing about the
 * actual encoding format, and some maps really give iso-8859-1 output
 * but for some in vt/keymaps seem to be UCS2 */
	else if (isdigit(tok[0])){
		int ucs2 = strtoul(tok, NULL, tok[1] == 'x' ? 16 : 10);
		to_utf8(ucs2, res.u8);
	}
	else{
		for (size_t i = 0; i < sizeof(bsdk_lut) / sizeof(bsdk_lut[0]); i++)
			if (strcmp(tok, bsdk_lut[i].tok) == 0){
				res.u8[0] = bsdk_lut[i].key;
				res.modmask = bsdk_lut[i].mask;
				res.sym = bsdk_lut[i].sym ? bsdk_lut[i].sym : res.u8[0];
				break;
			}
	}

	return res;
}

static bool load_keymap(struct devnode* dst, const char* path)
{
	char line_in[128];
	FILE* fpek = fopen(path, "r");
	if (!fpek){
		arcan_warning("couldn't open keymap (%s)\n", path);
		return false;
	}

	size_t linec = 0;
	while (!feof(fpek) && NULL != fgets(line_in, sizeof(line_in), fpek)){
		char* tok = NULL;
		size_t ofs = 0, nch;

/* we're expecting 10 tokens per well-formed line:
 * code base shft cntrl cntrl/shft alt alt/shft alt/cntrl alt/cntrl/shft lock
 * num  chtok ...                                                        CH
 * then there may be an empty row then the more complex format:
 * grp ch/num ( chnum chnum ) that may also contain linefeeds
where the firstg
 * is our keycode and the last is the lock-state modifier. The rest
 * follow modifier patterns */
		size_t tokofs = 0, code = 0;
		while(next_tok(line_in, &tok, &ofs, &nch)){
			char old = tok[nch];
			tok[nch] = '\0';
			ofs++;
			if (tokofs){
				if (tokofs <= 8){
					dst->keyb.lut[tokofs-1][code] = decode_tok(tok);
				}
/* ignore the permanent group switch */
				else
					break;
				tokofs++;
			}
			else {
				if (isdigit(tok[0])){
					code = strtoul(tok, NULL, 10);
					tokofs++;
/* scancodes should be 7-bit with MSB being hold/released */
					if (code > 127)
						break;
				}
/* we are in accent, ignore for now */
				else
					break;
			}
		}

		if (tok != NULL)
			linec++;
	}
	return true;
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

void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

static int mod_to_ind(uint16_t modmask)
{
	int ind = 0;

	if (modmask & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)){
		ind += 1;
	}

	if (modmask & (ARKMOD_LCTRL | ARKMOD_RCTRL)){
		ind += 2;
	}

	if (modmask & (ARKMOD_LALT | ARKMOD_RALT)){
		ind += 4;
	}

	return ind;
}

static void do_touchp(arcan_evctx* ctx, struct devnode* node)
{
/* see man psm and the MOUSE_SYN_GETHWINFO etc. for synaptics */
}

static void do_mouse(arcan_evctx* ctx, struct devnode* node)
{
/* mode 0(byte1..6), 1:
 * 8 bytes:
 * byte 1:  bit 2 (LMB, 0 press), 1 (MMB), 0 (LMB)
 * byte 2, 4: (add together) for int16_t range (x)
 * byte 3, 5: (add together) for int16_t range (y)
 * byte 6, 7: (add lower 7 bits together) for Zv (so btn 4/5)
 * byte 8: (lower 7 bits, button 4..10) */
}

static void do_keyb(arcan_evctx* ctx, struct devnode* node)
{
	uint8_t n, code;
	ssize_t count = read(evctx.tty, &n, 1);
	if (count <= 0)
		return;

	code = n & 0x7f;
	arcan_event ev = {
		.category = EVENT_IO,
		.io = {
			.kind = EVENT_IO_BUTTON,
			.devid = 1,
			.datatype = EVENT_IDATATYPE_TRANSLATED,
			.devkind = EVENT_IDEVKIND_KEYBOARD
		}
	};
	ev.io.input.translated.scancode = code;
	ev.io.subid = code;
	ev.io.input.translated.active = (n & 0x80) == 0;

/* it's safe to index based on modifier even though it's lagging behind
 * here as all state fields repeat the same modifer */
	struct bsdkey* key = &evctx.keyb.keyb.lut[mod_to_ind(node->keyb.mods)][code];

	memcpy(ev.io.input.translated.utf8, key->u8, 5);
	ev.io.input.translated.keysym = key->sym;
	if ((n & 0x80) == 0)
		node->keyb.mods |= key->modmask;
	else
		node->keyb.mods &= ~(key->modmask);

/* TODO: update code press bitmask table (2x 64-bit fields, 1 bit per code)
 * and check for repeat, if repeat and not modifier then emit release+press */
	ev.io.input.translated.modifiers = node->keyb.mods;
	arcan_event_enqueue(ctx, &ev);
}

void platform_event_process(arcan_evctx* ctx)
{
/* KEYBOARD format:
 * 1. Lookup code according to the current map which will yield
 *    our basic entry.
 * 2. If (modifier) update state tracking, translate modifier key
 * 3. lookup entry in map using modifier index
 * 4. use that to get SDL12 keysym, possible utf8- value
 *    set scancode, subid (dup. code), modifier-states, sym, utf8
 * 5. enqueue event.
 */
	struct pollfd infd[2] = {
		{ .fd = evctx.tty, .events = POLLIN },
		{ .fd = evctx.mouse.fd, .events = POLLIN }
	};

	bool okst = true;
	while (okst && poll(infd, 2, 0) > 0){
		okst = false;
		if (infd[0].revents == POLLIN){
			do_keyb(ctx, &evctx.keyb);
			okst = true;
		};

		if (infd[1].revents == POLLIN){
			do_mouse(ctx, &evctx.mouse);
			okst = true;
		}
	}
}

void platform_event_samplebase(int devid, float xyz[3])
{
/* for mouse dev, run ioctl on the console with struct mouse_info,
 * int_operttion, union { struct data, mode, event } */
}

void platform_event_keyrepeat(arcan_evctx* ctx, int* period, int* delay)
{
	struct keyboard_repeat rep;
	if (-1 == ioctl(evctx.keyb.fd, KDGETREPEAT, &rep))
		return;

	if (*period < 0)
		*period = rep.kb_repeat[1];
	else
		rep.kb_repeat[1] = *period;

	if (*delay < 0)
		*delay = rep.kb_repeat[0];
	else
		rep.kb_repeat[0] = *delay;

	ioctl(evctx.keyb.fd, KDSETREPEAT, &rep);
}

enum PLATFORM_EVENT_CAPABILITIES platform_input_capabilities()
{
	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH;
}

void platform_event_rescan_idev(arcan_evctx* ctx)
{
}

const char* platform_event_devlabel(int devid)
{
	return NULL;
}

static char* envopts[] = {
	"ARCAN_INPUT_IGNORETTY", "Don't change terminal processing state",
	"ARCAN_INPUT_KEYMAPS", "(temporary), path to keymap to use",
	NULL
};

const char** platform_input_envopts()
{
	return (const char**) envopts;
}

void platform_event_deinit(arcan_evctx* ctx)
{
/* restore TTY settings */
	if (-1 != evctx.tty){
		tcsetattr(evctx.tty, TCSAFLUSH, &evctx.ttystate);
		ioctl(evctx.tty, KDSETMODE, KD_TEXT);
		ioctl(evctx.keyb.fd, KDSKBMODE, K_XLATE);
	}
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_init(arcan_evctx* ctx)
{
/* save TTY settings, explicit for devices as we want kbd- access even
 * when testing from a remote shell */
	evctx.keyb.fd = STDIN_FILENO;

/* 7-bit scancode, 7 bit + MSB as active.  problem is that we need to do the
 * translation ourselves because the driver can't output both scancodes and
 * translated values, which would break cases where we need to forward scancode,
 * like in VMs
 */
	if (getenv("ARCAN_INPUT_KEYMAPS")){
		load_keymap(&evctx.keyb, getenv("ARCAN_INPUT_KEYMAPS"));
	}
	else{
		arcan_fatal("platform/freebsd: no keymap defined! set "
			"ARCAN_INPUT_KEYMAPS=/usr/share/syscons/keymap/???.kbd");
	}

	if (getenv("ARCAN_INPUT_IGNORETTY")){
		evctx.tty = -1;
		return;
	}

	evctx.tty = STDIN_FILENO;
	tcgetattr(evctx.tty, &evctx.ttystate);
	ioctl(evctx.tty, KDSETMODE, KD_GRAPHICS);

	if (-1 == ioctl(evctx.keyb.fd, KDSKBMODE, K_CODE)){
		arcan_warning("couldn't set code input mode\n");
	}
	struct termios raw = evctx.ttystate;
	raw.c_iflag &= ~(BRKINT);
	raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
	tcsetattr(evctx.tty, TCSAFLUSH, &raw);

	evctx.mouse.fd = open("/dev/sysmouse", O_RDWR);
	if (-1 != evctx.mouse.fd){
		ioctl(evctx.mouse.fd, MOUSE_SETLEVEL, 1);
		evctx.mouse.type = mouse;
	}
/* signal handler for VT switch */
}

void platform_event_reset(arcan_evctx* ctx)
{
	platform_event_deinit(ctx);
	platform_event_init(ctx);
}
