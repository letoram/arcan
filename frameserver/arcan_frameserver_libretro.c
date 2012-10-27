/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */
#include <SDL/SDL_loadso.h>

#include <math.h>
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <strings.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "arcan_frameserver_libretro.h"
#include "./ntsc/snes_ntsc.h"
#include "../arcan_frameserver_shmpage.h"
#include "libretro.h"

/* resampling at this level because it seems the linux + openAL + pulse-junk-audio
 * introduces audible pops on some soundcard / drivers at odd (so poorly tested) sampling rates) */
#include "resampler/speex_resampler.h"

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
 * the async and esync mechanisms will buffer locally and have that buffer flushed by the main application
 * whenever appropriate. For audio, this is likely limited by the buffering capacity of the sound device / pipeline
 * whileas the event queue might be a bit more bursty.
 *
 * however, we will lock to video, meaning that it is the framerate of the frameserver that will decide
 * the actual framerate, that may be locked to VREFRESH (or lower, higher / variable). Thus we also need frameskipping heuristics here.
 */
struct input_port {
	bool buttons[MAX_BUTTONS];
	signed axes[MAX_AXES];

/* special offsets into buttons / axes based on device */
	unsigned cursor_x, cursor_y, cursor_btns[5];
};

typedef void(*pixconv_fun)(const void* data, uint32_t* outp, unsigned width, unsigned height, size_t pitch);

/* interface for loading many different emulators,
 * we assume "resource" points to a dlopen:able library,
 * that can be handled by SDLs library management functions. */
static struct {
/* frame management */
		bool skipframe;
		bool pause;
		double mspf;
		double drift;
		long long int basetime;
		int skipmode;
		unsigned long long framecount;

/* number of audio frames delivered, used to determine
 * if a frame should be doubled or not */
		unsigned long long aframecount;

/* colour conversion / filtering */
		pixconv_fun converter;
		uint16_t* ntsc_imb;
		bool ntscconv;
		snes_ntsc_t ntscctx;
		snes_ntsc_setup_t ntsc_opts;

/* input-output */
		struct frameserver_shmcont shmcont;
		uint8_t* vidp, (* audp);

/* set as a canary after audb at a recalc to detect overflow */
		uint8_t* audguardb;

/* resample at the last minute when we have all frames associated with a logic run() */

		int16_t* audbuf;
		size_t audbuf_sz;
		off_t audbuf_ofs;
		SpeexResamplerState* resampler;

		file_handle last_fd;

		struct arcan_evctx inevq;
		struct arcan_evctx outevq;

/* libretro states / function pointers */
		struct retro_system_info sysinfo;
		struct retro_game_info gameinfo;
		unsigned state_size;

/* parent uses an event->push model for input, libretro uses a poll one, so
 * prepare a lookup table that events gets pushed into and libretro can poll */
		struct input_port input_ports[MAX_PORTS];
		
/* timing according to retro */
		struct retro_system_av_info avinfo;
		double avfps;

		void (*run)();
		void (*reset)();
		bool (*load_game)(const struct retro_game_info* game);
		size_t (*serialize_size)();
		bool (*serialize)(void*, size_t);
		bool (*deserialize)(const void*, size_t);
		void (*set_ioport)(unsigned, unsigned);
} retroctx = {0};

static void* libretro_requirefun(const char* const sym)
{
	void* res = frameserver_requirefun(sym);

	if (!res)
	{
		LOG("arcan_frameserver(libretro) -- missing library or symbol (%s) during lookup.\n", sym);
		exit(1);
	}

	return res;
}

#define RGB565(b, g, r) ((uint16_t)(((uint8_t)(r) >> 3) << 11) | (((uint8_t)(g) >> 2) << 5) | ((uint8_t)(b) >> 3))
static void push_ntsc(unsigned width, unsigned height, const uint16_t* ntsc_imb, uint32_t* outp)
{
	size_t linew = SNES_NTSC_OUT_WIDTH(width) * 4;

/* only draw on every other line, so we can easily mix or blend interleaved (or just duplicate) */
	snes_ntsc_blit(&retroctx.ntscctx, ntsc_imb, width, 0, width, height, outp, linew * 2);

	for (int row = 1; row < height * 2; row += 2)
		memcpy(&retroctx.vidp[row * linew], &retroctx.vidp[(row-1) * linew], linew);
}

