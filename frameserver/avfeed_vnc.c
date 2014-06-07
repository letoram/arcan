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

static struct {
	struct arcan_shmif_cont shmcont;
	char* pass;
	int depth;
	rfbClient* client;
	bool dirty;
} vncctx = {0}; 

static int symtbl_out[1024];
static int* symtbl_in;

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

	if (text)
		LOG("chat (%s)\n", text);
}

static void client_selection(rfbClient* client, const char* text, int len)
{
/* selection message */
	LOG("selection (%s)\n", text);
}

static char* client_password(rfbClient* client)
{
	LOG("(vnc-cl) requested password\n");
	return strdup(vncctx.pass);
}

static 

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
	vncctx.client->HandleKeyboardLedState = client_keyled;

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

static void map_cl_input(arcan_ioevent* ioev)
{
	static int mcount, mx, my, bmask;

	if (ioev->devkind != EVENT_IDEVKIND_KEYBOARD && 
		ioev->devkind != EVENT_IDEVKIND_MOUSE)
			return;

	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		int kv = 0;
	
		if (ioev->input.translated.keysym >= 0 &&
			ioev->input.translated.keysym < sizeof(symtbl_out) / sizeof(symtbl_out[0])){
			kv = symtbl_out[ioev->input.translated.keysym];
		}

		if (kv == 0)
			kv = ioev->input.translated.subid;

		SendKeyEvent(vncctx.client, kv, ioev->input.digital.active);		
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

/* 
 * Bidirectional internal <-> X keysym translation table
 * Patched together from Xev dumps + ClanLib (BSD licensed)
 */
static void gen_symtbl()
{
	symtbl_out[8] = XK_BackSpace;
	symtbl_out[9] = XK_Tab;
	symtbl_out[12] = XK_Clear;
	symtbl_out[13] = XK_Return;
	symtbl_out[19] = XK_Pause;
	symtbl_out[27] = XK_Escape;
	symtbl_out[32] = XK_space;
	symtbl_out[127] = XK_Delete;
	symtbl_out[256] = XK_KP_0;
	symtbl_out[257] = XK_KP_1;
	symtbl_out[258] = XK_KP_2;
	symtbl_out[259] = XK_KP_3;
	symtbl_out[260] = XK_KP_4;
	symtbl_out[261] = XK_KP_5;
	symtbl_out[262] = XK_KP_6;
	symtbl_out[263] = XK_KP_7;
	symtbl_out[264] = XK_KP_8;
	symtbl_out[265] = XK_KP_9;
	symtbl_out[266] = XK_KP_Decimal;
	symtbl_out[267] = XK_KP_Divide;
	symtbl_out[268] = XK_KP_Multiply; 
	symtbl_out[269] = XK_KP_Subtract;
	symtbl_out[270] = XK_KP_Add;
	symtbl_out[271] = XK_KP_Enter;
	symtbl_out[272] = XK_KP_Equal;
	symtbl_out[273] = XK_KP_Up;
	symtbl_out[274] = XK_KP_Down;
	symtbl_out[275] = XK_KP_Left;
	symtbl_out[276] = XK_KP_Right;
	symtbl_out[277] = XK_KP_Insert;
	symtbl_out[278] = XK_KP_Home;
	symtbl_out[279] = XK_KP_End;
	symtbl_out[280] = XK_KP_Page_Up;
	symtbl_out[281] = XK_KP_Page_Down;
	symtbl_out[282] = XK_F1;
	symtbl_out[283] = XK_F2;
	symtbl_out[284] = XK_F3;
	symtbl_out[285] = XK_F4;
	symtbl_out[286] = XK_F5;
	symtbl_out[287] = XK_F6;
	symtbl_out[288] = XK_F7;
	symtbl_out[289] = XK_F8;
	symtbl_out[290] = XK_F9;
	symtbl_out[291] = XK_F10;
	symtbl_out[292] = XK_F11;
	symtbl_out[293] = XK_F12;
	symtbl_out[294] = XK_F13;
	symtbl_out[295] = XK_F14;
	symtbl_out[296] = XK_F15;
	symtbl_out[300] = XK_Num_Lock;
	symtbl_out[301] = XK_Caps_Lock;
	symtbl_out[302] = XK_Scroll_Lock;
	symtbl_out[303] = XK_Shift_R;
	symtbl_out[304] = XK_Shift_L;
	symtbl_out[305] = XK_Control_R;
	symtbl_out[306] = XK_Control_L;
	symtbl_out[307] = XK_Alt_R;
	symtbl_out[308] = XK_Alt_L;
	symtbl_out[309] = XK_Meta_R;
	symtbl_out[310] = XK_Meta_L;
	symtbl_out[311] = XK_Super_L;
	symtbl_out[312] = XK_Super_R;
	symtbl_out[313] = XK_Mode_switch;
	symtbl_out[315] = XK_Help;
	symtbl_out[316] = XK_Print;
	symtbl_out[317] = XK_Sys_Req;
	symtbl_out[318] = XK_Break;
	symtbl_out[58] = XK_colon;
	symtbl_out[59] = XK_semicolon;
	symtbl_out[60] = XK_less;
	symtbl_out[61] = XK_equal;
	symtbl_out[62] = XK_greater;
	symtbl_out[63] = XK_question;
	symtbl_out[64] = XK_at;
	symtbl_out[91] = XK_bracketleft;
	symtbl_out[92] = XK_backslash;
	symtbl_out[93] = XK_bracketright;
	symtbl_out[94] = XK_asciicircum;
	symtbl_out[95] = XK_underscore;
	symtbl_out[96] = XK_quoteleft;
	symtbl_out[97] = XK_a;
	symtbl_out[98] = XK_b;
	symtbl_out[99] = XK_c;
	symtbl_out[100] = XK_d;
	symtbl_out[101] = XK_e;
	symtbl_out[102] = XK_f;
	symtbl_out[103] = XK_g;
	symtbl_out[104] = XK_h;
	symtbl_out[105] = XK_i;
	symtbl_out[106] = XK_j;
	symtbl_out[107] = XK_k;
	symtbl_out[108] = XK_l;
	symtbl_out[109] = XK_m;
	symtbl_out[110] = XK_n;
	symtbl_out[111] = XK_o;
	symtbl_out[112] = XK_p;
	symtbl_out[113] = XK_q;
	symtbl_out[114] = XK_r;
	symtbl_out[115] = XK_s;
	symtbl_out[116] = XK_t;
	symtbl_out[117] = XK_u;
	symtbl_out[118] = XK_v;
	symtbl_out[119] = XK_w;
	symtbl_out[120] = XK_x;
	symtbl_out[121] = XK_y;
	symtbl_out[122] = XK_z;
	symtbl_out[160] = XK_nobreakspace;
	symtbl_out[161] = XK_exclamdown;
	symtbl_out[162] = XK_cent;
	symtbl_out[163] = XK_sterling;
	symtbl_out[164] = XK_currency;
	symtbl_out[165] = XK_yen;
	symtbl_out[166] = XK_brokenbar;
	symtbl_out[167] = XK_section;
	symtbl_out[168] = XK_diaeresis;
	symtbl_out[169] = XK_copyright;
	symtbl_out[170] = XK_ordfeminine;
	symtbl_out[171] = XK_guillemotleft;
	symtbl_out[172] = XK_notsign;
	symtbl_out[173] = XK_hyphen;
	symtbl_out[174] = XK_registered;
	symtbl_out[175] = XK_macron;
	symtbl_out[176] = XK_degree;
	symtbl_out[177] = XK_plusminus;
	symtbl_out[178] = XK_twosuperior;
	symtbl_out[179] = XK_threesuperior;
	symtbl_out[180] = XK_acute;
	symtbl_out[181] = XK_mu;
	symtbl_out[182] = XK_paragraph;
	symtbl_out[183] = XK_periodcentered;
	symtbl_out[184] = XK_cedilla;
	symtbl_out[185] = XK_onesuperior;
	symtbl_out[186] = XK_masculine;
	symtbl_out[187] = XK_guillemotright;
	symtbl_out[188] = XK_onequarter;
	symtbl_out[189] = XK_onehalf;
	symtbl_out[190] = XK_threequarters;
	symtbl_out[191] = XK_questiondown;
	symtbl_out[192] = XK_Agrave;
	symtbl_out[193] = XK_Aacute;
	symtbl_out[194] = XK_Acircumflex;
	symtbl_out[195] = XK_Atilde;
	symtbl_out[196] = XK_Adiaeresis;
	symtbl_out[197] = XK_Aring;
	symtbl_out[198] = XK_AE;
	symtbl_out[199] = XK_Ccedilla;
	symtbl_out[200] = XK_Egrave;
	symtbl_out[201] = XK_Eacute;
	symtbl_out[202] = XK_Ecircumflex;
	symtbl_out[203] = XK_Ediaeresis;
	symtbl_out[204] = XK_Igrave;
	symtbl_out[205] = XK_Iacute;
	symtbl_out[206] = XK_Icircumflex;
	symtbl_out[207] = XK_Idiaeresis;
	symtbl_out[208] = XK_ETH;
	symtbl_out[209] = XK_Eth;
	symtbl_out[210] = XK_Ntilde;
	symtbl_out[211] = XK_Ograve;
	symtbl_out[212] = XK_Oacute;
	symtbl_out[213] = XK_Ocircumflex;
	symtbl_out[214] = XK_Otilde;
	symtbl_out[215] = XK_Odiaeresis;
	symtbl_out[216] = XK_multiply;
	symtbl_out[217] = XK_Ooblique;
	symtbl_out[218] = XK_oslash;
	symtbl_out[219] = XK_Ugrave;
	symtbl_out[220] = XK_Uacute;
	symtbl_out[221] = XK_Ucircumflex;
	symtbl_out[222] = XK_Udiaeresis;
	symtbl_out[223] = XK_Yacute;
	symtbl_out[224] = XK_THORN;
	symtbl_out[225] = XK_Thorn;
	symtbl_out[226] = XK_ssharp;
	symtbl_out[227] = XK_agrave;
	symtbl_out[228] = XK_aacute;
	symtbl_out[229] = XK_acircumflex;
	symtbl_out[230] = XK_atilde;
	symtbl_out[231] = XK_adiaeresis;
	symtbl_out[232] = XK_aring;
	symtbl_out[233] = XK_ae;
	symtbl_out[234] = XK_ccedilla;
	symtbl_out[235] = XK_egrave;
	symtbl_out[236] = XK_eacute;
	symtbl_out[237] = XK_ecircumflex;
	symtbl_out[238] = XK_ediaeresis;
	symtbl_out[239] = XK_igrave;
	symtbl_out[240] = XK_iacute;
	symtbl_out[241] = XK_icircumflex;
	symtbl_out[242] = XK_idiaeresis;
	symtbl_out[243] = XK_eth;
	symtbl_out[244] = XK_ntilde;
	symtbl_out[245] = XK_ograve;
	symtbl_out[246] = XK_oacute;
	symtbl_out[247] = XK_ocircumflex;
	symtbl_out[248] = XK_otilde;
	symtbl_out[249] = XK_odiaeresis;
	symtbl_out[250] = XK_division;
	symtbl_out[251] = XK_oslash;
	symtbl_out[252] = XK_Ooblique;
	symtbl_out[253] = XK_ugrave;
	symtbl_out[254] = XK_uacute;
	symtbl_out[255] = XK_ucircumflex;

	symtbl_in = malloc(65536 * sizeof(*symtbl_in));
	memset(symtbl_in, '\0', 65536 * sizeof(*symtbl_in));
	for (int i=0; i < sizeof(symtbl_out)/sizeof(symtbl_out[0]); i++){
		if (symtbl_out[i] > 65535){
			LOG("unexpectedly high constant in slot (%d): %d\n", i, symtbl_out[i]);
		}
		else
			symtbl_in[ symtbl_out[i] ] = i;
	}
}

void arcan_frameserver_avfeed_run(const char* resource, 
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

	if (strcmp(host, "listen") == 0){
/* dimensions is set by the parent, so just acquire and use. */
		vncctx.shmcont = arcan_shmif_acquire(keyfile, SHMIF_OUTPUT, true, false); 
		arcan_sem_post(vncctx.shmcont.vsem);
		server_loop();
		return;
	}

/* client connect / loop */
	int port = 5900;
	const char* argtmp = NULL;
	if (arg_lookup(args, "port", 0, &argtmp)){
		port = strtoul(argtmp, NULL, 10);
	}

	char buf[ strlen(host) + 8];
	snprintf(buf, sizeof(buf), "%s:%d", host, port);

	vncctx.shmcont = arcan_shmif_acquire(keyfile, SHMIF_INPUT, true, false);
	client_connect(buf);
	vncctx.client->frameBuffer = vncctx.shmcont.vidp;
	atexit( cleanup );

	while (true){
		int rc = WaitForMessage(vncctx.client, 100);
		if (-1 == rc)
			break;

		if (rc > 0)
			if (!HandleRFBServerMessage(vncctx.client))
				break;

		if (vncctx.dirty){
			vncctx.dirty = false;
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

				case TARGET_COMMAND_MESSAGE:
/* set text */
				break;

				case TARGET_COMMAND_EXIT:
					return;

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
