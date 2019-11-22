/*
 * VNC- Server Frameserver Support Implementation (Typically used with
 * encoding reference frameserver)
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: libvncserver (GPLv2)
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <rfb/rfb.h>

#include <arcan_shmif.h>
#include <arcan_tuisym.h>

#define DEFINE_XKB
#include "xsymconv.h"

static struct {
	const char* pass[2];
	pthread_mutex_t outsync;
	rfbScreenInfoPtr server;
	int last_x, last_y;
	int last_mask;
	struct arcan_shmif_cont shmcont;
	int client_counter;
} vncctx = {0};

struct cl_track {
	unsigned conn_id;

/* modifier mask */
	bool lshift, rshift, lctrl, rctrl, lalt, ralt, lmeta, rmeta;
};

static int vnc_btn_to_shmif(int i)
{
	switch (i){
	case 0: return MBTN_LEFT_IND;
	case 1: return MBTN_MIDDLE_IND;
	case 2: return MBTN_RIGHT_IND;
	case 3: return MBTN_WHEEL_DOWN_IND;
	case 4: return MBTN_WHEEL_UP_IND;
	}

	return i;
}

static void server_pointer (int buttonMask,int x,int y,rfbClientPtr cl)
{
/*
 * synch cursor position on change only, could theoretically allow multiple
 * cursors here by differentiating subid with a cl- derived identifier
 */
	if (vncctx.last_x != x || vncctx.last_y != y){
		struct arcan_event mouse = {
			.category = EVENT_IO,
			.io = {
				.kind = EVENT_IO_AXIS_MOVE,
				.devid = getpid(),
				.datatype = EVENT_IDATATYPE_ANALOG,
				.devkind = EVENT_IDEVKIND_MOUSE,
				.input.analog.gotrel = false,
				.input.analog.nvalues = 1
			}
		};

		if (vncctx.last_x != x){
			mouse.io.input.analog.axisval[0] = x;
			arcan_shmif_enqueue(&vncctx.shmcont, &mouse);
		}

		if (vncctx.last_y != y){
			mouse.io.input.analog.axisval[0] = y;
			mouse.io.subid = 1;
			arcan_shmif_enqueue(&vncctx.shmcont, &mouse);
		}

		vncctx.last_x = x;
		vncctx.last_y = y;
	}

/*
 * synch button state on change
 */
	if (buttonMask != vncctx.last_mask){
		for (size_t i = 0; i < 5; i++){
			if (((1 << i) & buttonMask) != ((1 << i) & vncctx.last_mask)){
				arcan_shmif_enqueue(&vncctx.shmcont, &(struct arcan_event){
					.category = EVENT_IO,
					.io = {
						.kind = EVENT_IO_BUTTON,
						.subid = vnc_btn_to_shmif(i),
						.datatype = EVENT_IDATATYPE_DIGITAL,
						.devkind = EVENT_IDEVKIND_MOUSE,
						.devid = getpid(),
						.input.digital.active = !!((1 << i & buttonMask) > 0)
					}
				});
			}
		}
		vncctx.last_mask = buttonMask;
	}
}

/*
 * copied from src/platform/sdl/event.c
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

/*
 * in the SDL lower layers these are blocked from presenting as
 * unicode, but here we get ' ' for many of them instead so need
 * separate filtering.
 */
static bool blocked_sym(uint16_t sym)
{
	return (sym &&
		sym < TUIK_SPACE) || (sym >= TUIK_F1 && sym <= TUIK_F12);
}

static arcan_event sdl_keydown(
	uint8_t scancode, uint16_t mod, uint16_t sym, uint16_t unicode)
{
	arcan_event newevent = {.category = EVENT_IO};

	newevent.io.datatype = EVENT_IDATATYPE_TRANSLATED;
	newevent.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
	newevent.io.input.translated.active = true;
	newevent.io.input.translated.keysym = sym;
	newevent.io.input.translated.modifiers = mod;
	newevent.io.input.translated.scancode = scancode;
	newevent.io.subid = unicode;

	if (!((mod & (ARKMOD_LCTRL | ARKMOD_RCTRL)) > 0)
		&& !blocked_sym(sym))
		to_utf8(unicode, newevent.io.input.translated.utf8);

	return newevent;
}

static arcan_event sdl_keyup(
	uint8_t scancode, uint16_t mod, uint16_t sym, uint16_t unicode)
{
	arcan_event newevent = {.category = EVENT_IO};

	newevent.io.datatype = EVENT_IDATATYPE_TRANSLATED;
	newevent.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
	newevent.io.input.translated.active = false;
	newevent.io.input.translated.keysym = sym;
	newevent.io.input.translated.modifiers = mod;
	newevent.io.input.translated.scancode = scancode;
	newevent.io.subid = unicode;

	return newevent;
}

static uint16_t track_modifiers(
	struct cl_track* cl, bool down, rfbKeySym key)
{
/* so why is there a XK_Shift and XKB_KEY, question for the ages */
	switch(key){
		case XKB_KEY_Shift_R:
			cl->rshift = down;
		break;
		case XKB_KEY_Shift_L:
			cl->lshift = down;
		break;
		case XKB_KEY_Control_L:
			cl->lctrl = down;
		break;
		case XKB_KEY_Control_R:
			cl->rctrl = down;
		break;
		case XKB_KEY_Alt_R:
			cl->ralt = down;
		break;
		case XKB_KEY_Alt_L:
			cl->lalt = down;
		break;
		case XKB_KEY_Super_R:
			cl->rmeta = down;
		break;
		case XKB_KEY_Super_L:
			cl->lmeta = down;
		break;
		default:
		break;
	}

/* then we have the latched modifiers as well (caps lock, num lock, scroll lock) */
	return
		(cl->lshift * TUIM_LSHIFT) |
		(cl->rshift * TUIM_RSHIFT) |
		(cl->lctrl  * TUIM_LCTRL ) |
		(cl->rctrl  * TUIM_RCTRL ) |
		(cl->lalt   * TUIM_LALT  ) |
		(cl->lalt   * TUIM_LALT  ) |
		(cl->lmeta  * TUIM_LMETA ) |
		(cl->rmeta  * TUIM_RMETA);
}

