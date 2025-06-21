#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <poll.h>
#include <assert.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <ctype.h>
#include <signal.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"

#include "dir_lua_support.h"

#include "../../engine/arcan_bootstrap.h"
#include "../../engine/alt/support.h"

/* pull in nbio as it is used in the tui-lua bindings */
#include "../../shmif/tui/lua/nbio.h"
#include "../../shmif/tui/lua/nbio_static_loop.h"

#include "directory.h"
#include "platform_types.h"
#include "os_platform.h"

static const int GROW_SLOTS = 7;

static struct {
	lua_State* L;
	struct arcan_shmif_cont SHMIF;
	bool shutdown;
	int in_filereq_handler;
	int filereq_handler_ref;
} G =
{
	.filereq_handler_ref = -1
};

enum {
	NS_CLID = 1,
	NS_NONBLOCK = 2
};

static int shmifopen_flags =
			SHMIF_ACQUIRE_FATALFAIL |
			SHMIF_NOACTIVATE        |
			SHMIF_NOAUTO_RECONNECT  |
			SHMIF_NOREGISTER        |
			SHMIF_SOCKET_PINGEVENT;

struct client {
	uint8_t name[64];
	char keyid[45]; /* 4 * 32 / 3 align to %4 + \0 */
	size_t clid;
	size_t msgbuf[128];
	size_t msgbuf_ofs;
	struct shmifsrv_client* shmif;
	const char* ident;
	bool registered;
};

static struct {
	int dirfd;
	size_t active;
	size_t set_sz;
	struct pollfd* pset;
	struct client* cset;
	size_t monitor_slot;
} CLIENTS = {.dirfd = -1};

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
/*
 * With a monitor attached we don't really shutdown, but rather just send
 * the trace and return to entrypoint- calling. It's up to the monitor to
 * detach or send a12:kill to parent -> HUP -> shutdown.
 */
	if (CLIENTS.monitor_slot){
		dirlua_monitor_watchdog(L, NULL);
		return 0;
	}

/* MISSING: need a _fatal with access to store_keys etc.  question is if we
 * should permit message_target still (it makes sense if the appl wants
 * recovery in their own layer). */

/* always cleanup and die - free:ing shmifsrv will pull DMS and enqueue an
 * EXIT. We could redirect back to parent and then let it spin up new and
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
	fprintf(logout, "\nScript Error:\nVM stack:\n");
	dump_stack(L, logout);
	arcan_shmif_last_words(&G.SHMIF, "script_error");
	arcan_shmif_drop(&G.SHMIF);

	exit(EXIT_FAILURE);
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

static bool validate_key(const char* key)
{
/* accept 0-9 and base64 valid values */
	while(*key){
		if (!isalnum(*key) && *key != '_'
			&& *key != '+' && *key != '/' && *key != '=')
			return false;
		key++;
	}

	return true;
}

static void send_setkey(
	const char* key, const char* val, bool use_dom, int domain)
{
	char* req = NULL;
	ssize_t req_len;

	if (use_dom)
		req_len = asprintf(&req, "setkey=%s:domain=%d:value=%s", key, domain, val);
	else
		req_len = asprintf(&req, "setkey=%s:value=%s", key, val);

	if (req_len < 0){
		return;
	}

/* use reference as identifier for the callback */
	arcan_shmif_pushutf8(&G.SHMIF, &(struct arcan_event){
		.category = ARCAN_EVENT(MESSAGE),
	}, req, req_len);

	free(req);
}

static int storekeys(lua_State* L)
{
/* argtbl[...]
 * argtbl[...], int:target
 * string:key, string:val
 * string:key, string:val, int:target
 */
	if (lua_type(L, 1) == LUA_TTABLE){
		int domain = luaL_optnumber(L, 2, 0);
		struct arcan_event beg = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(MESSAGE)
		};

		snprintf((char*) beg.ext.message.data,
			sizeof(beg.ext.message.data),
			"begin_kv_transaction:domain=%d", domain % 10
		);
		arcan_shmif_enqueue(&G.SHMIF, &beg);
		lua_pushnil(L);

		while (lua_next(L, 1) != 0){
			const char* key = lua_tostring(L, -2);
			if (!validate_key(key)){
				luaL_error(L, "store_keys(>tbl<) - invalid key (alphanum, no +/_=)");
			}
			const char* value = lua_tostring(L, -1);
			send_setkey(key, value, false, 0);
			lua_pop(L, 1);
		}

		arcan_shmif_enqueue(&G.SHMIF,
			&(struct arcan_event){
				.category = EVENT_EXTERNAL,
				.ext.kind = ARCAN_EVENT(MESSAGE),
				.ext.message.data = "end_kv_transaction"
			}
		);

		return 0;
	}

	const char* key = luaL_checkstring(L, 1);
	const char* value = luaL_checkstring(L, 2);
	int domain = luaL_optnumber(L, 3, 0);
	send_setkey(key, value, true, domain);

	return 0;
}