/* better distribution for conversion (white is white ..) */
static const uint8_t rgb565_lut5[] = {
	  0,   8,  16,  25,  33,  41,  49,  58,  66,   74,  82,  90,  99, 107, 115,
	123, 132, 140, 148, 156, 165, 173, 181, 189,  197, 206, 214, 222, 230, 239, 247, 255
};

static const uint8_t rgb565_lut6[] = {0, 4, 8, 12, 16, 20, 24,  28, 32, 36, 40, 45, 49, 53, 57, 61,
	65, 69, 73, 77, 81, 85, 89, 93, 97, 101,  105, 109, 113, 117, 121, 125, 130, 134, 138, 142, 146,
 150, 154, 158, 162, 166,  170, 174, 178, 182, 186, 190, 194, 198, 202, 206, 210, 215, 219, 223,
 227, 231,  235, 239, 243, 247, 251, 255
};

static void libretro_rgb565_rgba(const uint16_t* data, uint32_t* outp, unsigned width, unsigned height, size_t pitch)
{
	uint16_t* interm = retroctx.ntsc_imb;

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
 
static void libretro_xrgb888_rgba(const uint32_t* data, uint32_t* outp, unsigned width, unsigned height, size_t pitch)
{
	assert( (uintptr_t)data % 4 == 0 );
	assert( (video_channels == 4) );

	uint16_t* interm = retroctx.ntsc_imb;

	for (int y = 0; y < height; y++){
		for (int x = 0; x < width; x++){
			uint8_t* quad = (uint8_t*) (data + x);
			if (retroctx.ntscconv)
				*interm++ = RGB565(quad[0], quad[1], quad[2]);
			else
				*outp++ = 0xff << 24 | quad[0] << 16 | quad[1] << 8 | quad[2];
		}

		data += pitch >> 2;
	}

	if (retroctx.ntscconv)
		push_ntsc(width, height, retroctx.ntsc_imb, outp);
}

static void libretro_rgb1555_rgba(const uint16_t* data, uint32_t* outp, unsigned width, unsigned height, size_t pitch)
{
	uint16_t* interm = retroctx.ntsc_imb;

	for (int y = 0; y < height; y++){
		for (int x = 0; x < width; x++){
			uint16_t val = data[x];
			uint8_t r = ((val & 0x7c00) >> 10) << 3;
			uint8_t g = ((val & 0x03e0) >>  5) << 3;
			uint8_t b = ( val & 0x001f) <<  3;

/* unsure if the underlying libs assess endianess correct, big-endian untested atm. */
			if (retroctx.ntscconv)
				*interm++ = RGB565(r, g, b);
			else
				*outp++ = (0xff) << 24 | b << 16 | g << 8 | r;
		}

		data += pitch >> 1;
	}

	if (retroctx.ntscconv)
		push_ntsc(width, height, retroctx.ntsc_imb, outp);
}

static int testcounter = 0;

static void libretro_vidcb(const void* data, unsigned width, unsigned height, size_t pitch)
{
	testcounter++;
/* framecount is updated in sync */
	if (!data || retroctx.skipframe)
		return;

	unsigned outh = retroctx.ntscconv ? height * 2 : height;
	unsigned outw = retroctx.ntscconv ? SNES_NTSC_OUT_WIDTH( width ) : width;

/* the shmpage size will be larger than the possible values for width / height,
 * so if we have a mismatch, just change the shared dimensions and toggle resize flag */
	if (outw != retroctx.shmcont.addr->storage.w || outh != retroctx.shmcont.addr->storage.h){
		frameserver_shmpage_resize(&retroctx.shmcont, outw, outh, video_channels, audio_channels, audio_samplerate);
		frameserver_shmpage_calcofs(retroctx.shmcont.addr, &(retroctx.vidp), &(retroctx.audp) );

		retroctx.audguardb = retroctx.audp + SHMPAGE_AUDIOBUF_SIZE;
		retroctx.audguardb[0] = 0xde;
		retroctx.audguardb[1] = 0xad;

/* will be reallocated if needed and not set so just free and unset */
		if (retroctx.ntsc_imb){
			free(retroctx.ntsc_imb);
			retroctx.ntsc_imb = NULL;
		}
	}

/* intermediate storage for blargg NTSC filter, if toggled
 * ntscconv will be applied by the converter however */
	if (retroctx.ntscconv && !retroctx.ntsc_imb){
		retroctx.ntsc_imb = malloc(sizeof(uint16_t) * outw * outh);
	}

	if (retroctx.converter)
		retroctx.converter(data, (void*) retroctx.vidp, width, height, pitch);
}

/* the better way would be to just drop the videoframes, buffer the audio, 
 * calculate the highspeed samplerate and downsample the audio signal */
static void libretro_skipnframes(unsigned count)
{
	retroctx.skipframe = true;

	long long afc = retroctx.aframecount;
	long long vfc = retroctx.framecount;
	
	for (int i = 0; i < count; i++)
		retroctx.run();

	retroctx.aframecount = afc;
	retroctx.framecount = vfc;

	retroctx.skipframe = false;
}

void libretro_audscb(int16_t left, int16_t right)
{
	retroctx.aframecount++;

	if (retroctx.skipframe)
		return;

	retroctx.audbuf[retroctx.audbuf_ofs++] = left;
	retroctx.audbuf[retroctx.audbuf_ofs++] = right;
}

size_t libretro_audcb(const int16_t* data, size_t nframes)
{
	retroctx.aframecount += nframes;

	if (retroctx.skipframe)
		return nframes;

	memcpy(&retroctx.audbuf[retroctx.audbuf_ofs], data, nframes << 2); /* 2 bytes per sample, 2 channels */
	retroctx.audbuf_ofs += nframes * 2; /* audbuf is in int16_t and ofs used as index */

	return nframes;
}

/* we ignore these since before pushing for a frame, we've already processed the queue */
static void libretro_pollcb(){}

static bool libretro_setenv(unsigned cmd, void* data){
	char* sysdir;
	bool rv = false;

	switch (cmd){
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
			rv = true;

			switch ( *(enum retro_pixel_format*) data ){
				case RETRO_PIXEL_FORMAT_0RGB1555:
					retroctx.converter = (pixconv_fun) libretro_rgb1555_rgba;
				break;
				
				case RETRO_PIXEL_FORMAT_RGB565:
					retroctx.converter = (pixconv_fun) libretro_rgb565_rgba;
				break;

				case RETRO_PIXEL_FORMAT_XRGB8888:
					retroctx.converter = (pixconv_fun) libretro_xrgb888_rgba;
				break;

			default:
				LOG("(arcan_frameserver:libretro) - unknown pixelformat encountered (%d).\n", *(unsigned*)data);
				retroctx.converter = NULL;
			}
		break;

		case RETRO_ENVIRONMENT_GET_CAN_DUPE:
			rv = true;
		break;

/* ignore for now */
		case RETRO_ENVIRONMENT_SHUTDOWN:
			retroctx.shmcont.addr->dms = true;
			LOG("(arcan_frameserver:libretro) - shutdown requested from lib.\n");
		break;

/* unsure how we'll handle this when privsep is working, possibly through chroot to garbage dir */
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
			sysdir = getenv("ARCAN_SYSTEMPATH");
			if (!sysdir){
				sysdir = "./resources/games/system";
			}

/* some cores (mednafen-psx, ..) currently breaks on relative paths, so resolve to absolute one for the time being */
			sysdir = realpath(sysdir, NULL);

			LOG("(arcan_frameserver:libretro) - system directory set to (%s).\n", sysdir);
			*((const char**) data) = sysdir;
			rv = sysdir != NULL;
		break;
	}

	return rv;
}

/* use the context-tables from retroctx in combination with dev / ind / ...
 * to try and figure out what to return, this table is populated in flush_eventq() */
static int16_t libretro_inputstate(unsigned port, unsigned dev, unsigned ind, unsigned id){
	static bool butn_warning = false;
	static bool port_warning = false;

	if (id > MAX_BUTTONS){
		if (butn_warning == false)
			arcan_warning("arcan_frameserver(libretro) -- unexpectedly high button index (dev:%u)(%u:%%) requested, ignoring.\n", ind, id);

		butn_warning = true;
		return 0;
	}

	if (port > MAX_PORTS){
		if (port_warning == false)
			LOG("arcan_frameserver(libretro) -- core requested an unknown port id (%u:%u:%u), ignored.\n", dev, ind, id);

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
			LOG("(arcan_frameserver:libretro) Unknown device ID specified (%d), video will be disabled.\n", dev);
	}

	return 0;
}

static int remaptbl[] = {
	RETRO_DEVICE_ID_JOYPAD_A,
	RETRO_DEVICE_ID_JOYPAD_B,
	RETRO_DEVICE_ID_JOYPAD_X,
	RETRO_DEVICE_ID_JOYPAD_Y,
	RETRO_DEVICE_ID_JOYPAD_L,
	RETRO_DEVICE_ID_JOYPAD_R,
	0
};

static void ioev_ctxtbl(arcan_ioevent* ioev, const char* label)
{
	size_t remaptbl_sz = sizeof(remaptbl) / sizeof(remaptbl[0]) - 1;
	int ind, button = -1, axis;
	char* subtype;
	signed value = ioev->datatype == EVENT_IDATATYPE_TRANSLATED ? ioev->input.translated.active : ioev->input.digital.active;

	if (1 == sscanf(label, "PLAYER%d_", &ind) && ind > 0 && ind <= MAX_PORTS && (subtype = strchr(label, '_')) ){
		subtype++;
	
		if (1 == sscanf(subtype, "BUTTON%d", &button) && button > 0 && button <= MAX_BUTTONS - 6){
			button--;
			button = button > remaptbl_sz ? -1 : remaptbl[button];
		}
		else if (1 == sscanf(subtype, "AXIS%d", &axis) && axis > 0 && axis <= MAX_AXES){
			if (ioev->input.analog.gotrel)
				retroctx.input_ports[ind-1].axes[ axis - 1 ] = ioev->input.analog.axisval[1];
			else {
				static bool warned = false;
				if (!warned)
					LOG("libretro::analog input(%s), ignored. Absolute input currently unsupported.\n", label);
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
			LOG("arcan_frameserver(libretro) - descriptor transferred, %d\n", retroctx.last_fd);
		break;

		case TARGET_COMMAND_NTSCFILTER:
			toggle_ntscfilter(tgt->ioevs[0].iv);
		break;

/* ioev[0].iv = group, 1.fv, 2.fv, 3.fv */
		case TARGET_COMMAND_NTSCFILTER_ARGS:
			snes_ntsc_update_setup(&retroctx.ntscctx, &retroctx.ntsc_opts,
				tgt->ioevs[0].iv, tgt->ioevs[1].fv, tgt->ioevs[2].fv, tgt->ioevs[3].fv);

		break;

/* 0 : auto, -1 : single-step, > 0 render every n frames. */
		case TARGET_COMMAND_FRAMESKIP:
			retroctx.skipmode = tgt->ioevs[0].iv;
		break;

/* any event not being UNPAUSE is ignored, no frames are processed
 * and the core is allowed to sleep in between polls */
		case TARGET_COMMAND_PAUSE:
			retroctx.pause = true;
		break;

/* can safely assume there are no other events in the queue after this one,
 * more important for encode etc. that need to flush codecs */
		case TARGET_COMMAND_EXIT:
			return; 
		break;
		
		case TARGET_COMMAND_UNPAUSE:
			retroctx.pause = false;
			retroctx.basetime = frameserver_timemillis() + retroctx.framecount * retroctx.mspf;
			retroctx.framecount = 0;
			retroctx.aframecount = 0;
		break;

		case TARGET_COMMAND_SETIODEV:
			retroctx.set_ioport(tgt->ioevs[0].iv, tgt->ioevs[1].iv);
		break;

		case TARGET_COMMAND_STEPFRAME:
			if (tgt->ioevs[0].iv < 0);
				else
					while(tgt->ioevs[0].iv-- && retroctx.shmcont.addr->dms){ retroctx.run(); }
/* should also emit a corresponding event back with the current framenumber */
		break;

/* store / rewind operate on the last FD set through FDtransfer */
		case TARGET_COMMAND_STORE:
			if (BADFD != retroctx.last_fd){
				size_t dstsize = retroctx.serialize_size();
				void* buf;
				if (dstsize && ( buf = malloc( dstsize ) )){

					if ( retroctx.serialize(buf, dstsize) ){
						frameserver_dumprawfile_handle( buf, dstsize, retroctx.last_fd, true );
						retroctx.last_fd = BADFD;
					} else
						LOG("frameserver(libretro), serialization failed.\n");

					free(buf);
				}
			}
			else
				LOG("frameserver(libretro), snapshot store requested without any viable target.\n");
		break;

		case TARGET_COMMAND_RESTORE:
			if (BADFD != retroctx.last_fd){
				ssize_t dstsize = -1;

				void* buf = frameserver_getrawfile_handle( retroctx.last_fd, &dstsize );
				if (buf != NULL && dstsize > 0)
					retroctx.deserialize( buf, dstsize );

				retroctx.last_fd = BADFD;
			}
			else
				LOG("frameserver(libretro), snapshot restore requested without any viable target\n");
		break;

		default:
			arcan_warning("frameserver(libretro), unknown target event (%d), ignored.\n", ev->kind);
	}
}

/* use labels etc. for trying to populate the context table */
/* we also process requests to save state, shutdown, reset, plug/unplug input, here */
static inline void flush_eventq(){
	 arcan_event* ev;

	 do
		while ( (ev = arcan_event_poll(&retroctx.inevq)) ){
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
			retroctx.pause && (frameserver_delay(1), 1));
}

/* return true if we're in synch (may sleep),
 * return false if we're lagging behind */
static inline bool retroctx_sync()
{
	long long int timestamp = frameserver_timemillis();
	retroctx.framecount++;

	if (retroctx.skipmode == TARGET_SKIP_NONE)
		return true;

/* TARGET_SKIP_AUTO here */
	long long int now  = timestamp - retroctx.basetime;
	long long int next = floor( (double)retroctx.framecount * retroctx.mspf );
	int left = next - now;

/* ntpd, settimeofday, wonky OS etc. or some massive stall */
	if (now < 0 || abs( left ) > retroctx.mspf * 60){
		retroctx.basetime = timestamp;
		retroctx.framecount  = 1;
		retroctx.aframecount = 1;
		return true;
	}

/* more than a frame behind? just skip */
	if ( left < -1 * retroctx.mspf )
		return false;

/* used to measure the elapsed time between frames in order to wake up in time,
 * but frame- distribution didn't get better than this magic value on anything in the test set */
	if (left > 4)
		frameserver_delay( left - 4);

	return true;
}

/* map up a libretro compatible library resident at fullpath:game,
 * if resource is /info, no loading will occur but a dump of the capabilities
 * of the core will be sent to stdout. */
void arcan_frameserver_libretro_run(const char* resource, const char* keyfile)
{
	retroctx.converter  = (pixconv_fun) libretro_rgb1555_rgba;
	const char* libname  = resource;
	int errc;
	LOG("mode_libretro (%s)\n", resource);

/* abssopath : gamename */
	char* gamename = strchr(resource, ':');
	if (!gamename) return;
	*gamename = 0;
	gamename++;

	if (*libname == 0)
		return;

/* map up functions and test version */
	if (!frameserver_loadlib(libname)){
		LOG("arcan_frameserver(libretro) -- couldn't open library (%s), giving up.\n", libname);
		exit(1);
	}

	void (*initf)() = libretro_requirefun("retro_init");
	unsigned (*apiver)() = libretro_requirefun("retro_api_version");
	( (void(*)(retro_environment_t)) libretro_requirefun("retro_set_environment"))(libretro_setenv);

/* get the lib up and running */
	if ( (initf(), true) && apiver() == RETRO_API_VERSION){
		struct retro_system_info sysinf = {0};
		struct retro_game_info gameinf = {0};
		((void(*)(struct retro_system_info*)) libretro_requirefun("retro_get_system_info")) (&sysinf);

/* added as a support to romman etc. so they don't have to load the libs in question */
		if (strcmp(gamename, "/info") == 0){
			fprintf(stdout, "arcan_frameserver(info)\nlibrary:%s\nversion:%s\nextensions:%s\n/arcan_frameserver(info)", sysinf.library_name, sysinf.library_version, sysinf.valid_extensions);
			return;
		}

	LOG("libretro(%s), version %s loaded. Accepted extensions: %s\n", sysinf.library_name, sysinf.library_version, sysinf.valid_extensions);

/* load the rom, either by letting the emulator acts as loader, or by mmaping and handing that segment over */
		ssize_t bufsize;
		gameinf.path = strdup( gamename );
		gameinf.data = frameserver_getrawfile(gamename, &bufsize);
		if (bufsize == -1){
			LOG("libretro(%s), couldn't load data, giving up.\n", gamename);
			return;
		}

		gameinf.size = bufsize;
/* map functions to context structure */
		retroctx.run   = (void(*)()) libretro_requirefun("retro_run");
		retroctx.reset = (void(*)()) libretro_requirefun("retro_reset");

		retroctx.load_game  = (bool(*)(const struct retro_game_info* game)) libretro_requirefun("retro_load_game");
		retroctx.serialize  = (bool(*)(void*, size_t)) libretro_requirefun("retro_serialize");
		retroctx.set_ioport = (void(*)(unsigned,unsigned)) libretro_requirefun("retro_set_controller_port_device");

		retroctx.deserialize    = (bool(*)(const void*, size_t)) libretro_requirefun("retro_unserialize"); /* bah, unmarshal or deserialize.. not unserialize :p */
		retroctx.serialize_size = (size_t(*)()) libretro_requirefun("retro_serialize_size");

/* setup callbacks */
		( (void(*)(retro_video_refresh_t) )libretro_requirefun("retro_set_video_refresh"))(libretro_vidcb);
		( (size_t(*)(retro_audio_sample_batch_t)) libretro_requirefun("retro_set_audio_sample_batch"))(libretro_audcb);
		( (void(*)(retro_audio_sample_t)) libretro_requirefun("retro_set_audio_sample"))(libretro_audscb);
		( (void(*)(retro_input_poll_t)) libretro_requirefun("retro_set_input_poll"))(libretro_pollcb);
		( (void(*)(retro_input_state_t)) libretro_requirefun("retro_set_input_state") )(libretro_inputstate);

/* load the game, and if that fails, give up */
		if ( retroctx.load_game( &gameinf ) == false )
			return;

		( (void(*)(struct retro_system_av_info*)) libretro_requirefun("retro_get_system_av_info"))(&retroctx.avinfo);

/* setup frameserver, synchronization etc. */
		assert(retroctx.avinfo.timing.fps > 1);
		assert(retroctx.avinfo.timing.sample_rate > 1);
		retroctx.last_fd = BADFD;
		retroctx.avfps = retroctx.avinfo.timing.sample_rate / retroctx.avinfo.timing.fps;
		retroctx.mspf = ( 1000.0 * (1.0 / retroctx.avinfo.timing.fps) );

		retroctx.ntscconv  = false;
		retroctx.ntsc_opts = snes_ntsc_rgb;
		snes_ntsc_init(&retroctx.ntscctx, &retroctx.ntsc_opts);

		LOG("arcan_frameserver(libretro) -- setting up resampler, %lf => %d.\n", retroctx.avinfo.timing.sample_rate, audio_samplerate);
		retroctx.resampler = speex_resampler_init(audio_channels, retroctx.avinfo.timing.sample_rate, audio_samplerate, 3 /* quality */, &errc);

/* intermediate buffer for resampling and not relying on a well-behaving shmpage */
		retroctx.audbuf_sz = retroctx.avinfo.timing.sample_rate * sizeof(uint16_t) * 2;
		retroctx.audbuf = malloc(retroctx.audbuf_sz);
		memset(retroctx.audbuf, 0, retroctx.audbuf_sz);
		retroctx.audbuf_ofs = 0; /* initialize with some silence */

		retroctx.shmcont = frameserver_getshm(keyfile, true);
		struct frameserver_shmpage* shared = retroctx.shmcont.addr;

		if (!frameserver_shmpage_resize(&retroctx.shmcont,
			retroctx.avinfo.geometry.max_width,
			retroctx.avinfo.geometry.max_height, video_channels, audio_channels,
			audio_samplerate))
			return;

		frameserver_shmpage_calcofs(shared, &(retroctx.vidp), &(retroctx.audp) );
		retroctx.audguardb = retroctx.audp + SHMPAGE_AUDIOBUF_SIZE;
		retroctx.audguardb[0] = 0xde;
		retroctx.audguardb[1] = 0xad;

		frameserver_shmpage_setevqs(retroctx.shmcont.addr, retroctx.shmcont.esem, &(retroctx.inevq), &(retroctx.outevq), false);
		frameserver_semcheck(retroctx.shmcont.vsem, -1);

/* since we're guaranteed to get at least one input callback each run(), call, we multiplex
	* parent event processing as well */
		retroctx.reset();

/* basetime is used as epoch for all other timing calculations */
		retroctx.basetime = frameserver_timemillis();

/* since we might have requests to save state before we die, we use the flush_eventq as an atexit */
		atexit(flush_eventq);

/* setup standard device remapping tables, these can be changed by the calling process
 * with a corresponding target event. */
		for (int i = 0; i < MAX_PORTS; i++){
			retroctx.input_ports[i].cursor_x = 0;
			retroctx.input_ports[i].cursor_y = 1;
			retroctx.input_ports[i].cursor_btns[0] = 0;
			retroctx.input_ports[i].cursor_btns[1] = 1;
			retroctx.input_ports[i].cursor_btns[2] = 2;
			retroctx.input_ports[i].cursor_btns[3] = 3;
			retroctx.input_ports[i].cursor_btns[4] = 4;
		}

		while (retroctx.shmcont.addr->dms){
/* since pause and other timing anomalies are part of the eventq flush, take care of it
 * outside of frame frametime measurements */
			if (retroctx.skipmode >= TARGET_SKIP_STEP)
				libretro_skipnframes(retroctx.skipmode);

			flush_eventq();

			testcounter = 0;
			retroctx.run();

			if (testcounter != 1)
				LOG("(arcan_frameserver(libretro) -- inconsistent core behavior, expected 1 video frame / run(), got %d\n", testcounter);
			testcounter = 0;

			bool lastskip = retroctx.skipframe;
			retroctx.skipframe = !retroctx_sync();

/* the audp/vidp buffers have already been updated in the callbacks */
			if (lastskip == false){

/* possible to add a size lower limit here to maintain a larger resampling buffer than synched to videoframe */
				if (retroctx.audbuf_ofs){
					spx_uint32_t outc  = SHMPAGE_AUDIOBUF_SIZE; /*first number of bytes, then after process..., number of samples */
					spx_uint32_t nsamp = retroctx.audbuf_ofs >> 1;
					speex_resampler_process_interleaved_int(retroctx.resampler, (const spx_int16_t*) retroctx.audbuf, &nsamp, (spx_int16_t*) retroctx.audp, &outc);
					if (outc)
						retroctx.shmcont.addr->abufused += outc * audio_channels * sizeof(uint16_t);

					shared->aready = true;
					retroctx.audbuf_ofs = 0;
				}

				shared->vready = true;
				frameserver_semcheck( retroctx.shmcont.vsem, INFINITE);
			};

			assert(shared->aready == false);
			assert(shared->vready == false);
			assert(retroctx.audguardb[0] = 0xde && retroctx.audguardb[1] == 0xad);
		}

	}
}
