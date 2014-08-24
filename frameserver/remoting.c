#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/types.h>
#include <stddef.h>
#include <pthread.h>

#include <rfb/rfbclient.h>
#include <rfb/rfb.h>

#include "../shmif/arcan_shmif.h"
#include "frameserver.h"
#include "xsymconv.h"

static struct {
	struct arcan_shmif_cont shmcont;
	char* pass;
	int depth;
	rfbClient* client;
	bool dirty;
} vncctx = {0};

int mouse_button_map[] = {
	rfbButton1Mask,
	rfbButton2Mask,
	rfbButton3Mask,
	rfbButton4Mask,
	rfbButton5Mask
};

static rfbBool client_resize(struct _rfbClient* client)
{
	int neww = client->width;
	int newh = client->height;

	vncctx.depth = client->format.bitsPerPixel / 8;
	client->updateRect.x = 0;
	client->updateRect.y = 0;
	client->updateRect.w = neww;
	client->updateRect.h = newh;
	client->format.bitsPerPixel = 32;

	if (!arcan_shmif_resize(&vncctx.shmcont, neww, newh)){
		LOG("client requested a resize outside "
			"accepted dimensions (%d, %d)\n", neww, newh);
		return false;
	}

	client->frameBuffer = vncctx.shmcont.vidp;
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
	vncctx.dirty = true;
}

static void client_chat(rfbClient* client, int value, char* msg)
{
/*
 * send as message;
 * we have rfbTextChatOpen, rfbTextChatClose, rfbTextChatFinished
 */
	if (msg)
		LOG("msg (%s)\n", msg);
}

static void client_selection(rfbClient* client, const char* text, int len)
{
/* selection message */
	LOG("selection (%s)\n", text);
}

static void client_keyled(rfbClient* client, int state, int mode)
{
	LOG("ledstate (%d, %d)\n", state, mode);
}

static char* client_password(rfbClient* client)
{
	LOG("(vnc-cl) requested password\n");
	return strdup(vncctx.pass);
}

static bool client_connect(const char* host, int port)
{
/* how to transfer / set credentials .. */

	LOG("(vnc-cl) connecting to %s:%d\n", host, port);
	vncctx.client = rfbGetClient(8, 3, 4);
	vncctx.client->MallocFrameBuffer = client_resize;
	vncctx.client->canHandleNewFBSize = true;
	vncctx.client->GotFrameBufferUpdate = client_update;
	vncctx.client->HandleTextChat = client_chat;
	vncctx.client->GotXCutText = client_selection;
	vncctx.client->GetPassword = client_password;
	vncctx.client->HandleKeyboardLedState = client_keyled;
	vncctx.client->serverHost = strdup(host);
	vncctx.client->serverPort = port;

/*
 Note, if these are set, Rfb will actually BOUNCE
	vncctx.client->destHost = strdup(host);
	vncctx.client->destPort = port;
 */

	if (!rfbInitClient(vncctx.client, NULL, NULL)){
		LOG("(vnc-cl) couldn't initialize client.\n");
		return false;
	}

	LOG("(vnc-cl) connected.\n");
	return true;
}

static void cleanup()
{
	if (vncctx.client)
		rfbClientCleanup(vncctx.client);
}

static void cl_unstick()
{
	SendKeyEvent(vncctx.client, XK_Shift_R, false);
	SendKeyEvent(vncctx.client, XK_Shift_L, false);
	SendKeyEvent(vncctx.client, XK_Control_R, false);
	SendKeyEvent(vncctx.client, XK_Control_L, false);
	SendKeyEvent(vncctx.client, XK_Alt_R, false);
	SendKeyEvent(vncctx.client, XK_Alt_L, false);
	SendKeyEvent(vncctx.client, XK_Meta_R, false);
	SendKeyEvent(vncctx.client, XK_Meta_L, false);
	SendKeyEvent(vncctx.client, XK_Super_L, false);
	SendKeyEvent(vncctx.client, XK_Super_R, false);
}