/*
 * same procedure as with match_keys
 */
static int listtargets(lua_State* L)
{
	struct arcan_event ev = {
		.category = ARCAN_EVENT(MESSAGE),
	};
/* extract and reference continuation */
	if (!(lua_isfunction(L, 2) && !lua_iscfunction(L, 2))){
		luaL_error(L,
			"list_targets(>handler<), handler is not a function");
	}
	lua_pushvalue(L, 2);
	intptr_t ref = luaL_ref(L, LUA_REGISTRYINDEX);
	snprintf((char*)ev.ext.message.data,
		COUNT_OF(ev.ext.message.data), ".target_index:id=%d", (int) ref);

	arcan_shmif_enqueue(&G.SHMIF, &ev);

	return 0;
}

typedef struct LoadF {
  int extraline;
  FILE *f;
  char buff[LUAL_BUFFERSIZE];
} LoadF;

static int systemload(lua_State* L)
{
	const char* fn = luaL_checkstring(L, 1);
	bool dieonfail = luaL_optbnumber(L, 2, 1);

	return dirlua_loadfile(L, CLIENTS.dirfd, fn, dieonfail);
}

/* string:target-name, tbl:options, number:clid, handler
 * string:target-name, tbl:options, handler
 */
static int launchtarget(lua_State* L)
{
	const char* name = luaL_checkstring(L, 1);
	if (lua_type(L, 2) != LUA_TTABLE){
		luaL_error(L, "launch_target(name, >option table<, ...) no table provided");
	}

/* options:
 *  - hidden     (when used with [source-name])
 *  - sink-limit (when used with [source-name])
 *  - global     (don't register the source in the appl- specific namespace)
 *  - timeout    (unless source is opened within N seconds, terminate)
 *  - arguments  (packed argstr for sending to target-name)
 *                send it as b64 to avoid interleaving issues with unpacking
 *                the first argument.
 */
	const char* argstr = "";
	struct client* dst = NULL;

	size_t ind = 3;
	if (lua_type(L, 3) == LUA_TNUMBER){
		dst = alua_checkclient(L, 3);
		ind++;
	}

	if (!(lua_isfunction(L, ind) && !lua_iscfunction(L, ind))){
		luaL_error(L, "launch_target(..., >handler<) is not a function");
	}
	intptr_t ref = luaL_ref(L, LUA_REGISTRYINDEX);

/*
 * defining input files from the appl-local store or a nbio is a bit awkward,
 * the options are (for static) to provide [APPL]/ expansion and resolve the
 * file server side, have a force-injected monitor segment that allows us to
 * inject events into the queue of the primary and that gets paired here and
 * mapped to the event handler.
 *
 * that lets us open_nonblock into the thing to supply it with descriptors, and
 * possibly suggest that it should mask BCHUNK_IN coming only from the master
 * so that we can block clients from providing their own to leverage some
 * assumed vulnerability.
 */
	char* req = NULL;
	ssize_t req_len;

	if (!dst){
		req_len = asprintf(&req,
		"launch=%s:id=%"PRIdPTR":args=%s", name, (intptr_t) ref, argstr);
	}
	else {
		req_len = asprintf(&req,
		"launch=%s:dst=%s:id=%"PRIdPTR":args=%s",
		name, dst->ident, (intptr_t) ref, argstr);
	}

	if (req_len < 0){
		lua_pushboolean(L, false);
		return 1;
	}

	arcan_shmif_pushutf8(&G.SHMIF, &(struct arcan_event){
		.category = ARCAN_EVENT(MESSAGE),
	}, req, req_len);
	free(req);

	lua_pushboolean(L, true);
	return 1;
}

