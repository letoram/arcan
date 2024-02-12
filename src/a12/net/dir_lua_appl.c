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

static const int GROW_SLOTS = 4;

static lua_State* L;
static struct arcan_shmif_cont SHMIF;
static bool SHUTDOWN;

static int shmifopen_flags =
			SHMIF_ACQUIRE_FATALFAIL |
			SHMIF_NOACTIVATE |
			SHMIF_NOAUTO_RECONNECT |
			SHMIF_NOREGISTER;

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
static struct {
	char prefix_buf[128];
	size_t prefix_len;
	size_t prefix_maxlen;
	const char* last_ep;
} lua;

static FILE* logout;

#define log_print(fmt, ...) do { fprintf(logout, fmt "\n", ##__VA_ARGS__); } while (0)

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
#ifdef DEBUG
	log_print("kind=message:broken_utf8_message");
#endif
	dst[0] = '\0';
}

static bool setup_entrypoint(struct lua_State* L, const char* ep, size_t len)
{
	memcpy(&lua.prefix_buf[lua.prefix_len], ep, len);
	lua.prefix_buf[lua.prefix_len + len] = '\0';
	lua_getglobal(L, lua.prefix_buf);
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return false;
	}

	lua.last_ep = ep;
	return true;
}

static void dump_stack(lua_State* L, FILE* dst)
{
	int top = lua_gettop(L);
	fprintf(dst, "-- stack dump (%d)--\n", top);

	for (int i = 1; i <= top; i++){
		int t = lua_type(L, i);

		switch (t){
		case LUA_TBOOLEAN:
			fprintf(dst, lua_toboolean(L, i) ? "true" : "false");
		break;
		case LUA_TSTRING:
			fprintf(dst, "%d\t'%s'\n", i, lua_tostring(L, i));
			break;
		case LUA_TNUMBER:
			fprintf(dst, "%d\t%g\n", i, lua_tonumber(L, i));
			break;
		default:
			fprintf(dst, "%d\t%s\n", i, lua_typename(L, t));
			break;
		}
	}

	fprintf(dst, "\n");
}

static int panic(lua_State* L)
{
/* MISSING: need a _fatal with access to store_keys etc.  question is if we
 * should permit message_target still (it makes sense if the appl wants
 * recovery in their own layer). */

/* always cleanup and die - free:ing shmifsrv will pull DMS and enqueue an
 * EXIT. We could redirect back to parent and then let it spin up a new and
 * redirect us back, but just repeat the join cycle should be enough.
 *
 * The EXIT event will help us out of any blocked request for local bchunks
 * sent through _free will help us out of any pending bchunks */
	for (size_t i = 1; i < CLIENTS.set_sz; i++){
		if (!CLIENTS.cset[i].shmif)
			continue;

		shmifsrv_free(CLIENTS.cset[i].shmif, SHMIFSRV_FREE_FULL);
	}

/* generate a backtrace and dump into stdout which should be our logfd still,
 * set our last words as the crash so the parent knows to keep the log and
 * deliver to developer on request. */
	fprintf(logout, "\nscript error (%s):\n", lua.last_ep ? lua.last_ep : "(broken-ep)");
	fprintf(logout, "\nVM stack:\n");
	dump_stack(L, logout);
	arcan_shmif_last_words(&SHMIF, "script_error");
	arcan_shmif_drop(&SHMIF);

	exit(EXIT_FAILURE);
}

static int wrap_pcall(lua_State* L, int nargs, int nret)
{
	int errind = lua_gettop(L) - nargs;
	lua_pushcfunction(L, panic);
	lua_insert(L, errind);
	lua_pcall(L, nargs, nret, errind);
	lua_remove(L, errind);
	lua.last_ep = NULL;
	return 0;
}

static void expose_api(lua_State* L, const luaL_Reg* funtbl)
{
	while(funtbl->name != NULL){
		lua_pushstring(L, funtbl->name);
		lua_pushcclosure(L, funtbl->func, 1);
		lua_setglobal(L, funtbl->name);
		funtbl++;
	}
}

static struct client* alua_checkclient(lua_State* L, int ind)
{
	size_t clid = luaL_checknumber(L, ind);
	for (size_t i = 0; i < CLIENTS.set_sz; i++){
		struct client* cl = &CLIENTS.cset[i];
		if (cl->clid == clid){
			if (!cl->shmif){
				luaL_error(L, "client identifier to dead client: %zu\n", clid);
			}
			return cl;
		}
	}

	luaL_error(L, "unknown client identifier: %zu\n", clid);
	return NULL;
}

