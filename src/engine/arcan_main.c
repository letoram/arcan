/*
 * Copyright 2003-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <pthread.h>
#include <setjmp.h>

#include <string.h>
#include <signal.h>
#include <fcntl.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>

#include <sys/resource.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>

#include <math.h>
#include <limits.h>
#include <errno.h>
#include <time.h>
#include <ctype.h>

#include <sqlite3.h>

#include "getopt.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_audio.h"
#include "arcan_video.h"
#include "arcan_img.h"
#include "arcan_frameserver.h"
#include "arcan_lua.h"
#include "../platform/video_platform.h"
#include "arcan_led.h"
#include "arcan_db.h"
#include "arcan_videoint.h"
#include "arcan_conductor.h"

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
struct arcan_luactx* main_lua_context;

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
#ifdef ARCAN_LWA
	{ "pipe-stdout",  no_argument,       NULL, '1'},
#endif
	{ "pipe-stdin",   no_argument,       NULL, '0'},
	{ "monitor",      required_argument, NULL, 'M'},
	{ "monitor-out",  required_argument, NULL, 'O'},
	{ "version",      no_argument,       NULL, 'V'},
	{ NULL,           no_argument,       NULL,  0 }
};

static void vplatform_usage()
{
	const char** cur = platform_video_envopts();
	if (*cur){
	printf("Video platform configuration options:\n");
	printf("(use ARCAN_VIDEO_XXX=val for env, or "
		"arcan_db add_appl_kv arcan video_xxx for db)\n");
	while(1){
		const char* a = *cur++;
		if (!a) break;
		const char* b = *cur++;
		if (!b) break;
		printf("\t%s - %s\n", a, b);
	}
	printf("\n");
	}

	cur = agp_envopts();
	printf("Graphics platform configuration options:\n");
	printf("(use ARCAN_GRAPHICS_XXX=val for env, graphics_xxx=val for db)\n");
	if (*cur){
	while(1){
		const char* a = *cur++;
		if (!a) break;
		const char* b = *cur++;
		if (!b) break;
		printf("\t%s - %s\n", a, b);
	}
	}
	printf("\n");
}

static void usage()
{
printf("Usage: arcan [-whfmWMOqspTBtHbdgaSV] applname "
	"[appl specific arguments]\n\n"
"-w\t--width       \tdesired initial canvas width (auto: 0)\n"
"-h\t--height      \tdesired initial canvas height (auto: 0)\n"
"-f\t--fullscreen  \ttoggle fullscreen mode ON (default: off)\n"
"-m\t--conservative\ttoggle conservative memory management (default: off)\n"
"-W\t--sync-strat  \tspecify video synchronization strategy (see below)\n"
"-M\t--monitor     \tenable monitor session (arg: samplerate, ticks/sample)\n"
"-O\t--monitor-out \tLOG:fname or applname\n"
"-q\t--timedump    \twait n ticks, dump snapshot to resources/logs/timedump\n"
"-s\t--windowed    \ttoggle borderless window mode\n"
#ifdef DISABLE_FRAMESERVERS
"-B\t--binpath     \tno-op, frameserver support was disabled compile-time\n"
#else
"-B\t--binpath     \tchange default searchpath for arcan_frameserver/afsrv*\n"
#endif
#ifdef ARCAN_LWA
"-1\t--pipe-stdout \t(for pipe-mode) negotiate an initial connection\n"
#endif
"-0\t--pipe-stdin  \t(for pipe-mode) accept requests for an initial connection\n"
"-p\t--rpath       \tchange default searchpath for shared resources\n"
"-t\t--applpath    \tchange default searchpath for applications\n"
"-T\t--scriptpath  \tchange default searchpath for builtin (system) scripts\n"
"-H\t--hook        \trun a post-appl() script from (SHARED namespace)\n"
"-b\t--fallback    \tset a recovery/fallback application if appname crashes\n"
"-d\t--database    \tsqlite database (default: arcandb.sqlite)\n"
"-g\t--debug       \ttoggle debug output (events, coredumps, etc.)\n"
"-S\t--nosound     \tdisable audio output\n"
"-V\t--version     \tdisplay a version string then exit\n\n");

	const char** cur = platform_video_synchopts();
	if (*cur){
	printf("Video platform synchronization options (-W strat):\n");
	while(1){
		const char* a = *cur++;
		if (!a) break;
		const char* b = *cur++;
		if (!b) break;
		printf("\t%s - %s\n", a, b);
	}
	printf("\n");
	}

	vplatform_usage();

/* built-in envopts for _event.c, should really be moved there */
	printf("Input platform configuration options:\n");
	printf("(use ARCAN_EVENT_XXX for env, event_xxx for db)\n");
	printf("\trecord=file - record input-layer events to file\n");
	printf("\treplay=file - playback previous input recording\n");
	printf("\tshutdown=keysym:modifiers - press to inject shutdown event\n");
	cur = platform_input_envopts();
	if (*cur){
	while(1){
		const char* a = *cur++;
		if (!a) break;
		const char* b = *cur++;
		if (!b) break;
		printf("\t%s - %s\n", a, b);
	}
	printf("\n");
	}
}

