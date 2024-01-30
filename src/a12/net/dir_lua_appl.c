#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <poll.h>

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"
#include "../../engine/arcan_bootstrap.h"
#include "../../engine/alt/support.h"
#include "platform_types.h"
#include "os_platform.h"

static const int GROW_SLOTS = 64;

static lua_State* L;
static struct arcan_shmif_cont SHMIF;
static bool shutdown;

struct client {
	uint8_t name[64];
	char keyid[45]; /* 4 * 32 / 3 align to %4 + \0 */
	size_t clid;
	size_t msgbuf[128];
	size_t msgbuf_ofs;
	struct shmifsrv_client* shmif;
	bool registered;
};

static struct {
	size_t active;
	size_t set_sz;
	struct pollfd* pset;
	struct client* cset;
} CLIENTS;

/* used to prefill applname_entrypoint */
static char prefix_buf[128];
static size_t prefix_len;
static size_t prefix_maxlen;

#define debug_print(fmt, ...) do { fprintf(stdout, fmt "\n", ##__VA_ARGS__); } while (0)

/* These are just lifted from src/engine/arcan_lua.c */
#include "../../frameserver/util/utf8.c"
#define MSGBUF_UTF8(X) slim_utf8_push((char*)(X), COUNT_OF((X))-1, (char*)(X))

static void slim_utf8_push(char* dst, int ulim, char* inmsg)
{
	uint32_t state = 0;
	uint32_t codepoint = 0;
	size_t i = 0;

	for (; inmsg[i] != '\0' && i < ulim; i++){
		dst[i] = inmsg[i];

		if (utf8_decode(&state, &codepoint, (uint8_t)(inmsg[i])) == UTF8_REJECT)
			goto out;
	}

	if (state == UTF8_ACCEPT){
		dst[i] = '\0';
		return;
	}

/* for broken state, just ignore. The other options would be 'warn' (will spam)
 * or to truncate (might in some cases be prefered). */
out:
	dst[0] = '\0';
}


static bool setup_entrypoint(
	struct client* cl, const char* ep, size_t len)
{
	memcpy(&prefix_buf[prefix_len], ep, len);
	prefix_buf[prefix_len + len] = '\0';
	lua_getglobal(L, prefix_buf);
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return false;
	}

	return true;
}

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
	prefix_len = len;

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

static bool join_worker(int fd, const char* name)
{
/* just naively grow, parent process is responsible for more refined handling
 * of constraining resources */
	if (CLIENTS.active == CLIENTS.set_sz){
		size_t new_sz = CLIENTS.set_sz + GROW_SLOTS;
		struct pollfd* new_pset = malloc(sizeof(struct pollfd) * new_sz);
		if (!new_pset)
			goto err;

		struct client* new_cset = malloc(sizeof(struct client) * new_sz);
		if (!new_cset){
			free(new_pset);
			goto err;
		}

		memcpy(new_pset, CLIENTS.pset, sizeof(struct pollfd) * CLIENTS.set_sz);
		memcpy(new_cset, CLIENTS.cset, sizeof(struct client) * CLIENTS.set_sz);
		free(CLIENTS.pset);
		free(CLIENTS.cset);
		CLIENTS.cset = new_cset;
		CLIENTS.pset = new_pset;
		CLIENTS.set_sz = new_sz;
	}

/* slot 0 is reserved for shmif connection */
	size_t ind = 0;
	for (;ind < CLIENTS.set_sz; ind++){
		if (CLIENTS.pset[ind].fd <= 0)
			break;
	}

/* the client isn't visible to the script until we get the netstate register
 * with the derived H(Salt | Keypub). so the pcall will happen later */
	CLIENTS.pset[ind] = (struct pollfd){
		.fd = fd,
		.events = POLLIN | POLLERR | POLLHUP
	};
	int tmp;
	CLIENTS.cset[ind] = (struct client){
		.registered = false,
		.clid = ind
	};

/* another subtle thing, shmifsrv_inherit_connection does not actually
 * send the key so do that now. */
	if (ind != 0){
		struct client* cl = &CLIENTS.cset[ind];
		cl->shmif = shmifsrv_inherit_connection(fd, &tmp);
		shmifsrv_poll(cl->shmif);
	}

	CLIENTS.active++;
	return true;

err:
	close(fd);
	return false;
}