static void map_cl_input(arcan_ioevent* ioev)
{
	static int mcount, mx, my, bmask;
	int sym = ioev->input.translated.keysym;

	if (ioev->devkind != EVENT_IDEVKIND_KEYBOARD &&
		ioev->devkind != EVENT_IDEVKIND_MOUSE)
			return;

	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		int kv = 0;

		if (sym >= 0 && sym < sizeof(symtbl_out) / sizeof(symtbl_out[0])){
			kv = symtbl_out[sym];
		}

/* last resort, just use the unicode value and hope for the best */
		if (kv == 0)
			kv = ioev->input.translated.subid;

		printf("kv: %d, in: %d, mod: %d\n",
			ioev->input.translated.keysym, kv,
			ioev->input.translated.modifiers);

		SendKeyEvent(vncctx.client, kv, ioev->input.translated.active);
	}
	else if (ioev->datatype == EVENT_IDATATYPE_DIGITAL){
		int btn = ioev->input.digital.subid;
		int value = 0;

		if (btn >= 0 && btn <= 4)
			value = mouse_button_map[btn];

		bmask = ioev->input.digital.active ? bmask | value : bmask & ~value;
		SendPointerEvent(vncctx.client, mx, my, bmask);
	}
	else if (ioev->datatype == EVENT_IDATATYPE_ANALOG){
		if (ioev->input.analog.subid == 0)
			mx = ioev->input.analog.axisval[0];
		else if (ioev->input.analog.subid == 1)
			my = ioev->input.analog.axisval[0];

/* only send when we get updates in pairs */
		if (++mcount % 2){
			mcount = 0;
			SendPointerEvent(vncctx.client, mx, my, bmask);
		}
	}

	SendFramebufferUpdateRequest(vncctx.client, 0, 0, vncctx.shmcont.addr->w,
		vncctx.shmcont.addr->h, true);
}


void arcan_frameserver_remoting_run(const char* resource,
	const char* keyfile)
{
	struct arg_arr* args = arg_unpack(resource);
	const char* host;
	vncctx.pass = "";
	arg_lookup(args, "password", 0, (const char**) &vncctx.pass);

	if (!arg_lookup(args, "host", 0, &host)){
		LOG("avfeed_vnc(), no host specified (host=addr:port or host=listen)\n");
		return;
	}

	gen_symtbl();

/* client connect / loop */
	int port = 5900;
	const char* argtmp = NULL;
	if (arg_lookup(args, "port", 0, &argtmp)){
		port = strtoul(argtmp, NULL, 10);
	}

	vncctx.shmcont = arcan_shmif_acquire(keyfile, SHMIF_INPUT, true, false);
	if (!client_connect(host, port)){
		return;
	}

	arcan_event regev = {
		.category = EVENT_EXTERNAL,
		.kind = EVENT_EXTERNAL_REGISTER,
		.data.external.registr.kind = SEGID_REMOTING,
		.data.external.registr.title = "VNC Client",
	};
	arcan_event_enqueue(&vncctx.shmcont.outev, &regev);

	vncctx.client->frameBuffer = vncctx.shmcont.vidp;
	atexit( cleanup );

	while (true){
		int rc = WaitForMessage(vncctx.client, 100);
		if (-1 == rc){
			arcan_event outev = {
				.category = EVENT_EXTERNAL,
				.kind = EVENT_EXTERNAL_FAILURE,
				.data.external.message = "(01) server connection broken"
			};

			arcan_event_enqueue(&vncctx.shmcont.outev, &outev);
			break;
		}

		if (rc > 0)
			if (!HandleRFBServerMessage(vncctx.client)){
				arcan_event outev = {
					.category = EVENT_EXTERNAL,
					.kind = EVENT_EXTERNAL_FAILURE,
					.data.external.message = "(02) couldn't parse server message"
				};

				arcan_event_enqueue(&vncctx.shmcont.outev, &outev);
				break;
			}

		if (vncctx.dirty){
			vncctx.dirty = false;
/*
 * couldn't find a decent flag to set this in
 * the first draw batch unfortunately
 */
			int nb = vncctx.shmcont.addr->w * vncctx.shmcont.addr->h *
				ARCAN_SHMPAGE_VCHANNELS;

			for (int ofs = ARCAN_SHMPAGE_VCHANNELS-1;
				ofs < nb; ofs += ARCAN_SHMPAGE_VCHANNELS)
				vncctx.shmcont.vidp[ofs] = 0xff;

			arcan_shmif_signal(&vncctx.shmcont, SHMIF_SIGVID);
		}

		arcan_event inev;
		while (arcan_event_poll(&vncctx.shmcont.inev, &inev) == 1){
			if (inev.category == EVENT_TARGET)
				switch(inev.kind){
				case TARGET_COMMAND_STEPFRAME:
					SendFramebufferUpdateRequest(vncctx.client, 0, 0,
						vncctx.shmcont.addr->w, vncctx.shmcont.addr->h, FALSE);
				break;

				case TARGET_COMMAND_EXIT:
					return;

				case TARGET_COMMAND_RESET:
					cl_unstick();
				break;

				default:
					LOG("unhandled target event (%d)\n", inev.kind);
				}
			else if (inev.category == EVENT_IO)
				map_cl_input(&inev.data.io);
			else
				LOG("unhandled event (%d:%d)\n", inev.kind, inev.category);
		}
/* map input for mouse motion, keyboard, exit etc.
 * use SendKeyEvent for that, need translation table
 */
	}
}
