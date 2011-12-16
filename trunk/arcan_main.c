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

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <SDL.h>
#include <sqlite3.h>

#include "getopt.h"
#include "arcan_general.h"
#include "arcan_audio.h"
#include "arcan_video.h"
#include "arcan_framequeue.h"
#include "arcan_frameserver_backend.h"
#include "arcan_event.h"
#include "arcan_lua.h"
#include "arcan_led.h"
#include "arcan_db.h"
#include "arcan_util.h"

arcan_dbh* dbhandle = NULL;

/* globals, hackishly used in other places */
char* arcan_themename = "arcan";
char* arcan_themepath = NULL;
char* arcan_resourcepath = NULL;
char* arcan_libpath = NULL;
char* arcan_binpath = NULL;

static const struct option longopts[] = {
	{ "help", no_argument, NULL, '?' },
	{ "width", required_argument, NULL, 'w' },
	{ "height", required_argument, NULL, 'h' },
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
/* no points guessing which platform forcing this .. */
	{ "stdout", required_argument, NULL, '1'}, 
	{ "stderr", required_argument, NULL, '2'},
	{ NULL, no_argument, NULL, 0 }
};

/* sandboxing needs some overhaul,
 * should really block all filesystem operations,
 * along with sockets and "possible extensions" */
static const luaL_Reg lualibs[] = {
  {"", luaopen_base},
  {LUA_LOADLIBNAME, luaopen_package},
  {LUA_TABLIBNAME, luaopen_table},
  {LUA_STRLIBNAME, luaopen_string},
  {LUA_MATHLIBNAME, luaopen_math},
  {LUA_DBLIBNAME, luaopen_debug},
  {NULL, NULL}
};

void usage()
{
	printf("usage:\narcan [-whfmsptoldg12] [theme]\n"
		"-w\t--width       \tdesired width (default: 640)\n"
		"-h\t--height      \tdesired height (default: 480)\n"
		"-f\t--fullscreen  \ttoggle fullscreen mode ON (default: off)\n"
		"-m\t--conservative\ttoggle conservative memory management (default: off)\n"
		"-s\t--windowed    \ttoggle windowed fullscreen\n"
		"-p\t--rpath       \tchange path for resources (default: autodetect)\n"
		"-t\t--themepath   \tchange path for themes (default: autodetect)\n"
		"-o\t--frameserver \tforce frameserver (default: autodetect)\n"
		"-l\t--hijacklib   \tforce library for internal launch (default: autodetect)\n"
		"-d\t--database    \tsqlite database (default: arcandb.sqlite)\n"
		"-g\t--debug       \ttoggle LUA debug output (stacktraces, etc.)\n"
		"-r\t--scalemode   \tset texture mode (0,1,2)\n\t"
		"0(rectangle sized textures),\n\t"
		"1(scale to power of two)\n\t"
		"2(tweak texture coordinates)\n"
		"-1\t--stdout      \tforce stdout- output to filename\n"
		"-2\t--stderr      \tforce stderr- output to filename\n");
}

