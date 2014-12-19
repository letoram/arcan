/*
 * Copyright 2003-2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <pthread.h>
#include <setjmp.h>

#include <string.h>
#include <signal.h>
#include <fcntl.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>

#ifndef _WIN32
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#endif

#include <math.h>
#include <limits.h>
#include <errno.h>
#include <time.h>
#include <ctype.h>

#include <sqlite3.h>

#include "getopt.h"
#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_audio.h"
#include "arcan_video.h"
#include "arcan_frameserver.h"
#include "arcan_lua.h"
#include "../platform/video_platform.h"

#ifdef ARCAN_LED
#include "arcan_led.h"
#endif

#include "arcan_db.h"
#include "arcan_videoint.h"

struct {
	bool in_monitor;
	int monitor, monitor_counter;
	int mon_infd;
	FILE* mon_outf;

	int timedump;

	struct arcan_luactx* lua;
	uint64_t tick_count;
} settings = {0};

bool stderr_redirected = false;
bool stdout_redirected = false;
struct arcan_dbh* dbhandle;

/*
 * The arcanmain recover state is used either at the volition of the
 * running script (see system_collapse) or in wrapping a failing pcall.
 * This allows a simpler recovery script to adopt orphaned frameservers.
 */
jmp_buf arcanmain_recover_state;

/*
 * default, probed / replaced on some systems
 */
extern int system_page_size;

static const struct option longopts[] = {
	{ "help",         no_argument,       NULL, '?'},
	{ "sync-strat",   required_argument, NULL, 'W'},
	{ "width",        required_argument, NULL, 'w'},
	{ "height",       required_argument, NULL, 'h'},
	{ "fullscreen",   no_argument,       NULL, 'f'},
	{ "windowed",     no_argument,       NULL, 's'},
	{ "debug",        no_argument,       NULL, 'g'},
	{ "binpath",      required_argument, NULL, 'B'},
	{ "rpath",        required_argument, NULL, 'p'},
	{ "applpath" ,    required_argument, NULL, 't'},
	{ "conservative", no_argument,       NULL, 'm'},
	{ "fallback",     required_argument, NULL, 'b'},
	{ "database",     required_argument, NULL, 'd'},
	{ "scalemode",    required_argument, NULL, 'r'},
	{ "timedump",     required_argument, NULL, 'q'},
	{ "nosound",      no_argument,       NULL, 'S'},
	{ "hook",         required_argument, NULL, 'H'},
	{ "stdout",       required_argument, NULL, '1'},
	{ "stderr",       required_argument, NULL, '2'},
	{ "monitor",      required_argument, NULL, 'M'},
	{ "monitor-out",  required_argument, NULL, 'O'},
	{ "monitor-in",   required_argument, NULL, 'I'},
	{ "version",      no_argument,       NULL, 'V'},
	{ NULL,           no_argument,       NULL,  0 }
};

