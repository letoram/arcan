/*
 * Copyright 2014-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <string.h>
#include <poll.h>
#include <limits.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <pthread.h>

#include <errno.h>

#include <assert.h>
#include <errno.h>

#include PLATFORM_HEADER

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_db.h"
#include "arcan_audio.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_frameserver.h"
#include "arcan_conductor.h"

static char* add_interpose(struct arcan_strarr* libs, struct arcan_strarr* envv)
{
	char* interp = NULL;
	size_t lib_sz = 0;
#ifdef __APPLE__
	char basestr[] = "DYLD_INSERT_LIBRARIES=";
#else
	char basestr[] = "LD_PRELOAD=";
#endif

/* concatenate and build library string */
	char** work = libs->data;
	while(work && *work){
		lib_sz += strlen(*work) + 1;
		work++;
	}

	if (lib_sz > 0){
		interp = malloc(lib_sz + sizeof(basestr));
		memcpy(interp, basestr, sizeof(basestr));
		char* ofs = interp + sizeof(basestr)-1;

		work = libs->data;
		while (*work){
			size_t len = strlen(*work);
			memcpy(ofs, *work, len);
			ofs[len] = ':'; /* ' ' or ':', afaik : works on more platforms */
			ofs += len + 1;
			work++;
		}

		ofs[-1] = '\0';
	}

	if (envv->limit - envv->count < 2)
		arcan_mem_growarr(envv);

	envv->data[envv->count++] = interp;

	return interp;
}

unsigned long arcan_target_launch_external(const char* fname,
	struct arcan_strarr* argv, struct arcan_strarr* envv,
	struct arcan_strarr* libs, int* exitc)
{
	add_interpose(libs, envv);
	pid_t child = fork();

	if (child > 0) {
		int stat_loc;
		waitpid(child, &stat_loc, 0);

		if (WIFEXITED(stat_loc)){
			*exitc = WEXITSTATUS(stat_loc);
		}
		else
			*exitc = EXIT_FAILURE;

		unsigned long ticks = arcan_timemillis();
		return arcan_timemillis() - ticks;
	}
	else {
/* GNU extension warning */
		execve(fname, argv->data, envv->data);
		_exit(1);
	}

	*exitc = EXIT_FAILURE;
	return 0;
}

