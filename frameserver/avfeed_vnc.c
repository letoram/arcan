#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/types.h>
#include <stddef.h>

#include <rfb/rfbclient.h>
#include <rfb/rfb.h>

#include "../shmif/arcan_shmif.h"
#include "frameserver.h"

static struct {
	struct arcan_shmif_cont shmcont;
	char* pass;
	int depth;
	rfbClient* client;

} vncctx; 

static rfbBool client_resize(struct _rfbClient* client)
{
	int neww = client->width;
	int newh = client->height;

	LOG("resize to %d, %d\n", neww, newh);
	vncctx.depth = client->format.bitsPerPixel;
	client->updateRect.x = 0;
	client->updateRect.y = 0;
	client->updateRect.w = neww;
	client->updateRect.h = newh;

	if (!arcan_shmif_resize(&vncctx.shmcont, neww, newh)){
		LOG("client requested a resize outside "
			"accepted dimensions (%d, %d)\n", neww, newh);
		return false;
	}

	SetFormatAndEncodings(client);
	return true;
}

/*
 * updates server->client is checked by maintaining a statistical selection;
 * corners, center-point, sides at an arbitrary tile size. 
 * (so for a 640x480 screen at a tile-size of 16, we use ~10800 samples
 * vs. 307200 per frame. If this is too little to detect relevant changes,
 * we dynamically select tiles for higher samplerates based on previous
 * validations. ( less than 1% of the samples needed for say, 25Hz)
 * x--x--x
 * |  |  |
 * x--x--x
 * |  |  |
 * x--x--x
 *
 */

static void client_update(rfbClient* client, int x, int y, int w, int h)
{
	LOG("update: %d, %d, %d, %d\n", x, y, w, h);
	arcan_shmif_signal(&vncctx.shmcont, SHMIF_SIGVID);
}

static void client_chat(rfbClient* client, int value, char* msg)
{
/* encode message */
}

static void client_selection(rfbClient* client, const char* text, int len)
{
/* selection message */
}

static char* client_password(rfbClient* client)
{
	return strdup(vncctx.pass);
}

static void client_connect(const char* host)
{
/* how to transfer / set credentials .. */

	LOG("(vnc-cl) connecting to %s\n", host);
	vncctx.client = rfbGetClient(8, 3, 4);
	vncctx.client->MallocFrameBuffer = client_resize;
	vncctx.client->canHandleNewFBSize = true;
	vncctx.client->GotFrameBufferUpdate = client_update;
	vncctx.client->HandleTextChat = client_chat;
	vncctx.client->GotXCutText = client_selection;
	vncctx.client->GetPassword = client_password;

/*
 * possible argc, argv;
 * listen (incoming), listennofork,
 * play (previos recording)
 * encodings (next is type)
 * compress (next is level)
 * scale (next is level)
 * last argument is host 
 */
	int argc = 1;
	char* argv[] = {
		(char*)host,
		NULL
	};

	if (!rfbInitClient(vncctx.client, &argc, argv)){
		LOG("(vnc-cl) couldn't initialize client.\n");
		return;
	}

	LOG("(vnc-cl) connected.\n");
}

static void server_pointer (int buttonMask,int x,int y,rfbClientPtr cl)
{

}

static void server_key(rfbBool down,rfbKeySym key,rfbClientPtr cl)
{
	
}

static enum rfbNewClientAction server_newclient(rfbClientPtr cl)
{
	return RFB_CLIENT_ACCEPT;
}

static void server_loop()
{
	const char* argv[] = {
		"listennofork",
		"scale",
		 "1",
		 NULL
	};

	int argc = 3;

	rfbScreenInfoPtr server = rfbGetScreen(&argc, (char**) argv, 
		vncctx.shmcont.addr->w, vncctx.shmcont.addr->h, 8, 3, 4); 

	server->frameBuffer = (char*) vncctx.shmcont.vidp;
	server->desktopName = "arcan VNC session";
	server->alwaysShared = TRUE; /* what does this one do? */
	server->ptrAddEvent = server_pointer;
	server->kbdAddEvent = server_key;
	server->newClientHook = server_newclient;

	rfbInitServer(server);
	rfbRunEventLoop(server, -1, TRUE);

	arcan_event ev;
	while (arcan_event_wait(&vncctx.shmcont.outev, &ev)){
		switch(ev.kind){
		case TARGET_COMMAND_STEPFRAME:
/* approximate the deviating rectangle, transfer and set flag,
 * remove flag on send rfbMarkRectAsModified(server,0,0,WIDTH,HEIGHT);
 */
		break;
/*
 *rfbRegisterTightVNCFileTransferExtension();
 */
		default:
		break;
		}
	}
}

static void cleanup()
{
	if (vncctx.client)
		rfbClientCleanup(vncctx.client);
}

void arcan_frameserver_avfeed_run(const char* resource, 
	const char* keyfile)
{
	bool server = false;
	struct arg_arr* args = arg_unpack(resource);
	const char* host;
	vncctx.pass = "";
	arg_lookup(args, "pass", 0, (const char**) &vncctx.pass);

	if (!arg_lookup(args, "host", 0, &host)){
		LOG("avfeed_vnc(), no host specified (host=addr:port or host=listen)\n");
		return;	
	}
	
	if (strcmp(host, "listen") == 0){
/* dimensions is set by the parent, so just acquire and use. */
		vncctx.shmcont = arcan_shmif_acquire(keyfile, SHMIF_OUTPUT, true, false); 
		arcan_sem_post(vncctx.shmcont.vsem);
		server_loop();
		return;
	}

/* connect first, then setup etc. */
	int port = 5900;
	const char* argtmp = NULL;
	if (arg_lookup(args, "port", 0, &argtmp)){
		port = strtoul(argtmp, NULL, 10);
	}

	char buf[ strlen(host) + 8];
	snprintf(buf, sizeof(buf), "%s:%d", host, port);
	client_connect(buf);

	vncctx.shmcont = arcan_shmif_acquire(keyfile, 
		server ? SHMIF_OUTPUT : SHMIF_INPUT, true, false);

	atexit( cleanup );

	while (true){
		arcan_event inev;
		while (arcan_event_poll(&vncctx.shmcont.inevq, &inev)){
/* map input for mouse motion, keyboard, exit etc. 
 * use SendKeyEvent for that, need translation table
 */
		}
	}
}