static void usage()
{
printf("Usage: arcan [-whfmWMOqspBtHbdgaSV] applname "
	"[appl specific arguments]\n\n"
"-w\t--width       \tdesired initial canvas width (default: 640, auto: 0)\n"
"-h\t--height      \tdesired initial canvas height (default: 480, auto: 0)\n"
"-f\t--fullscreen  \ttoggle fullscreen mode ON (default: off)\n"
"-m\t--conservative\ttoggle conservative memory management (default: off)\n"
"-W\t--sync-strat  \tspecify video synchronization strategy (see below)\n"
#ifndef _WIN32
"-M\t--monitor     \tenable monitor session (arg: samplerate, ticks/sample)\n"
"-O\t--monitor-out \tLOG:fname or applname\n"
#endif
"-q\t--timedump    \twait n ticks, dump snapshot to resources/logs/timedump\n"
"-s\t--windowed    \ttoggle borderless window mode\n"
"-p\t--rpath       \tchange default searchpath for shared resources\n"
"-B\t--binpath     \tchange default searchpath for arcan_frameserver*\n"
"-t\t--applpath    \tchange default searchpath for applications\n"
"-H\t--hook        \trun a post-appl() script from (SHARED namespace)\n"
"-b\t--fallback    \tset a recovery/fallback application if appname crashes\n"
"-d\t--database    \tsqlite database (default: arcandb.sqlite)\n"
"-g\t--debug       \ttoggle debug output (events, coredumps, etc.)\n"
"-S\t--nosound     \tdisable audio output\n"
"-V\t--version     \tdisplay a version string then exit\n\n");

	const char** cur = platform_video_synchopts();
	printf("Video platform synchronization options (-W strat):\n");
	while(*cur){
		const char* a = *cur++;
		const char* b = *cur++;
		printf("\t%s - %s\n", a, b);
	}
	printf("\n");

	cur = platform_video_envopts();
	if (*cur){
	printf("Video platform environment variables:\n");
	while(*cur){
		const char* a = *cur++;
		const char* b = *cur++;
		printf("\t%s - %s\n", a, b);
	}
	printf("\n");
	}

	if (*cur){
	cur = agp_envopts();
	printf("AGP environment variables:\n");
	while(*cur){
		const char* a = *cur++;
		const char* b = *cur++;
		printf("\t%s - %s\n", a, b);
	}
	printf("\n");
	}

	cur = platform_input_envopts();
	printf("Input platform environment variables:\n");
	printf("\tARCAN_EVENT_RECORD=file - record input-layer events to file\n");
	printf("\tARCAN_EVENT_REPLAY=file - playback previous input recording\n");
	printf("\tARCAN_EVENT_SHUTDOWN=keysym:modifiers "
		"- press to inject shutdown event\n");
	if (*cur){
	while(*cur){
		const char* a = *cur++;
		const char* b = *cur++;
		printf("\t%s - %s\n", a, b);
	}
	printf("\n");
	}
}

bool switch_appl(const char* appname)
{
	arcan_video_shutdown();
	arcan_audio_shutdown();
	arcan_event_deinit(arcan_event_defaultctx());
	arcan_db_close(&dbhandle);

	const char* err_msg;
	if (!arcan_verifyload_appl(appname, &err_msg)){
		arcan_warning("(verifyload) in switch app "
			"failed, reason: %s\n", err_msg);
		return false;
	}

	return true;
}

/*
 * current several namespaces are (legacy) specified relative
 * to the old resources namespace, since those are expanded in
 * set_namespace_defaults where the command-line switch isn't
 * available, we have to generate these dependent namespaces
 * overrides as well.
 */
static void override_resspaces(const char* respath)
{
	size_t len = strlen(respath);
	if (len == 0 || !arcan_isdir(respath)){
		arcan_warning("-p argument ignored, invalid path specified.");
		return;
	}

	char debug_dir[ len + sizeof("/logs") ];
	char state_dir[ len + sizeof("/savestates") ];
	char font_dir[ len + sizeof("/fonts") ];

	snprintf(debug_dir, sizeof(debug_dir), "%s/logs", respath);
	snprintf(state_dir, sizeof(state_dir), "%s/savestates", respath);
	snprintf(font_dir, sizeof(font_dir), "%s/fonts", respath);

	arcan_override_namespace(respath, RESOURCE_APPL_SHARED);
	arcan_override_namespace(debug_dir, RESOURCE_SYS_DEBUG);
	arcan_override_namespace(state_dir, RESOURCE_APPL_STATE);
	arcan_override_namespace(font_dir, RESOURCE_SYS_FONT);
}

static void preframe()
{
	arcan_lua_callvoidfun(settings.lua, "preframe_pulse", false);
}

static void postframe()
{
	arcan_lua_callvoidfun(settings.lua, "postframe_pulse", false);
	arcan_bench_register_frame();
}

