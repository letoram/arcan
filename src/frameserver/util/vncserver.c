/*
 * VNC- Server Frameserver Support Implementation (Typically used with
 * encoding reference frameserver)
 * Copyright 2014-2015, Björn Ståhl
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
	const char* pass;
	pthread_mutex_t outsync;
	rfbScreenInfoPtr server;
	struct arcan_shmif_cont shmcont;
} vncctx = {0};

struct cl_track {
	unsigned conn_id;
};

static void server_pointer (int buttonMask,int x,int y,rfbClientPtr cl)
{
	arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_CURSORINPUT,
		.ext.cursor.id = ((struct cl_track*)cl->clientData)->conn_id,
		.ext.cursor.x = x,
		.ext.cursor.y = y
	};

	outev.ext.cursor.buttons[0] = buttonMask & (1 << 1);
	outev.ext.cursor.buttons[1] = buttonMask & (1 << 2);
	outev.ext.cursor.buttons[2] = buttonMask & (1 << 3);
	outev.ext.cursor.buttons[3] = buttonMask & (1 << 4);
	outev.ext.cursor.buttons[4] = buttonMask & (1 << 5);

	arcan_shmif_enqueue(&vncctx.shmcont, &outev);
}

static void server_key(rfbBool down,rfbKeySym key,rfbClientPtr cl)
{
	arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_KEYINPUT,
		.ext.key.id = ((struct cl_track*)cl->clientData)->conn_id,
		.ext.key.keysym = 0,
		.ext.key.active = down
	};

	if (key < 65536)
		outev.ext.key.keysym = symtbl_in[key];

	arcan_shmif_enqueue(&vncctx.shmcont, &outev);
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
 * FIXME: subdivide image into a dynamic set of tiles,
 * maintain a backbuffer, compare each tile center (and shared corners)
 * for changes, if change detected, scan outwards until match found.
 * Mark each rect-region as modified.
 *
 * One possible representation for this is to use a display-sized 1byte grid,
 * where you scan like a regular image, and the value represents the next
 * coordinate distance. It's quicker but perhaps not as effective ..
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
	arg_lookup(args, "pass", 0, &vncctx.pass);

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

/*
 * FIXME: missing password auth
 */
	vncctx.server->frameBuffer = (char*) vncctx.shmcont.vidp;
	vncctx.server->desktopName = name;
	vncctx.server->alwaysShared = TRUE;
	vncctx.server->ptrAddEvent = server_pointer;
	vncctx.server->newClientHook = server_newclient;
	vncctx.server->kbdAddEvent = server_key;
	vncctx.server->port = port;

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