void arcan_closefrom(int fd)
{
#if defined(__APPLE__) || defined(__linux__)
	struct rlimit rlim;
	int lim = 512;
	if (0 == getrlimit(RLIMIT_NOFILE, &rlim))
		lim = rlim.rlim_cur;

	struct pollfd* fds = arcan_alloc_mem(sizeof(struct rlimit)*lim,
		ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO |
			ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

	for (size_t i = 0; i < lim; i++)
		fds[i].fd = i+fd;

	poll(fds, lim, 0);

	for (size_t i = 0; i < lim; i++)
		if (!(fds[i].revents & POLLNVAL))
			close(fds[i].fd);

	arcan_mem_free(fds);
#else
	closefrom(fd);
#endif
}

/*
 * expand-env pre-fork and make sure appropriate namespaces are present
 * and that there's enough room in the frameserver_envp for NULL term.
 * The caller will cleanup env with free_strarr.
 */
static void append_env(struct arcan_strarr* darr,
	char* argarg, char* sockmsg, char* conn)
{
/*
 * slightly unsure which ones we actually need to propagate, for now these go
 * through the chainloader so it is much less of an issue as most namespace
 * remapping features will go there, and arcterm need to configure the new
 * userenv anyhow.
 */
	const char* spaces[] = {
		getenv("PATH"),
		getenv("CWD"),
		getenv("HOME"),
		getenv("LANG"),
		getenv("ARCAN_FRAMESERVER_DEBUGSTALL"),
		getenv("ARCAN_RENDER_NODE"),
		getenv("ARCAN_VIDEO_NO_FDPASS"),
		arcan_fetch_namespace(RESOURCE_APPL),
		arcan_fetch_namespace(RESOURCE_APPL_TEMP),
		arcan_fetch_namespace(RESOURCE_APPL_STATE),
		arcan_fetch_namespace(RESOURCE_APPL_SHARED),
		arcan_fetch_namespace(RESOURCE_SYS_DEBUG),
		sockmsg,
		argarg,
		conn,
		getenv("LD_LIBRARY_PATH")
	};

/* HARDENING / REFACTOR: we should NOT pass logdir here as it should
 * not be accessible due to exfiltration risk. We should setup the log-
 * entry here and inherit that descriptor as stderr instead!. For harder
 * sandboxing, we can also pass the directory descriptors here */
	size_t n_spaces = sizeof(spaces) / sizeof(spaces[0]);
	const char* keys[] = {
		"PATH",
		"CWD",
		"HOME",
		"LANG",
		"ARCAN_FRAMESERVER_DEBUGSTALL",
		"ARCAN_RENDER_NODE",
		"ARCAN_VIDEO_NO_FDPASS",
		"ARCAN_APPLPATH",
		"ARCAN_APPLTEMPPATH",
		"ARCAN_STATEPATH",
		"ARCAN_RESOURCEPATH",
		"ARCAN_FRAMESERVER_LOGDIR",
		"ARCAN_SOCKIN_FD",
		"ARCAN_ARG",
		"ARCAN_SHMKEY",
		"LD_LIBRARY_PATH"
	};

/* growarr is set to FATALFAIL internally, this should be changed
 * when refactoring _mem and replacing strdup to properly handle OOM */
	while(darr->count + n_spaces + 1 > darr->limit)
		arcan_mem_growarr(darr);

	size_t max_sz = 0;
	for (size_t i = 0; i < n_spaces; i++){
		size_t len = spaces[i] ? strlen(spaces[i]) : 0;
		max_sz = len > max_sz ? len : max_sz;
	}

	char convb[max_sz + sizeof("ARCAN_FRAMESERVER_LOGDIR==")];
	size_t ofs = darr->count > 0 ? darr->count - 1 : 0;
	size_t step = ofs;

	for (size_t i = 0; i < n_spaces; i++){
		if (spaces[i] && strlen(spaces[i]) &&
			snprintf(convb, sizeof(convb), "%s=%s", keys[i], spaces[i])){
			darr->data[step] = strdup(convb);
			step++;
		}
	}

	darr->count = step;
	darr->data[step] = NULL;
}

arcan_frameserver* platform_launch_listen_external(
	const char* key, const char* pw, int fd, mode_t mode, uintptr_t tag)
{
	arcan_frameserver* res =
		platform_fsrv_listen_external(key, pw, fd, mode, tag);

	if (!res)
		return NULL;

	if (pw)
		strncpy(res->clientkey, pw, PP_SHMPAGE_SHMKEYLIM-1);

/*
 * Allocate a container vid, set it to have the socket/auth poll handler
 * sequence as a ffunc
 */
	img_cons cons = {
		.w = res->desc.width,
		.h = res->desc.height,
		.bpp = res->desc.bpp
	};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = res};

	res->launchedtime = arcan_frametime();
	res->vid = arcan_video_addfobject(FFUNC_SOCKPOLL, state, cons, 0);
	if (res->vid == ARCAN_EID){
		platform_fsrv_destroy(res);
		return NULL;
	}

	return res;
}

/*
 * this warrants explaining - to avoid dynamic allocations in the asynch unsafe
 * context of fork, we prepare the str_arr in *setup along with all envs needed
 * for the two to find eachother. The descriptor used for passing socket etc.
 * is inherited and duped to a fix position and possible leaked fds are closed.
 * On systems where this is a bad idea(tm), define the closefrom function to
 * nop. It's a safeguard against propagation from bad libs, not a feature that
 * is relied upon.
 */
struct arcan_frameserver* platform_launch_fork(
	struct frameserver_envp* setup, uintptr_t tag)
{
	struct arcan_strarr arr = {0};
	const char* source;
	int modem = 0;
	bool add_audio = true;
	int clsock;

	struct arcan_frameserver* ctx =
		platform_fsrv_spawn_server(
			SEGID_UNKNOWN, setup->init_w, setup->init_h, tag, &clsock);

	if (!ctx)
		return NULL;

	ctx->launchedtime = arcan_frametime();

/* just map the frameserver archetypes to preset context configs, nowadays
 * these are rather minor - in much earlier versions it covered queues, thread
 * scheduling and so on. */
	if (setup->use_builtin){
		append_env(&arr,
			(char*) setup->args.builtin.resource, "3", ctx->shm.key);
		if (strcmp(setup->args.builtin.mode, "game") == 0){
			ctx->segid = SEGID_GAME;
		}
		else if (strcmp(setup->args.builtin.mode, "net-cl") == 0){
			ctx->segid = SEGID_NETWORK_CLIENT;
			ctx->queue_mask |= EVENT_NET;
		}
		else if (strcmp(setup->args.builtin.mode, "net-srv") == 0){
			ctx->segid = SEGID_NETWORK_SERVER;
			ctx->queue_mask |= EVENT_NET;
		}
		else if (strcmp(setup->args.builtin.mode, "encode") == 0){
			ctx->segid = SEGID_ENCODER;
			ctx->sz_audb = 65535;
			add_audio = false;
			ctx->audb = arcan_alloc_mem(
				65535, ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);
		}
		else if (strcmp(setup->args.builtin.mode, "terminal") == 0){
			ctx->segid = SEGID_TERMINAL;
		}
	}
	else
		append_env(setup->args.external.envv,
			setup->args.external.resource ?
			setup->args.external.resource : "", "3", ctx->shm.key);

/* build the video object */
	img_cons cons  = {
		.w = setup->init_w,
		.h = setup->init_h,
		.bpp = 4
	};
	vfunc_state state = {
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = ctx
	};
	ctx->source = strdup(setup->args.builtin.resource);

