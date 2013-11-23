/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,MA 02110-1301,USA.
 *
 */
#include <math.h>
#include <stdlib.h>
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <string.h>
#include <strings.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "ntsc/snes_ntsc.h"
#include "graphing/net_graph.h"
#include "ievsched.h"
#include "stateman.h"
#include "libretro.h"

#include "resampler/speex_resampler.h"

#ifdef FRAMESERVER_LIBRETRO_3D 
#include "../platform/platform.h"
#include "../arcan_video.h"
#include "../arcan_videoint.h"

/* linking hijacks to workaround the platform
 * split problem (to be refactored when decent
 * KMS etc. support is added) */
struct arcan_video_display arcan_video_display = {0};
#endif

#ifndef MAX_PORTS
#define MAX_PORTS 4
#endif

#ifndef MAX_AXES
#define MAX_AXES 8
#endif

#ifndef MAX_BUTTONS
#define MAX_BUTTONS 16
#endif

/* note on synchronization:
 * the async and esync mechanisms will buffer locally and have that buffer 
 * flushed by the main application whenever appropriate. For audio, this is 
 * likely limited by the buffering capacity of the sound device / pipeline 
 * whileas the event queue might be a bit more bursty.
 *
 * however, we will lock to video, meaning that it is the framerate of the 
 * frameserver that will decide the actual framerate, that may be locked 
 * to VREFRESH (or lower, higher / variable). Thus we also need frameskipping
 * heuristics here.
 */
struct input_port {
	bool buttons[MAX_BUTTONS];
	signed axes[MAX_AXES];

/* special offsets into buttons / axes based on device */
	unsigned cursor_x, cursor_y, cursor_btns[5];
};

typedef void(*pixconv_fun)(const void* data, uint32_t* outp, 
	unsigned width, unsigned height, size_t pitch, bool postfilter);

static struct {
/* frame management */
/* flag for rendering callbacks, should the frame be processed or not */
		bool skipframe_a, skipframe_v; 

		bool pause;     /* event toggle frame, are we paused */
		double mspf;    /* static for each run, 1000/fps */

/* when did we last seed gameplay timing */
		long long int basetime;

/* for debugging / testing, added extra jitter to 
 * the cost for the different stages */
		int jitterstep, jitterxfer; 
		
/* add 'n' frames pseudoskipping to populate audiobuffers */
		int preaudiogen;                    
/* user changeable variable, how synching should be treated */
		int skipmode; 
/* for frameskip auto to compensate for jitter in transfer etc. */
		int prewake;  

/* how many video frames have we processed, used to calculate when the next
 * frame is supposed to be used */
		unsigned long long vframecount;

/* audio frame counter, used to determine jitter in samplerate */
		unsigned long long aframecount;

		struct retro_system_av_info avinfo; /* timing according to libretro */

/* statistics */
		int rebasecount, frameskips, transfercost, framecost;
		long long int frame_ringbuf[160];
		long long int drop_ringbuf[40];
		int xfer_ringbuf[MAX_SHMWIDTH];
		short int framebuf_ofs, dropbuf_ofs, xferbuf_ofs;
		const char* colorspace;

/* colour conversion / filtering */
		pixconv_fun converter;
		uint16_t* ntsc_imb;
		bool ntscconv;
		snes_ntsc_t ntscctx;
		snes_ntsc_setup_t ntsc_opts;

/* SHM- API input /output */
		struct frameserver_shmcont shmcont;
		uint8_t* vidp, (* audp);
		struct graph_context* graphing;
		int graphmode;
		file_handle last_fd; /* state management */
		struct arcan_evctx inevq;
		struct arcan_evctx outevq;

/* set as a canary after audb at a recalc to detect overflow */
		uint8_t* audguardb;

/* internal resampling */
		int16_t* audbuf;
		size_t audbuf_sz;
		off_t audbuf_ofs;
		SpeexResamplerState* resampler;

/* libretro states / function pointers */
		struct retro_system_info sysinfo;
		struct retro_game_info gameinfo;

/* parent uses an event->push model for input, libretro uses a poll one, so
 * prepare a lookup table that events gets pushed into and libretro can poll */
		struct input_port input_ports[MAX_PORTS];

		void (*run)();
		void (*reset)();
		bool (*load_game)(const struct retro_game_info* game);
		size_t (*serialize_size)();
		bool (*serialize)(void*, size_t);
		bool (*deserialize)(const void*, size_t);
		void (*set_ioport)(unsigned, unsigned);
} retroctx = {.prewake = 4, .preaudiogen = 0};

/* render statistics unto *vidp, at the very end of this .c file */
static void push_stats(); 
static void setup_3dcore(struct retro_hw_render_callback*);

static void* libretro_requirefun(const char* const sym)
{
	void* res = frameserver_requirefun(sym);

	if (!res)
	{
		LOG("(libretro) -- missing library or symbol (%s) during lookup.\n", sym);
		exit(1);
	}

	return res;
}

#define RGB565(b, g, r) ((uint16_t)(((uint8_t)(r) >> 3) << 11) | \
								(((uint8_t)(g) >> 2) << 5) | ((uint8_t)(b) >> 3))

static void push_ntsc(unsigned width, unsigned height, 
	const uint16_t* ntsc_imb, uint32_t* outp)
{
	size_t linew = SNES_NTSC_OUT_WIDTH(width) * 4;

/* only draw on every other line, so we can easily mix or 
 * blend interleaved (or just duplicate) */
	snes_ntsc_blit(&retroctx.ntscctx, ntsc_imb, width, 0, 
		width, height, outp, linew * 2);

	for (int row = 1; row < height * 2; row += 2)
	memcpy(&retroctx.vidp[row * linew], &retroctx.vidp[(row-1) * linew], linew); 
}

/* better distribution for conversion (white is white ..) */
static const uint8_t rgb565_lut5[] = {
  0,   8,  16,  25,  33,  41,  49,  58,  66,   74,  82,  90,  99, 107, 115,123,
132, 140, 148, 156, 165, 173, 181, 189,  197, 206, 214, 222, 230, 239, 247,255
};

static const uint8_t rgb565_lut6[] = {
  0,   4,   8,  12,  16,  20,  24,  28,  32,  36,  40,  45,  49,  53,  57, 61,
 65,  69,  73,  77,  81,  85,  89,  93,  97, 101, 105, 109, 113, 117, 121, 125,
130, 134, 138, 142, 146, 150, 154, 158, 162, 166, 170, 174, 178, 182, 186, 190,
194, 198, 202, 206, 210, 215, 219, 223, 227, 231, 235, 239, 243, 247, 251, 255
};

