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

#include <stdint.h>
#include <stdbool.h>
#include <strings.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>

#include <SDL/SDL_loadso.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_frameserver_backend_shmpage.h"
#include "libretro.h"

#define VID_FD 3
#define AUD_FD 4
#define CTRL_FD 5

#include "arcan_frameserver_decode.h"

FILE* logdev = NULL;
char* active_shmkey = NULL;
static sem_handle async, vsync, esync;

#define LOG(...) ( fprintf(logdev, __VA_ARGS__))

char* arcan_themepath = "";
char* arcan_resourcepath = "";
char* arcan_themename = "";
char* arcan_binpath = "";
char *arcan_libpath = "";

void arcan_frameserver_dropsemaphores(char* shmkey){
	if (NULL == shmkey) 
		return;
	
	char* work = strdup(shmkey);
		work[ strlen(work) - 1] = 'v';
		sem_unlink(work);
		work[strlen(work) - 1] = 'a';
		sem_unlink(work);
		work[strlen(work) - 1] = 'e';
		sem_unlink(work);
	free(work);	
}

/* based on the idea that init inherits an orphaned process */
static bool parent_alive()
{
	return getppid() != 1;
}

/* need the timeout to avoid a deadlock situation */
bool semcheck(sem_handle semaphore, unsigned mstimeout){
	struct timespec st = {.tv_sec  = 0, .tv_nsec = 1000000L}, rem; /* 5 ms */
	bool rv = true;
	int rc;

	do {
		rc = sem_trywait(semaphore);
		if (-1 == rc){
				if (errno == EINVAL){
					LOG("arcan_frameserver -- fatal error while waiting for semaphore\n");
					exit(1);
				}
			nanosleep(&st, &rem); /* don't care about precision here really */
		}
	} while ( (rv = parent_alive()) && rc != 0 );

	return rv;
}

void cleanshmkey(){
	LOG("arcan_frameserver() -- atexit( cleanshmkey )\n");
	arcan_frameserver_dropsemaphores(active_shmkey);
	shm_unlink(active_shmkey);
}

static struct frameserver_shmpage* get_shm(char* shmkey, unsigned width, unsigned height, unsigned bpp, unsigned nchan, unsigned freq){
/* step 1, use the fd (which in turn is set up by the parent to point to a mmaped "tempfile" */
	struct frameserver_shmpage* buf = NULL;
	unsigned bufsize = MAX_SHMSIZE;
	int fd = shm_open(shmkey, O_RDWR, 0700);

	if (-1 == fd) {
		LOG("arcan_frameserver() -- couldn't open keyfile (%s)\n", shmkey);
		return NULL;
	}

	LOG("arcan_frameserver() -- mapping shm, %i from %i\n", bufsize, fd);
	/* map up the shared key- file */
	buf = (struct frameserver_shmpage*) mmap(NULL,
		bufsize,
		PROT_READ | PROT_WRITE,
		MAP_SHARED,
		fd,
	0);
	
	if (buf == MAP_FAILED){
		LOG("arcan_frameserver() -- couldn't map shared memory keyfile.\n");
		close(fd);
		return NULL;
	}
	
/* step 2, buffer all set-up, map it to the shared structure */
	buf->w = width;
	buf->h = height;
	buf->bpp = bpp;
	buf->vready = false;
	buf->aready = false;
	buf->vbufofs = sizeof(struct frameserver_shmpage);
	buf->channels = nchan;
	buf->frequency = freq;

/* ensure vbufofs is aligned, and the rest should follow (bpp forced to 4) */
	buf->abufofs = buf->vbufofs + (buf->w* buf->h* buf->bpp);
	buf->abufbase = 0;

	active_shmkey = shmkey;
	atexit(cleanshmkey);
	LOG("arcan_frameserver() -- shmpage configured and filled.\n");

	return buf;
}

/* interface for loading many different emulators,
 * we assume "resource" points to a dlopen:able library,
 * that can be handled by SDLs library management functions. */
static struct {
		bool alive; /* toggle this flag off to terminate main loop */
		struct frameserver_shmpage* shared;
		
		struct arcan_evctx inevq;
		struct arcan_evctx outevq;
	
		struct retro_system_info sysinfo;
		struct retro_game_info gameinfo;
		unsigned state_size;
		
		void (*run)();
		void (*reset)();
		bool (*load_game)(const struct retro_game_info* game);
} retroctx;

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

