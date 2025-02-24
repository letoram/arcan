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

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <ctype.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"

#include "../../engine/arcan_bootstrap.h"
#include "../../engine/alt/support.h"

/* pull in nbio as it is used in the tui-lua bindings */
#include "../../shmif/tui/lua/nbio.h"

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
	arcan_shmif_pushutf8(&SHMIF, &(struct arcan_event){
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
		arcan_shmif_enqueue(&SHMIF, &beg);
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

		arcan_shmif_enqueue(&SHMIF,
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
		COUNT_OF(ev.ext.message.data), ".target_index:id=%d", ref);

	arcan_shmif_enqueue(&SHMIF, &ev);

	return 0;
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
 *  - timeout    (unless source is opened within N seconds, terminate)
 *  - arguments  (packed argstr for sending to target-name)
 *                send it as b64 to avoid interleaving issues with unpacking
 *                the first argument.
 */
	const char* argstr = "";
	size_t ind = 3;
	if (lua_type(L, 3) == LUA_TNUMBER)
		ind++;

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
	ssize_t req_len = asprintf(&req,
		"launch=%s:id=%"PRIdPTR":args=%s", name, (int) ref, argstr);

	if (req_len < 0){
		lua_pushboolean(L, false);
		return 1;
	}

	arcan_shmif_pushutf8(&SHMIF, &(struct arcan_event){
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
	arcan_shmif_pushutf8(&SHMIF, &(struct arcan_event){
		.category = ARCAN_EVENT(MESSAGE),
	}, req, req_len);
	free(req);

	return 0;
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
		return luaL_error(L, "'tostring' must return a string to 'print'");
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

/* For the dynamic reload case we first run an entrypoint that lets the current
 * scripts shut down gracefully and save any state to be persisted. */
	if (L){
		log_print("existing:reset");
		if (setup_entrypoint(L, "_reset", sizeof("_reset"))){
			wrap_pcall(L, 1, 0);
		}
		lua_close(L);
		L = NULL;
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
			{"store_key", storekeys},
			{"match_keys", matchkeys},
			{"list_targets", listtargets},
			{"launch_target", launchtarget},
/*
 * lift from arcan_lua.c:
 *
 *   - match_keys
 *   - get_key / get_keys
 *   - store_key
 *   - launch_target (with modified semantics to connect source to dirsrv)
 *     this would become something like MESSAGE to parent, get message back
 *     with source identifier, expect the appl to forward this to a connected
 *     client.
 *
 *     Then we can re-use arcan-net + arcan_lwa to loopback connect as a
 *     source execute an appl.
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
		expose_api(L, api);
		wrap_pcall(L, 0, LUA_MULTRET);
	}
	arcan_release_map(reg);
	arcan_release_resource(&source);

/* run script entrypoint */
	if (setup_entrypoint(L, "", 0)){
		wrap_pcall(L, 0, 0);
	}

/* re-expose any existing clients,
 * this can have holes (as _leave will not compact) so linear search */
	log_print("status=adopt=%zu", CLIENTS.active);
	for (size_t i = 0; i < CLIENTS.set_sz; i++){
		if (!CLIENTS.cset[i].shmif)
			continue;

		if (setup_entrypoint(L, "_adopt", sizeof("_adopt"))){
			lua_pushnumber(L, CLIENTS.cset[i].clid);
			wrap_pcall(L, 1, 0);
		}
	}
}

static bool join_worker(int fd)
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

static void lua_pushkv_buffer(char* pos, char* end)
{
	assert(pos);
	lua_newtable(L);
	if (!pos)
		return;

/* these come in key=value form, set it as a keyed table */
	while (pos < end){
		size_t len = strlen(pos);
		char* key = strchr(pos, '=');
		if (key){
			size_t keylen = (uintptr_t) key - (uintptr_t) pos;
			lua_pushlstring(L, pos, keylen);
			lua_pushstring(L, &key[1]);
		}
		else{
			lua_pushlstring(L, pos, len);
			lua_pushboolean(L, true);
		}
		lua_rawset(L, -3);
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
	if (strncmp(msg, ".worker", 8) == 0){
		join_worker(fd);
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
		lua_rawgeti(L, LUA_REGISTRYINDEX, id);
		if (lua_type(L, -1) != LUA_TFUNCTION)
			luaL_error(L, "BUG:request_reply into invalid callback");

/* -2 : LUA_TABLE, -1 : LUA_BOOLEAN */
		lua_pushkv_buffer(reg.ptr, reg.ptr + reg.sz);
		lua_pushboolean(L, true);

		arcan_release_map(reg);
		arcan_release_resource(&source);
		lua_call(L, 2, 0);
		luaL_unref(L, LUA_REGISTRYINDEX, id);
	}
	else
		log_print("unhandled:%s\n", msg);
	close(fd);
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
		int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, false);
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
	case TARGET_COMMAND_MESSAGE:{
/* merge multipart, arg_unpack and extract, if it is key=%s:id= then get from
 * lua_registry and callback into it until we get one with :last set */
	}
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

/* only allow once */
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

/*
 * NAK until we have the client side of file access done.
 *
 * Otherwise .index is an entrypoint for providing a list of known hash=name
 * and then the request goes for the hash. It can also cover an IPFS private
 * key + hash or a public IPFS hash.
 */
		if (ev.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
			if (ev.ext.bchunk.input){
				if (setup_entrypoint(L, "_index", sizeof("_index"))){
					lua_pushnumber(L, cl->clid);
					MSGBUF_UTF8(ev.ext.bchunk.extensions);
					wrap_pcall(L, 2, 1);
				}
			}
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

/* L might not be initialised here yet as it depends on the event delivery */
		while (nt > 0 && L &&
			setup_entrypoint(L, "_clock_pulse", sizeof("_clock_pulse"))){
			wrap_pcall(L, 0, 0);
			nt--;
		}

/* First prioritize the privileged parent inbound events, and if it's dead we
 * shutdown as well. */
		if (CLIENTS.pset[0].revents){
			struct arcan_event ev;
			if (!arcan_shmif_wait(&SHMIF, &ev)){
				SHUTDOWN = true;
				continue;
			}

			parent_control_event(&ev);
			int rv;
			while ((rv = arcan_shmif_poll(&SHMIF, &ev) > 0)){
				parent_control_event(&ev);
			}
			if (rv == -1){
				SHUTDOWN = true;
				continue;
			}

			CLIENTS.pset[0].revents = 0;
			pv--;
		}

/* flush out each client, rate-limit comes from queue size caps */
		for (size_t i = 1; i < CLIENTS.set_sz && pv > 0; i++){
			if (CLIENTS.cset[i].shmif){
				worker_instance_event(
					&CLIENTS.cset[i], CLIENTS.pset[i].fd, CLIENTS.pset[i].revents);

/* two possible triggers, one is that poll on the descriptor failed (dead
 * proces) or that shmifsrv_poll has marked it as dead (instance_event) which
 * would come from a proper _EXIT */
				if (CLIENTS.pset[i].revents & (POLLHUP | POLLNVAL)){
					release_worker(i);
				}

				CLIENTS.pset[i].revents = 0;
			}
		}
	}

	if (L)
		lua_close(L);

	log_print("parent_exit");
}