static int targetmessage(lua_State* L)
{
/* unicast or broadcast? */
	size_t strind = 1;
	struct client* target = NULL;

	if (lua_type(L, 1) == LUA_TNUMBER){
		target = alua_checkclient(L, 1);
		strind = 2;
	}

/* right now this error-outs rather than multipart chunks as the
 * queueing isn't clean enough throughout - with the approach of
 * returning an error */
	const char* msg = luaL_checkstring(L, strind);
	struct arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_MESSAGE
	};

	if (strlen(msg)+1 >= COUNT_OF(outev.ext.message.data)){
		log_print("kind=error:msg_overflow=%s", msg);
		lua_pushboolean(L, false);
		return 1;
	}

	snprintf(
		(char*)outev.ext.message.data,
		COUNT_OF(outev.ext.message.data), "%s", msg);

	if (target){
		if (!target->shmif){
			log_print("kind=error:bad_shmif:"
				"source=message_target:id=%zu", (size_t) lua_tonumber(L, 1));
		}
#ifdef DEBUG
		log_print("kind=message:"
				"id=%zu:message=%s", (size_t) lua_tonumber(L, 1), msg);
#endif
		lua_pushboolean(L,
			shmifsrv_enqueue_event(target->shmif, &outev, -1)
		);
		return 1;
	}

#ifdef DEBUG
	log_print("kind=message:id=%zu:message=%s", (size_t) lua_tonumber(L, 1), msg);
#endif

	for (size_t i = 0; i < CLIENTS.set_sz; i++){
		if (!CLIENTS.cset[i].shmif)
			continue;

/* should this return a list of workers that failed due to a saturated
 * event queue in order to detect stalls / livelocks? */
		shmifsrv_enqueue_event(CLIENTS.cset[i].shmif, &outev, -1);
	}

	lua_pushboolean(L, true);
	return 1;
}

/* luaB_print with a different output FILE */
static int print_log(lua_State* L)
{
	int n = lua_gettop(L);  /* number of arguments */
	int i;
	lua_getglobal(L, "tostring");
	fputs("kind=lua:print=", logout);

	for (i=1; i<=n; i++) {
		const char *s;
		lua_pushvalue(L, -1);  /* function to be called */
		lua_pushvalue(L, i);   /* value to print */
		lua_call(L, 1, 1);
		s = lua_tostring(L, -1);  /* get result */
		if (s == NULL)
		return luaL_error(L, LUA_QL("tostring") " must return a string to " LUA_QL("print"));
		if (i>1)
			fputs("\t", logout);
		fputs(s, logout);
		lua_pop(L, 1);  /* pop result */
	}
	  fputs("\n", logout);

	return 0;
}

static void open_appl(int dfd, const char* name)
{
	int dirfd = -1;
	log_print("dir_lua:open=%.*s", (int) sizeof(name), name);
	size_t len = strlen(name);

/* maxlen set after the longest named entry point (applname_clock_pulse) */
	if (!lua.prefix_maxlen){
		lua.prefix_maxlen =
			COUNT_OF(lua.prefix_buf) - sizeof("_clock_pulse") - 1;
	}

	if (len > lua.prefix_maxlen){
		log_print("dir_lua:applname_too_long");
		return;
	}

	if (L){
		log_print("dir_lua:missing:dynamic_reload");
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
	lua_atpanic(L, (lua_CFunction) panic);

	int rv =
		luaL_loadbuffer(L,
		(const char*) arcan_bootstrap_lua,
		arcan_bootstrap_lua_len, "bootstrap"
	);
	if (0 != rv){
		log_print("dir_lua:build_error:bootstrap.lua");
		return;
	}
/* first just setup and parse, don't expose API yet */
	luaL_openlibs(L);
	lua_pushcfunction(L, print_log);
	lua_setglobal(L, "print");
	lua_pcall(L, 0, 0, 0);

	memcpy(lua.prefix_buf, name, len);
	lua.prefix_buf[len] = '\0';
	lua.prefix_len = len;

	char scratch[len + sizeof(".lua")];

/* open, map, load as string */
	snprintf(scratch, sizeof(scratch), "%s.lua", name);
	data_source source = {
		.fd = openat(dfd, scratch, O_RDONLY),
	};
	map_region reg = arcan_map_resource(&source, false);

	if (0 == luaL_loadbuffer(L, reg.ptr, reg.sz, name)){
		static const luaL_Reg api[] = {
			{"message_target", targetmessage},
			{NULL, NULL}
		};
		expose_api(L, api);
		wrap_pcall(L, 0, LUA_MULTRET);
	}
	arcan_release_map(reg);
	arcan_release_resource(&source);

/* import API, call entrypoint */
}

static bool join_worker(int fd)
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

		for (size_t i = CLIENTS.active; i < new_sz; i++){
			new_pset[i] = (struct pollfd){.fd = -1};
			new_cset[i] = (struct client){.0};
		}

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
		int pv = shmifsrv_poll(cl->shmif);
		while (pv != CLIENT_IDLE && pv != CLIENT_DEAD){
			pv = shmifsrv_poll(cl->shmif);
		}
		if (pv == CLIENT_DEAD){
			log_print("status=worker_broken");
			shmifsrv_free(cl->shmif, SHMIFSRV_FREE_FULL);
			cl->shmif = NULL;
			return false;
		}
		log_print("status=joined:worker=%zu", cl->clid);
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
		setup_entrypoint(L, "_leave", sizeof("_leave"))){
		lua_pushnumber(L, cl->clid);
		wrap_pcall(L, 1, 0);
	}

	log_print("status=left:worker=%zu", cl->clid);
	shmifsrv_free(cl->shmif, SHMIFSRV_FREE_FULL);
	*cl = (struct client){0};
}

