/*
 * Copyright 2016-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://arcan-fe.com
 * Description: Quick and dirty FreeBSD specific event input layer. It seems
 * like they will be moving, at least partially, to an evdev implementation so
 * this is kept as minimal effort.
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
#include <sys/types.h>

#include <termios.h>
#include <ctype.h>
#include <signal.h>
#include <errno.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"

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
			int buttons;
			int mx, my;
			mousemode_t mode;
			mousehw_t hw;
		} mouse;
	};
};

static struct {
	struct termios ttystate;
	struct devnode keyb, mdev;
	int tty;
	int sigpipe[2];
} evctx = {
	.tty = -1,
	.sigpipe = {-1, -1}
};

static char* accents[] = {
	"dgra", "dacu", "dcir", "dtil", "dmac", "dbre", "ddot", "duml",
	"ddia", "dsla", "drin", "dced", "dapo", "ddac", "dogo", "dcar",
	NULL
};

static const int vt_trm = 'z';
static void sigusr_term(int sign, siginfo_t* info, void* ctx)
{
	int s_errn = errno;
	if (write(evctx.sigpipe[1], &vt_trm, 1))
		;
	errno = s_errn;
}

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
	{.key =  6, .tok = "ack"}, {.key =  7, .tok = "bel"}, {.key =  8, .tok =  "bs", .sym = 8},
	{.key =  9, .tok = "ht", .sym = 9}, {.key = 10, .tok =  "lf"}, {.key = 11, .tok =  "vt"},
	{.key = 12, .tok =  "ff"}, {.key = 13, .tok =  "cr"}, {.key = 14, .tok =  "so"},
	{.key = 15, .tok =  "si"},
	{.key = 16, .tok = "dle"}, {.key = 17, .tok = "dc1"},
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
		res.sym = tolower(res.u8[0]);
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

static inline void check_btn(arcan_evctx* ctx,
	int oldstate, int newstate, int fl, int ind)
{
	if (!((oldstate & fl) ^ (newstate & fl)))
		return;

	arcan_event ev = {
	.category = EVENT_IO,
	.io = {
		.kind = EVENT_IO_BUTTON,
		.subid = MBTN_LEFT_IND + ind,
		.datatype = EVENT_IDATATYPE_DIGITAL,
			.devkind = EVENT_IDEVKIND_MOUSE,
			.input = { .digital = { .active = (oldstate & fl) } }
	}};
	arcan_event_enqueue(ctx, &ev);
}

static void wheel_ev(arcan_evctx* ctx, int idofs, int val)
{
	arcan_event aev = {
		.category = EVENT_IO,
		.io = {
			.kind = EVENT_IO_AXIS_MOVE,
			.datatype = EVENT_IDATATYPE_ANALOG,
			.devkind = EVENT_IDEVKIND_MOUSE,
			.subid = 2 + idofs,
			.input = {
				.analog = {
					.nvalues = 1,
					.gotrel = true,
					.axisval = {val}
				}
			},
		},
	};
	arcan_event_enqueue(ctx, &aev);

	arcan_event dev = {
		.category = EVENT_IO,
			.io = {
				.kind = EVENT_IO_BUTTON,
/* sysmouse descriptions says add byte 6, 7 and treat as signed but
 * from the mice I had to test with, down triggered 127 and up triggered 1 */
				.subid = MBTN_WHEEL_UP_IND + (val > 0 &&
					val <= 126 ? 1 : 0) + (idofs * 2),
				.datatype = EVENT_IDATATYPE_DIGITAL,
				.devkind = EVENT_IDEVKIND_MOUSE,
				.input = {
					.digital = {
						.active = true
					}
				}
			}
	};
	arcan_event_enqueue(ctx, &dev);
	dev.io.input.digital.active = false;
	arcan_event_enqueue(ctx, &dev);
}