static void libretro_rgb565_rgba(const uint16_t* data, uint32_t* outp, 
	unsigned width, unsigned height, size_t pitch)
{
	uint16_t* interm = retroctx.ntsc_imb;
	retroctx.colorspace = "RGB565->RGBA";

/* with NTSC on, the input format is already correct */
	for (int y = 0; y < height; y++){
		for (int x = 0; x < width; x++){
			uint16_t val = data[x];
			uint8_t r = rgb565_lut5[ (val & 0xf800) >> 11 ];
			uint8_t g = rgb565_lut6[ (val & 0x07e0) >> 5  ];
			uint8_t b = rgb565_lut5[ (val & 0x001f)       ];

			if (retroctx.ntscconv)
				*interm++ = RGB565(r, g, b);
			else
				*outp++ = 0xff << 24 | b << 16 | g << 8 | r;
		}
		data += pitch >> 1;
	}

	if (retroctx.ntscconv)
		push_ntsc(width, height, retroctx.ntsc_imb, outp);

	return;
}

static void libretro_xrgb888_rgba(const uint32_t* data, uint32_t* outp, 
	unsigned width, unsigned height, size_t pitch)
{
	assert( (uintptr_t)data % 4 == 0 );
	retroctx.colorspace = "XRGB888->RGBA";

	uint16_t* interm = retroctx.ntsc_imb;

	for (int y = 0; y < height; y++){
		for (int x = 0; x < width; x++){
			uint8_t* quad = (uint8_t*) (data + x);
			if (retroctx.ntscconv)
				*interm++ = RGB565(quad[2], quad[1], quad[0]);
			else
				*outp++ = 0xff << 24 | quad[0] << 16 | quad[1] << 8 | quad[2];
		}

		data += pitch >> 2;
	}

	if (retroctx.ntscconv)
		push_ntsc(width, height, retroctx.ntsc_imb, outp);
}

static void libretro_rgb1555_rgba(const uint16_t* data, uint32_t* outp, 
	unsigned width, unsigned height, size_t pitch, bool postfilter)
{
	uint16_t* interm = retroctx.ntsc_imb;
	retroctx.colorspace = "RGB1555->RGBA";

	unsigned dh = height >= MAX_SHMHEIGHT ? MAX_SHMHEIGHT : height;
	unsigned dw =  width >=  MAX_SHMWIDTH ?  MAX_SHMWIDTH : width;

	for (int y = 0; y < dh; y++){
		for (int x = 0; x < dw; x++){
			uint16_t val = data[x];
			uint8_t r = ((val & 0x7c00) >> 10) << 3;
			uint8_t g = ((val & 0x03e0) >>  5) << 3;
			uint8_t b = ( val & 0x001f) <<  3;

			if (postfilter)
				*interm++ = RGB565(r, g, b);
			else
				*outp++ = (0xff) << 24 | b << 16 | g << 8 | r;
		}

		data += pitch >> 1;
	}

	if (postfilter)
		push_ntsc(width, height, retroctx.ntsc_imb, outp);
}

/* some cores have been wrongly implemented in the past, 
 * yielding > 1 frames for each run(), so this is reset and checked 
 * after each retro_run() */
static int testcounter;
static void libretro_vidcb(const void* data, unsigned width, 
	unsigned height, size_t pitch)
{
	testcounter++;
/* framecount is updated in sync */
	if (!data || retroctx.skipframe_v)
		return;

/* width / height can be changed without notice, so we have to be ready
 * for the fact that the cost of conversion can suddenly move outside the
 * allowed boundaries, then NTSC is ignored */
	unsigned outw = width;
	unsigned outh = height;
	bool ntscconv = retroctx.ntscconv;

	if (ntscconv && SNES_NTSC_OUT_WIDTH(width)<= MAX_SHMWIDTH
		&& height * 2 <= MAX_SHMHEIGHT){
		outh = outh << 1;
		outw = SNES_NTSC_OUT_WIDTH( width );
	}
	else {
		outw = width;
		outh = height;
		ntscconv = false;
	}

/* the shmpage size will be larger than the possible values for width / height,
 * so if we have a mismatch, just change the shared dimensions
 * and toggle resize flag */
	if (outw != retroctx.shmcont.addr->storage.w || outh != 
		retroctx.shmcont.addr->storage.h){
		frameserver_shmpage_resize(&retroctx.shmcont, outw, outh);
		frameserver_shmpage_calcofs(retroctx.shmcont.addr, &(retroctx.vidp), 
			&(retroctx.audp) );
		graphing_destroy(retroctx.graphing);
		retroctx.graphing = graphing_new(outw, outh, (uint32_t*) retroctx.vidp);

		retroctx.audguardb = retroctx.audp + SHMPAGE_AUDIOBUF_SIZE;
		retroctx.audguardb[0] = 0xde;
		retroctx.audguardb[1] = 0xad;

/* will be reallocated if needed and not set so just free and unset */
		if (retroctx.ntsc_imb){
			free(retroctx.ntsc_imb);
			retroctx.ntsc_imb = NULL;
		}
	}

/* intermediate storage for blargg NTSC filter, if toggled, 
 * ntscconv will be applied by the converter however */
	if (ntscconv && !retroctx.ntsc_imb){
		retroctx.ntsc_imb = malloc(sizeof(uint16_t) * outw * outh);
	}

/* lastly, convert / blit, this will possibly clip */
	if (retroctx.converter)
		retroctx.converter(data, (void*) retroctx.vidp, width, 
			height, pitch, ntscconv);
}

static void do_preaudio()
{
	if (retroctx.preaudiogen == 0)
		return;

	retroctx.skipframe_v = true;
	retroctx.skipframe_a = false;

	int afc = retroctx.aframecount;
	int vfc = retroctx.vframecount;

	for (int i = 0; i < retroctx.preaudiogen; i++)
		retroctx.run();

	retroctx.aframecount = afc;
	retroctx.vframecount = vfc;
}

static void libretro_skipnframes(unsigned count, bool fastfwd)
{
	retroctx.skipframe_v = true;
	retroctx.skipframe_a = fastfwd;
	
	long long afc = retroctx.aframecount;

	for (int i = 0; i < count; i++)
		retroctx.run();

	if (fastfwd){
		retroctx.aframecount = afc;
		retroctx.frameskips += count;
	}
	else
		retroctx.vframecount += count;

	retroctx.skipframe_a = false;
	retroctx.skipframe_v = false;
}

static void reset_timing()
{
	retroctx.basetime = arcan_timemillis();
	do_preaudio();
	retroctx.vframecount = 1;
	retroctx.aframecount = 1;
	retroctx.frameskips  = 0;
	retroctx.rebasecount++;
}

