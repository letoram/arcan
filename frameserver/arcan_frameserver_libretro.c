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

#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <strings.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "arcan_frameserver_libretro.h"
#include "../arcan_frameserver_shmpage.h"
#include "libretro.h"

#ifndef MAX_PORTS
#define MAX_PORTS 4
#endif

#ifndef MAX_BUTTONS
#define MAX_BUTTONS 12
#endif

/* interface for loading many different emulators,
 * we assume "resource" points to a dlopen:able library,
 * that can be handled by SDLs library management functions. */
static struct {
		bool alive; /* toggle this flag off to terminate main loop */
		int16_t audbuf[4196]; /* audio buffer for retro- targets that supply samples one call at a time */
		size_t audbuf_used;
		
		struct frameserver_shmpage* shared;
		
		struct arcan_evctx inevq;
		struct arcan_evctx outevq;
	
		struct retro_system_info sysinfo;
		struct retro_game_info gameinfo;
		unsigned state_size;
		
/* 
 * current versions only support a subset of inputs (e.g. 1 mouse/lightgun + 12 buttons per port.
 * we map PLAYERn_BUTTONa and substitute n for port and a for button index, with a LUT for UP/DOWN/LEFT/RIGHT
 * MOUSE_X, MOUSE_Y to both mouse and lightgun inputs, and the PLAYER- buttons to MOUSE- buttons 
 */ 
		struct {
			bool joypad[MAX_PORTS][MAX_BUTTONS];
			signed axis[2];
		} inputmatr;
		
		void (*run)();
		void (*reset)();
		bool (*load_game)(const struct retro_game_info* game);
} retroctx = {0};

/* XRGB555 */
static void* libretro_h = NULL;
static void* libretro_requirefun(const char* sym)
{
	void* rfun = NULL;

	if (!libretro_h || !(rfun = SDL_LoadFunction(libretro_h, sym)) )
	{
		LOG("arcan_frameserver(libretro) -- missing library or symbol (%s) during lookup.\n", sym);
		exit(1);
	}
	
	return rfun;
}

static void libretro_vidcb(const void* data, unsigned width, unsigned height, size_t pitch)
{
/* the shmpage size will be larger than the possible values for width / height,
 * so if we have a mismatch, just change the shared dimensions and toggle resize flag */
	if (width != retroctx.shared->w || height != retroctx.shared->h){
		retroctx.shared->w = width;
		retroctx.shared->h = height;
		retroctx.shared->resized = true;
		LOG("resize() to %d, %d\n", retroctx.shared->w, retroctx.shared->h);
	}
	
	uint16_t* buf  = (uint16_t*) data; /* assumes aligned 8-bit */
	uint32_t* dbuf = (uint32_t*) ((void*) retroctx.shared + retroctx.shared->vbufofs);
	
	for (int y = 0; y < height; y++){
		for (int x = 0; x < width; x++){
			uint16_t val = buf[x];
			uint8_t r = ((val & 0x7c00) >> 10 ) << 3;
			uint8_t g = ((val & 0x3e0) >> 5) << 3;
			uint8_t b = (val & 0x1f) << 3;

			*dbuf = (0xff) << 24 | b << 16 | g << 8 | r;
			dbuf++;
		}
			
		buf  += pitch >> 1;
	}

	retroctx.shared->vready = true;
	
	if (!frameserver_semcheck(video_sync, 0))
		exit(1);
}

size_t libretro_audcb(const int16_t* data, size_t nframes)
{
	size_t new_s = nframes * 2 * sizeof(int16_t);
	off_t dstofs = retroctx.shared->abufofs + retroctx.shared->abufused;

	if ( arcan_sem_timedwait(audio_sync, -1) ){
/* if we can't buffer safely, drop the new data */
		if (retroctx.shared->abufused + new_s < SHMPAGE_AUDIOBUF_SIZE){
			memcpy(((void*) retroctx.shared) + dstofs, data, new_s);
			retroctx.shared->abufused += new_s;
		}
		
		arcan_sem_post(audio_sync);
		return nframes;
	}
	
	return 0;
}

