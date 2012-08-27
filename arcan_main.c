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

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#include <string.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>
#include <limits.h>
#include <errno.h>
#include <time.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <SDL.h>
#include <sqlite3.h>

#include "getopt.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_audio.h"
#include "arcan_video.h"
#include "arcan_framequeue.h"
#include "arcan_frameserver_backend.h"
#include "arcan_lua.h"
#include "arcan_led.h"
#include "arcan_db.h"
#include "arcan_util.h"
#include "arcan_videoint.h"

arcan_dbh* dbhandle = NULL;

/* globals, hackishly used in other places */
extern char* arcan_themename;
extern char* arcan_themepath;
extern char* arcan_resourcepath;
extern char* arcan_libpath;
extern char* arcan_binpath;

bool stderr_redirected = false;
bool stdout_redirected = false;

static const struct option longopts[] = {
	{ "help", no_argument, NULL, '?' },
	{ "width", required_argument, NULL, 'w' },
	{ "height", required_argument, NULL, 'h' },
	{ "winx", required_argument, NULL, 'x' },
	{ "winy", required_argument, NULL, 'y' },
	{ "fullscreen", no_argument, NULL, 'f' },
	{ "windowed", no_argument, NULL, 's' },
	{ "debug", no_argument, NULL, 'g' },
	{ "rpath", required_argument, NULL, 'p'},
	{ "themepath", required_argument, NULL, 't'},
	{ "hijacklib", required_argument, NULL, 'l'},
	{ "frameserver", required_argument, NULL, 'o'},
	{ "conservative", no_argument, NULL, 'm'},
	{ "database", required_argument, NULL, 'd'},
	{ "scalemode", required_argument, NULL, 'r'}, 
	{ "multisamples", required_argument, NULL, 'a'},
	{ "nosound", no_argument, NULL, 'S'},
	{ "ratelimit", required_argument, NULL, 'V'},
	{ "novsync", no_argument, NULL, 'v'},
/* no points guessing which platform forcing this .. */
	{ "stdout", required_argument, NULL, '1'}, 
	{ "stderr", required_argument, NULL, '2'},
	{ NULL, no_argument, NULL, 0 }
};

void usage()
{
	printf("usage:\narcan [-whxyfmstptodgavVSr] [theme] [themearguments]\n"
		"-w\t--width       \tdesired width (default: 640)\n"
		"-h\t--height      \tdesired height (default: 480)\n"
		"-x\t--winx        \tforce window x position (default: don't set)\n"
		"-y\t--winy        \tforce window y position (default: don't set)\n" 
		"-f\t--fullscreen  \ttoggle fullscreen mode ON (default: off)\n"
		"-m\t--conservative\ttoggle conservative memory management (default: off)\n"
		"-s\t--windowed    \ttoggle borderless window mode\n"
		"-p\t--rpath       \tchange path for resources (default: autodetect)\n"
		"-t\t--themepath   \tchange path for themes (default: autodetect)\n"
		"-o\t--frameserver \tforce frameserver (default: autodetect)\n"
		"-l\t--hijacklib   \tforce library for internal launch (default: autodetect)\n"
		"-d\t--database    \tsqlite database (default: arcandb.sqlite)\n"
		"-g\t--debug       \ttoggle debug output (stacktraces, events, etc.)\n"
		"-a\t--multisamples\tset number of multisamples (default 4, disable 0)\n"
		"-v\t--novsync     \tdisable synch to video refresh (default, vsync on)\n"
		"-V\t--ratelimit   \tvsync off, with simulated Hz to (%i .. 120)\n"
		"-S\t--nosound     \tdisable audio output\n"
		"-r\t--scalemode   \tset texture mode:\n\t"
		"%i(rectangle sized textures, default),\n\t"
		"%i(scale to power of two)\n\t"
		"%i(tweak texture coordinates)\n", ARCAN_TIMER_TICK, ARCAN_VIMAGE_NOPOW2, ARCAN_VIMAGE_SCALEPOW2, ARCAN_VIMAGE_TXCOORD);
}