static void libretro_vidcb(const void* data, unsigned width, unsigned height, size_t pitch){
/* the shmpage size will be larger than the possible values for width / height,
 * so if we have a mismatch, just change the shared dimensions and toggle resize flag */
	if (width != retroctx.shared->w || height != retroctx.shared->h){
		retroctx.shared->w = width;
		retroctx.shared->h = height;
		retroctx.shared->resized = true;
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
	
	if (!semcheck(vsync, 0))
		exit(1);
}

size_t libretro_audcb(const int16_t* data, size_t nframes)
{
	memcpy(((void*) retroctx.shared) + retroctx.shared->abufofs, data, nframes * 2 * sizeof(int16_t) );
	retroctx.shared->abufused = nframes * 2 * sizeof(int16_t);
	retroctx.shared->aready = true;

	if (!semcheck( async, 0 ))
		exit(1);
	
	return nframes;
}

static void libretro_pollcb(){
}

static bool libretro_setenv(unsigned cmd, void* data){ return false; }
static int16_t libretro_inputstate(unsigned port, unsigned dev, unsigned ind, unsigned id){
	return 0;
}

void flush_eventq(){
	 arcan_event* ev;
	while ( (ev = arcan_event_poll(&retroctx.inevq)) ){ 
		switch (ev->category){
			case EVENT_IO:
				LOG("IO Event!");
			break;
			default:
				LOG("Unhandled: %d\n", ev->category);
		}
	}
}

/* map up a libretro compatible library resident at fullpath:game */
static void mode_libretro(char* resource, char* keyfile)
{
	char* libname  = resource;
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
		retroctx.load_game = (bool(*)(const struct retro_game_info* game)) libretro_requirefun("retro_load_game");
	
/* setup callbacks */
LOG("setup callbacks\n");

		( (void(*)(retro_video_refresh_t)) libretro_requirefun("retro_set_video_refresh"))(libretro_vidcb);
		( (void(*)(retro_audio_sample_batch_t)) libretro_requirefun("retro_set_audio_sample_batch"))(libretro_audcb);
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
		retroctx.shared = get_shm(keyfile, avinfo.geometry.max_width, avinfo.geometry.max_height, 4, 2, avinfo.timing.sample_rate);
		retroctx.inevq.synch.shared = esync;
		retroctx.inevq.local = false;
		retroctx.outevq.synch.shared = esync;
		retroctx.inevq.eventbuf = retroctx.shared->childdevq;
		retroctx.outevq.eventbuf = retroctx.shared->parentdevq;
		
		retroctx.alive = true;
		retroctx.shared->resized = true;
		sem_post(vsync);
		
	/* since we're guaranteed to get at least one input callback each run(), call, we multiplex 
	* parent event processing as well */
		while (retroctx.alive){
			flush_eventq();
			retroctx.run();
		}
	}
}

/* Stream-server is used as a 'reverse' movie mode,
 * i.e. it is the frameserver that reads from the shmpage,
 * feeding whatever comes to ffmpeg */
void mode_streamserv(char* resource, char* keyfile)
{
	/* incomplete, first version should just take
	 * a vid (so buffercopy or readback) and an aid (due to buffering,
	 * we can't treat this the same as vid), encode and store in a file.
	 * 
	 * next step would be to compare this with a more established straming protocol 
	 */
}

void mode_video(char* resource, char* keyfile)
{
	arcan_ffmpeg_context* vidctx = ffmpeg_preload(resource);
	if (!vidctx) return;
	LOG("video(%s)\n", resource);
	vidctx->shared = get_shm(keyfile, vidctx->width, vidctx->height, vidctx->bpp, vidctx->channels, vidctx->samplerate);
	vidctx->async = async;
	vidctx->vsync = vsync;
	vidctx->esync = esync;
	
	if (vidctx->shared){
		int semv, rv;
		vidctx->shared->resized = true;
		sem_post(vidctx->vsync);
		
		LOG("arcan_frameserver(video) -- decoding\n");
		
/* reuse the shmpage, anyhow, the main app should support
 * relaunching the frameserver when looping to cover for
 * memory leaks, crashes and other ffmpeg goodness */
		while (ffmpeg_decode(vidctx) && vidctx->shared->loop) {
			struct frameserver_shmpage* page = vidctx->shared;
			LOG("arcan_frameserver(video) -- decode finished, looping\n");
			ffmpeg_cleanup(vidctx);
			vidctx = ffmpeg_preload(resource);

			/* sanity check, file might have changed between loads */
			if (!vidctx ||
				vidctx->width != page->w ||
				vidctx->height != page->h ||
				vidctx->bpp != page->bpp)
			break;

			vidctx->shared = page;
			vidctx->async = async;
			vidctx->vsync = vsync;
			vidctx->esync = esync;
		}
	}
}

/* args accepted;
 * fname
 * keyfile
 * these are set-up by the parent before exec, so is the sempage.
 * all of these are derived from the keyfile (last char replaced with v, a, e for sems) 
 * and we release vid (within a few seconds or get killed).
 */
 int main(int argc, char** argv)
{
	char* resource = argv[1];
	char* keyfile  = argv[2];
	char* fsrvmode = argv[3];
	
	logdev = stderr;
	if (argc != 4 || !resource || !keyfile || !fsrvmode){
		LOG("arcan_frameserver(), invalid arguments in exec()\n");
		return 1;
	}

	char* work = strdup(keyfile);
		work[strlen(work) - 1] = 'v';
		vsync = sem_open(work, 0);
		work[strlen(work) - 1] = 'a';
		async = sem_open(work, 0);
		work[strlen(work) - 1] = 'e';
		esync = sem_open(work, 0);	
	free(work);
	
	if (async == 0x0 ||
		vsync == 0x0 ||
		esync == 0x0 ){
			LOG("arcan_frameserver() -- couldn't map semaphores, giving up.\n");
			return 1;  
	}

/*
	close(0);
	close(1);
	close(2);
*/
	LOG("frameserver with %s\n", fsrvmode);

	if (strcmp(fsrvmode, "movie") == 0 || strcmp(fsrvmode, "audio") == 0)
		mode_video(resource, keyfile);
	else if (strcmp(fsrvmode, "libretro") == 0)
		mode_libretro(resource, keyfile);
	else if (strcmp(fsrvmode, "streamserve") == 0)
		mode_streamserv(resource, keyfile);
	else;

	return 0;
}