void libretro_audscb(int16_t left, int16_t right){
	retroctx.audbuf[ retroctx.audbuf_used++ ] = left;
	retroctx.audbuf[ retroctx.audbuf_used++ ] = right; 
}

/* we ignore these since before pushing for a frame, we've already processed the queue */
static void libretro_pollcb(){}

static bool libretro_setenv(unsigned cmd, void* data){ return false; }

/* use the context-tables from retroctx in combination with dev / ind / ... 
 * to try and figure out what to return, this table is populated in flush_eventq() */
static int16_t libretro_inputstate(unsigned port, unsigned dev, unsigned ind, unsigned id){
	assert(ind < MAX_PORTS);
	assert(id  < MAX_BUTTONS);
	
	switch (dev){
		case RETRO_DEVICE_JOYPAD:
			return (int16_t) retroctx.inputmatr.joypad[ind][id];
		break;
		
		case RETRO_DEVICE_MOUSE:
		break;
		
		case RETRO_DEVICE_LIGHTGUN:
		break;
		
		default:
			LOG("(arcan_frameserver:libretro) Unknown device ID specified (%d)\n", dev);
	}
	
	return 0;
}

static int remaptbl[] = { 
	RETRO_DEVICE_ID_JOYPAD_A,
	RETRO_DEVICE_ID_JOYPAD_B,
	RETRO_DEVICE_ID_JOYPAD_X,
	RETRO_DEVICE_ID_JOYPAD_Y,
	RETRO_DEVICE_ID_JOYPAD_L,
	RETRO_DEVICE_ID_JOYPAD_R
};
		
