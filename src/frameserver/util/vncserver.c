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
#include "vncserver.h"
#include "xsymconv.h"

static struct {
	const char* pass[2];
	pthread_mutex_t outsync;
	rfbScreenInfoPtr server;
	int last_x, last_y;
	int last_mask;
	struct arcan_shmif_cont shmcont;
} vncctx = {0};

struct cl_track {
	unsigned conn_id;
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

static void server_key(rfbBool down,rfbKeySym key,rfbClientPtr cl)
{
/*
 * A possible option here would be to time and track modifier keys and
 * have a timed safety release etc. in the event of client errors (not
 * uncommon).
 */
	arcan_shmif_enqueue(&vncctx.shmcont, &(struct arcan_event){
		.category = EVENT_IO,
		.io = {
		.devid = getpid(),
		.subid = key,
			.kind = EVENT_IO_BUTTON,
			.devkind = EVENT_IDEVKIND_KEYBOARD,
			.datatype = EVENT_IDATATYPE_TRANSLATED,
			.input.translated = {
				.active = down,
				.keysym = (key < 65536 ? symtbl_in[key] : 0)
			}
		}
	});
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
	rfbMarkRectAsModified(vncctx.server, 0, 0,
		vncctx.shmcont.addr->w, vncctx.shmcont.addr->h);
	vncctx.shmcont.addr->vready = false;
}

void vnc_serv_run(struct arg_arr* args, struct arcan_shmif_cont cont)
{
/* at this point, we really should drop ALL syscalls
 * that aren't strict related to socket manipulation */
	int port = 5900;
	gen_symtbl();

	vncctx.shmcont = cont;

	const char* name = "Arcan VNC session";
	const char* tmpstr;

	arg_lookup(args, "name", 0, &name);

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

	if (SHMIF_RGBA(0xff, 0x00, 0x00, 0x00) == 0xff000000)
		vncctx.server->serverFormat.redShift = 24;
	else if (SHMIF_RGBA(0xff, 0x00, 0x00, 0x00) == 0x00ff0000)
		vncctx.server->serverFormat.redShift = 16;
	else if (SHMIF_RGBA(0xff, 0x00, 0x00, 0x00) == 0x0000ff00)
		vncctx.server->serverFormat.redShift = 8;
	else
		vncctx.server->serverFormat.redShift = 0;

	if (SHMIF_RGBA(0x00, 0xff, 0x00, 0x00) == 0xff000000)
		vncctx.server->serverFormat.greenShift = 24;
	else if (SHMIF_RGBA(0x00, 0xff, 0x00, 0x00) == 0x00ff0000)
		vncctx.server->serverFormat.greenShift = 16;
	else if (SHMIF_RGBA(0x00, 0xff, 0x00, 0x00) == 0x0000ff00)
		vncctx.server->serverFormat.greenShift = 8;
	else
		vncctx.server->serverFormat.greenShift = 0;

	if (SHMIF_RGBA(0x00, 0x00, 0xff, 0x00) == 0xff000000)
		vncctx.server->serverFormat.blueShift = 24;
	else if (SHMIF_RGBA(0x00, 0x00, 0xff, 0x00) == 0x00ff0000)
		vncctx.server->serverFormat.blueShift = 16;
	else if (SHMIF_RGBA(0x00, 0x00, 0xff, 0x00) == 0x0000ff00)
		vncctx.server->serverFormat.blueShift = 8;
	else
		vncctx.server->serverFormat.blueShift = 0;

	vncctx.server->serverFormat.redShift =
		SHMIF_RGBA(0xff, 0x00, 0x00, 0x00) == 0xff000000 ? 24 : 0;
	vncctx.server->serverFormat.greenShift =
		SHMIF_RGBA(0x00, 0xff, 0x00, 0x00) == 0x00ff0000 ? 16 : 8;
	vncctx.server->serverFormat.blueShift =
		SHMIF_RGBA(0x00, 0x00, 0xff, 0x00) == 0x0000ff00 ? 8 : 16;

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