int main(int argc, char* argv[])
{
	bool windowed = false;
	bool fullscreen = false;
	bool conservative = false;
	bool nosound = false;
	unsigned char luadebug = 0;
	
	int scalemode = ARCAN_VIMAGE_NOPOW2;
	int width = 640;
	int height = 480;
	int winx = -1;
	int winy = -1;
	
	int ch;
	FILE* errc;
	char* dbfname = "arcandb.sqlite";
	srand( time(0) ); 

/* start this here since some SDL builds have the nasty (albeit understandable) habit of 
 * redirecting STDIN / STDOUT, and we might want to do that ourselves */
	SDL_Init(SDL_INIT_VIDEO);

	while ((ch = getopt_long(argc, argv, "w:h:x:y:?fvV:msp:t:o:l:a:d:1:2:gr:S", longopts, NULL)) != -1){
		switch (ch) {
			case '?' :
				usage();
				exit(1);
			break;
			case 'w' : width = strtol(optarg, NULL, 10); break;
			case 'h' : height = strtol(optarg, NULL, 10); break;
			case 'm' : conservative = true; break;
			case 'x' : winx = strtol(optarg, NULL, 10); break;
			case 'y' : winy = strtol(optarg, NULL, 10); break;
			case 'f' : fullscreen = true; break;
			case 's' : windowed = true; break;
			case 'l' : arcan_libpath = strdup(optarg); break;
			case 'd' : dbfname = strdup(optarg); break;
			case 'S' : nosound = true; break;
			case 'a' : arcan_video_display.msasamples = strtol(optarg, NULL, 10); break;
			case 'V' : 
				arcan_video_display.vsync = false;
				arcan_video_display.ratelimit = strtol(optarg, NULL, 10); break;
			case 'v' : arcan_video_display.vsync = false; break;
			case 'p' : arcan_resourcepath = strdup(optarg); break;
			case 't' : arcan_themepath = strdup(optarg); break;
			case 'o' : arcan_binpath = strdup(optarg); break;
			case 'g' :
				luadebug++;
				srand(0xdeadbeef); 
				break;
			case 'r' :
				scalemode = strtol(optarg, NULL, 10);
				if (scalemode != ARCAN_VIMAGE_NOPOW2 && scalemode != ARCAN_VIMAGE_SCALEPOW2 && scalemode != ARCAN_VIMAGE_TXCOORD){
					arcan_warning("Warning: main(), -r, invalid scalemode. Ignoring.\n");
					scalemode = ARCAN_VIMAGE_SCALEPOW2;
				}
				break;
		case '1' :
			stdout_redirected = true;
			errc = freopen(optarg, "a", stdout);
			break;
		case '2' :
			stderr_redirected = true;
			errc = freopen(optarg, "a", stderr);
			break;

			default:
				break;
		}
	}

	if (arcan_setpaths() == false)
		goto error;
	
	if (check_theme(*(argv + optind)))
		arcan_themename = *(argv + optind);
	else if (check_theme("welcome"))
		arcan_themename = "welcome";
	else {
		arcan_fatal("No theme found.\n");
	}

	if (strcmp(arcan_themename, "arcan") == 0){
		arcan_fatal("Theme name 'arcan' is reserved\n");
	}
	
	char* dbname = arcan_expand_resource(dbfname, true);

/* try to open the specified database,
 * if that fails, warn, try to create an empty database and if that fails, give up. */
	dbhandle = arcan_db_open(dbname, arcan_themename);
	if (!dbhandle) {
		arcan_warning("Couldn't open database (requested: %s), trying to create a new one.\n", dbfname);
		FILE* fpek = fopen(dbname, "a");
		if (fpek){
			fclose(fpek);
			dbhandle = arcan_db_open(dbname, arcan_themename);
		}
		
		if (!dbhandle)
			goto error;
	}
	free(dbname);

	const SDL_VideoInfo* vi = SDL_GetVideoInfo();
	if (!vi){
		arcan_fatal("SDL_GetVideoInfo() failed, broken display subsystem.");
		goto error;
	}
	
	if (winx != -1 || winy != -1){
		char windbuf[64] = {0}; 
		snprintf(windbuf, 63, "SDL_VIDEO_WINDOW_POS=%i,%i", winx >= 0 ? winx : 0, winy >= 0 ? winy : 0);
		putenv(windbuf);
	}

	if (width == 0 || height == 0) {
		width = vi->current_w;
		height = vi->current_h;
	}
	
	arcan_warning("Notice: [SDL] Video Info: %i, %i, hardware acceleration: %s, window manager: %s, scalemode: %i, VSYNC: %i, MSA: %i\n", 
			vi->current_w, vi->current_h, vi->hw_available ? "yes" : "no", vi->wm_available ? "yes" : "no", scalemode, arcan_video_display.vsync,
			arcan_video_display.msasamples);
	arcan_video_default_scalemode(scalemode);
    
	if (windowed) {
		fullscreen = false;
	}

/* grab video, (necessary) */
	if (arcan_video_init(width, height, 32, fullscreen, windowed, conservative) == ARCAN_OK) {
		errno = 0;
		/* grab audio, (possible to live without) */
		if (ARCAN_OK != arcan_audio_setup(nosound)){
			arcan_warning("Warning: No audio devices could be found.\n");
		}

/* setup device polling, cleanup, ... */
		arcan_event_init( arcan_event_defaultctx() );
		arcan_led_init();

/* export what we know and load theme */
		lua_State* luactx = luaL_newstate();
		luaL_openlibs(luactx);

/* this one also sandboxes os/io functions (just by setting to nil) */
		arcan_lua_exposefuncs(luactx, luadebug);
		arcan_lua_pushglobalconsts(luactx);

		if (argc > optind)
			arcan_lua_pushargv(luactx, argv + optind + 1);

		int err_func = 0;

		char* themescr = (char*) malloc(strlen(arcan_themename) + 5);
		sprintf(themescr, "%s.lua", arcan_themename);
		char* fn = arcan_find_resource(themescr, ARCAN_RESOURCE_THEME);

		if ( luaL_dofile(luactx, fn) == 1 ){
			const char* msg = lua_tostring(luactx, -1);
			arcan_fatal("Fatal: main(), Error loading theme script (%s) : (%s)\n", themescr, msg);
			goto error;
		}

		free(fn);
		free(themescr);

/* entry point follows the name of the theme,
 * hand over execution and begin event loop */
		arcan_lua_callvoidfun(luactx, arcan_themename);
		arcan_lua_callvoidfun(luactx, "show");

		bool done = false;
		while (!done) {
			arcan_event* ev;

			unsigned nticks;
			float frag = arcan_event_process(arcan_event_defaultctx(), &nticks);

/* priority is always in maintaining logical clock and event processing */
			if (nticks > 0){
				arcan_video_tick(nticks);
				arcan_audio_tick(nticks);
			}
			else{
/* we separate the ffunc per-frame update and the video refresh */
				arcan_video_pollfeed();
				arcan_video_refresh(frag);
				arcan_audio_refresh();
			}

/* note that an onslaught of I/O operations can currently
 * saturate tick / video instead of evenly distribute between the two.
 * since these can also propagate to LUA and user scripts, there 
 * should really be a timing balance here (keep track of avg. time to dispatch
 * event, figure out how many we can handle before we must push a logic- frame */
			while ((ev = arcan_event_poll(arcan_event_defaultctx()))) {

				switch (ev->category) {
					case EVENT_IO:
					break;

					case EVENT_VIDEO:
					/* these events can typically be determined in video_tick(), 
					 * however there are so many hierarchical dependencies (linked objs, instances, ...)
					 * that a full delete is not safe there (e.g. event -> callback -> */
						if (ev->kind == EVENT_VIDEO_EXPIRE)
							arcan_video_deleteobject(ev->data.video.source);
						
						else if (ev->kind == EVENT_VIDEO_ASYNCHIMAGE_LOADED ||
							ev->kind == EVENT_VIDEO_ASYNCHIMAGE_LOAD_FAILED)
							arcan_video_pushasynch(ev->data.video.source);
						
					break;

					case EVENT_SYSTEM:
					/* note the LUA shutdown() call actually emits this event */
						if (ev->kind == EVENT_SYSTEM_EXIT)
							done = true;
						else
							if (ev->kind == EVENT_SYSTEM_LAUNCH_EXTERNAL) {}
							else
								if (ev->kind == EVENT_SYSTEM_CLEANUP_EXTERNAL) {}

						continue;
						break;
				}

				arcan_lua_pushevent(luactx, ev);
			}
		}

		arcan_lua_callvoidfun(luactx, "shutdown");
		arcan_led_cleanup();
		arcan_video_shutdown();
	}
	else{
		arcan_fatal("Error; Couldn't initialize video system, try other windowing options (-f, -w, ...)\n");
	}
error:
	SDL_Quit();
	exit(1);

	return 0;
}