int main(int argc, char* argv[])
{
	bool windowed = false;
	bool fullscreen = false;
	bool conservative = false;
	bool luadebug = false;
	
	int scalemode = ARCAN_VIMAGE_SCALEPOW2;
	int width = 640;
	int height = 480;
	int ch;
	char* dbfname = "arcandb.sqlite";
	
/* start this here since some SDL builds have the nasty (albeit understandable) habit of 
 * redirecting STDIN / STDOUT, and we might want to do that ourselves */
	SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK);

	while ((ch = getopt_long(argc, argv, "w:h:?fmsp:t:o:l:d:1:2:gr:", longopts, NULL)) != -1){
		switch (ch) {
			case 'w' :
				width = strtol(optarg, NULL, 10);
				break;
			case 'h' :
				height = strtol(optarg, NULL, 10);
				break;
			case '?' :
				usage();
				exit(1);
				break;
			case 'm' :
				conservative = true;
				break;
			case 'f' :
				fullscreen = true;
				break;
			case 's' :
				windowed = true;
				break;
			case 'l' :
				arcan_libpath = strdup(optarg);
				break;
			case 'd' :
				dbfname = strdup(optarg);
				break;
			case 'g' :
				luadebug = true;
				break;
			case 'r' :
					scalemode = strtol(optarg, NULL, 10);
					if (scalemode < 0 || scalemode > 2){
						fprintf(stderr, "Warning: main(), -r, invalid scalemode. Ignoring.\n");
						scalemode = ARCAN_VIMAGE_SCALEPOW2;
					}
					
				break;
			case 'p' :
				arcan_resourcepath = strdup(optarg);
				break;
			case 't' :
				arcan_themepath = strdup(optarg);
				break;
			case 'o' :
				arcan_binpath = strdup(optarg);
			break;
			case '1' :
				freopen(optarg, "a", stdout);
			break;
			case '2' :
				freopen(optarg, "a", stderr);
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
		fprintf(stderr, "Fatal: main(), No theme found.\n");
		goto error;
	}

	char* dbname = arcan_find_resource(dbfname, ARCAN_RESOURCE_SHARED);

	dbhandle = arcan_db_open(dbname, arcan_themename);
	if (!dbhandle) {
		fprintf(stderr, "Fatal: main(), Creating database connection (%s)=>%s.\n", dbfname, dbname);
		goto error;
	}
	free(dbname);

	const SDL_VideoInfo* vi = SDL_GetVideoInfo();
	
	if (width == 0 || height == 0 || windowed) {
		width = vi->current_w;
		height = vi->current_h;
		putenv("SDL_VIDEO_WINDOW_POS=0,0");
	}
	
	fprintf(stderr, "Notice: [SDL] Video Info: %i, %i, hardware acceleration: %s, window manager: %s, scalemode: %i\n", 
			vi->current_w, vi->current_h, vi->hw_available ? "yes" : "no", vi->wm_available ? "yes" : "no", scalemode);
	
	if (windowed) {
		fullscreen = false;
		SDL_WM_GrabInput(SDL_GRAB_ON);
		putenv("SDL_VIDEO_WINDOW_POS=0,0");

		/* some kind of call is missing on OSX in order to put the priority above the menu-bar (and disable border/bar) */
	}

	/* grab video, (necessary) */
	if (arcan_video_init(width, height, 32, fullscreen, windowed, conservative) == ARCAN_OK) {
		errno = 0;
		/* grab audio, (possible to live without) */
		if (ARCAN_OK != arcan_audio_setup()){
			fprintf(stderr, "Warning: No audio devices could be found.\n");
		}

		/* setup device polling, cleanup, ... */
		arcan_event_init();
		arcan_led_init();

		/* export what we know and load theme */
		lua_State* luactx = lua_open();

		/* prevent some functions (particularly file-system related) from being loaded,
		 * not that the few "sandboxing"- options in LUA are particularly effective */
		const luaL_Reg *lib = lualibs;
		for (; lib->func; lib++) {
			lua_pushcfunction(luactx, lib->func);
			lua_pushstring(luactx, lib->name);
			lua_call(luactx, 1, 0);
		}
		
		arcan_lua_exposefuncs(luactx, luadebug);
		arcan_lua_pushglobalconsts(luactx);
		int err_func = 0;

		char* themescr = (char*) malloc(strlen(arcan_themename) + 5);
		sprintf(themescr, "%s.lua", arcan_themename);
		char* fn = arcan_find_resource(themescr, ARCAN_RESOURCE_THEME);

		if ( luaL_dofile(luactx, fn) == 1 ){
			const char* msg = lua_tostring(luactx, -1);
			fprintf(stderr, "Fatal: main(), Error loading theme script (%s) : (%s)\n", themescr, msg);
			goto error;
		}

		free(fn);
		free(themescr);

		/* entry point follows the name of the theme,
		 * hand over execution and begin event loop */
		arcan_lua_callvoidfun(luactx, arcan_themename);
		arcan_lua_callvoidfun(luactx, "on_show");

		bool done = false;
		while (!done) {
			arcan_event* ev;

			unsigned nticks;
			float frag = arcan_process(&nticks);

			if (nticks > 0){
				arcan_video_tick(nticks);
				arcan_audio_tick(nticks);
			}
			else
				arcan_video_refresh(frag);

	    /* note that an onslaught of I/O operations can currently
		 * saturate tick / video instead of evenly distribute between the two.
		 * since these can also propagate to LUA and user scripts, there 
		 * should really be a timing balance here (keep track of avg. time to dispatch
		 * event, figure out how many we can handle before we must push a logic- frame */
			while ((ev = arcan_event_poll())) {

				switch (ev->category) {
					case EVENT_IO:
					break;

					case EVENT_VIDEO:
					/* these events can typically be determined in video_tick(), 
					 * however there are so many hierarchical dependencies (linked objs, instances, ...)
					 * that a full delete is not safe there */
						if (ev->kind == EVENT_VIDEO_EXPIRE)
							arcan_video_deleteobject(ev->data.video.source);
						else if (ev->kind == EVENT_VIDEO_FRAMESERVER_TERMINATED)
							arcan_frameserver_check_frameserver(ev->data.video.data);
					break;
						

					case EVENT_AUDIO:
						if (ev->kind == EVENT_AUDIO_PLAYBACK_FINISHED)
							arcan_audio_stop(ev->data.audio.source);
						else if (ev->kind == EVENT_AUDIO_FRAMESERVER_TERMINATED)
							arcan_frameserver_check_frameserver(ev->data.audio.data);
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

				arcan_lua_pushevent(luactx, *ev);
			}
		}

		arcan_led_cleanup();
		arcan_video_shutdown();
	}
	else{
		fprintf(stderr, "Error; Couldn't initialize video system, try other windowing options (-f, -w, ...)\n");
	}
	error:
	SDL_Quit();
	exit(1);

	return 0;
}