/*
 * current several namespaces are (legacy) specified relative to the old
 * resources namespace, since those are expanded in set_namespace_defaults
 * where the command-line switch isn't available, we have to generate these
 * dependent namespaces overrides as well.
 */
static void override_resspaces(const char* respath)
{
	size_t len = strlen(respath);
	if (len == 0 || !arcan_isdir(respath)){
		arcan_warning("-p argument ignored, invalid path specified.\n");
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

 void appl_user_warning(const char* name, const char* err_msg)
{
	arcan_warning("\x1b[1mCouldn't load application (\x1b[33m%s\x1b[39m)\n",
		name, err_msg);

	if (!name || !strlen(name))
		arcan_warning("\x1b[1m\tthe appl-name argument is empty\x1b[22m\n");
	else {
		if (name[0] == '.')
			arcan_warning("\x1b[32m\ttried to load "
	"relative to current directory\x1b[22m\x1b[39m\n");
		else if (name[0] == '/')
			arcan_warning("\x1b[32m\ttried to load "
	"from absolute path. \x1b[39m\x1b[22m\n");
		else{
			char* space = arcan_expand_resource("", RESOURCE_SYS_APPLBASE);
			arcan_warning("\x1b[32m\ttried to load "
	"appl relative to base: \x1b[33m %s\x1b[22m\x1b[39m\n", space);
		}
	}
}

static void fatal_shutdown()
{
	arcan_audio_shutdown();
	arcan_video_shutdown(false);
}

/* invoked from the conductor when it has processed a monotonic tick */
static struct {
	bool in_monitor;
	int monitor, monitor_counter;
	int mon_infd;
	FILE* mon_outf;
	int timedump;
} settings = {0};

static void main_cycle()
{
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

	if (settings.in_monitor)
		arcan_lua_stategrab(main_lua_context, "sample", settings.mon_infd);
}

/*
 * needed to be able to shift entry points on a per- target basis in cmake
 * (lwa/normal/sdl and other combinations all mess around with main as an entry
 * point
 */
#ifndef MAIN_REDIR
#define MAIN_REDIR main
#endif

int MAIN_REDIR(int argc, char* argv[])
{
/*
 * these are, in contrast to normal video_init/event_init, only set once
 * and not rerun on appl- switch etc. typically no-ops but may be used to
 * setup priv- sep style scenarios at a point where fork()/suid() shouldn't
 * be much of an issue
 */
	platform_device_init();
	platform_video_preinit();
	platform_event_preinit();

/*
 * Protect against launching the arcan instance from an environment where
 * there already is indication of a connection destination.
 */
#ifndef ARCAN_LWA
	if (getenv("ARCAN_CONNPATH")){
		if (fork() == 0){
			execvp("arcan_lwa", argv);
		}
		exit(EXIT_SUCCESS);
	}
#endif

	arcan_log_destination(stderr, 0);

	settings.in_monitor = getenv("ARCAN_MONITOR_FD") != NULL;
	bool windowed = false;
	bool fullscreen = false;
	bool conservative = false;
	bool nosound = false;
	bool stdin_connpoint = false;

	unsigned char debuglevel = 0;

	int scalemode = ARCAN_VIMAGE_NOPOW2;
	int width = -1;
	int height = -1;

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

	while ((ch = getopt_long(argc, argv,
		"w:h:mx:y:fsW:d:Sq:a:p:b:B:M:O:t:T:H:g01V", longopts, NULL)) >= 0){
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
#ifdef ARCAN_LWA
/* send the connection point we will try to connect through, and update the
 * env that SHMIF_ uses to get the behavior of connection looping */
	case '1' :{
		char cbuf[PP_SHMPAGE_SHMKEYLIM+1];
		snprintf(cbuf, sizeof(cbuf), "apipe%d", (int) getpid());
		setenv("ARCAN_CONNFL", "16", 1); /* SHMIF_CONNECT_LOOP */
		setenv("ARCAN_CONNPATH", strdup(cbuf), 1);
		puts(cbuf);
		fflush(stdout);
		arcan_warning("requesting pipe-connection via %s\n", cbuf);
	}
	break;
#endif

#ifndef ARCAN_BUILDVERSION
#define ARCAN_BUILDVERSION "build-less"
#endif

/* a prealloc:ed connection primitive is needed, defer this to when we have
 * enough resources and context allocated to be able to do so. This does not
 * survive appl-switching */
	case '0' : stdin_connpoint = true; break;
	case 'q' : settings.timedump = strtol(optarg, NULL, 10); break;
	case 'p' : override_resspaces(optarg); break;
	case 'T' : arcan_override_namespace(optarg, RESOURCE_SYS_SCRIPTS); break;
	case 'b' : fallback = strdup(optarg); break;
	case 'V' : fprintf(stdout, "%s\nshmif-%" PRIu64"\nluaapi-%d:%d\n",
		ARCAN_BUILDVERSION, arcan_shmif_cookie(), LUAAPI_VERSION_MAJOR,
		LUAAPI_VERSION_MINOR
		);
		exit(EXIT_SUCCESS);
	break;
	case 'H' : hookscript = strdup( optarg ); break;
	case 'M' : settings.monitor_counter = settings.monitor =
		abs( (int)strtol(optarg, NULL, 10) ); break;
	case 'O' : monitor_arg = strdup( optarg ); break;
	case 't' :
		arcan_override_namespace(optarg, RESOURCE_SYS_APPLBASE);
		arcan_override_namespace(optarg, RESOURCE_SYS_APPLSTORE);
	break;
	case 'B' :
		arcan_override_namespace(optarg, RESOURCE_SYS_BINS);
	break;
	case 'g' :
		debuglevel++;
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
	arcan_ffunc_initlut();
#ifdef DISABLE_FRAMESERVERS
	arcan_override_namespace("", RESOURCE_SYS_BINS);
#endif

	const char* err_msg;

	if (!arcan_verifyload_appl(argv[optind], &err_msg)){
		appl_user_warning(argv[optind], err_msg);

		if (fallback && strcmp(fallback, ":self") != 0){
			arcan_warning("trying to load fallback appl (%s)\n", fallback);
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
		arcan_warning("\x1b[32mCouldn't verify filesystem namespaces.\x1b[39m\n");
/* with debuglevel, we have separate reporting. */
		if (!debuglevel){
			arcan_warning("\x1b[33mLook through the following list and note the "
				"entries marked broken, \nCheck the manpage for config and environment "
				"variables, or try the arguments: \n"
				"\t <system-scripts> : -T path/to/arcan/data/scripts\n"
				"\t <application-shared> : -p any/valid/user/path\n"
				"\x1b[39m\n"
			);
			arcan_verify_namespaces(true);
		}
		goto error;
	}

	if (debuglevel > 1)
		arcan_verify_namespaces(true);

/* pipe to file, socket or launch script based on monitor output,
 * format will be LUA tables with the exception of each cell ending with
 * #ENDSAMPLE . The block will be sampled, parsed and should return a table
 * pushed through the sample() function in the LUA space */
	if (settings.in_monitor){
		settings.mon_infd = strtol( getenv("ARCAN_MONITOR_FD"), NULL, 10);
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
			}
		}

		fullscreen = false;
	}

/* two main sources for sigpipe, one being monitor and the other being
 * lua- layer open_nonblock calls, neither has any use for it so mask */
	sigaction(SIGPIPE, &(struct sigaction){
		.sa_handler = SIG_IGN, .sa_flags = 0}, 0);

	struct arcan_dbh* dbhandle = NULL;
/* fallback to whatever is the platform database- storepath */
	if (dbfname || (dbfname = platform_dbstore_path()))
		dbhandle = arcan_db_open(dbfname, arcan_appl_id());

	if (!dbhandle){
		arcan_warning("Couldn't open/create database (%s), "
			"fallback to :memory:\n", dbfname);
		dbhandle = arcan_db_open(":memory:", arcan_appl_id());
	}

	if (!dbhandle){
		arcan_warning("In memory db fallback failed, giving up\n");
		goto error;
	}
	arcan_db_set_shared(dbhandle);
	const char* target_appl = NULL;
	dbhandle = arcan_db_get_shared(&target_appl);

/* either use previous explicit dimensions (if found and cached)
 * or revert to platform default or store last */
	if (-1 == width){
		char* dbw = arcan_db_appl_val(dbhandle, target_appl, "width");
		if (dbw){
			width = (uint16_t) strtoul(dbw, NULL, 10);
			arcan_mem_free(dbw);
		}
		else
			width = 0;
	}
	else{
		char buf[6] = {0};
		snprintf(buf, sizeof(buf), "%d", width);
		arcan_db_appl_kv(dbhandle, target_appl, "width", buf);
	}

	if (-1 == height){
		char* dbh = arcan_db_appl_val(dbhandle, target_appl, "height");
		if (dbh){
			height = (uint16_t) strtoul(dbh, NULL, 10);
			arcan_mem_free(dbh);
		}
		else
			height = 0;
	}
	else{
		char buf[6] = {0};
		snprintf(buf, sizeof(buf), "%d", height);
		arcan_db_appl_kv(dbhandle, target_appl, "height", buf);
	}

	arcan_video_default_scalemode(scalemode);

	if (windowed)
		fullscreen = false;

/* grab video, (necessary) */
	if (arcan_video_init(width, height, 32, fullscreen, windowed,
		conservative, arcan_appl_id()) != ARCAN_OK){
		printf("Error: couldn't initialize video subsystem. Check permissions, "
			" try other video platform options (-f, -w, -h)\n");
		vplatform_usage();
		arcan_fatal("Video platform initialization failed\n");
	}

/* defined in warning.c for arcan_fatal, we avoid the use of an atexit() as
 * this can be routed through abort() or similar functions but some video
 * platforms are extremely volatile if we don't initiate a shutdown (egl-dri
 * for one) */
	extern void(*arcan_fatal_hook)(void);
	arcan_fatal_hook = fatal_shutdown;

	errno = 0;
/* grab audio, (possible to live without) */
	if (ARCAN_OK != arcan_audio_setup(nosound))
		arcan_warning("Warning: No audio devices could be found.\n");

	arcan_math_init();
	arcan_img_init();

/* setup device polling, cleanup, ... */
	arcan_evctx* evctx = arcan_event_defaultctx();
	arcan_led_init();
	arcan_event_init(evctx);

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
	system_page_size = sysconf(_SC_PAGE_SIZE);

/*
 * fallback implementation resides here and a little further down
 * in the "if adopt" block. Use verifyload to reconfigure application
 * namespace and scripts to run, then recoverexternal will cleanup
 * audio/video/event and invoke adopt() in the script
 */
	bool adopt = false, in_recover = false;
	int jumpcode = setjmp(arcanmain_recover_state);
	int saved, truncated;

	if (jumpcode == 1 || jumpcode == 2){
		arcan_db_close(&dbhandle);
		arcan_db_set_shared(NULL);

		dbhandle = arcan_db_open(dbfname, arcan_appl_id());
		if (!dbhandle)
			goto error;

		arcan_db_set_shared(dbhandle);
		arcan_lua_cbdrop();
		arcan_lua_shutdown(main_lua_context);

		arcan_event_maskall(evctx);

/* switch and adopt or just switch */
		if (jumpcode == 2){
			int lastctxc = arcan_video_popcontext();
			int lastctxa;
			while( lastctxc != (lastctxa = arcan_video_popcontext()) )
				lastctxc = lastctxa;
		}
		else{
			arcan_video_recoverexternal(true, &saved, &truncated, NULL, NULL);
			adopt = true;
		}
		arcan_event_clearmask(evctx);
	}
/* fallback recovery with adoption */
	else if (jumpcode == 3){
		if (in_recover){
			arcan_warning("Double-Failure (main appl + adopt appl), giving up.\n");
			close(STDERR_FILENO);
			goto error;
		}

		if (!fallback){
			arcan_warning("Lua VM failed with no fallback defined, (see -b arg).\n");
			close(STDERR_FILENO);
			goto error;
		}

		arcan_event_maskall(evctx);
		arcan_video_recoverexternal(true, &saved, &truncated, NULL, NULL);
		arcan_event_clearmask(evctx);
		platform_video_recovery();

		const char* errmsg;
		arcan_lua_cbdrop();
		arcan_lua_shutdown(main_lua_context);
		if (strcmp(fallback, ":self") == 0)
			fallback = argv[optind];

		if (!arcan_verifyload_appl(fallback, &errmsg)){
			arcan_warning("Lua VM error fallback, failure loading (%s), reason: %s\n",
				fallback, errmsg);
			goto error;
		}

		if (!arcan_verify_namespaces(false))
			goto error;

/* to track if we get a crash in the fallback application and not get stuck
 * in an endless loop */
		in_recover = true;
		adopt = true;
	}

/* setup VM, map arguments and possible overrides */
	main_lua_context = arcan_lua_alloc();
	arcan_lua_mapfunctions(main_lua_context, debuglevel);

	bool inp_file;
	const char* inp = arcan_appl_basesource(&inp_file);
	if (!inp){
		arcan_warning("main(), No main script found for (%s)\n", arcan_appl_id());
		goto error;
	}

	char* msg = arcan_lua_main(main_lua_context, inp, inp_file);
	if (msg != NULL){
		arcan_warning("\n\x1b[1mParsing error in (\x1b[33m%s\x1b[39m):\n"
			"\x1b[35m%s\x1b[22m\x1b[39m\n\n", arcan_appl_id(), msg);
		goto error;
	}
	free(msg);

	if (!arcan_lua_callvoidfun(main_lua_context, "", false, (const char**)
		(argc > optind ? (argv + optind + 1) : NULL)))
		arcan_fatal("couldn't load appl, missing %s function\n", arcan_appl_id() ?
		arcan_appl_id() : "");

	if (hookscript)
		arcan_lua_dostring(main_lua_context, hookscript);

	if (adopt){
		arcan_lua_setglobalint(main_lua_context, "CLOCK", evctx->c_ticks);
		arcan_lua_adopt(main_lua_context);

/* re-issue video recovery here as adopt CLEARS THE EVENTQUEUE, this is quite a
 * complex pattern as the work in selectively recovering the event-queue after
 * an error is much too dangerous */
		platform_video_recovery();
		in_recover = false;
	}
	else if (stdin_connpoint){
		char cbuf[PP_SHMPAGE_SHMKEYLIM+1];
/* read desired connection point from stdin, strip trailing \n */
		if (fgets(cbuf, sizeof(cbuf), stdin)){
			size_t len = strlen(cbuf);
			cbuf[len-1] = '\0';
			for (const char* c = cbuf; *c; c++)
				if (!isalnum(*c)){
					arcan_warning("-1, %s failed (only [a->Z0-9] accepted)\n", cbuf);
					goto error;
				}
			if (!arcan_lua_launch_cp(main_lua_context, cbuf, NULL)){
				arcan_fatal("-1, couldn't setup connection point (%s)\n", cbuf);
				goto error;
			}
		}
		else{
			arcan_warning("-1, couldn't read a valid connection point from stdin\n");
			goto error;
		}
	}

	bool done = false;
	int exit_code = arcan_conductor_run(main_cycle);

	free(hookscript);
	arcan_lua_callvoidfun(main_lua_context, "shutdown", false, NULL);

	arcan_led_shutdown();
	arcan_event_deinit(evctx);
	arcan_audio_shutdown();
	arcan_video_shutdown(exit_code != 256);
	arcan_mem_free(dbfname);
	if (dbhandle){
		arcan_db_close(&dbhandle);
		arcan_db_set_shared(NULL);
	}

	return exit_code == 256 ? EXIT_SUCCESS : exit_code;

error:
	if (debuglevel > 1){
		arcan_warning("fatal: main loop failed, arguments: \n");
		for (size_t i = 0; i < argc; i++)
			arcan_warning("%s ", argv[i]);
		arcan_warning("\n\n");

		arcan_verify_namespaces(true);
	}

	arcan_event_deinit(evctx);
	arcan_mem_free(dbfname);
	arcan_audio_shutdown();
	arcan_video_shutdown(false);

	return EXIT_FAILURE;
}
