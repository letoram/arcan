/*
 * Copyright: Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include "arcan_hmeta.h"

/*
 * list of scripts to inject
 */
static struct arcan_strarr arr_hooks = {0};

/*
 * The arcanmain recover state is used either at the volition of the
 * running script (see system_collapse) or in wrapping a failing pcall.
 * This allows a simpler recovery script to adopt orphaned frameservers.
 */
jmp_buf arcanmain_recover_state;
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
	{ "libpath",      required_argument, NULL, 'L'},
	{ "rpath",        required_argument, NULL, 'p'},
	{ "applpath" ,    required_argument, NULL, 't'},
	{ "conservative", no_argument,       NULL, 'm'},
	{ "fallback",     required_argument, NULL, 'b'},
	{ "database",     required_argument, NULL, 'd'},
	{ "scalemode",    required_argument, NULL, 'r'},
	{ "nosound",      no_argument,       NULL, 'S'},
	{ "hook",         required_argument, NULL, 'H'},
#ifdef ARCAN_LWA
	{ "pipe-stdout",  no_argument,       NULL, '1'},
#endif
	{ "pipe-stdin",   no_argument,       NULL, '0'},
	{ "monitor",      required_argument, NULL, 'M'},
	{ "monitor-out",  required_argument, NULL, 'O'},
	{ "monitor-ctrl", no_argument,       NULL, 'C'},
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
	printf("\tignore_dirty - always update regardless of 'dirty' state\n");
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
"-M\t--monitor     \tenable monitor session (arg: [ticks/sample], -1 debug only)\n"
"-O\t--monitor-out \tLOG:fname or LOGFD:num\n"
"-C\t--monitor-ctrl\tuse STDIN as control interface (with SIGUSR1)\n"
"-s\t--windowed    \ttoggle borderless window mode\n"
#ifdef DISABLE_FRAMESERVERS
"-B\t--binpath     \tno-op, frameserver support was disabled compile-time\n"
#else
"-B\t--binpath     \tchange default searchpath for arcan_frameserver/afsrv*\n"
#endif
"-L\t--libpath     \tchange library search patch\n"
#ifdef ARCAN_LWA
"-1\t--pipe-stdout \t(for pipe-mode) negotiate an initial connection\n"
#endif
"-0\t--pipe-stdin  \t(for pipe-mode) accept requests for an initial connection\n"
"-p\t--rpath       \tchange default searchpath for shared resources\n"
"-t\t--applpath    \tchange default searchpath for applications\n"
"-T\t--scriptpath  \tchange default searchpath for builtin (system) scripts\n"
"-H\t--hook        \trun a post-appl() script (shared/sys-script namespaces)\n"
"-b\t--fallback    \tset a recovery/fallback application if appname crashes\n"
"-d\t--database    \tsqlite database (default: arcandb.sqlite)\n"
"-g\t--debug       \ttoggle debug output (events, coredumps, etc.)\n"
"-S\t--nosound     \tdisable audio output\n"
"-V\t--version     \tdisplay a version string then exit\n\n");

	const char** cur = arcan_conductor_synchopts();
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
	cur = platform_event_envopts();
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
	arcan_warning("\x1b[1mCouldn't load application \x1b[33m(%s): \x1b[31m%s\x1b[39m\n",
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

static void add_hookscript(const char* instr)
{
/* convert to filesystem path */
	char* expand = arcan_expand_resource(instr, RESOURCE_SYS_SCRIPTS);

	if (!expand){
		arcan_warning("-H, couldn't expand hook-script: %s\n", instr ? instr : "");
		return;
	}

/* open for reading */
	data_source src = arcan_open_resource(expand);
	if (src.fd == BADFD){
		arcan_warning("-H, couldn't open hook-script: %s\n", expand);
		free(expand);
		return;
	}

/* get a memory mapping */
	map_region reg = arcan_map_resource(&src, false);
	if (!reg.ptr){
		arcan_release_resource(&src);
		return;
	}

/* and copy the final script into the array */
	if (arr_hooks.count + 1 >= arr_hooks.limit)
		arcan_mem_growarr(&arr_hooks);

/* to "reuse" the string, take the ugly approach of string-in-string,
 * alloc_mem is fatal unless explicitly set NONFATAL */
	size_t dlen = strlen(reg.ptr);
	size_t blen = strlen(instr);
	char* comp = arcan_alloc_mem(dlen + blen + 2,
		ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	memcpy(comp, instr, blen);
	memcpy(&comp[blen+1], reg.ptr, dlen);

	arr_hooks.data[arr_hooks.count++] = comp;

	arcan_release_map(reg);
	arcan_release_resource(&src);
}

/*
 * Needed to be able to shift entry points on a per- target basis in cmake
 * (lwa/normal/sdl and other combinations all mess around with main as an
 * entry point.
 *
 * This really needs a severe refactor to distinguish between the phases:
 * 1. argument parsing => state block
 * 2. engine-main init
 * 3. longjmp based recovery stages and partial engine re-init
 */
#ifndef MAIN_REDIR
#define MAIN_REDIR main
#endif

int MAIN_REDIR(int argc, char* argv[])
{
/* needed first as device_init might fork and need some shared mem */
	system_page_size = sysconf(_SC_PAGE_SIZE);
	arcan_conductor_enable_watchdog();

/*
 * these are, in contrast to normal video_init/event_init, only set once
 * and not rerun on appl- switch etc. typically no-ops but may be used to
 * setup priv- sep style scenarios at a point where fork()/suid() shouldn't
 * be much of an issue
 */
	platform_device_init();
	platform_video_preinit();
	platform_audio_preinit();
	platform_event_preinit();
	arcan_log_destination(stderr, 0);

/*
 * Protect against launching the main arcan instance from an environment where
 * there already is indication of a connection destination. This is not
 * entirely sufficient for wayland either as that implementation has a default
 * display that it tries to open if no env was set - but fringe enough to not
 * bother with.
 */
#if defined(ARCAN_EGL_DRI) && !defined(ARCAN_LWA)
	if ((getenv("DISPLAY") || getenv("WAYLAND_DISPLAY"))){
		arcan_warning("%s running, switching to "
			"arcan_sdl\n", getenv("DISPLAY") ? "Xorg" : "Wayland");
		execvp("arcan_sdl", argv);
		arcan_warning("exec arcan_sdl failed, error code: %d\n", errno);
#if defined(ARCAN_HYBRID_SDL)
		arcan_warning("check that your build was made with -DHYBRID_SDL=ON\n");
#endif
		exit(EXIT_FAILURE);
	}
#endif

#if !defined(ARCAN_LWA) && !defined(ARCAN_HEADLESS)
	if (getenv("ARCAN_CONNPATH")){
		execvp("arcan_lwa", argv);
		exit(EXIT_FAILURE);
	}
#endif

	arcan_mem_growarr(&arr_hooks);

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
	int monitor_rate = 0;
	char* monitor_arg = NULL;
	FILE* monitor_ctrl = NULL;

/*
 * if we crash in the Lua VM, switch to this app and have it
 * adopt our external connections
 */
	char* fallback = NULL;
	char* dbfname = NULL;
	int ch;

/* initialize conductor by setting the default profile, we need to
 * do this early as it affects buffer management and so on */
	arcan_conductor_setsynch("vsynch");

/*
 * accumulation string-list for filenames provided via -H, can't
 * add them to the hookscripts array immediately as the namespaces
 * has not been resolved yet
 */
	struct arcan_strarr tmplist = {0};

	while ((ch = getopt_long(argc, argv,
		"w:h:mx:y:fsW:d:Sq:a:p:b:B:L:M:O:Ct:T:H:g01V", longopts, NULL)) >= 0){
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
	case 'W' : arcan_conductor_setsynch(optarg); break;
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
	case '0' :
		if (monitor_ctrl){
			arcan_fatal("argument misuse, cannot combing -0 with -C");
		}
		stdin_connpoint = true;
	break;
	case 'p' : override_resspaces(optarg); break;
	case 'T' : arcan_override_namespace(optarg, RESOURCE_SYS_SCRIPTS); break;
	case 'b' : fallback = strdup(optarg); break;
	case 'V' :
		fprintf(stdout, "%s\nshmif-%" PRIu64"\nluaapi-%d:%d\n",
			ARCAN_BUILDVERSION, arcan_shmif_cookie(), LUAAPI_VERSION_MAJOR,
			LUAAPI_VERSION_MINOR
		);
		exit(EXIT_SUCCESS);
	break;
	case 'H' :
		if (tmplist.count + 1 >= tmplist.limit)
			arcan_mem_growarr(&tmplist);
		tmplist.data[tmplist.count++] = strdup(optarg);
	break;
	case 'M' :
		monitor_rate = (int)strtol(optarg, NULL, 10);
	break;
	case 'O' :
		monitor_arg = strdup( optarg );
	break;
	case 'C' :
		if (stdin_connpoint){
			arcan_fatal("argument misuse, cannot combine -C with -O");
		}
		monitor_ctrl = stdin;
	break;
	case 't' :
		arcan_override_namespace(optarg, RESOURCE_SYS_APPLBASE);
		arcan_override_namespace(optarg, RESOURCE_SYS_APPLSTORE);
	break;
	case 'B' :
		arcan_override_namespace(optarg, RESOURCE_SYS_BINS);
	break;
	case 'L' :
		arcan_override_namespace(optarg, RESOURCE_SYS_LIBS);
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

/* namespaces are resolved, time to figure out the hookscripts */
	if (tmplist.count){
		for (size_t i = 0; i < tmplist.count; i++){
			if (tmplist.data[i])
				add_hookscript(tmplist.data[i]);
		}
		arcan_mem_freearr(&tmplist);
	}

/* external cooperation - check arcan_monitor.c */
	if (monitor_rate || monitor_ctrl)
		arcan_monitor_configure(monitor_rate, monitor_arg, monitor_ctrl);

/* two main sources for sigpipe, one being monitor and the other being
 * lua- layer open_nonblock calls, neither has any use for it so mask */
	sigaction(SIGPIPE,&(struct sigaction){.sa_handler = SIG_IGN}, 0);

	struct arcan_dbh* dbhandle = NULL;
/* fallback to whatever is the platform database- storepath */
	if (dbfname || (dbfname = platform_dbstore_path()))
		dbhandle = arcan_db_open(dbfname, arcan_appl_id());

	if (!dbhandle){
		arcan_warning(
			"Couldn't open/create database (%s), fallback to :memory:\n", dbfname);
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
	arcan_evctx* evctx = arcan_event_defaultctx();
	arcan_event_init(evctx);

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
	arcan_led_init();

/*
 * fallback implementation resides here and a little further down in the "if
 * adopt" block. Use verifyload to reconfigure application namespace and
 * scripts to run, then recoverexternal will cleanup audio/video/event and
 * invoke adopt() in the script
 */
	bool adopt = false, in_recover = false;

	int jumpcode = setjmp(arcanmain_recover_state);
	int saved, truncated;

	if (jumpcode == ARCAN_LUA_SWITCH_APPL ||
			jumpcode == ARCAN_LUA_SWITCH_APPL_NOADOPT){

/* close down the database and reinitialize with the name of the new appl */
		arcan_db_close(&dbhandle);
		arcan_db_set_shared(NULL);
		arcan_conductor_reset_count(true);

		dbhandle = arcan_db_open(dbfname, arcan_appl_id());
		if (!dbhandle)
			goto error;

		arcan_db_set_shared(dbhandle);
		arcan_lua_cbdrop();
		arcan_lua_shutdown(main_lua_context);

		const char trace_msg[] = "Switching appls, resetting trace";
		arcan_trace_log(trace_msg, sizeof(trace_msg));
		arcan_trace_close();

/* mask off errors so shutdowns etc. won't queue new events that enter
 * the event queue and gets exposed to the new appl */
		arcan_event_maskall(evctx);

/* with the 'no adopt' we can just safely flush the video stack and all
 * connections will be closed and freed */
		if (jumpcode == ARCAN_LUA_SWITCH_APPL_NOADOPT){
			int lastctxc = arcan_video_popcontext();
			int lastctxa;
			while( lastctxc != (lastctxa = arcan_video_popcontext()) )
				lastctxc = lastctxa;

/* rescan so devices seem to be added again */
			platform_event_rescan_idev(evctx);
		}
		else{
/* for adopt the rescan is deferred (adopt messes with the eventqueu) */
			arcan_video_recoverexternal(true, &saved, &truncated, NULL, NULL);
			adopt = true;
		}
		arcan_event_clearmask(evctx);
	}
/* fallback recovery with adoption */
	else if (jumpcode == ARCAN_LUA_RECOVERY_SWITCH){
		if (in_recover || !arcan_conductor_valid_cycle()){
			arcan_warning("Double-Failure (main appl + adopt appl), giving up.\n");
			goto error;
		}

/*
 * There is another edge condition here, and that is if some non-user triggered
 * event happens on reload after in_recover has been cleared. The last resort
 * from a livelock then is to have some crash-recovery timeout and counter.
 * This is also not water tight if the client has a long load/init stage BUT
 * with the ANR requirement on 10s so that sets an upper limit, use half that.
 */
		static uint64_t last_recover;
		static uint8_t recover_counter;
		if (!last_recover)
			last_recover = arcan_timemillis();

		if (last_recover && arcan_timemillis() - last_recover < 5000){
			recover_counter++;
			if (recover_counter > 5){
				arcan_warning("Script handover / recover safety timeout exceeded.\n");
				goto error;
			}
		}
		else {
			recover_counter = 0;
		}

		if (!fallback){
			arcan_warning("Lua VM failed with no fallback defined, (see -b arg).\n");
			goto error;
		}

		arcan_conductor_reset_count(true);
		arcan_event_maskall(evctx);
		arcan_video_recoverexternal(true, &saved, &truncated, NULL, NULL);
		arcan_event_clearmask(evctx);
		platform_video_recovery();

		const char* errmsg;
		arcan_lua_cbdrop();
		arcan_lua_shutdown(main_lua_context);
		if (strcmp(fallback, ":self") == 0)
			fallback = argv[optind];

		const char trace_msg[] = "Recovering from crash, resetting trace";
		arcan_trace_log(trace_msg, sizeof(trace_msg));
		arcan_trace_close();

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
	else if (jumpcode == ARCAN_LUA_RECOVERY_FATAL_IGNORE){
		goto run_loop;
	}
	else if (jumpcode == ARCAN_LUA_KILL_SILENT){
		goto cleanup;
	}

/* setup VM, map arguments and possible overrides */
	main_lua_context =
		arcan_lua_alloc(monitor_ctrl ? arcan_monitor_watchdog : NULL);
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

	if (monitor_ctrl)
		arcan_monitor_watchdog((lua_State*)main_lua_context, NULL);

	if (!arcan_lua_callvoidfun(main_lua_context, "", false,
		(const char**) (argc > optind ? (argv + optind + 1) : NULL))){
		arcan_warning("\n\x1b[1mCouldn't load (\x1b[33m%s\x1b[39m):"
			"\x1b[35m missing '%s' function\x1b[22m\x1b[39m\n\n", arcan_appl_id(), arcan_appl_id());
		goto error;
	}

/* mark that we are in hook so a script can know that is being used as a hook-
 * scripts and not as embedded by the appl itself */
	arcan_lua_setglobalint(main_lua_context, "IN_HOOK", 1);
	for (size_t i = 0; i < arr_hooks.count; i++){
		if (arr_hooks.data[i]){
			const char* name = arr_hooks.data[i];
			const char* src = &name[strlen(name)+1];
			arcan_lua_dostring(main_lua_context, src, name);
		}
	}
	arcan_lua_setglobalint(main_lua_context, "IN_HOOK", 0);

	if (adopt){
		arcan_lua_setglobalint(main_lua_context, "CLOCK", evctx->c_ticks);
		arcan_lua_adopt(main_lua_context);

/* re-issue video recovery here as adopt CLEARS THE EVENTQUEUE, this is quite a
 * complex pattern as the work in selectively recovering the event-queue after
 * an error is much too dangerous */
		platform_video_recovery();
		platform_event_rescan_idev(evctx);

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
	int exit_code = 0;

run_loop:
	exit_code = arcan_conductor_run(arcan_monitor_tick);
	arcan_lua_callvoidfun(main_lua_context, "shutdown", false, NULL);

/* destroy monitor first as it will need to snapshot the lua/VM stat e*/
cleanup:
	arcan_monitor_finish(exit_code == 256 || exit_code == 0);
	arcan_mem_freearr(&arr_hooks);
	arcan_led_shutdown();
	arcan_event_deinit(evctx, true);
	arcan_audio_shutdown();
	arcan_video_shutdown(exit_code != 256);
	arcan_mem_free(dbfname);

	if (dbhandle){
		arcan_db_close(&dbhandle);
		arcan_db_set_shared(NULL);
	}

	return exit_code == 256 || exit_code == 0 ? EXIT_SUCCESS : exit_code;

error:
	if (!monitor_ctrl && debuglevel > 1){
		arcan_warning("fatal: main loop failed, arguments: \n");
		for (size_t i = 0; i < argc; i++)
			arcan_warning("%s ", argv[i]);
		arcan_warning("\n\n");

		arcan_verify_namespaces(true);
	}

/* first write the reason as 'last words' if we are running in lwa as that
 * needs to be done BEFORE video_shutdown as that closes the context */
	const char* crashmsg = arcan_lua_crash_source(main_lua_context);
#ifdef ARCAN_LWA
	arcan_shmif_last_words(arcan_shmif_primary(SHMIF_INPUT), crashmsg);
#endif

/* now we can shutdown the subsystems themselves */
	arcan_monitor_finish(false);
	arcan_event_deinit(evctx, true);
	arcan_mem_free(dbfname);
	arcan_audio_shutdown();
	arcan_video_shutdown(false);

/* and finally write the reason to stdout as well now that native platforms
 * have restored the context to having valid stdout/stderr */
	if (crashmsg && !monitor_ctrl){
		arcan_warning(
			"\n\x1b[1mImproper API use from Lua script\n"
			":\n\t\x1b[32m%s\x1b[39m\n", crashmsg
		);

		arcan_warning("version:\n\t%s\n\tshmif-%" PRIu64"\n\tluaapi-%d:%d\n",
		ARCAN_BUILDVERSION, arcan_shmif_cookie(), LUAAPI_VERSION_MAJOR,
		LUAAPI_VERSION_MINOR
		);
	}
	return EXIT_FAILURE;
}