static int matchkeys(lua_State* L)
{
/* string:pattern, function: continuation,
 * string:pattern, function: continuation, int: domain
 * continuation(string:key, string:value, bool: last)
 */
	const char* pattern = luaL_checkstring(L, 1);

/* extract and reference continuation */
	if (!(lua_isfunction(L, 2) && !lua_iscfunction(L, 2))){
		luaL_error(L,
			"match_keys(pattern, >handler<, [domain]), handler is not a function");
	}
	lua_pushvalue(L, 2);
	intptr_t ref = luaL_ref(L, LUA_REGISTRYINDEX);

	int domain = luaL_optnumber(L, 3, 0);

	char* req = NULL;
	ssize_t req_len = asprintf(&req,
		"match=%s:domain=%d:id=%"PRIdPTR, pattern, domain, ref);

	if (req_len < 0){
		lua_pushboolean(L, false);
		return 1;
	}

/* use reference as identifier for the callback */
	arcan_shmif_pushutf8(&G.SHMIF, &(struct arcan_event){
		.category = ARCAN_EVENT(MESSAGE),
	}, req, req_len);
	free(req);

	return 0;
}

/*
 * message_target(clid, msg) | message_target(msg, clid) -> true
 */
static int targetmessage(lua_State* L)
{
/* unicast or broadcast? */
	size_t strind = 1;
	struct client* target = NULL;

	if (lua_type(L, 1) == LUA_TNUMBER){
		target = alua_checkclient(L, 1);
		strind = 2;
	}

/* right now this error-outs rather than multipart chunks as the queueing isn't
 * clean enough throughout - with the approach of returning an error */
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

static int acceptnonblock(lua_State* L)
{
/* only valid from within a .load / .store / .index entrypoint and only
 * once per invocation */
	if (!G.in_filereq_handler)
		luaL_error(L,
			"accept_nonblock() - only valid inside client request entrypoint");

	if (G.filereq_handler_ref != -1)
		luaL_error(L,
			"accept_nonblock() - only allowed once within scope of entrypoint");

	int pair[2];
	if (-1 == pipe(pair))
		return 0;

/* send the nbio immediately, the reply to worker will propagate from the
 * originating entrypoint call */
	if (G.in_filereq_handler == O_RDONLY){
		alt_nbio_import(L, pair[1], O_WRONLY, NULL, NULL);
		G.filereq_handler_ref = pair[0];
	}
	else {
		alt_nbio_import(L, pair[0], O_RDONLY, NULL, NULL);
		G.filereq_handler_ref = pair[1];
	}

	return 1;
}

static int reqnonblock(lua_State* L)
{
	if (!(lua_isfunction(L, 3) && !lua_iscfunction(L, 3))){
		luaL_error(L,
			"request_nonblock(name, mode, >handler<), handler is not a function");
	}

	bool write = luaL_checkbnumber(L, 2);
	const char* name = luaL_checkstring(L, 1);

/* register callback, mark in event and queue - when it comes back as BCHUNK
 * the descriptor gets converted to nonblock, callback is triggered and unref */
	lua_pushvalue(L, 3);
	struct arcan_event ev = {
		.category = ARCAN_EVENT(BCHUNKSTATE),
		.ext.bchunk.identifier = luaL_ref(L, LUA_REGISTRYINDEX),
		.ext.bchunk.input = !write,
		.ext.bchunk.ns = NS_NONBLOCK
	};

	snprintf(
		(char*) ev.ext.bchunk.extensions,
		COUNT_OF(ev.ext.bchunk.extensions), "%s", name
	);

	arcan_shmif_enqueue(&G.SHMIF, &ev);
	return 0;
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
		return luaL_error(L, "'tostring' must return a string to 'print'");
		if (i>1)
			fputs("\t", logout);
		fputs(s, logout);
		lua_pop(L, 1);  /* pop result */
	}
	  fputs("\n", logout);

	return 0;
}

static void nbio_error(lua_State* L, int fd, intptr_t tag, const char* src)
{
#ifdef _DEBUG
	fprintf(stderr, "unexpected error in nbio(%s)\n", src);
	dump_stack(L, stdout);
#endif
}

static void open_appl(int dfd, const char* name)
{
/* swap out known dirfd */
	if (-1 != CLIENTS.dirfd)
		close(CLIENTS.dirfd);
	CLIENTS.dirfd = dfd;

	log_print("dir_lua:open=%.*s", (int) sizeof(name), name);
	size_t len = strlen(name);

/* For the dynamic reload case we first run an entrypoint that lets the current
 * scripts shut down gracefully and save any state to be persisted. */
	if (G.L){
		log_print("existing:reset");
		if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_RESET)){
			dirlua_pcall(G.L, 0, 0, panic);
		}

		lua_close(G.L);
		G.L = NULL;
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
	G.L = luaL_newstate();
	lua_atpanic(G.L, (lua_CFunction) panic);

	int rv =
		luaL_loadbuffer(G.L,
		(const char*) arcan_bootstrap_lua,
		arcan_bootstrap_lua_len, "bootstrap"
	);
	if (0 != rv){
		log_print("dir_lua:build_error:bootstrap.lua");
		return;
	}