static void release_worker(size_t ind)
{
	if (ind >= CLIENTS.set_sz || !ind)
		return;

/* mark it as available for new join */
	struct client* cl = &CLIENTS.cset[ind];
	close(CLIENTS.pset[ind].fd);
	CLIENTS.pset[ind].fd = -1;
	CLIENTS.active--;

	if (cl->registered &&
		setup_entrypoint(cl, "_leave", sizeof("_leave"))){
		lua_pushnumber(L, cl->clid);
		lua_pcall(L, 1, 0, 0);
	}

	shmifsrv_free(cl->shmif, SHMIFSRV_FREE_FULL);
	*cl = (struct client){0};
}

static void meta_resource(int fd, const char* msg)
{
	if (strncmp(msg, ".worker=", 8) == 0){
		join_worker(fd, &msg[8]);
	}
/* new key-value store to work with */
	else if (strcmp(msg, ".sqlite3") == 0){
	}
	else
		debug_print("unhandled:%s\n", msg);
}

static void process_event(struct arcan_event* ev)
{
	if (ev->category != EVENT_TARGET)
		return;

	switch (ev->tgt.kind){
	case TARGET_COMMAND_BCHUNK_IN:{
		int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
		if (ev->tgt.message[0] != '.')
			open_appl(fd, ev->tgt.message);
		else
			meta_resource(fd, ev->tgt.message);
	}
	break;
	case TARGET_COMMAND_BCHUNK_OUT:{
		if (strcmp(ev->tgt.message, ".log") == 0){
			arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, STDOUT_FILENO, false);
		}
	}
	case TARGET_COMMAND_STEPFRAME:
	break;
	default:
	break;
	}
}

static void process_client(struct client* cl, int fd, int revents)
{
	struct arcan_event ev;
	while (1 == shmifsrv_dequeue_events(cl->shmif, &ev, 1)){
		debug_print("%zu:%s\n", cl->clid, arcan_shmif_eventstr(&ev, NULL, 0));

		if (!cl->registered){
			if (ev.ext.kind == EVENT_EXTERNAL_NETSTATE){
				blake3_hasher hash;
				blake3_hasher_init(&hash);
				blake3_hasher_update(&hash, ev.ext.netstate.name, 32);
				uint8_t khash[32];
				blake3_hasher_finalize(&hash, khash, 32);
				unsigned char* b64 = a12helper_tob64(khash, 32, &(size_t){0});
				snprintf(cl->keyid, COUNT_OF(cl->keyid), "%s", (char*) b64);
				free(b64);
				cl->registered = true;

				if (setup_entrypoint(cl, "_join", sizeof("_join"))){
					lua_pushnumber(L, cl->clid);
					lua_pcall(L, 1, 0, 0);
				}
			}
			continue;
		}

		if (ev.ext.kind == EVENT_EXTERNAL_MESSAGE &&
			setup_entrypoint(cl, "_message", sizeof("_message"))){
			lua_pushnumber(L, cl->clid);
			lua_newtable(L);
			int top = lua_gettop(L);
			tblbool(L, "multipart", ev.tgt.ioevs[0].iv != 0, top);
			MSGBUF_UTF8(ev.tgt.message);
			tbldynstr(L, "message", ev.tgt.message, top);
			lua_pcall(L, 2, 0, 0);
		}

/* other relevant, BCHUNKSTATE now that dir_srv.c can be sidestepped (mostly),
 * private- store won't be accessible from here */
	 }
	if (shmifsrv_poll(cl->shmif) == CLIENT_DEAD){
		release_worker(cl->clid);
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

/* shmif connection gets reserved index 0 */
	join_worker(SHMIF.epipe, ".shmif");

	while (!shutdown){
		int pv = poll(CLIENTS.pset, CLIENTS.set_sz, -1);
		if (pv <= 0)
			continue;

		if (CLIENTS.pset[0].revents){
			struct arcan_event ev;
			arcan_shmif_wait(&SHMIF, &ev);
			process_event(&ev);
			while (arcan_shmif_poll(&SHMIF, &ev) > 0){
				process_event(&ev);
			}
			CLIENTS.pset[0].revents = 0;
			pv--;
		}

/* these are shmifsrv_ client but with an extra signalling step on enqueue that
 * is normally reserved for shmifsrv_enqueue */
		for (size_t i = 1; i < CLIENTS.set_sz && pv; i++){
			if (CLIENTS.pset[i].revents){
				process_client(
					&CLIENTS.cset[i], CLIENTS.pset[i].fd, CLIENTS.pset[i].revents);
				pv--;
				CLIENTS.pset[i].revents = 0;
			}
		}
	}

	debug_print("parent_exit");
}
