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
	
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;

	int depth;

	rfbClient* client;

	uint8_t* vidp, (* audp);

} vncctx; 

static rfbBool client_resize(struct _rfbClient* client)
{
	int neww = client->width;
	int newh = client->height;

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

static void client_connect(const char* host)
{
/* how to transfer / set credentials .. */

	vncctx.client = rfbGetClient(8, 3, 4);
	vncctx.client->MallocFrameBuffer = client_resize;
	vncctx.client->canHandleNewFBSize = true;
	vncctx.client->GotFrameBufferUpdate = client_update;
	vncctx.client->HandleTextChat = client_chat;
	vncctx.client->GotXCutText = client_selection;

/* what's the contents of argc argv */
	int argc = 0;
	char* argv[] = {NULL};

	if (!rfbInitClient(vncctx.client, &argc, argv)){
		LOG("(vnc-cl) couldn't initialize client.\n");
		return;
	}

/* eventloop, handleRFBServerMessage */
}

static void server_listen()
{
	const char* argv[] = {
		"listennofork",
		"scale",
		 "1"
	};

	vncctx.client = rfbGetClient(8, 3, 4);
	vncctx.client->canHandleNewFBSize = false;
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

	vncctx.shmcont = arcan_shmif_acquire(keyfile, 
		server ? SHMIF_OUTPUT : SHMIF_INPUT, true, false);

	arcan_shmif_setevqs(vncctx.shmcont.addr, vncctx.shmcont.esem,
		&(vncctx.inevq), &(vncctx.outevq), false);

	atexit( cleanup );

	while (true){
		arcan_event inev;
		while (arcan_event_poll(&vncctx.inevq, &inev)){
/* map input for mouse motion, keyboard, exit etc. 
 * use SendKeyEvent for that, need translation table
 */
		}
	}
}