/* first just setup and parse, don't expose API yet */
	luaL_openlibs(G.L);
	lua_pushcfunction(G.L, print_log);
	lua_setglobal(G.L, "print");
	lua_pcall(G.L, 0, 0, 0);

	dirlua_pcall_prefix(G.L, name);
	char scratch[len + sizeof(".lua")];

/* open, map, load as string */
	snprintf(scratch, sizeof(scratch), "%s.lua", name);
	data_source source = {
		.fd = openat(dfd, scratch, O_RDONLY),
	};
	fchdir(dfd);

	map_region reg = arcan_map_resource(&source, false);

	if (0 == luaL_loadbuffer(G.L, reg.ptr, reg.sz, name)){
		static const luaL_Reg api[] = {
			{"message_target", targetmessage},
			{"store_key", storekeys},
			{"match_keys", matchkeys},
			{"list_targets", listtargets},
			{"launch_target", launchtarget},
			{"system_load", systemload},
			{"request_nonblock", reqnonblock},
			{"accept_nonblock", acceptnonblock},
/*
 * lift from arcan_lua.c:
 *
 *  - launch_decode would be a specialised form of launch_target but with
 *    the same semantics. More interesting is how we initiate this over a
 *    dirsrv network in order to load balance.
 *
 *  - we should also have a keyspace that is distributed so that the main
 *    process can synch that to any directory that joins us (or that we join)
 *    those also need some kind of strata and timestamp on set/synch so that
 *    we can merge / deduplicate.
 */
			{NULL, NULL}
		};
		expose_api(G.L, api);

		alt_nbio_register(G.L, nbio_queue, nbio_dequeue, nbio_error);

/* function already on stack so go directly to pcall */
		dirlua_pcall(G.L, 0, 0, panic);
	}
	arcan_release_map(reg);
	arcan_release_resource(&source);

	if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_MAIN)){
		dirlua_pcall(G.L, 0, 0, panic);
	}

/* re-expose any existing clients, we do this as faked 'join' calls
 * rather than 'adopt' */
	log_print("status=adopt=%zu", CLIENTS.active);
	for (size_t i = 0; i < CLIENTS.set_sz; i++){
		if (!CLIENTS.cset[i].shmif)
			continue;

		if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_JOIN)){
			lua_pushnumber(G.L, CLIENTS.cset[i].clid);
			dirlua_pcall(G.L, 1, 0, panic);
		}
	}
}

static void monitor_sigusr(int sig)
{
	lua_sethook(G.L, dirlua_monitor_watchdog, LUA_MASKCOUNT, 1);
	struct dirlua_monitor_state* state = dirlua_monitor_getstate();
	if (state)
		state->dumppause = true;
}

static bool join_worker(int fd, const char* ident, bool monitor)
{
/* just naively grow, parent process is responsible for more refined handling
 * of constraining resources outside the natural cap of permitted descriptors
 * per process */
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
		.clid = ind,
		.ident = strdup(ident)
	};

/* another subtle thing, shmifsrv_inherit_connection does not actually
 * send the key so do that now. */
	if (ind != 0){
		struct client* cl = &CLIENTS.cset[ind];
		cl->shmif = shmifsrv_inherit_connection(fd, -1, &tmp);
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

/* When the full interface is fleshed out with breakpoints etc. we should
 * ensure that only the one monitor is permitted. This will always happen
 * outside of the Lua VM first, so no reason to set or control hooks. */
		if (monitor){
			cl->registered = true;
			CLIENTS.monitor_slot = ind;
			shmifsrv_enqueue_event(cl->shmif, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_MESSAGE,
				.tgt.message = "#WAITING\n"
				}, -1);

/* monitor tracking state is a heap allocation referenced into TLS to
 * nandle both 'external' (single process) and internal (per-thread)
 * handling of the Lua VM runner */
			dirlua_monitor_allocstate(&G.SHMIF);
			sigaction(SIGUSR1,
				&(struct sigaction){.sa_handler = monitor_sigusr}, 0);
		}
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

/* release any pending hooks or breakpoints if the worker was a monitor */
	if (ind == CLIENTS.monitor_slot){
		CLIENTS.monitor_slot = 0;
		anet_directory_merge_multipart(NULL, NULL, NULL, NULL);
		dirlua_monitor_releasestate(G.L);
	}