	if (!setup->custom_feed){
		ctx->vid = arcan_video_addfobject(FFUNC_NULLFRAME, state, cons, 0);
		ctx->metamask |= setup->metamask;

		if (!ctx->vid){
			platform_fsrv_destroy(ctx);
			return NULL;
		}
	}
	else {
		ctx->vid = setup->custom_feed;
	}

/* spawn the process */
	pid_t child = fork();
	if (child){
		ctx->child = child;
	}
	else if (child == 0){
		close(STDERR_FILENO+1);
/* will also strip CLOEXEC */
		dup2(clsock, STDERR_FILENO+1);
		arcan_closefrom(STDERR_FILENO+2);

/* split out into a new session */
		if (setsid() == -1)
			_exit(EXIT_FAILURE);

		int nfd = open("/dev/null", O_RDONLY);
		if (-1 != nfd){
			dup2(nfd, STDIN_FILENO);
			close(nfd);
		}

/*
 * we need to mask this signal as when debugging parent process, GDB pushes
 * SIGINT to children, killing them and changing the behavior in the core
 * process
 */
		sigaction(SIGPIPE, &(struct sigaction){
			.sa_handler = SIG_IGN}, NULL);

		if (setup->use_builtin){
			char* argv[] = {
				arcan_fetch_namespace(RESOURCE_SYS_BINS),
				(char*) setup->args.builtin.mode,
				NULL
			};

/* OVERRIDE/INHERIT rather than REPLACE environment (terminal, ...) */
			if (setup->preserve_env){
				for (size_t i = 0; i < arr.count;	i++){
					if (!(arr.data[i] || arr.data[i][0]))
						continue;

					char* val = strchr(arr.data[i], '=');
					*val++ = '\0';
					setenv(arr.data[i], val, 1);
				}
				execv(argv[0], argv);
			}
			else
				execve(argv[0], argv, arr.data);

			arcan_warning("platform_fsrv_spawn_server() failed: %s, %s\n",
				strerror(errno), argv[0]);
				;
			_exit(EXIT_FAILURE);
		}
/* non-frameserver executions (hijack libs, ...) */
		else {
			execve(setup->args.external.fname,
				setup->args.external.argv->data, setup->args.external.envv->data);
			_exit(EXIT_FAILURE);
		}
	}
/* out of alloted limit of subprocesses */
	else {
		arcan_video_deleteobject(ctx->vid);
		platform_fsrv_destroy(ctx);
		return NULL;
	}
	close(clsock);

/* most kinds will need this, not the encode though */
	arcan_errc errc;
	if (add_audio)
		ctx->aid = arcan_audio_feed(
			(arcan_afunc_cb) arcan_frameserver_audioframe_direct, ctx, &errc);

/* "fake" a register since that step has already happened */
	if (ctx->segid != SEGID_UNKNOWN){
		arcan_event_enqueue(arcan_event_defaultctx(), &(arcan_event){
			.category = EVENT_FSRV,
			.fsrv.kind = EVENT_FSRV_PREROLL,
			.fsrv.video = ctx->vid
		});
	}

	arcan_conductor_register_frameserver(ctx);

	return ctx;
}

arcan_frameserver* platform_launch_internal(const char* fname,
	struct arcan_strarr* argv, struct arcan_strarr* envv,
	struct arcan_strarr* libs, uintptr_t tag)
{
	add_interpose(libs, envv);

	argv->data = arcan_expand_namespaces(argv->data);
	envv->data = arcan_expand_namespaces(envv->data);

	struct frameserver_envp args = {
		.use_builtin = false,
		.args.external.fname = (char*) fname,
		.args.external.envv = envv,
		.args.external.argv = argv
	};

	return platform_launch_fork(&args, tag);
}