static void on_clock_pulse(int nticks)
{
/* priority is always in maintaining logical clock and event processing */
	unsigned njobs;

	arcan_video_tick(nticks, &njobs);
	arcan_audio_tick(nticks);

	if (settings.monitor && !settings.in_monitor){
		if (--settings.monitor_counter == 0){
			static int mc;
			char buf[8];
			snprintf(buf, 8, "%d", mc++);
			settings.monitor_counter = settings.monitor;
			arcan_lua_statesnap(settings.mon_outf, buf, true);
		}
	}

/* debugging functionality to generate a dump and abort after n ticks */
	if (settings.timedump){
		settings.timedump--;

	if (!settings.timedump)
		arcan_state_dump("timedump", "user requested a dump", __func__);
	}

#ifndef WIN32
		if (settings.in_monitor)
			arcan_lua_stategrab(settings.lua, "sample", settings.mon_infd);
#endif

	settings.tick_count += nticks;
}

int main(int argc, char* argv[])
{
	settings.in_monitor = getenv("ARCAN_MONITOR_FD") != NULL;

	bool windowed = false;
	bool fullscreen = false;
	bool conservative = false;
	bool nosound = false;

	unsigned char debuglevel = 0;

	int scalemode = ARCAN_VIMAGE_NOPOW2;
	int width = 640;
	int height = 480;

/* only used when monitor mode is activated, where we want some
 * of the global paths etc. accessible, but not *all* of them */
	char* monitor_arg = "LOG";

/*
 * if we crash in the Lua VM, switch to this app and have it
 * adopt our external connections
 */
	char* fallback = NULL;
	char* hookscript = NULL;
	char* dbfname = NULL;
	int ch;

	srand( time(0) );
/* VIDs all have a randomized base to provoke crashes in poorly written scripts,
 * only -g will make their base and sequence repeatable */

	while ((ch = getopt_long(argc, argv,
		"w:h:mx:y:fsW:d:Sq:a:p:b:B:M:O:t:H:g1:2:V", longopts, NULL)) >= 0){
	switch (ch) {
	case '?' :
		usage();
		exit(EXIT_SUCCESS);
	break;
	case 'w' : width = strtol(optarg, NULL, 10); break;
	case 'h' : height = strtol(optarg, NULL, 10); break;
	case 'm' : conservative = true; break;
	case 'f' : fullscreen = true; break;
	case 's' : windowed = true; break;
	case 'W' : platform_video_setsynch(optarg); break;
	case 'd' : dbfname = strdup(optarg); break;
	case 'S' : nosound = true; break;
	case 'q' : settings.timedump = strtol(optarg, NULL, 10); break;
	case 'p' : arcan_override_namespace(optarg, RESOURCE_APPL_SHARED); break;
	case 'b' : fallback = strdup(optarg); break;
	case 'V' : fprintf(stdout, "%s\n", ARCAN_BUILDVERSION);
		exit(EXIT_SUCCESS);
	break;
	case 'H' : hookscript = strdup( optarg ); break;
#ifndef _WIN32
	case 'M' : settings.monitor_counter = settings.monitor =
		abs( strtol(optarg, NULL, 10) ); break;
	case 'O' : monitor_arg = strdup( optarg ); break;
#endif
	case 't' :
		arcan_override_namespace(optarg, RESOURCE_SYS_APPLBASE);
		arcan_override_namespace(optarg, RESOURCE_SYS_APPLSTORE);
	break;
	case 'B' :
		arcan_override_namespace(optarg, RESOURCE_SYS_BINS);
	break;
	case 'g' :
		debuglevel++;
		srand(0xdeadbeef);
		break;
	break;
	case '1' :
		stdout_redirected = true;
		if (freopen(optarg, "a", stdout) == NULL);
		break;
	case '2' :
		stderr_redirected = true;
		if (freopen(optarg, "a", stderr) == NULL);
		break;

	default:
		break;
	}
	}

	if (optind >= argc){
		arcan_warning("Couldn't start, missing 'applname' argument. \n"
			"Consult the manpage (man arcan) for additional details\n");
		usage();
		exit(EXIT_SUCCESS);
	}

/* probe system, load environment variables, ... */
	arcan_set_namespace_defaults();

	const char* err_msg;
	if (!arcan_verifyload_appl(argv[optind], &err_msg)){
		arcan_warning("arcan_verifyload_appl(), "
			"failed to load (%s), reason: %s.",
			argv[optind], err_msg);

		if (fallback){
			arcan_warning("trying to load fallback application (%s)\n", fallback);
			if (!arcan_verifyload_appl(fallback, &err_msg)){
				arcan_warning("fallback application failed to load (%s), giving up.\n",
					err_msg);
				goto error;
			}
		}
		else
			goto error;
	}

	if (!arcan_verify_namespaces(false)){
		arcan_warning("namespace verification failed, status:\n");
		goto error;
	}

#ifndef _WIN32
/* pipe to file, socket or launch script based on monitor output,
 * format will be LUA tables with the exception of each cell ending with
 * #ENDSAMPLE . The block will be sampled, parsed and should return a table
 * pushed through the sample() function in the LUA space */
	if (settings.in_monitor){
		settings.mon_infd = strtol( getenv("ARCAN_MONITOR_FD"), NULL, 10);
	 	signal(SIGPIPE, SIG_IGN);
	}
	else if (settings.monitor > 0){
		extern arcan_benchdata benchdata;
		benchdata.bench_enabled = true;

		if (strncmp(monitor_arg, "LOG:", 4) == 0){
			settings.mon_outf = fopen(&monitor_arg[4], "w+");
			if (NULL == settings.mon_outf)
				arcan_fatal("couldn't open log output (%s) for writing\n",
					monitor_arg[4]);
			fcntl(fileno(settings.mon_outf), F_SETFD, FD_CLOEXEC);
		}
		else {
			int pair[2];

			pid_t p1;
			if (pipe(pair) == 0)
				;

			if ( (p1 = fork()) == 0){
				close(pair[1]);

/* double-fork to get away from parent */
				if (fork() != 0)
					exit(EXIT_SUCCESS);

/*
 * set the descriptor of the inherited pipe as an envvariable,
 * this will have the program be launched with in_monitor set to true
 * the monitor args will then be ignored and appname replaced with
 * the monitorarg
 */
				char monfd_buf[8] = {0};
				snprintf(monfd_buf, 8, "%d", pair[0]);
				setenv("ARCAN_MONITOR_FD", monfd_buf, 1);
				argv[optind] = strdup(monitor_arg);

				execv(argv[0], argv);
				exit(EXIT_FAILURE);
			}
			else {
/* don't terminate just because the pipe gets broken (i.e. dead monitor) */
				close(pair[0]);
				settings.mon_outf = fdopen(pair[1], "w");
			 	signal(SIGPIPE, SIG_IGN);
			}
		}

		fullscreen = false;
	}
#endif

/* also used as restart point for switching appls */
applswitch:

/*
 * try to open the specified database,
 * if that fails, warn, try to create an empty
 * database and if that fails, give up.
 */
	if (!dbfname)
		dbfname = arcan_expand_resource("arcandb.sqlite", RESOURCE_APPL_SHARED);

	dbhandle = arcan_db_open(dbfname, arcan_appl_id());

	if (!dbhandle) {
		arcan_warning("Couldn't open database (requested: %s),"
			"trying to create a new one.\n", dbfname);
		FILE* fpek = fopen(dbfname, "w+");

/* case of non-write:able dbpath */
		if (!fpek){
			arcan_mem_free(dbfname);
			dbfname = arcan_expand_resource("arcandb.sqlite", RESOURCE_APPL_TEMP);
			if (!dbfname)
				goto error;

			fpek = fopen(dbfname, "w+");
		}

		if (fpek){
			fclose(fpek);
			dbhandle = arcan_db_open(dbfname, arcan_appl_id());
		}

		if (!dbhandle){
			arcan_warning("Couldn't create database, giving up.\n");
			goto error;
		}
	}

	arcan_video_default_scalemode(scalemode);

	if (windowed)
		fullscreen = false;

/* grab video, (necessary) */
	if (arcan_video_init(width, height, 32, fullscreen, windowed,
		conservative, arcan_appl_id()) != ARCAN_OK){
		arcan_fatal("Error; Couldn't initialize video system,"
			"try other windowing options (-f, -w, ...)\n");
	}

/* defined in warning.c for arcan_fatal, we avoid the use of an
 * atexit() as this can be routed through abort() or similar
 * functions but some video platforms are extremely volatile
 * if we don't initiate a shutdown (egl-dri for one) */
	extern void(*arcan_fatal_hook)(void);
	arcan_fatal_hook = arcan_video_shutdown;

	errno = 0;
/* grab audio, (possible to live without) */
	if (ARCAN_OK != arcan_audio_setup(nosound))
		arcan_warning("Warning: No audio devices could be found.\n");

	arcan_math_init();

/* setup device polling, cleanup, ... */
	arcan_evctx* def = arcan_event_defaultctx();
	arcan_event_init( def );

#ifdef ARCAN_LED
	arcan_led_init();
#endif

/*
 * system integration note here, this could essentially provide
 * a side-channel into debugdata as the path can be expanded to
 * the debug directory, thus a compromised frameserver could possibly
 * leak crash-dumps etc. outside the sandbox. If this is a concern,
 * change this behavior or define a different logpath in the env.
 */
	if (getenv("ARCAN_FRAMESERVER_LOGDIR") == NULL){
		char* lpath = arcan_expand_resource("", RESOURCE_SYS_DEBUG);
		setenv("ARCAN_FRAMESERVER_LOGDIR", lpath, 1);
	}

	if (hookscript){
		char* tmphook = arcan_expand_resource(hookscript, RESOURCE_APPL_SHARED);
		free(hookscript);
		hookscript = NULL;

		if (tmphook){
			data_source src = arcan_open_resource(tmphook);
			if (src.fd != BADFD){
				map_region reg = arcan_map_resource(&src, false);

				if (reg.ptr){
					hookscript = strdup(reg.ptr);
					arcan_release_map(reg);
				}

				arcan_release_resource(&src);
			}

			free(tmphook);
		}
	}
#ifndef _WIN32
	system_page_size = sysconf(_SC_PAGE_SIZE);
#endif

/*
 * fallback implementation resides here and a little further down
 * in the "if adopt" block. Use verifyload to reconfigure application
 * namespace and scripts to run, then recoverexternal will cleanup
 * audio/video/event and invoke adopt() in the script
 */
	bool adopt = false, in_recover = false;
	int jumpcode = setjmp(arcanmain_recover_state);

	if (jumpcode == 1){
		arcan_db_close(&dbhandle);

		dbhandle = arcan_db_open(dbfname, arcan_appl_id());
		if (!dbhandle)
			goto error;

		adopt = true;
	}
	else if (jumpcode == 2){
		if (in_recover){
			arcan_warning("Double-Failure (main appl + adopt appl), giving up.\n");
			goto error;
		}

		if (!fallback){
			arcan_warning("Lua VM instance failed and no "
				"fallback defined, giving up.\n");
			goto error;
		}

		const char* errmsg;
		arcan_luaL_shutdown(settings.lua);
		if (!arcan_verifyload_appl(fallback, &errmsg)){
			arcan_warning("Lua VM error fallback, failure loading (%s), reason: %s\n",
				fallback, errmsg);
			goto error;
		}

		if (!arcan_verify_namespaces(true)){
			arcan_warning("namespace verification failed "
				" after loading (%s)\n", fallback);
			goto error;
		}

		in_recover = true;
		adopt = true;
	}

/* setup VM, map arguments and possible overrides */
	settings.lua = arcan_lua_alloc();
	arcan_lua_mapfunctions(settings.lua, debuglevel);

	bool inp_file;
	const char* inp = arcan_appl_basesource(&inp_file);
	if (!inp){
		arcan_warning("main(), No main script found for (%s)\n", arcan_appl_id());
		goto error;
	}

	char* msg = arcan_luaL_main(settings.lua, inp, inp_file);
	if (msg != NULL){
#ifdef ARCAN_LUA_NOCOLOR
		arcan_warning("\nParsing error in %s:\n%s\n", arcan_appl_id(), msg);
#else
		arcan_warning("\n\x1b[1mParsing error in (\x1b[33m%s\x1b[39m):\n"
			"\x1b[35m%s\x1b[22m\x1b[39m\n\n", arcan_appl_id(), msg);
#endif
		goto error;
	}
	free(msg);

/* entry point follows the name of the appl,
 * hand over execution and begin event loop */
	if (argc > optind)
		arcan_lua_pushargv(settings.lua, argv + optind + 1);

	if (!arcan_lua_callvoidfun(settings.lua, "", false))
		arcan_fatal("couldn't load appl, missing %s function\n", arcan_appl_id() ?
			arcan_appl_id() : "");

	if (hookscript)
		arcan_luaL_dostring(settings.lua, hookscript);

	if (adopt){
		int saved, truncated;
		arcan_video_recoverexternal(false, &saved, &truncated,
			arcan_luaL_adopt, settings.lua);
		arcan_warning("switching applications, %d adopted.\n", saved);
	}

	arcan_evctx* evctx = arcan_event_defaultctx();
	bool done = false;
	int exit_code = EXIT_SUCCESS;

	while (!done) {
/* pollfeed can actually populate event-loops, assuming we don't exceed a
 * compile- time threshold */
		arcan_video_pollfeed();
		arcan_audio_refresh();

		arcan_event ev;
		while (1 == arcan_event_poll(evctx, &ev)){
			switch (ev.category){
			case EVENT_VIDEO:
				if (ev.kind == EVENT_VIDEO_EXPIRE)
					arcan_video_deleteobject(ev.data.video.source);
			break;

/* this event category is never propagated to the scripting engine itself */
			case EVENT_SYSTEM:
				if (ev.kind == EVENT_SYSTEM_EXIT){
					exit_code = ev.data.system.errcode;
					done = true;
					goto out;
				}

/* slated for deprecation in favor of collapsing to .. */
				else if (ev.kind == EVENT_SYSTEM_SWITCHAPPL){
					arcan_luaL_shutdown(settings.lua);
					if (switch_appl(ev.data.system.data.message))
						goto applswitch;
					else
						goto error;
				}
				else
					continue;
			break;
			}

			arcan_lua_pushevent(settings.lua, &ev);
		}

		float frag = arcan_event_process(evctx, on_clock_pulse);
		platform_video_synch(settings.tick_count, frag, preframe, postframe);
	}

out:
	free(hookscript);
	arcan_lua_callvoidfun(settings.lua, "shutdown", false);
#ifdef ARCAN_LED
	arcan_led_shutdown();
#endif
	arcan_video_shutdown();
	arcan_event_deinit(arcan_event_defaultctx());

	return exit_code;

error:
	if (debuglevel > 1){
		arcan_warning("fatal: main loop failed, arguments: \n");
		for (size_t i = 0; i < argc; i++)
			arcan_warning("%s ", argv[i]);
		arcan_warning("\n\n");
	}

	arcan_video_shutdown();
	arcan_event_deinit(arcan_event_defaultctx());

/* for cases where we have a broken namespace, also dump
 * the current namespace state as that might help troubleshoot */
	arcan_verify_namespaces(true);

	return EXIT_FAILURE;
}