/* mark it as available for new join */
	struct client* cl = &CLIENTS.cset[ind];
	close(CLIENTS.pset[ind].fd);
	CLIENTS.pset[ind].fd = -1;
	CLIENTS.active--;

	if (cl->registered){
		if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_LEAVE)){
			lua_pushnumber(G.L, cl->clid);
			dirlua_pcall(G.L, 1, 0, panic);
		}
	}

	log_print("status=left:worker=%zu:ident=%s", cl->clid, cl->ident);
	shmifsrv_free(cl->shmif, SHMIFSRV_FREE_FULL);
	*cl = (struct client){0};
}

static void lua_pushkv_buffer(char* pos, char* end)
{
	assert(pos);
	lua_newtable(G.L);
	if (!pos)
		return;

/* these come in key=value form, set it as a keyed table */
	while (pos < end){
		size_t len = strlen(pos);
		char* key = strchr(pos, '=');
		if (key){
			size_t keylen = (uintptr_t) key - (uintptr_t) pos;
			lua_pushlstring(G.L, pos, keylen);
			lua_pushstring(G.L, &key[1]);
		}
		else{
			lua_pushlstring(G.L, pos, len);
			lua_pushboolean(G.L, true);
		}
		lua_rawset(G.L, -3);
		pos += len + 1;
	}
}

/* SECURITY NOTE:
 * These come from a the higher-privilege level parent, thus malicious use of
 * map_resource, luaL_ref and callbacks etc. isn't considered as anything they
 * can achieve the parent can do through other means.
 */
static void meta_resource(int fd, const char* msg)
{
	if (strncmp(msg, ".worker-", 8) == 0){
		join_worker(fd, &msg[8], false);
		return;
	}
	if (strncmp(msg, ".monitor", 9) == 0){
		join_worker(fd, ".monitor", true);
		return;
	}
/* for the time being, just read everything into a memory buffer and then
 * provide that as a unified strarr - we don't want this blocking when the key
 * domain is distributed and we want to feed all the replies piecemeal so
 * the callback interface has EOF builtin */
	if (strncmp(msg, ".reply=", 7) == 0){
		data_source source = {
		 .fd = fd
		};
		long id = strtoul(&msg[7], NULL, 10);
		map_region reg = arcan_map_resource(&source, false);
		lua_rawgeti(G.L, LUA_REGISTRYINDEX, id);
		if (lua_type(G.L, -1) != LUA_TFUNCTION)
			luaL_error(G.L, "BUG:request_reply into invalid callback");

/* -2 : LUA_TABLE, -1 : LUA_BOOLEAN */
		lua_pushkv_buffer(reg.ptr, reg.ptr + reg.sz);
		lua_pushboolean(G.L, true);

		arcan_release_map(reg);
		arcan_release_resource(&source);
		lua_call(G.L, 2, 0);
		luaL_unref(G.L, LUA_REGISTRYINDEX, id);
	}
	else
		log_print("unhandled:%s\n", msg);
	close(fd);
}

static void route_bchunk_rep(struct arcan_event* ev)
{
	if (ev->tgt.ioevs[4].iv == NS_CLID){
		struct client* cl = &CLIENTS.cset[ev->tgt.ioevs[3].iv];
		shmifsrv_enqueue_event(cl->shmif, ev, ev->tgt.ioevs[0].iv);
	}

/* otherwise NS_NONBLOCK */
	int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, false);
	if (-1 == fd){
		log_print("kind=error:source=dup:bchunk:message=%s", ev->tgt.message);
		return;
	}

	lua_rawgeti(G.L, LUA_REGISTRYINDEX, ev->tgt.ioevs[0].iv);

	if (lua_type(G.L, -1) != LUA_TFUNCTION)
		luaL_error(G.L, "BUG:request_reply:bchunk into invalid callback");

	alt_nbio_import(G.L, fd,
		ev->tgt.kind == TARGET_COMMAND_BCHUNK_IN ? O_RDONLY : O_RDWR, NULL, NULL);

	lua_call(G.L, 1, 0);
	luaL_unref(G.L, LUA_REGISTRYINDEX, ev->tgt.ioevs[0].iv);
}

