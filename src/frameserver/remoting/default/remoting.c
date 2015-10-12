/*
 * Arcan Remoting reference Frameserver
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: libvncserver (GPLv2)
 */

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
#include <sys/poll.h>
#include <errno.h>

/*
 * some ports for vncserver install endian.h that push out an annoying warning
 */
#ifdef __APPLE__
#define APPLE
#endif
#include <rfb/rfbclient.h>
#include <rfb/rfb.h>

#include "arcan_shmif.h"
#include "frameserver.h"
#include "xsymconv.h"

/*
 * missing:
 *  cut and paste (GotXCutTextProc), sending receiving files
 *  connecting through incoming descriptor
 *  partial updates
 *  polling / multi
 *  labels
 *  xvb -> force reset (extension)
 *  ExtendedDesktopSize -> respond to displayhints with SetDesktopSize
 *  HandleTextChatProc
 *  FinishedFramebuffferUpdateProc
 *  rfbRegisterTightVNCFileTransferExtension()
 *  desktopName propagation
 *  specifyEncodingType
 */

static struct {
	struct arcan_shmif_cont shmcont;
	char* pass;
	int depth;
	rfbClient* client;
	bool dirty, forcealpha;
} vncctx = {0};

int mouse_button_map[] = {
	rfbButton1Mask,
	rfbButton3Mask,
	rfbButton2Mask,
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
	else
		LOG("client resize to %d, %d\n", neww, newh);

	client->frameBuffer = (uint8_t*) vncctx.shmcont.vidp;
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
			kv = ioev->subid;

		SendKeyEvent(vncctx.client, kv, ioev->input.translated.active);
	}
/* just use one of the first four buttons of any device, not necessarily
 * a mouse */
	else if (ioev->datatype == EVENT_IDATATYPE_DIGITAL){
		int btn = ioev->subid-1;
		int value = 0;

		if (btn >= 0 && btn <= 4)
			value = mouse_button_map[btn];

		bmask = ioev->input.digital.active ? bmask | value : bmask & ~value;
		SendPointerEvent(vncctx.client, mx, my, bmask);
	}
	else if (ioev->datatype == EVENT_IDATATYPE_ANALOG &&
		ioev->devkind == EVENT_IDEVKIND_MOUSE){
		if (ioev->subid == 0)
			mx = ioev->input.analog.axisval[0];
		else if (ioev->subid == 1)
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

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" password\t val       \t use this (7-bit ascii) password for auth\n"
	  " host    \t hostname  \t connect to the specified host\n"
		" port    \t portnum   \t use the specified port for connecting\n"
		" forcealpha           \t set alpha channel to fullbright (normally off)\n"
		"---------\t-----------\t----------------\n"
	);
}

bool process_shmif()
{
	arcan_event inev;

	while (arcan_shmif_poll(&vncctx.shmcont, &inev) > 0){
		if (inev.category == EVENT_TARGET)
			switch(inev.tgt.kind){
			case TARGET_COMMAND_STEPFRAME:
				SendFramebufferUpdateRequest(vncctx.client, 0, 0,
					vncctx.shmcont.addr->w, vncctx.shmcont.addr->h, FALSE);
			break;

			case TARGET_COMMAND_EXIT:
				return false;

			case TARGET_COMMAND_RESET:
				cl_unstick();
			break;

			default:
				LOG("unhandled target event (%d:%s)\n",
					inev.tgt.kind, arcan_shmif_eventstr(&inev, NULL, 0));
			}
			else if (inev.category == EVENT_IO)
				map_cl_input(&inev.io);
			else
				LOG("unhandled event (%d:%s)\n", inev.tgt.kind,
					arcan_shmif_eventstr(&inev, NULL, 0));
		}
	return true;
}

int afsrv_remoting(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	const char* host;
	vncctx.pass = "";
	if (!args || !con){
		dump_help();
		return EXIT_FAILURE;
	}

	arg_lookup(args, "password", 0, (const char**) &vncctx.pass);

	if (!arg_lookup(args, "host", 0, &host)){
		LOG("avfeed_vnc(), no host specified (host=addr:port or host=listen)\n");
		return EXIT_FAILURE;
	}

	gen_symtbl();

/* client connect / loop */
	int port = 5900;
	const char* argtmp = NULL;
	if (arg_lookup(args, "port", 0, &argtmp)){
		port = strtoul(argtmp, NULL, 10);
	}

	if (arg_lookup(args, "noalpha", 0, &argtmp))
		vncctx.forcealpha = true;

	vncctx.shmcont = *con;

	if (!client_connect(host, port))
		return EXIT_FAILURE;

	arcan_event ev_cfail = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(FAILURE),
		.ext.message = "(01) server connection broken"
	};

/* this is cheating a bit as we don't guarantee the color format used */
	vncctx.client->frameBuffer = (uint8_t*) vncctx.shmcont.vidp;
	atexit( cleanup );

	short poller = POLLHUP | POLLNVAL;
	short pollev = POLLIN | poller;

	while (true){
/* no obvious way to make vncclient set full alpha channel without modifying
 * source code, and that means pulling it in and patching in the build system,
 * so for now, take the suboptimal "flip alpha on" */
		if (vncctx.dirty){
			vncctx.dirty = false;
			shmif_pixel* avp = vncctx.shmcont.vidp;
			size_t ntc = vncctx.shmcont.pitch * vncctx.shmcont.h;

			if (vncctx.forcealpha)
			for (size_t i = 0; i < ntc; i++)
				avp[i] |= RGBA(0x00, 0x00, 0x00, 0xff);

			arcan_shmif_signal(&vncctx.shmcont, SHMIF_SIGVID);
		}

		struct pollfd fds[2] = {
			{	.fd = vncctx.client->sock, .events = pollev},
			{ .fd = vncctx.shmcont.epipe, .events = pollev}
		};

		int sv = poll(fds, 2, -1);
		if (0 == sv)
			continue;

		if (-1 == sv){
			if (errno == EINTR || errno == EAGAIN)
				continue;
			else{
				LOG("polling on arcan signalling socket / RFB connection failed\n");
				break;
			}
		}

		if ( ((fds[0].revents & POLLIN) && !HandleRFBServerMessage(vncctx.client))
			|| (fds[0].revents & poller)){
			arcan_shmif_enqueue(&vncctx.shmcont, &ev_cfail);
			arcan_shmif_drop(&vncctx.shmcont);
			break;
		}

		int rev = fds[1].revents;
		if ( ((rev & POLLIN)) ){
			if (!process_shmif()){
				LOG("arcan- connection requested termination.\n");
				break;
			}
			if ((rev & poller)){
				uint8_t buf;
				if (-1 == read(fds[1].fd, &buf, 1)){
					LOG("arcan- connection socket failure: %s\n", strerror(errno));
				}
				else
					LOG("arcan connection suspiciously failed poll"
						" hup: %s, err: %s, nval: %s\n", (rev & POLLERR) ? "yes" : "no",
						(rev & POLLHUP) ? "yes" : "no", (rev & POLLNVAL) ? "yes" : "no");
				break;
			}
		}
	}
/* shutdown */
	return EXIT_SUCCESS;
}