static void do_mouse(arcan_evctx* ctx, struct devnode* node)
{
	size_t pkt_sz = node->mouse.mode.packetsize;
	uint8_t buf[pkt_sz];
	arcan_event outev = {
		.category = EVENT_IO,
		.io = { .label = "mouse", .devkind = EVENT_IDEVKIND_MOUSE }
	};

/* another option here would be to aggregate the motion events at least
 * to lessen the impact of a pile-up casade from suspend or similar */
	while (read(node->fd, buf, pkt_sz) == pkt_sz){
		int buttons, dx, dy, wheel_h, wheel_v;
		buttons = dx = dy = wheel_h = wheel_v = 0;

/* mouse.h seems to be the better source of documentation for deciphering */
		if (pkt_sz >= 5){
			buttons = (~buf[0] & 0x07);
			dx =  ((int8_t)buf[1] + (int8_t)buf[3]);
			dy = -((int8_t)buf[2] + (int8_t)buf[4]);
		}

/* append the values to the button mask (but shifted, so do the same with
 * the constant value for it to work. The reason is so that we can do a
 * simple cmp on each mouse sample to know if we need to recheck individual
 * buttons */
		if (pkt_sz >= 8){
			wheel_v = (int8_t)buf[5]+(int8_t)buf[6];
			buttons |= (buf[7] & MOUSE_SYS_EXTBUTTONS) << 3;
		}
/*
 * 	seen this protocol somewhere but havn't anything to test with that
 * 	actually activates it, so keep as a note for now
		if (pkt_sz >= 16){
			dx =  ((int16_t)((buf[ 8] << 9) | (buf[ 9] << 2)) >> 2);
			dy = -((int16_t)((buf[10] << 9) | (buf[11] << 2)) >> 2);
			wheel_v = -((int16_t)((buf[12] << 9) | (buf[13] << 2)) >> 2);
			wheel_h =  ((int16_t)((buf[14] << 9) | (buf[15] << 2)) >> 2);
		}
 */

/* our own input model has its problems too, absolute vs relative,
 * separate events or grouped together, always %2 events or only on
 * change, the interface is not particularly pretty */
		if (dx || dy){
			node->mouse.mx += dx;
			outev.io.datatype = EVENT_IDATATYPE_ANALOG;
			outev.io.kind = EVENT_IO_AXIS_MOVE;
			outev.io.input.analog.gotrel = true;
			outev.io.subid = 0;
			outev.io.input.analog.axisval[0] = node->mouse.mx;
			outev.io.input.analog.axisval[1] = dx;
			outev.io.input.analog.nvalues = 2;
			arcan_event_enqueue(ctx, &outev);

			node->mouse.my += dy;
			outev.io.datatype = EVENT_IDATATYPE_ANALOG;
			outev.io.kind = EVENT_IO_AXIS_MOVE;
			outev.io.input.analog.gotrel = true;
			outev.io.subid = 1;
			outev.io.input.analog.axisval[0] = node->mouse.my;
			outev.io.input.analog.axisval[1] = dy;
			outev.io.input.analog.nvalues = 2;
			arcan_event_enqueue(ctx, &outev);
		}

/* unfortunately we get a packed state table rather than changes-only,
 * so we have to extract and check each one. sysmouse uses 1 to indicate
 * released, we use that to indicate pressed */
		buttons = ~buttons;

		if (buttons != node->mouse.buttons){
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON1UP, 0);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON2UP, 1);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON3UP, 2);
/* 3,4 and 5,6 are wheel digitals */
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON4UP << 3, 7);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON5UP << 3, 8);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON6UP << 3, 9);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON7UP << 3,10);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON8UP << 3,11);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON9UP << 3,12);
			check_btn(ctx, node->mouse.buttons, buttons, MOUSE_SYS_BUTTON10UP <<3,13);
			node->mouse.buttons = buttons;
		}

/* this has to be split into three events: [press+release] and analog axis */
		if (wheel_v)
			wheel_ev(ctx, 0, wheel_v);

		if (wheel_h)
			wheel_ev(ctx, 1, wheel_h);
 	}
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
	struct bsdkey* okey = &evctx.keyb.keyb.lut[0][code];

/* the symbols are taken from their non-modified state */

	memcpy(ev.io.input.translated.utf8, key->u8, 5);
	ev.io.input.translated.keysym = okey->sym;
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
	struct pollfd infd[3] = {
		{ .fd = evctx.tty, .events = POLLIN },
		{ .fd = evctx.mdev.fd, .events = POLLIN },
		{ .fd = evctx.sigpipe[0], .events = POLLIN }
	};

/* allow one "sweep" */
	bool okst = true;
	while (okst && poll(infd, 2, 0) > 0){
		okst = false;
		if (infd[0].revents == POLLIN){
			do_keyb(ctx, &evctx.keyb);
			okst = true;
		};

		if (infd[1].revents == POLLIN){
			do_mouse(ctx, &evctx.mdev);
			okst = true;
		}

		if (infd[2].revents == POLLIN){
			char ch;
			if (1 == read(infd[2].fd, &ch, 1))
				switch(ch){
				case 'z':
					arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
						.category = EVENT_SYSTEM,
						.sys.kind = EVENT_SYSTEM_EXIT,
						.sys.errcode = EXIT_SUCCESS
					});
				break;
				}
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