static void parent_control_event(struct arcan_event* ev)
{
	if (ev->category != EVENT_TARGET)
		return;

#ifdef DEBUG
	log_print("%s", arcan_shmif_eventstr(ev, NULL, 0));
#endif

	switch (ev->tgt.kind){
	case TARGET_COMMAND_BCHUNK_IN:{
/* reply to a worker_file_request, the index is trusted as it comes from
 * ourselves and only routed through a more trusted context. Other id mapping
 * is performed in the worker that is blocking for our response */
		if (ev->tgt.ioevs[4].iv){
			route_bchunk_rep(ev);
			return;
		}

/* duplicate so we keep around */
		int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, false);
		if (ev->tgt.message[0] != '.')
			open_appl(fd, ev->tgt.message);
		else
			meta_resource(fd, ev->tgt.message);
	}
	break;
/* we need a ns selector here when adding open_nonblock as well */
	case TARGET_COMMAND_REQFAIL:{
		if (ev->tgt.ioevs[4].iv == NS_CLID){
			struct client* cl = &CLIENTS.cset[ev->tgt.ioevs[0].iv];
			shmifsrv_enqueue_event(cl->shmif, ev, -1);
		}
/* 32- bit indices are fine here */
		else if (ev->tgt.ioevs[4].iv == NS_NONBLOCK){
			lua_rawgeti(G.L, LUA_REGISTRYINDEX, ev->tgt.ioevs[0].iv);
			if (lua_type(G.L, -1) != LUA_TFUNCTION)
				luaL_error(G.L, "BUG:request_reply:bchunk into invalid callback");
			lua_pushnil(G.L);
			lua_call(G.L, 1, 0);
			luaL_unref(G.L, LUA_REGISTRYINDEX, ev->tgt.ioevs[0].iv);
		}
		break;
	}
	case TARGET_COMMAND_MESSAGE:{
/* No command need MESSAGE right now as match_key replies etc. all go over
 * bchunk-in and pass it that way. */
	}
	case TARGET_COMMAND_BCHUNK_OUT:{
		if (ev->tgt.ioevs[4].iv){
			route_bchunk_rep(ev);
			return;
		}

		if (strcmp(ev->tgt.message, ".log") == 0){
			int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
			logout = fdopen(fd, "w");
			setlinebuf(logout);
			log_print("--- log opened ---");
#ifdef DEBUG
			setenv("ARCAN_SHMIF_DEBUG", "1", true);
#endif
		}
	}
	break;
	case TARGET_COMMAND_EXIT:
		G.shutdown = true;
	break;
	case TARGET_COMMAND_STEPFRAME:
	break;
	default:
	break;
	}
}

static void flush_to_client(struct client* cl)
{
/* flush / pack reply */
	char* out_buf;
	size_t out_sz = dirlua_monitor_flush(&out_buf);
	if (!out_sz)
		return;

/* we should have a blocking version here on overflow, as there is no
 * priority inversion, monitor has equal privilege as this process given
 * eval() */
	struct arcan_event outev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_MESSAGE
	};

	shmifsrv_enqueue_multipart_message(cl->shmif, &outev, out_buf, out_sz);
	fseek(dirlua_monitor_getstate()->out, 0L, SEEK_SET);
}

static void monitor_message(struct client* cl, struct arcan_event* ev)
{
	size_t out_sz;
	char* out_ptr = NULL;
	char* msg_ptr = NULL;

/* merge / buffer event */
	int err;
	if (!anet_directory_merge_multipart(ev, NULL, &msg_ptr, &err))
	{
		if (err)
			log_print("monitor:merge_multipart:error=%d", err);
		return;
	}

/* buffer / apply */
	if (!dirlua_monitor_command(msg_ptr, G.L, NULL))
		log_print("monitor:unhandled_cmd=%s", msg_ptr);

	flush_to_client(cl);
}

static void flush_parent()
{
	struct arcan_event ev;
	if (!arcan_shmif_wait(&G.SHMIF, &ev)){
		G.shutdown = true;
		return;
	}

	parent_control_event(&ev);
	int rv;
	while ((rv = arcan_shmif_poll(&G.SHMIF, &ev) > 0)){
		parent_control_event(&ev);
	}

	if (rv == -1)
		G.shutdown = true;
}

static void worker_file_request(struct client* cl, arcan_event* ev)
{
	arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.ext.bchunk.identifier = cl->clid,
		.ext.bchunk.ns = 1
	};

	int reqev;
	if (ev->ext.bchunk.input){
		int ep = EP_TRIGGER_LOAD;
		reqev = TARGET_COMMAND_BCHUNK_IN;

		outev.ext.bchunk.input = true;
		G.in_filereq_handler = O_RDONLY;

		if (strcmp((const char*) ev->ext.bchunk.extensions, ".index") == 0){
			ep = EP_TRIGGER_INDEX;
		}

		if (dirlua_setup_entrypoint(G.L, ep)){
			lua_pushnumber(G.L, cl->clid);
			MSGBUF_UTF8(ev->ext.bchunk.extensions);
			lua_pushstring(G.L, (char*) ev->ext.bchunk.extensions);

			dirlua_pcall(G.L, 2, 1, panic);
		}
		else
			goto fail;
	}
	else if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_STORE)){
		G.in_filereq_handler = O_WRONLY;
		reqev = TARGET_COMMAND_BCHUNK_OUT;

		lua_pushnumber(G.L, cl->clid);
		MSGBUF_UTF8(ev->ext.bchunk.extensions);
		lua_pushstring(G.L, (char*) ev->ext.bchunk.extensions);
		dirlua_pcall(G.L, 2, 1, panic);
	}
	else
		goto fail;

