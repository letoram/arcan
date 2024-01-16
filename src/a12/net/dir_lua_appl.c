#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>

#include "../../engine/arcan_bootstrap.h"
#include "platform_types.h"
#include "os_platform.h"

static lua_State* L;
static struct arcan_shmif_cont SHMIF;

/* used to prefill applname_entrypoint */
static char prefix_buf[128];
static size_t prefix_len;
static size_t prefix_maxlen;

#ifdef _DEBUG
#define debug_print(fmt, ...) do { fprintf(stderr, fmt "\n", ##__VA_ARGS__); } while (0)
#else
#define debug_print(...)
#endif

/* event mapping:
 *
 *  BCHUNK_IN: ".[something]" for secondary resources, e.g. appl-shared namespace
 *  BCHUNK_IN: ".worker" for a descriptor to inherit connection
 *  BCHUNK_IN: ".sqlite3" for a key-value store
 *
 *  STEPFRAME: used for low-precision monotonic clock to feed into script
 */
static void open_appl(int dfd, const char* name)
{
	int dirfd = -1;
	debug_print("dir_lua:open=%.*s", (int) sizeof(name), name);
	size_t len = strlen(name);

	if (!prefix_maxlen){
		prefix_maxlen = COUNT_OF(prefix_buf) - sizeof("_clock_pulse");
	}

	if (len > prefix_maxlen){
		debug_print("dir_lua:applname_too_long");
		return;
	}

	if (L){
		debug_print("dir_lua:missing:dynamic_reload");
	}

/* This mimics much of the setup of the client side API, though the specifics
 * are still to be figured out. The big pieces are feeding nbio_open, the _keys
 * functions and how to support on-demand spawning 'special' clients as sources
 * only exposed to named clients.
 *
 * What we'd like to do is something like:
 *   launch_(target,decode) ->
 *       spinup shmifsrv,
 *       connect client,
 *       register as source in the directory,
 *       restrict it to a token that we pass
 *       to the intended recipient
 *       let the other end create a new connection that sources our new sink
 */
	L = luaL_newstate();
	int rv =
		luaL_loadbuffer(L,
		(const char*) arcan_bootstrap_lua,
		arcan_bootstrap_lua_len, "bootstrap"
	);
	if (0 != rv){
		debug_print("dir_lua:build_error:bootstrap.lua");
		return;
	}
	luaL_openlibs(L);
	lua_pcall(L, 0, 0, 0);

/* first just setup and parse, don't expose API yet */
	memcpy(prefix_buf, name, len);
	prefix_buf[len] = '\0';

	char scratch[len + sizeof(".lua")];

/* open, map, load as string */
	snprintf(scratch, sizeof(scratch), "%s.lua", name);
	data_source source = {
		.fd = openat(dfd, scratch, O_RDONLY),
	};
		map_region reg = arcan_map_resource(&source, false);
		luaL_loadbuffer(L, reg.ptr, reg.sz, name) || lua_pcall(L, 0, LUA_MULTRET, 0);
		arcan_release_map(reg);
	arcan_release_resource(&source);

/* import API, call entrypoint */
}

static void process_event(struct arcan_event* ev)
{
	if (ev->category != EVENT_TARGET)
		return;

	switch (ev->tgt.kind){
	case TARGET_COMMAND_BCHUNK_IN:
		if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_IN){
			int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
			if (ev->tgt.message[0] != '.'){
				open_appl(fd, ev->tgt.message);
			}
			else {
				close(fd);
				debug_print("dir_lua:unhandled=%s", ev->tgt.message);
			}
			break;
		}
	break;
	case TARGET_COMMAND_STEPFRAME:
	break;
	default:
	break;
	}
}

void anet_directory_appl_runner()
{
	struct arg_arr* args;
	SHMIF = arcan_shmif_open(
		SEGID_NETWORK_SERVER,
		SHMIF_ACQUIRE_FATALFAIL |
		SHMIF_NOACTIVATE |
		SHMIF_DISABLE_GUARD |
		SHMIF_NOREGISTER,
		&args
	);

/* wait for the directory descriptor */
	struct arcan_event ev;
	while (arcan_shmif_wait(&SHMIF, &ev)){
		process_event(&ev);
	}

	debug_print("parent_exit");
}