static void ioev_ctxtbl(arcan_event* ioev)
{
	int ind, button = -1;
	char* subtype;
	signed value = ioev->data.io.datatype == EVENT_IDATATYPE_TRANSLATED ? ioev->data.io.input.translated.active : ioev->data.io.input.digital.active;

	if (1 == sscanf(ioev->label, "PLAYER%d_", &ind) && ind > 0 && ind < MAX_PORTS &&
		(subtype = index(ioev->label, '_')) ){
		subtype++;
		if (1 == sscanf(subtype, "BUTTON%d", &button) && button > 0 && button <= MAX_BUTTONS - 6){
			button--;
			button = button > sizeof(remaptbl) / sizeof(remaptbl[0]) - 1 ? -1 : remaptbl[button];
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

		if (button >= 0){
			retroctx.inputmatr.joypad[ind-1][button] = value;
		}
	}

/* if we found a matching remap */
}

static void flush_eventq(){
	 arcan_event* ev;
	 
/* use labels etc. for trying to populate the context table */
/* we also process requests to save state, shutdown, reset, plug/unplug input, here */
	while ( (ev = arcan_event_poll(&retroctx.inevq)) ){ 
		switch (ev->category){
			case EVENT_IO:
				ioev_ctxtbl(ev);
			break;
		}
	}
}

/* map up a libretro compatible library resident at fullpath:game */
void arcan_frameserver_libretro_run(const char* resource, const char* keyfile)
{
	const char* libname  = resource;
	LOG("mode_libretro (%s)\n", resource);
	
/* abssopath : gamename */
	char* gamename = index(resource, ':');
	if (!gamename) return;
	*gamename = 0;
	gamename++;
	
	if (*libname == 0) 
		return;

/* map up functions and test version */
	libretro_h = SDL_LoadObject(libname);
	void (*initf)() = libretro_requirefun("retro_init");
	unsigned (*apiver)() = libretro_requirefun("retro_api_version");
	( (void(*)(retro_environment_t)) libretro_requirefun("retro_set_environment"))(libretro_setenv);

/* get the lib up and running */
	if ( (initf(), true) && apiver() == RETRO_API_VERSION){
		struct retro_system_info sysinf = {0};
		struct retro_game_info gameinf = {0};
		((void(*)(struct retro_system_info*)) libretro_requirefun("retro_get_system_info")) (&sysinf);
LOG("libretro(%s), version %s loaded. Accepted extensions: %s\n", sysinf.library_name, sysinf.library_version, sysinf.valid_extensions);
		
/* load the rom, either by letting the emulator acts as loader, or by mmaping and handing that segment over */
		if (sysinf.need_fullpath){
			gameinf.path = strdup( gamename );
		} else {
			struct stat filedat;
			int fd;
			if (-1 == stat(gamename, &filedat) || -1 == (fd = open(gamename, O_RDWR)) || 
				MAP_FAILED == ( gameinf.data = mmap(NULL, filedat.st_size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0) ) )
				return;
			gameinf.size = filedat.st_size;
			LOG("mmapped buffer (%d), (%d)\n", fd, gameinf.size);
		}

/* map functions to context structure */
LOG("map functions\n");
		retroctx.run = (void(*)()) libretro_requirefun("retro_run");
		retroctx.reset = (void(*)()) libretro_requirefun("retro_reset");
		retroctx.load_game = (bool(*)(const struct retro_game_info* game)) libretro_requirefun("retro_load_game");
	
/* setup callbacks */
LOG("setup callbacks\n");

		( (void(*)(retro_video_refresh_t) )libretro_requirefun("retro_set_video_refresh"))(libretro_vidcb);
		( (size_t(*)(retro_audio_sample_batch_t)) libretro_requirefun("retro_set_audio_sample_batch"))(libretro_audcb);
		( (void(*)(retro_audio_sample_t)) libretro_requirefun("retro_set_audio_sample"))(libretro_audscb);
		( (void(*)(retro_input_poll_t)) libretro_requirefun("retro_set_input_poll"))(libretro_pollcb);
		( (void(*)(retro_input_state_t)) libretro_requirefun("retro_set_input_state") )(libretro_inputstate);

/* load the game, and if that fails, give up */
LOG("load_game\n");
		if ( retroctx.load_game( &gameinf ) == false )
			return;

		struct retro_system_av_info avinfo;
		( (void(*)(struct retro_system_av_info*)) libretro_requirefun("retro_get_system_av_info"))(&avinfo);
		
LOG("map shm\n");
/* setup frameserver, synchronization etc. */
LOG("samplerate: %lf\n", avinfo.timing.sample_rate);
		retroctx.shared = frameserver_getshm(keyfile, avinfo.geometry.max_width, avinfo.geometry.max_height, 4, 2, avinfo.timing.sample_rate);

		retroctx.inevq.synch.shared = event_sync;
		retroctx.inevq.local = false;
		retroctx.inevq.eventbuf = retroctx.shared->childdevq.evqueue;
		retroctx.inevq.front = &retroctx.shared->childdevq.front;
		retroctx.inevq.back  = &retroctx.shared->childdevq.back;
		retroctx.inevq.n_eventbuf = sizeof(retroctx.shared->childdevq.evqueue) / sizeof(arcan_event);
	
		retroctx.outevq.synch.shared = event_sync;
		retroctx.outevq.local =false;
		retroctx.outevq.eventbuf = retroctx.shared->parentdevq.evqueue;
		retroctx.outevq.front = &retroctx.shared->parentdevq.front;
		retroctx.outevq.back  = &retroctx.shared->parentdevq.back;
		retroctx.outevq.n_eventbuf = sizeof(retroctx.shared->parentdevq.evqueue) / sizeof(arcan_event);

		retroctx.alive = true;
		retroctx.shared->resized = true;
		arcan_sem_post(video_sync);
		
/* since we're guaranteed to get at least one input callback each run(), call, we multiplex 
	* parent event processing as well */
		retroctx.reset();
		
		while (retroctx.alive){
/* the libretro poll input function isn't used, since we have to flush the eventqueue for other events,
 * I/O is already mapped into the table by that point anyhow */
			flush_eventq();
			retroctx.run();
			
/* wrapper around the audscb buffering */
			if (retroctx.audbuf_used){
				libretro_audcb(retroctx.audbuf, retroctx.audbuf_used / 2);
				retroctx.audbuf_used = 0;
			}

		}
	}
}