/* did the script call accept_nonblock in order to dynamically generate? */
	if (G.filereq_handler_ref != -1){
		shmifsrv_enqueue_event(cl->shmif, &(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = reqev,
			.tgt.ioevs[0].iv = ev->ext.bchunk.identifier
		}, G.filereq_handler_ref);
		G.in_filereq_handler = 0;
		G.filereq_handler_ref = -1;
		return;
	}
/* or should we relay to parent? */
	else if (lua_type(G.L, -1) == LUA_TSTRING){
		snprintf(
			(char*) outev.ext.bchunk.extensions,
			COUNT_OF(outev.ext.bchunk.extensions),
			"%s", lua_tostring(G.L, -1)
		);
		arcan_shmif_enqueue(&G.SHMIF, &outev);
		return;
	}

fail:
	shmifsrv_enqueue_event(cl->shmif, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_REQFAIL,
		.tgt.ioevs[0].iv = ev->ext.bchunk.identifier
	}, -1);
}

static void worker_instance_event(struct client* cl, int fd, int revents)
{
	struct arcan_event ev;
	bool flush = false;

	while (1 == shmifsrv_dequeue_events(cl->shmif, &ev, 1)){
		flush = true;
#ifdef DEBUG
		log_print("kind=shmif:source=%zu:data=%s", cl->clid, arcan_shmif_eventstr(&ev, NULL, 0));
#endif

/* Only allow once, registered is ignored if the worker is attached as
 * debugger. cl->ident is provided when the worker requests to join the ctrl to
 * pair requests to parent, netstate is sent here with H(Kpub, applname) to
 * give a persistent identifier that can be used for tracking state */
		if (!cl->registered){
			if (ev.ext.kind == EVENT_EXTERNAL_NETSTATE){
				unsigned char* b64 = a12helper_tob64(ev.ext.netstate.pubk, 32, &(size_t){0});
				snprintf(cl->keyid, COUNT_OF(cl->keyid), "%s", (char*) b64);
				log_print(
					"kind=status:worker=%zu:registered:key=%s", cl->clid, cl->keyid);
				free(b64);
				cl->registered = true;
				if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_JOIN)){
					lua_pushnumber(G.L, cl->clid);
					dirlua_pcall(G.L, 1, 0, panic);
				}
			}
			else {
				log_print("kind=error:worker=%zu:unregistered_event=%s",
					cl->clid, arcan_shmif_eventstr(&ev, NULL, 0));
			}
			continue;
		}

/*
 * Provide an entrypoint for _load, _store and _index. Since we don't have
 * access to our filesystem store the request may need to be deferred, in
 * multiple layers to allow transparent retrieval / caching through linked
 * directory workers.
 *
 * Setup the corresponding entrypoint and provide the desired extensions. If
 * the function returns a string, we forward that as a request to the parent to
 * get a descriptor or REQFAIL back, using .ns to encode clid in order to route
 * the event.
 *
 * If the function returns a nbio from open_nonblock() we instead forward the
 * descriptor from that as the result. This allows the ctrl to have in- memory
 * cache of common files, while at the same time using external lookup oracles
 * (@HASH) to go through a retrieval service.
 */
		if (ev.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
			worker_file_request(cl, &ev);
		}
		else if (ev.ext.kind == EVENT_EXTERNAL_MESSAGE){
			if (cl->clid == CLIENTS.monitor_slot){
				monitor_message(cl, &ev);
			}
			else {
				if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_MESSAGE)){
					lua_newtable(G.L);
					int top = lua_gettop(G.L);
					tblbool(G.L, "multipart", ev.ext.message.multipart, top);
					MSGBUF_UTF8(ev.ext.message.data);
					tbldynstr(G.L, "message", (char*) ev.ext.message.data, top);
					dirlua_pcall(G.L, 2, 0, panic);
				}
			}
		}
	}

	if (shmifsrv_poll(cl->shmif) == CLIENT_DEAD){
		release_worker(cl->clid);
	}