enum PLATFORM_EVENT_CAPABILITIES platform_event_capabilities(const char** out)
{
	if (out)
		*out = "freebsd";

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

const char** platform_event_envopts()
{
	return (const char**) envopts;
}

void platform_event_deinit(arcan_evctx* ctx)
{
/* this is also performed in psep_open */
	if (-1 != evctx.tty){
		tcsetattr(evctx.tty, TCSAFLUSH, &evctx.ttystate);
		ioctl(evctx.tty, KDSETMODE, KD_TEXT);
		ioctl(evctx.keyb.fd, KDSKBMODE, K_XLATE);
	}
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_preinit()
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
/* just pick a layout, chances are the user can't / won't see the error so
 * better to do something. Other (real) option should be to check rc.conf or
 * rc.conf.local after the keymap variable and load that */
	else{
		arcan_warning("platform/freebsd: no keymap defined! set "
			"ARCAN_INPUT_KEYMAPS=/usr/share/syscons/keymaps/???.kbd");
		load_keymap(&evctx.keyb, "/usr/share/syscons/keymaps/us.iso.kbd");
	}

	if (getenv("ARCAN_INPUT_IGNORETTY")){
		evctx.tty = -1;
		return;
	}

	evctx.tty = STDIN_FILENO;
	tcgetattr(evctx.tty, &evctx.ttystate);
	ioctl(evctx.tty, KDSETMODE, KD_GRAPHICS);

	if (-1 == ioctl(evctx.keyb.fd, KDSKBMODE, K_RAW)){
		arcan_warning("couldn't set code input mode\n");
	}
	struct termios raw = evctx.ttystate;
	cfmakeraw(&raw);
	tcsetattr(evctx.tty, TCSAFLUSH, &raw);

	evctx.mdev.fd = platform_device_open("/dev/sysmouse", O_RDWR);
	if (-1 != evctx.mdev.fd){
		int level = 1;
		if (-1 == ioctl(evctx.mdev.fd, MOUSE_SETLEVEL, &level)){
			close(evctx.mdev.fd);
			evctx.mdev.fd = -1;
			arcan_warning("no acceptable mouse protocol found for sysmouse %d, %s\n",
				errno, strerror(errno));
			goto sigset;
		}
		if (-1 == ioctl(evctx.mdev.fd, MOUSE_GETMODE, &evctx.mdev.mouse.mode)){
			close(evctx.mdev.fd);
			arcan_warning("couldn't get mousemode from /dev/sysmouse\n");
			evctx.mdev.fd = -1;
			goto sigset;
		}
		if (evctx.mdev.mouse.mode.protocol != MOUSE_PROTO_SYSMOUSE ||
			evctx.mdev.mouse.mode.packetsize < 0){
			close(evctx.mdev.fd);
			evctx.mdev.fd = -1;
			arcan_warning("unexpected mouse protocol state\n");
			goto sigset;
		}
		int flags = fcntl(evctx.mdev.fd, F_GETFL);
		if (-1 == fcntl(evctx.mdev.fd, F_SETFL, flags | O_NONBLOCK)){
			close(evctx.mdev.fd);
			evctx.mdev.fd = -1;
			arcan_warning("couldn't set non-blocking mouse device\n");
			goto sigset;
		}
	}

sigset:
/* use a pipe to handle TERM / VT switching */
	if (0 != pipe(evctx.sigpipe)){
		arcan_fatal("couldn't create signalling pipe, code: %d, reason: %s\n",
			errno, strerror(errno));

		fcntl(evctx.sigpipe[0], F_SETFD, FD_CLOEXEC);
		fcntl(evctx.sigpipe[1], F_SETFD, FD_CLOEXEC);
		struct sigaction er_sh = {.sa_handler = SIG_IGN};
		sigaction(SIGINT, &er_sh, NULL);
		er_sh.sa_handler = NULL;
		er_sh.sa_sigaction = sigusr_term;
		er_sh.sa_flags = SA_RESTART;
		sigaction(SIGTERM, &er_sh, NULL);
	}
}

void platform_event_reset(arcan_evctx* ctx)
{
	platform_event_deinit(ctx);
	platform_event_init(ctx);
}