static void meta_resource(int fd, const char* msg)
{
	if (strncmp(msg, ".worker", 8) == 0){
		join_worker(fd);
	}
/* new key-value store to work with */
	else if (strcmp(msg, ".sqlite3") == 0){
	}
	else
		log_print("unhandled:%s\n", msg);
}

static void parent_control_event(struct arcan_event* ev)
{
	if (ev->category != EVENT_TARGET)
		return;

	switch (ev->tgt.kind){
	case TARGET_COMMAND_BCHUNK_IN:{
		int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
		if (-1 == fd){
			log_print("kind=error:source=dup:bchunk:message=%s", ev->tgt.message);
			return;
		}

		if (ev->tgt.message[0] != '.')
			open_appl(fd, ev->tgt.message);
		else
			meta_resource(fd, ev->tgt.message);
	}
	break;
	case TARGET_COMMAND_BCHUNK_OUT:{
		if (strcmp(ev->tgt.message, ".log") == 0){
			int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
			logout = fdopen(fd, "w");
			setlinebuf(logout);
			log_print("--- log opened ---");
		}
	}
	break;
	case TARGET_COMMAND_EXIT:
		SHUTDOWN = true;
	break;
	case TARGET_COMMAND_STEPFRAME:
	break;
	default:
	break;
	}
}

static void worker_instance_event(struct client* cl, int fd, int revents)
{
	struct arcan_event ev;
	while (1 == shmifsrv_dequeue_events(cl->shmif, &ev, 1)){
#ifdef DEBUG
		log_print("kind=shmif:source=%zu:data=%s", cl->clid, arcan_shmif_eventstr(&ev, NULL, 0));
#endif

		if (!cl->registered){
			if (ev.ext.kind == EVENT_EXTERNAL_NETSTATE){
				blake3_hasher hash;
				blake3_hasher_init(&hash);
				blake3_hasher_update(&hash, ev.ext.netstate.name, 32);
				uint8_t khash[32];
				blake3_hasher_finalize(&hash, khash, 32);
				unsigned char* b64 = a12helper_tob64(khash, 32, &(size_t){0});
				snprintf(cl->keyid, COUNT_OF(cl->keyid), "%s", (char*) b64);
				log_print(
					"kind=status:worker=%zu:registered:key=%s", cl->clid, cl->keyid);
				free(b64);
				cl->registered = true;

				if (setup_entrypoint(L, "_join", sizeof("_join"))){
					lua_pushnumber(L, cl->clid);
					wrap_pcall(L, 1, 0);
				}
			}
			else {
				log_print("kind=error:worker=%zu:unregistered_event=%s",
					cl->clid, arcan_shmif_eventstr(&ev, NULL, 0));
			}
			continue;
		}
/* NAK until we have the client side of file access done */
		if (ev.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
			shmifsrv_enqueue_event(cl->shmif, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_REQFAIL,
				}, -1);
			continue;
		}
		if (ev.ext.kind == EVENT_EXTERNAL_MESSAGE){
			if (setup_entrypoint(L, "_message", sizeof("_message"))){
				lua_pushnumber(L, cl->clid);
				lua_newtable(L);
				int top = lua_gettop(L);
				tblbool(L, "multipart", ev.ext.message.multipart, top);
				MSGBUF_UTF8(ev.ext.message.data);
				tbldynstr(L, "message", (char*) ev.ext.message.data, top);
				wrap_pcall(L, 2, 0);
			}
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
	logout = stdout;

	SHMIF = arcan_shmif_open(SEGID_NETWORK_SERVER, shmifopen_flags, &args);
	shmifsrv_monotonic_rebase();

/* shmif connection gets reserved index 0 */
	join_worker(SHMIF.epipe);
	int left = 25;

	while (!SHUTDOWN){
		int pv = poll(CLIENTS.pset, CLIENTS.set_sz, left);
		int nt = shmifsrv_monotonic_tick(&left);
		while (nt > 0 && setup_entrypoint(L, "_clock_pulse", sizeof("_clock_pulse"))){
			wrap_pcall(L, 0, 0);
			nt--;
		}

		if (CLIENTS.pset[0].revents){
			struct arcan_event ev;
			arcan_shmif_wait(&SHMIF, &ev);
			parent_control_event(&ev);
			while (arcan_shmif_poll(&SHMIF, &ev) > 0){
				parent_control_event(&ev);
			}
			CLIENTS.pset[0].revents = 0;
			pv--;
		}

		for (size_t i = 1; i < CLIENTS.set_sz; i++){
			if (CLIENTS.cset[i].shmif){
				worker_instance_event(
					&CLIENTS.cset[i], CLIENTS.pset[i].fd, CLIENTS.pset[i].revents);
				if (CLIENTS.pset[i].revents & (POLLHUP | POLLNVAL)){
					release_worker(i);
				}

				CLIENTS.pset[i].revents = 0;
			}
		}
	}

	log_print("parent_exit");
}