/*
 * only for waking poll, don't care about the data in this direction
 */
	if (flush){
		char buf[256];
		read(fd, buf, 256);
	}
}

static bool flush_worker(struct client* cl, int fd, int revents, size_t ind)
{
	if (!cl->shmif)
		return false;

	worker_instance_event(cl, fd, revents);

/* two possible triggers, one is that poll on the descriptor failed (dead
 * proces) or that shmifsrv_poll has marked it as dead (instance_event) which
 * would come from a proper _EXIT */
	if (revents & (POLLHUP | POLLNVAL)){
		release_worker(ind);
	}

	return true;
}

static bool in_monitor_lock()
{
	struct dirlua_monitor_state* state = dirlua_monitor_getstate();
	return state && state->lock;
}

static void process_nbio_in(lua_State* L)
{
	if (!nbio_jobs.fdin_used)
		return;

	struct pollfd fds[32] = {0};
	size_t ofs = 0;

	for (size_t i = 0; i < 32; i++){
		fds[ofs++] = (struct pollfd){
			.events = POLLIN | POLLERR | POLLNVAL | POLLHUP,
			.fd = nbio_jobs.fdin[i]
		};
	}

	int sv = poll(fds, ofs, 0);
	for (size_t i = 0; i < ofs && sv > 0; i++){
		if (!fds[i].revents)
			continue;

		sv--;
		alt_nbio_data_in(L, nbio_jobs.fdin_tags[i]);
	}
}

void anet_directory_appl_runner()
{
	struct arg_arr* args;
	logout = stdout;

	G.SHMIF = arcan_shmif_open(SEGID_NETWORK_SERVER, shmifopen_flags, &args);
	shmifsrv_monotonic_rebase();

/* shmif connection gets reserved index 0 */
	join_worker(G.SHMIF.epipe, ".main", false);
	int left = 25;

	while (!G.shutdown){
		if (in_monitor_lock()){
			flush_to_client(&CLIENTS.cset[CLIENTS.monitor_slot]);

/* special case: if there's a monitor attached and it holds a global lock, only
 * process that until it disconnects or unlocks. */
			struct pollfd pset[2] = {
				CLIENTS.pset[0],
				CLIENTS.pset[CLIENTS.monitor_slot]
			};
			int pv = poll(pset, 2, -1);
			if (pv > 0){
				if (pset[0].revents)
					flush_parent();
				if (pset[1].revents)
					flush_worker(
						&CLIENTS.cset[CLIENTS.monitor_slot],
						pset[1].fd,
						pset[1].revents, CLIENTS.monitor_slot
					);
			}
			continue;
		}

/*
 * Note that large timeskips will just rebase and not actually trigger a tick,
 * this might be undesired and will happen repeatedly with a debugger attached.
 * Number of backlogged ticks are forwarded as to allow the script to deal with
 * falling behind on timing and only yield one call (as that in turn might
 * trigger monitor conditions).
 */
		int pv = poll(CLIENTS.pset, CLIENTS.set_sz, left);
		int nt = shmifsrv_monotonic_tick(&left);
		if (nt > 0){
			if (dirlua_setup_entrypoint(G.L, EP_TRIGGER_CLOCK)){
				lua_pushnumber(G.L, nt);
				dirlua_pcall(G.L, 1, 0, panic);
			}
		}

		if (in_monitor_lock())
			continue;

		process_nbio_in(G.L);
		nbio_run_outbound(G.L);

/* First prioritize the privileged parent inbound events,
 * and if it's dead we shutdown as well. */
		if (CLIENTS.pset[0].revents){
			flush_parent();
			pv--;
		}

/* Since we have a timer already, and nbio isn't supposed to be for throughput
 * here but rather fringe use to supplement other queueing / transfer
 * mechanisms we do a quick check for the nbio- pollset and run through that
 * aligned roughly with timer ticks. If the need arises we move this to a
 * separate thread + condition variable form */


/* flush out each client, rate-limit comes from queue size caps - need to keep
 * checking the monitor lock so we don't accidentally run ahead and keep
 * calling into VM on error condition. */
		for (size_t i = 1; i < CLIENTS.set_sz && pv > 0; i++){
			if (in_monitor_lock())
				continue;

			if (flush_worker(&CLIENTS.cset[i],
				CLIENTS.pset[i].fd, CLIENTS.pset[i].revents, i)){
				pv--;
			}
		}
	}

	if (G.L)
		lua_close(G.L);

	log_print("parent_exit");
}