void libretro_audscb(int16_t left, int16_t right)
{
	retroctx.aframecount++;

	if (retroctx.skipframe_a)
		return;

/* can happen if we skip a lot and never transfer */
	if (retroctx.audbuf_ofs + 2 < retroctx.audbuf_sz >> 1){
		retroctx.audbuf[retroctx.audbuf_ofs++] = left;
		retroctx.audbuf[retroctx.audbuf_ofs++] = right;
	}
}

size_t libretro_audcb(const int16_t* data, size_t nframes)
{
	retroctx.aframecount += nframes;

	if (retroctx.skipframe_a || (retroctx.audbuf_ofs << 1) + 
		(nframes << 1) + (nframes << 2) > retroctx.audbuf_sz )
		return nframes;
	
/* 2 bytes per sample, 2 channels */
/* audbuf is in int16_t and ofs used as index */
	memcpy(&retroctx.audbuf[retroctx.audbuf_ofs], data, nframes << 2);
	retroctx.audbuf_ofs += nframes << 1; 

	return nframes;
}

/* we ignore these since before pushing for a frame,
 * we've already processed the queue */
static void libretro_pollcb(){}

static bool libretro_setenv(unsigned cmd, void* data){
	char* sysdir;
	bool rv = false;

	switch (cmd){
	case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
		rv = true;

		switch ( *(enum retro_pixel_format*) data ){
		case RETRO_PIXEL_FORMAT_0RGB1555:
			LOG("(libretro) -- pixel format set to RGB1555\n");
			retroctx.converter = (pixconv_fun) libretro_rgb1555_rgba;
		break;

		case RETRO_PIXEL_FORMAT_RGB565:
			LOG("(libretro) -- pixel format set to RGB565\n");
			retroctx.converter = (pixconv_fun) libretro_rgb565_rgba;
		break;

		case RETRO_PIXEL_FORMAT_XRGB8888:
			LOG("(libretro) -- pixel format set to XRGB8888\n");
			retroctx.converter = (pixconv_fun) libretro_xrgb888_rgba;
		break;

		default:
			LOG("(arcan_frameserver:libretro) -- "
			"unknown pixelformat encountered (%d).\n", *(unsigned*)data);
			retroctx.converter = NULL;
		}
	break;

	case RETRO_ENVIRONMENT_GET_CAN_DUPE:
		*((bool*) data) = true;
		rv = true;
	break;

/* ignore for now */
	case RETRO_ENVIRONMENT_SHUTDOWN:
		retroctx.shmcont.addr->dms = true;
		LOG("(arcan_frameserver:libretro) -- shutdown requested from lib.\n");
	break;

/* unsure how we'll handle this when privsep is working, 
 * possibly through chroot to garbage dir */
	case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
		sysdir = getenv("ARCAN_SYSTEMPATH");
		if (!sysdir){
			sysdir = "./resources/games/system";
		}

/* some cores (mednafen-psx, ..) currently breaks on relative paths, 
 * so resolve to absolute one for the time being */
		sysdir = realpath(sysdir, NULL);

		LOG("(arcan_frameserver:libretro) -- system directory "
			"set to (%s).\n", sysdir);
		*((const char**) data) = sysdir;
		rv = sysdir != NULL;
	break;

#ifdef FRAMESERVER_LIBRETRO_3D
	case RETRO_ENVIRONMENT_SET_HW_RENDER:
		setup_3dcore( (struct retro_hw_render_callback*) data);
	break;
#endif

	default:
		LOG("arcan_frameserver:libretro), unhandled retro request (%d)\n", cmd);
	}

	return rv;
}

/* use the context-tables from retroctx in combination with dev / ind / ...
 * to try and figure out what to return, this table is 
 * populated in flush_eventq() */
static inline int16_t libretro_inputmain(unsigned port, unsigned dev, 
	unsigned ind, unsigned id){
	static bool butn_warning = false;
	static bool port_warning = false;

	if (id > MAX_BUTTONS){
		if (butn_warning == false)
			arcan_warning("arcan_frameserver(libretro) -- unexpectedly high button "
				"index (dev:%u)(%u:%%) requested, ignoring.\n", ind, id);

		butn_warning = true;
		return 0;
	}

	if (port > MAX_PORTS){
		if (port_warning == false)
			LOG("(libretro) -- core requested an unknown port id (%u:%u:%u), " 
				"ignored.\n", dev, ind, id);

		port_warning = true;
		return 0;
	}

	int16_t rv = 0;
	struct input_port* inp;

	switch (dev){
		case RETRO_DEVICE_JOYPAD:
			return (int16_t) retroctx.input_ports[port].buttons[id];
		break;

		case RETRO_DEVICE_KEYBOARD:
		break;

		case RETRO_DEVICE_MOUSE:
			if (port == 1) port = 0;
			inp = &retroctx.input_ports[port];
			switch (id){
				case RETRO_DEVICE_ID_MOUSE_LEFT:
					return inp->buttons[ inp->cursor_btns[0] ];

				case RETRO_DEVICE_ID_MOUSE_RIGHT:
					return inp->buttons[ inp->cursor_btns[2] ];

				case RETRO_DEVICE_ID_MOUSE_X:
					rv = inp->axes[ inp->cursor_x ];
					inp->axes[ inp->cursor_x ] = 0;
					return rv;

				case RETRO_DEVICE_ID_MOUSE_Y:
					rv = inp->axes[ inp->cursor_y ];
					inp->axes[ inp->cursor_y ] = 0;
					return rv;
			}
		break;

		case RETRO_DEVICE_LIGHTGUN:
			switch (id){
				case RETRO_DEVICE_ID_LIGHTGUN_X:
					return (int16_t) retroctx.input_ports[port].axes[
						retroctx.input_ports[port].cursor_x
					];

				case RETRO_DEVICE_ID_LIGHTGUN_Y:
					return (int16_t) retroctx.input_ports[port].axes[
						retroctx.input_ports[port].cursor_y
					];

				case RETRO_DEVICE_ID_LIGHTGUN_TRIGGER:
					return (int16_t) retroctx.input_ports[port].buttons[
						retroctx.input_ports[port].cursor_btns[0]
					];

				case RETRO_DEVICE_ID_LIGHTGUN_CURSOR:
					return (int16_t) retroctx.input_ports[port].buttons[
						retroctx.input_ports[port].cursor_btns[1]
					];

				case RETRO_DEVICE_ID_LIGHTGUN_START:
					return (int16_t) retroctx.input_ports[port].buttons[
					retroctx.input_ports[port].cursor_btns[2]
				];

					case RETRO_DEVICE_ID_LIGHTGUN_TURBO:
					return (int16_t) retroctx.input_ports[port].buttons[
					retroctx.input_ports[port].cursor_btns[3]
				];

				case RETRO_DEVICE_ID_LIGHTGUN_PAUSE:
					return (int16_t) retroctx.input_ports[port].buttons[
					retroctx.input_ports[port].cursor_btns[4]
				];
		}
		break;

		case RETRO_DEVICE_ANALOG:
			return (int16_t) retroctx.input_ports[port].axes[id];
		break;

		default:
			LOG("(arcan_frameserver:libretro) Unknown device ID specified (%d),"
				"	video will be disabled.\n", dev);
	}

	return 0;
}