static void server_key(rfbBool down,rfbKeySym key,rfbClientPtr cl)
{
/*
 * since rfb only reasons in X keys, we either need to plug it through
 * libxkbcommon (platform/evdev has the approach for that, as well as
 * src/tool/waybridge).
 */
	uint16_t mod = track_modifiers(cl->clientData, down, key);

/*
 * first convert the rfbKeySym to the corresponding SDL one to mimic
 * the behaviour in our old sdl video platform
 */
	uint8_t scancode = 0;
	uint16_t sym = symtbl_in[key];

/* just plugged into subid */
	uint16_t unicode = key;

	struct arcan_event ev = down ?
		sdl_keydown(scancode, mod, sym, unicode) : sdl_keyup(scancode, mod, sym, unicode);

	arcan_shmif_enqueue(&vncctx.shmcont, &ev);
}

static void server_dropclient(rfbClientPtr cl)
{
	assert(cl->clientData);
	free(cl->clientData);
	cl->clientData = NULL;
}

static enum rfbNewClientAction server_newclient(rfbClientPtr cl)
{
	struct cl_track* clt = malloc(sizeof(struct cl_track));
	static int step_c;

	memset(clt, '\0', sizeof(struct cl_track));
	clt->conn_id = step_c++;
	cl->clientData = clt;
	cl->clientGoneHook = server_dropclient;

	return RFB_CLIENT_ACCEPT;
}

static void vnc_serv_deltaupd()
{
/*
 * We're missing a delta- function here, the reason it isn't implemented
 * yet is that we want the feature to be part of the server- shmif side
 * as it can be made more efficiently there.
 */
	struct arcan_shmif_region dirty;
	dirty = atomic_load(&vncctx.shmcont.addr->dirty);
	if (dirty.x2 < vncctx.shmcont.w)
		dirty.x2++;
	if (dirty.y2 < vncctx.shmcont.h)
		dirty.y2++;

	rfbMarkRectAsModified(vncctx.server, dirty.x1, dirty.y1, dirty.x2, dirty.y2);
	vncctx.shmcont.addr->vready = false;
}

void vnc_serv_run(struct arg_arr* args, struct arcan_shmif_cont cont)
{
/* at this point, we really should drop ALL syscalls
 * that aren't strict related to socket manipulation */
	int port = 5900;
	gen_symtbl();

	vncctx.shmcont = cont;

	const char* tmpstr;

	const char* name;
	if (!arg_lookup(args, "name", 0, &name))
		name = "Arcan VNC session";

	if (arg_lookup(args, "port", 0, &tmpstr)){
		port = strtoul(tmpstr, NULL, 10);
	}

	int argc = 0;
	char* argv[] = {NULL};

	vncctx.server = rfbGetScreen(&argc, (char**) argv,
		vncctx.shmcont.addr->w, vncctx.shmcont.addr->h, 8, 3, 4);

/*
 * other relevant members;
 * width, height, (nevershared or alwaysshared) dontdisconnect,
 * port, autoport, width should be %4==0,
 * permitFileTransfer, maxFd, authPasswd, ...
 */

	if (arg_lookup(args, "pass", 0, &vncctx.pass[0]) && vncctx.pass[0][0] != '\0'){
		vncctx.server->passwordCheck = rfbCheckPasswordByList;
		vncctx.server->authPasswdData = (void*)vncctx.pass;
	}

	vncctx.server->frameBuffer = (char*) vncctx.shmcont.vidp;
	vncctx.server->desktopName = name;
	vncctx.server->alwaysShared = TRUE;
	vncctx.server->ptrAddEvent = server_pointer;
	vncctx.server->newClientHook = server_newclient;
	vncctx.server->kbdAddEvent = server_key;
	vncctx.server->port = port;
	vncctx.server->serverFormat.redShift = SHMIF_RGBA_RSHIFT;
	vncctx.server->serverFormat.greenShift = SHMIF_RGBA_GSHIFT;
	vncctx.server->serverFormat.blueShift = SHMIF_RGBA_BSHIFT;

/*
 * other hooks;
 * server->getCursorPtr, setTranslateFunction, displayHook,
 * displayFinishedHook, KeyboardLedStateHook, xvpHook, setXCutText
 *
 */

	rfbInitServer(vncctx.server);
	rfbRunEventLoop(vncctx.server, -1, TRUE);

	arcan_event ev;
	while (arcan_shmif_wait(&vncctx.shmcont, &ev) != 0){
		if (ev.category != EVENT_TARGET)
			continue;

		switch(ev.tgt.kind){
		case TARGET_COMMAND_STEPFRAME:
			while (!vncctx.shmcont.addr->vready){
			}
			vnc_serv_deltaupd();
		break;

		case TARGET_COMMAND_EXIT:
			goto done;
		break;

		default:
			LOG("unknown: %d\n", ev.tgt.kind);
		}
	}

done:
	return;
}