static int16_t libretro_inputstate(unsigned port, unsigned dev, 
	unsigned ind, unsigned id)
{
	int16_t rv = libretro_inputmain(port, dev, ind, id);
/* indirection to be used for debug graphing what inputs
 * the core actually requested */
	return rv;
}

static int remaptbl[] = {
	RETRO_DEVICE_ID_JOYPAD_A,
	RETRO_DEVICE_ID_JOYPAD_B,
	RETRO_DEVICE_ID_JOYPAD_X,
	RETRO_DEVICE_ID_JOYPAD_Y,
	RETRO_DEVICE_ID_JOYPAD_L,
	RETRO_DEVICE_ID_JOYPAD_R,
	RETRO_DEVICE_ID_JOYPAD_L2,
	RETRO_DEVICE_ID_JOYPAD_R2,
	RETRO_DEVICE_ID_JOYPAD_L3,
	RETRO_DEVICE_ID_JOYPAD_R3
};

static void ioev_ctxtbl(arcan_ioevent* ioev, const char* label)
{
	size_t remaptbl_sz = sizeof(remaptbl) / sizeof(remaptbl[0]) - 1;
	int ind, button = -1, axis;
	char* subtype;
	signed value = ioev->datatype == EVENT_IDATATYPE_TRANSLATED ? 
		ioev->input.translated.active : ioev->input.digital.active;

	if (1 == sscanf(label, "PLAYER%d_", &ind) && ind > 0 && 
		ind <= MAX_PORTS && (subtype = strchr(label, '_')) ){
		subtype++;

		if (1 == sscanf(subtype, "BUTTON%d", &button) && button > 0 &&
			button <= MAX_BUTTONS - remaptbl_sz){
			button--;
			button = remaptbl[button];
		}
		else if (1 == sscanf(subtype, "AXIS%d", &axis) && axis > 0 
			&& axis <= MAX_AXES){
			if (ioev->input.analog.gotrel)
				retroctx.input_ports[ind-1].axes[ axis - 1 ] = 
					ioev->input.analog.axisval[1];
			else {
				static bool warned = false;
				if (!warned)
					LOG("libretro::analog input(%s), ignored. Absolute input "
						"currently unsupported.\n", label);
				warned = true;
			}
		}
		else if ( strcmp(subtype, "UP") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_UP;
		else if ( strcmp(subtype, "DOWN") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_DOWN;
		else if ( strcmp(subtype, "LEFT") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_LEFT;
		else if ( strcmp(subtype, "RIGHT") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_RIGHT;
		else if ( strcmp(subtype, "SELECT") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_SELECT;
		else if ( strcmp(subtype, "START") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_START;
		else;

		if (button >= 0)
			retroctx.input_ports[ind-1].buttons[button] = value;
	}

}

static void toggle_ntscfilter(int toggle)
{
	if (retroctx.ntscconv && toggle == 0){
		free(retroctx.ntsc_imb);
		retroctx.ntsc_imb = NULL;
		retroctx.ntscconv = false;
	}
	else if (!retroctx.ntscconv && toggle == 1) {
/* malloc etc. happens in resize */
		retroctx.ntscconv = true;
	}
}

static inline void targetev(arcan_event* ev)
{
	arcan_tgtevent* tgt = &ev->data.target;
	switch (ev->kind){
		case TARGET_COMMAND_RESET:
			retroctx.reset();
		break;

/* FD transfer has different behavior on Win32 vs UNIX,
 * Win32 has a handle attribute that directly is set as the latest active FD,
 * for UNIX, we read it from the socket connection we have */
		case TARGET_COMMAND_FDTRANSFER:
			retroctx.last_fd = frameserver_readhandle( ev );
			LOG("(libretro) -- descriptor transferred, %d\n", retroctx.last_fd);
		break;

		case TARGET_COMMAND_GRAPHMODE:
			retroctx.graphmode = tgt->ioevs[0].iv;
		break;

		case TARGET_COMMAND_NTSCFILTER:
			toggle_ntscfilter(tgt->ioevs[0].iv);
		break;

/* ioev[0].iv = group, 1.fv, 2.fv, 3.fv */
		case TARGET_COMMAND_NTSCFILTER_ARGS:
			snes_ntsc_update_setup(&retroctx.ntscctx, &retroctx.ntsc_opts,
				tgt->ioevs[0].iv, tgt->ioevs[1].fv, tgt->ioevs[2].fv,tgt->ioevs[3].fv);

		break;

/* 0 : auto, -1 : single-step, > 0 render every n frames.
 * with 0, the second ioev defines pre-wake. -1 (last frame cost), 
 * 0 (whatever), 1..mspf-1 
 * ioev[2] audio preemu- frames, whenever the counter is reset,
 * perform n extra run() 
 * passes to populate audiobuffer -- increases latency but reduces pops.. 
 * ioev[3] debugging 
 * options -- added emulation cost ms (0 default, +n constant n ms, 
 * -n 1..abs(n) random)
 */
		case TARGET_COMMAND_FRAMESKIP:
			retroctx.skipmode    = tgt->ioevs[0].iv;
			retroctx.prewake     = tgt->ioevs[1].iv;
			retroctx.preaudiogen = tgt->ioevs[2].iv;
			retroctx.audbuf_ofs  = 0;
			retroctx.jitterstep  = tgt->ioevs[3].iv;
			retroctx.jitterxfer  = tgt->ioevs[4].iv;
			reset_timing();
		break;

/* any event not being UNPAUSE is ignored, no frames are processed
 * and the core is allowed to sleep in between polls */
		case TARGET_COMMAND_PAUSE:
			retroctx.pause = true;
		break;

/* can safely assume there are no other events in the queue after this one,
 * more important for encode etc. that need to flush codecs */
		case TARGET_COMMAND_EXIT:
			exit(EXIT_SUCCESS);
		break;

		case TARGET_COMMAND_UNPAUSE:
			retroctx.pause = false;
			reset_timing();
		break;

		case TARGET_COMMAND_SETIODEV:
			retroctx.set_ioport(tgt->ioevs[0].iv, tgt->ioevs[1].iv);
		break;

/* should also emit a corresponding event back with the current framenumber */
		case TARGET_COMMAND_STEPFRAME:
			if (tgt->ioevs[0].iv < 0);
				else
					while(tgt->ioevs[0].iv-- && retroctx.shmcont.addr->dms)
						retroctx.run(); 
		break;

/* store / rewind operate on the last FD set through FDtransfer */
		case TARGET_COMMAND_STORE:
			if (BADFD != retroctx.last_fd){
				size_t dstsize = retroctx.serialize_size();
				void* buf;
				if (dstsize && ( buf = malloc( dstsize ) )){

					if ( retroctx.serialize(buf, dstsize) ){
						frameserver_dumprawfile_handle( buf, dstsize, 
							retroctx.last_fd, true );
						retroctx.last_fd = BADFD;
					} else
						LOG("frameserver(libretro), serialization failed.\n");

					free(buf);
				}
			}
			else
				LOG("frameserver(libretro), snapshot store requested without"
					"	any viable target.\n");
		break;

		case TARGET_COMMAND_RESTORE:
			if (BADFD != retroctx.last_fd){
				ssize_t dstsize = -1;

				void* buf = frameserver_getrawfile_handle( retroctx.last_fd, &dstsize);
				if (buf != NULL && dstsize > 0){
					retroctx.deserialize( buf, dstsize );
					reset_timing();
				}

				retroctx.last_fd = BADFD;
			}
			else
				LOG("frameserver(libretro), snapshot restore requested "
					"without any viable target\n");
		break;

		default:
			arcan_warning("frameserver(libretro), unknown target event (%d),"
				"	ignored.\n", ev->kind);
	}
}

/* use labels etc. for trying to populate the context table */
/* we also process requests to save state, shutdown, reset, 
 * plug/unplug input, here */
static inline void flush_eventq(){
	 arcan_event* ev;
	 arcan_errc evstat;

	 do
		while ( (ev = arcan_event_poll(&retroctx.inevq, &evstat)) ){
			switch (ev->category){
				case EVENT_IO:
					ioev_ctxtbl(&(ev->data.io), ev->label);
				break;

				case EVENT_TARGET:
					targetev(ev);
				break;
			}
		}
/* Only pause if the DMS isn't released */
		while (retroctx.shmcont.addr->dms &&
			retroctx.pause && (arcan_timesleep(1), 1));
}

/* return true if we're in synch (may sleep),
 * return false if we're lagging behind */
static inline bool retroctx_sync()
{
	long long int timestamp = arcan_timemillis();
	retroctx.vframecount++;

	long long int now  = timestamp - retroctx.basetime;
	long long int next = floor( (double)retroctx.vframecount * retroctx.mspf );
	int left = next - now;

/* ntpd, settimeofday, wonky OS etc. or some massive stall */
	if (now < 0 || abs( left ) > retroctx.mspf * 60.0){
		LOG("(libretro) -- stall detected, resetting timers.\n");
		reset_timing();
		return true;
	}

/* more than a frame behind? just skip */
	if ( retroctx.skipmode == TARGET_SKIP_AUTO && left < -retroctx.mspf ){
		retroctx.frameskips++;
		retroctx.drop_ringbuf[retroctx.dropbuf_ofs] = timestamp;
		retroctx.dropbuf_ofs = (retroctx.dropbuf_ofs + 1) % 
			(sizeof(retroctx.drop_ringbuf) / sizeof(retroctx.drop_ringbuf[0]));
		return false;
	}

/* since we have to align the transfer with the parent, and it's better to 
 * under- than overshoot- a deadline in that respect, prewake 
 * tries to compensate lightly for scheduling jitter etc. */
	int prewake = retroctx.prewake;
	if (retroctx.prewake < 0)
		prewake = retroctx.framecost; /* use last frame cost as an estimate */
	else if (retroctx.prewake > 0) /* or just a constant number */
		prewake = retroctx.prewake > retroctx.mspf?retroctx.mspf:retroctx.prewake;

	if (left > prewake )
		arcan_timesleep( left - prewake );

	return true;
}

static inline void add_jitter(int num)
{
	if (num < 0)
		arcan_timesleep( rand() % abs(num) );
	else if (num > 0)
		arcan_timesleep( num );
}

/* 
 * A selected few cores need a fully working GL context and then
 * emit the output as an FBO. We currently lack a good way of 
 * sharing the output texture with the parent process, so 
 * we initialize a dumb "1x1" window with the FBO being our
 * desired output resolution, and then doing a readback
 * into the shmpage
 */
#ifdef FRAMESERVER_LIBRETRO_3D
static void setup_3dcore(struct retro_hw_render_callback* ctx)
{
	platform_video_init(32, 32, 4, false, false, false);
	LOG("got 3dcore request");	
}
#endif

/* a big issue is that the libretro- modules are not guaranteed to act 
 * in a nice library way, meaning that they (among other things) install
 * signal handlers, spawn threads, change working directory, work with 
 * file-system etc. etc. There are a few ideas for how
 * this can be handled:
 * (1) use PIN to intercept all syscalls in the loaded library 
 * (x86/x86-64 only though)
 * (2) using a small loader and PTRACE-TRACEME PTRACE_O_TRACESYSGOOD 
 * then patch the syscalls so they redirect through a jumptable
 * trigger on installation of signal handlers etc.
 * (3) use FUSE as a means of intercepting file-system related syscalls
 * (4) LD_PRELOAD ourselves, replacing the usual batch of open/close/,... 
 * wrappers
 */

/* map up a libretro compatible library resident at fullpath:game,
 * if resource is /info, no loading will occur but a dump of the capabilities
 * of the core will be sent to stdout. */
void arcan_frameserver_libretro_run(const char* resource, const char* keyfile)
{
	retroctx.converter    = (pixconv_fun) libretro_rgb1555_rgba;
	const char* libname   = resource;
	int errc;
	LOG("mode_libretro (%s)\n", resource);

/* abssopath : gamename */
	char* gamename = strrchr(resource, '*');
	if (!gamename) return;
	*gamename = 0;
	gamename++;

	if (*libname == 0)
		return;

/* map up functions and test version */
	if (!frameserver_loadlib(libname)){
		LOG("(libretro) -- couldn't open library (%s), giving up.\n", libname);
		exit(1);
	}

	void (*initf)() = libretro_requirefun("retro_init");
	unsigned (*apiver)() = libretro_requirefun("retro_api_version");
	( (void(*)(retro_environment_t)) 
		libretro_requirefun("retro_set_environment"))(libretro_setenv);

/* get the lib up and running */
	if ( (initf(), true) && apiver() == RETRO_API_VERSION){
		((void(*)(struct retro_system_info*)) 
		 libretro_requirefun("retro_get_system_info"))(&retroctx.sysinfo);

/* added as a support to romman etc. so they don't have 
 * to load the libs in question */
		if (strcmp(gamename, "/info") == 0){
			fprintf(stdout, "arcan_frameserver(info)\nlibrary:%s\n"
				"version:%s\nextensions:%s\n/arcan_frameserver(info)", 
				retroctx.sysinfo.library_name, retroctx.sysinfo.library_version, 
				retroctx.sysinfo.valid_extensions);
			return;
		}

		LOG("libretro(%s), version %s loaded. Accepted extensions: %s\n",
			retroctx.sysinfo.library_name, retroctx.sysinfo.library_version, 
			retroctx.sysinfo.valid_extensions);

/* map functions to context structure */
		retroctx.run   = (void(*)()) libretro_requirefun("retro_run");
		retroctx.reset = (void(*)()) libretro_requirefun("retro_reset");

		retroctx.load_game  = (bool(*)(const struct retro_game_info* game)) 
			libretro_requirefun("retro_load_game");
		retroctx.serialize  = (bool(*)(void*, size_t)) 
			libretro_requirefun("retro_serialize");
		retroctx.set_ioport = (void(*)(unsigned,unsigned)) 
			libretro_requirefun("retro_set_controller_port_device");

		retroctx.deserialize    = (bool(*)(const void*, size_t)) 
			libretro_requirefun("retro_unserialize"); 
/* bah, unmarshal or deserialize.. not unserialize :p */

		retroctx.serialize_size = (size_t(*)()) 
			libretro_requirefun("retro_serialize_size");

/* setup callbacks */
		( (void(*)(retro_video_refresh_t) )
			libretro_requirefun("retro_set_video_refresh"))(libretro_vidcb);
		( (size_t(*)(retro_audio_sample_batch_t)) 
			libretro_requirefun("retro_set_audio_sample_batch"))(libretro_audcb);
		( (void(*)(retro_audio_sample_t)) 
			libretro_requirefun("retro_set_audio_sample"))(libretro_audscb);
		( (void(*)(retro_input_poll_t)) 
			libretro_requirefun("retro_set_input_poll"))(libretro_pollcb);
		( (void(*)(retro_input_state_t)) 
			libretro_requirefun("retro_set_input_state") )(libretro_inputstate);

/* for event enqueue, shared memory interface is needed */
		retroctx.shmcont = frameserver_getshm(keyfile, true);
		struct frameserver_shmpage* shared = retroctx.shmcont.addr;
		frameserver_shmpage_setevqs(retroctx.shmcont.addr, 
			retroctx.shmcont.esem, &(retroctx.inevq), &(retroctx.outevq), false);

/* send some information on what core is actually loaded etc. */
		arcan_event outev = {
						.category = EVENT_EXTERNAL,
					 	.kind = EVENT_EXTERNAL_NOTICE_IDENT
		};

		size_t msgsz = sizeof(outev.data.external.message) / 
			sizeof(outev.data.external.message[0]);
		snprintf((char*)outev.data.external.message, msgsz, "%s %s", 
			retroctx.sysinfo.library_name, retroctx.sysinfo.library_version);
		arcan_event_enqueue(&retroctx.outevq, &outev);

/* load the rom, either by letting the emulator acts as loader, or by 
 * mmaping and handing that segment over */
		ssize_t bufsize = 0;

		if (retroctx.sysinfo.need_fullpath){
			LOG("libretro(%s), core requires fullpath, resolved to (%s).\n", 
				retroctx.sysinfo.library_name, gamename); 
			retroctx.gameinfo.data = NULL;
			retroctx.gameinfo.path = strdup( gamename );
		} else {
			retroctx.gameinfo.path = strdup( gamename );
			retroctx.gameinfo.data = frameserver_getrawfile(gamename, &bufsize);
			if (bufsize == -1){
				LOG("libretro(%s), couldn't map data, giving up.\n", gamename);
				return;
			}
		}	

		retroctx.gameinfo.size = bufsize;
		
/* load the game, and if that fails, give up */
		outev.kind = EVENT_EXTERNAL_NOTICE_RESOURCE;
		snprintf((char*)outev.data.external.message, msgsz, "loading");
		arcan_event_enqueue(&retroctx.outevq, &outev);
		
		if ( retroctx.load_game( &retroctx.gameinfo ) == false ){
			snprintf((char*)outev.data.external.message, msgsz, "failed");
			arcan_event_enqueue(&retroctx.outevq, &outev);
			return;
		}

		snprintf((char*)outev.data.external.message, msgsz, "loaded");
		arcan_event_enqueue(&retroctx.outevq, &outev);

		( (void(*)(struct retro_system_av_info*)) 
			libretro_requirefun("retro_get_system_av_info"))(&retroctx.avinfo);
	
/* setup frameserver, synchronization etc. */
		assert(retroctx.avinfo.timing.fps > 1);
		assert(retroctx.avinfo.timing.sample_rate > 1);
		retroctx.last_fd = BADFD;
		retroctx.mspf = ( 1000.0 * (1.0 / retroctx.avinfo.timing.fps) );

		retroctx.ntscconv  = false;
		retroctx.ntsc_opts = snes_ntsc_rgb;
		snes_ntsc_init(&retroctx.ntscctx, &retroctx.ntsc_opts);

		LOG("(libretro) -- video timing: %f fps (%f ms), "
			"audio samplerate: %f Hz\n", 
			(float)retroctx.avinfo.timing.fps, (float)retroctx.mspf, 
			(float)retroctx.avinfo.timing.sample_rate);

		LOG("(libretro) -- setting up resampler, %f => %d.\n", 
			(float)retroctx.avinfo.timing.sample_rate, SHMPAGE_SAMPLERATE);

		retroctx.resampler = speex_resampler_init(SHMPAGE_ACHANNELCOUNT, 
			retroctx.avinfo.timing.sample_rate, SHMPAGE_SAMPLERATE, 
			RESAMPLER_QUALITY, &errc);

/* intermediate buffer for resampling and not 
 * relying on a well-behaving shmpage */
		retroctx.audbuf_sz = retroctx.avinfo.timing.sample_rate * 
			sizeof(uint16_t) * 2;
		retroctx.audbuf = malloc(retroctx.audbuf_sz);
		memset(retroctx.audbuf, 0, retroctx.audbuf_sz);

		if (!frameserver_shmpage_resize(&retroctx.shmcont,
			retroctx.avinfo.geometry.max_width,
			retroctx.avinfo.geometry.max_height))
			return;

		frameserver_shmpage_calcofs(shared, &(retroctx.vidp), &(retroctx.audp) );
		retroctx.graphing = graphing_new(
			retroctx.avinfo.geometry.max_width,
			retroctx.avinfo.geometry.max_height, (uint32_t*) retroctx.vidp
		);

		retroctx.audguardb = retroctx.audp + SHMPAGE_AUDIOBUF_SIZE;
		retroctx.audguardb[0] = 0xde;
		retroctx.audguardb[1] = 0xad;

		frameserver_semcheck(retroctx.shmcont.vsem, -1);

/* since we're guaranteed to get at least one input callback each run(), 
 * call, we multiplex parent event processing as well */
		outev.data.external.framestatus.framenumber = 0;
/* some cores die on this kind of reset, retroctx.reset() e.g. NXengine */

/* basetime is used as epoch for all other timing calculations */
		retroctx.basetime = arcan_timemillis();

/* since we might have requests to save state before we die, 
 * we use the flush_eventq as an atexit */
		atexit(flush_eventq);

/* setup standard device remapping tables, these can be changed 
 * by the calling process with a corresponding target event. */
		for (int i = 0; i < MAX_PORTS; i++){
			retroctx.input_ports[i].cursor_x = 0;
			retroctx.input_ports[i].cursor_y = 1;
			retroctx.input_ports[i].cursor_btns[0] = 0;
			retroctx.input_ports[i].cursor_btns[1] = 1;
			retroctx.input_ports[i].cursor_btns[2] = 2;
			retroctx.input_ports[i].cursor_btns[3] = 3;
			retroctx.input_ports[i].cursor_btns[4] = 4;
		}

/* only now, when a game is loaded and set-up, can we know how large a
 * savestate might possibly be, the frontend need to know this in order 
 * to determine strategy for netplay and for enabling / disabling savestates */
		outev.kind = EVENT_EXTERNAL_NOTICE_STATESIZE;
		outev.category = EVENT_EXTERNAL;
		outev.data.external.state_sz = retroctx.serialize_size();
		arcan_event_enqueue(&retroctx.outevq, &outev);
		long long int start, stop;

		do_preaudio();
	while (retroctx.shmcont.addr->dms){
/* since pause and other timing anomalies are part of the eventq flush, 
 * take care of it outside of frame frametime measurements */
			if (retroctx.skipmode >= TARGET_SKIP_FASTFWD)
				libretro_skipnframes(retroctx.skipmode - 
					TARGET_SKIP_FASTFWD + 1, true);
			else if (retroctx.skipmode >= TARGET_SKIP_STEP)
				libretro_skipnframes(retroctx.skipmode - 
					TARGET_SKIP_STEP + 1, false);
			else ;

			flush_eventq();

			testcounter = 0;

			start = arcan_timemillis();
			add_jitter(retroctx.jitterstep);
			retroctx.run();
			stop = arcan_timemillis();
			retroctx.framecost = stop - start;

/* finished frames and their alignment is what actually matters */
			size_t stepsz = sizeof(retroctx.frame_ringbuf) / 
				sizeof(retroctx.frame_ringbuf)[0];
			retroctx.frame_ringbuf[retroctx.framebuf_ofs] = start;
			retroctx.framebuf_ofs = (retroctx.framebuf_ofs + 1) % stepsz;

			retroctx.frame_ringbuf[retroctx.framebuf_ofs] = stop;
			retroctx.framebuf_ofs = (retroctx.framebuf_ofs + 1) % stepsz;

/* some FE applications need a grasp of "where" we are frame-wise, 
 * particularly for single-stepping etc. */
			outev.kind = EVENT_EXTERNAL_NOTICE_FRAMESTATUS;
			outev.data.external.framestatus.framenumber++;
			arcan_event_enqueue(&retroctx.outevq, &outev);

			if (testcounter != 1)
				LOG("(arcan_frameserver(libretro) -- inconsistent core behavior, "
					"expected 1 video frame / run(), got %d\n", testcounter);

/* frameskipping here is a simple adaptive thing, 
 * if we're too out of alignment against the next deadline, 
 * drop the transfer / parent synch */
			bool lastskip = retroctx.skipframe_v;
			retroctx.skipframe_a = false;
			retroctx.skipframe_v = !retroctx_sync();

/* the audp/vidp buffers have already been updated in the callbacks */
			if (lastskip == false){

/* possible to add a size lower limit here to maintain a larger
 * resampling buffer than synched to videoframe */
				if (retroctx.audbuf_ofs){
					spx_uint32_t outc  = SHMPAGE_AUDIOBUF_SIZE; 
/*first number of bytes, then after process..., number of samples */
					spx_uint32_t nsamp = retroctx.audbuf_ofs >> 1;
					speex_resampler_process_interleaved_int(retroctx.resampler, 
						(const spx_int16_t*) retroctx.audbuf, &nsamp, 
						(spx_int16_t*) retroctx.audp, &outc);
					if (outc)
						retroctx.shmcont.addr->abufused += outc * 
							SHMPAGE_ACHANNELCOUNT * sizeof(uint16_t);

					shared->aready = true;
					retroctx.audbuf_ofs = 0;
				}

/* Possibly overlay as much tracking / debugging data we can muster */
				if (retroctx.graphmode)
					push_stats();

/* Frametransfer step */
				start = arcan_timemillis();
					add_jitter(retroctx.jitterxfer);
					shared->vready = true;
					frameserver_semcheck( retroctx.shmcont.vsem, INFINITE);
				stop = arcan_timemillis();

				retroctx.transfercost = stop - start;
				retroctx.xfer_ringbuf[ retroctx.xferbuf_ofs ] = retroctx.transfercost;
			}
			else
				retroctx.xfer_ringbuf[ retroctx.xferbuf_ofs ] = -1;

			retroctx.xferbuf_ofs = (retroctx.xferbuf_ofs + 1) % 
				( sizeof(retroctx.xfer_ringbuf) / sizeof(retroctx.xfer_ringbuf[0]) );
			assert(retroctx.audguardb[0] == 0xde && retroctx.audguardb[1] == 0xad);
		}

	}
}

/* ---- Long and tedious statistics output follows, nothing to see here ---- */
#define STEPMSG(X) \
	draw_box(retroctx.graphing, 0, yv, PXFONT_WIDTH * strlen(X),\
		PXFONT_HEIGHT, 0xff000000);\
	draw_text(retroctx.graphing, X, 0, yv, 0xffffffff);\
	yv += PXFONT_HEIGHT + PXFONT_HEIGHT * 0.3;

static void push_stats()
{
	char scratch[64];
	int yv = 0;

	snprintf(scratch, 64, "%s, %s", retroctx.sysinfo.library_name, 
		retroctx.sysinfo.library_version);
	STEPMSG(scratch);
	snprintf(scratch, 64, "%s", retroctx.colorspace);
	STEPMSG(scratch);
	snprintf(scratch, 64, "%f fps, %f Hz", (float)retroctx.avinfo.timing.fps, 
		(float)retroctx.avinfo.timing.sample_rate);
	STEPMSG(scratch);
	snprintf(scratch, 64, "%d mode, %d preaud, %d/%d jitter", 
		retroctx.skipmode, retroctx.preaudiogen, retroctx.jitterstep, 
		retroctx.jitterxfer);
	STEPMSG(scratch);
	snprintf(scratch, 64, "(A,V - A/V) %lld,%lld - %lld", 
		retroctx.aframecount, retroctx.vframecount, 
		retroctx.aframecount / retroctx.vframecount);
	STEPMSG(scratch);

	long long int timestamp = arcan_timemillis();
	snprintf(scratch, 64, "Real (Hz): %f\n", 1000.0f * (float) 
		retroctx.aframecount / (float)(timestamp - retroctx.basetime));
	STEPMSG(scratch);

	snprintf(scratch, 64, "cost,wake,xfer: %d, %d, %d ms\n", 
		retroctx.framecost, retroctx.prewake, retroctx.transfercost);
	STEPMSG(scratch);

	if (retroctx.skipmode == TARGET_SKIP_AUTO){
		STEPMSG("Frameskip: Auto");
		snprintf(scratch, 64, "%d skipped", retroctx.frameskips);
		STEPMSG(scratch);
	}
	else if (retroctx.skipmode == TARGET_SKIP_NONE){
		STEPMSG("Frameskip: None");
	}
	else if (retroctx.skipmode >= TARGET_SKIP_STEP && 
		retroctx.skipmode < TARGET_SKIP_FASTFWD){
		snprintf(scratch, 64, "Frameskip: Step (%d)\n", retroctx.skipmode);
		STEPMSG(scratch);
	}
	else if (retroctx.skipmode == TARGET_SKIP_FASTFWD){
		snprintf(scratch, 64, "Frameskip: Fast-Fwd (%d)\n", 
			retroctx.skipmode - TARGET_SKIP_FASTFWD);
		STEPMSG(scratch);
	}
/* color-coded frame timing / alignment, starting at the far right 
 * with the next intended frame, horizontal resolution is 2 px / ms */

	int dw = retroctx.shmcont.addr->storage.w;
	draw_box(retroctx.graphing, 0, yv, dw, PXFONT_HEIGHT * 2, 0xff000000);
	draw_hline(retroctx.graphing, 0, yv + PXFONT_HEIGHT, dw, 0xff999999);

/* first, ideal deadlines, now() is at the end of the X scale */
	int stepc = 0;
	double current = arcan_timemillis();
	double minp    = current - dw;
	double mspf    = retroctx.mspf;
	double startp  = (double) current - modf(current, &mspf);

	while ( startp - (stepc * retroctx.mspf) >= minp ){
		draw_vline(retroctx.graphing, startp - 
			(stepc * retroctx.mspf) - minp, yv + PXFONT_HEIGHT - 1, 
				-(PXFONT_HEIGHT-1), 0xff00ff00);
		stepc++;
	}

/* second, actual frames, plot against ideal, step back etc.
 * until we land outside range */
	size_t cellsz = sizeof(retroctx.frame_ringbuf) / 
		sizeof(retroctx.frame_ringbuf[0]);

#define STEPBACK(X) ( (X) > 0 ? (X) - 1 : cellsz - 1)

	int ofs = STEPBACK(retroctx.framebuf_ofs);

	while (true){
		if (retroctx.frame_ringbuf[ofs] >= minp)
			draw_vline(retroctx.graphing, current - 
				retroctx.frame_ringbuf[ofs], yv + PXFONT_HEIGHT + 1, 
				PXFONT_HEIGHT - 1, 0xff00ffff);
		else
			break;

		ofs = STEPBACK(ofs);
		if (retroctx.frame_ringbuf[ofs] >= minp)
			draw_vline(retroctx.graphing, current - 
				retroctx.frame_ringbuf[ofs], yv + PXFONT_HEIGHT + 1, 
				PXFONT_HEIGHT - 1, 0xff00aaaa);
		else
			break;

		ofs = STEPBACK(ofs);
	}

	cellsz = sizeof(retroctx.drop_ringbuf) / sizeof(retroctx.drop_ringbuf[0]);
	ofs = STEPBACK(retroctx.dropbuf_ofs);

	while (retroctx.drop_ringbuf[ofs] >= minp){
		draw_vline(retroctx.graphing, current - 
			retroctx.drop_ringbuf[ofs], yv + PXFONT_HEIGHT + 1, 
				PXFONT_HEIGHT - 1, 0xff0000ff);
		ofs = STEPBACK(ofs);
	}

/* lastly, the transfer costs, sweep twice, 
 * first for Y scale then for drawing */
	cellsz = sizeof(retroctx.xfer_ringbuf) / sizeof(retroctx.xfer_ringbuf[0]);
	ofs = STEPBACK(retroctx.xferbuf_ofs);
	int maxv = 0, count = 0;

	while( count < retroctx.shmcont.addr->storage.w ){
		if (retroctx.xfer_ringbuf[ ofs ] > maxv)
			maxv = retroctx.xfer_ringbuf[ ofs ];

		count++;
		ofs = STEPBACK(ofs);
	}

	if (maxv > 0){
			yv += PXFONT_HEIGHT * 2;
		float yscale = (float)(PXFONT_HEIGHT * 2) / (float) maxv;
		ofs = STEPBACK(retroctx.xferbuf_ofs);
		count = 0;
		draw_box(retroctx.graphing, 0, yv, dw, PXFONT_HEIGHT * 2, 0xff000000);

		while (count < dw){
			int sample = retroctx.xfer_ringbuf[ofs];

			if (sample > -1)
				draw_vline(retroctx.graphing, dw - count - 1, yv + 
					(PXFONT_HEIGHT * 2), -1 * yscale * sample, 0xff00ff00);
			else
				draw_vline(retroctx.graphing, dw - count - 1, yv + 
					(PXFONT_HEIGHT * 2), -1 * PXFONT_HEIGHT * 2, 0xff0000ff);

			ofs = STEPBACK(ofs);
			count++;
		}
	}

}

#undef STEPBACK
#undef STEPMSG
