#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <errno.h>
#include <arcan_shmif.h>
#include <fcntl.h>
#include <arcan_shmif_server.h>
#include <poll.h>

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <ctype.h>
#include <signal.h>

#include "../a12.h"
#include "../a12_int.h"
#include "../../engine/arcan_mem.h"
#include "../../engine/arcan_db.h"
#include "a12_helper.h"
#include "nbio.h"
#include "external/x25519.h"

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <netdb.h>

#include "anet_helper.h"
#include "directory.h"

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

static lua_State* L;
static struct arcan_dbh* DB;
static struct global_cfg* CFG;
static bool INITIALIZED;

#define A12INT_DIRTRACE(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	struct a12_state tmp_state = {.tracetag = "lua"};\
	struct a12_state* S = &tmp_state;\
\
	dirsrv_global_lock(__FILE__, __LINE__);\
		a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	dirsrv_global_unlock(__FILE__, __LINE__);\
	} while (0);

#define A12INT_DIRTRACE_LOCKED(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	struct a12_state tmp_state = {.tracetag = "lua"};\
	struct a12_state* S = &tmp_state;\
	a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	} while (0);

#define STRINGIFY(X) #X
#define STRINGIFY_WRAP(X) STRINGIFY(X)
#define LINE_AS_STRING __func__, STRINGIFY_WRAP(__LINE__)

struct runner_state {
	pthread_mutex_t lock;
	struct shmifsrv_client* cl;
	struct appl_meta* appl;
	volatile bool alive;
	volatile _Atomic bool appl_sent;
	int store_dfd;
};

struct strrep_meta {
	struct arcan_strarr res;
	int dst;
};

struct client_userdata {
	struct dircl* C;
	bool directory_link;
	intptr_t client_ref;
};

static void fdifd_event(struct shmifsrv_client* C,
	struct arcan_event base, int fd, const char* idstr, const char* prefix)
{
		int idlen = (int) strtol(idstr, NULL, 10);
		snprintf((char*)&base.tgt.message,
			COUNT_OF(base.tgt.message), prefix, idlen);
		shmifsrv_enqueue_event(C, &base, fd);
}

static void dealloc_runner(struct runner_state* runner)
{
	if (0 < runner->store_dfd){
		close(runner->store_dfd);
	}

	free(runner);
}

static void run_detached_thread(void* (*ptr)(void*), void* arg)
{
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pth, &pthattr, ptr, arg);
}

static void send_runner_appl(struct runner_state* runner)
{
	struct arcan_event outev =
	(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
	};

	int srcdir =
		runner->appl->server_appl == SERVER_APPL_TEMP ?
		CFG->dirsrv.appl_server_temp_dfd :
		CFG->dirsrv.appl_server_dfd;

	int dfd = openat(srcdir,
		(char*) runner->appl->appl.name, O_RDONLY | O_DIRECTORY);

	snprintf(outev.tgt.message,
		sizeof(outev.tgt.message), "%s", runner->appl->appl.name);

	shmifsrv_enqueue_event(runner->cl, &outev, dfd);
}

static void launchtarget(struct runner_state* runner,
	struct arcan_dbh* db,
	const char* tgt, const char* ident, int id, struct dircl* dircl)
{
	struct arcan_strarr argv, env, libs = {0};
	enum DB_BFORMAT bfmt;

	arcan_configid cid =
		arcan_db_configid(db, arcan_db_targetid(db, tgt, NULL), "default");

	argv = env = libs;
	char* exec = arcan_db_targetexec(db, cid, &bfmt, &argv, &env, &libs);

	if (!exec){
		A12INT_DIRTRACE("launch_target:eexist=%s", tgt);
		return;
	}

/* libs are ignored as we don't support interposition here */
	A12INT_DIRTRACE("launch_target:prepare_source=%s", tgt);
	anet_directory_dirsrv_exec_source(
		dircl, id, runner->appl->appl.name, exec, &argv, &env);

	free(exec);
	arcan_mem_freearr(&argv);
	arcan_mem_freearr(&libs);
	arcan_mem_freearr(&env);
}

static void* strarr_copy(void* arg)
{
	struct strrep_meta* M = arg;
	char** curr = M->res.data;
	FILE* fout = fdopen(M->dst, "w");
	if (!fout)
		goto out;

/* write each reply with \0 terminated strings blocking */
	while (*curr && !ferror(fout)){
		fputs(*curr, fout);
		fputc('\0', fout);
		curr++;
	}
	fclose(fout);

out:
	arcan_mem_freearr(&M->res);
	free(M);
	return NULL;
}

static void process_file_request(
	struct runner_state* runner, struct arcan_event* ev)
{
	if (-1 == runner->store_dfd)
		goto fail;

/* only alnum permitted ( and . for ext) */
	size_t i = 0;
	for (size_t i = 0;
		i < COUNT_OF(ev->ext.bchunk.extensions) && ev->ext.bchunk.extensions[i]; i++)
		if (!isalnum(ev->ext.bchunk.extensions[i]) &&
			!(i && ev->ext.bchunk.extensions[i] == '.'))
			goto fail;

/* no \0 */
	if (i == COUNT_OF(ev->ext.bchunk.extensions))
		goto fail;

/* unveil / landlock (guuh) gets is responsible for dirtraversal, on top of cap
 * and alphanum limit. ".index" is special as it should also be synched with
 * any links we have, as well as support metadata / hash / signature. */
	int fd = openat(
		runner->store_dfd, (char*) ev->ext.bchunk.extensions,
		ev->ext.bchunk.input ? O_RDONLY : O_RDWR
	);

	if (-1 == fd)
		goto fail;

	shmifsrv_enqueue_event(runner->cl, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = ev->ext.bchunk.input ?
			TARGET_COMMAND_BCHUNK_IN : TARGET_COMMAND_BCHUNK_OUT,
		.tgt.ioevs[3].iv = ev->ext.bchunk.identifier,
/* namespace selector for identifier: dir_lua_appl uses 1 for clid, 2 for nbio */
		.tgt.ioevs[4].iv = ev->ext.bchunk.ns
	}, fd);
	close(fd);

	return;

fail:
	shmifsrv_enqueue_event(runner->cl, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_REQFAIL,
		.tgt.ioevs[0].iv = ev->ext.bchunk.identifier,
		.tgt.ioevs[4].iv = ev->ext.bchunk.ns
	}, -1);
}

static void controller_dispatch(
	struct runner_state* runner, struct arg_arr* arr, struct arcan_dbh* db)
{
 /*
 * setkey=key:val=value:domain or
 * possibly with begin_kv_transaction:domain=%d and terminated with
 * end_kv_transaction, just forward those into arcan_db calls.
 *
 * only domain 0 is interesting now, otherwise for directory network
 * we need to query linked directories as distributed K/V store with
 * timestamp of the request or propagate update with timestamp.
 */
	union arcan_dbtrans_id dbid = {.applname = runner->appl->appl.name};
	const char* arg;
	const char* val;

	if (arg_lookup(arr, "begin_kv_transaction", 0, NULL)){
		arcan_db_begin_transaction(db, DVT_APPL, dbid);
	}
	else if
		(arg_lookup(arr, "setkey", 0, &arg) && arg &&
		 arg_lookup(arr, "value", 0, &val) && val){
			arcan_db_add_kvpair(db, arg, val);
	}
	else if (arg_lookup(arr, "end_kv_transaction", 0, NULL)){
		arcan_db_end_transaction(db);
	}
	else if (arg_lookup(arr, "report_collect", 0, NULL)){
	}
	else if (arg_lookup(arr, "launch", 0, &arg) && arg &&
		arg_lookup(arr, "id", 0, &val) && val){
		int id = (int) strtol(val, NULL, 10);
		struct dircl* dircl = NULL;
		const char* dst = NULL;

/* this is a point to support multicasting by checking for multiple [dst], if
 * so the shmif connection is actually an arcan_lwa that runs a wm appl and
 * then launch_targets the real one. */
		if (arg_lookup(arr, "dst", 0, &dst) && dst){
/* reverse-resolve and ensure the dst is actually in the group */
			dircl = dirsrv_find_cl_ident(runner->appl->identifier, dst);
			if (!dircl){
				A12INT_DIRTRACE("launch_target_directed:badid=%s", dst);
				return;
			}
		}

		arg_lookup(arr, "dst", 0, &dst);
		launchtarget(runner, db, arg, "testsource", id, dircl);
	}
/* trigger the same path as initial ctrl-appl loading */
	else if (arg_lookup(arr, "reload", 0, NULL)){
		send_runner_appl(runner);
	}
	else if (arg_lookup(arr, "match", 0, &arg) && arg &&
		arg_lookup(arr, "domain", 0, NULL) &&
		arg_lookup(arr, "id", 0, &val) && val){
		struct arcan_strarr res =
			arcan_db_applkeys(db, runner->appl->appl.name, arg);

/* sending the replies as events might be saturating the outgoing event queue
 * and thus we always need a fallback with a copy-thread carrying the replies.
 *
 * start with that and consider the fallback later with a delay-queue for
 * making sure that the request end has guaranteed delivery. */
		if (res.count){
			int ppair[2];
			if (-1 == pipe(ppair)){
				fdifd_event(runner->cl, (struct arcan_event)
					{.tgt.kind = TARGET_COMMAND_MESSAGE}, -1, val, "fail:id=%d");
				arcan_mem_freearr(&res);
			}
			else {
				fdifd_event(runner->cl,
					(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_BCHUNK_IN
					}, ppair[0], val, ".reply=%d"
				);
				struct strrep_meta* M = malloc(sizeof(struct strrep_meta));
				M->res = res;
				M->dst = ppair[1];
				close(ppair[0]);
				run_detached_thread(strarr_copy, M);
			}
		}
		else {
			fdifd_event(runner->cl, (struct arcan_event)
				{.tgt.kind = TARGET_COMMAND_MESSAGE}, -1, val, "ok:id=%d");
			arcan_mem_freearr(&res);
		}
	}

/* launch=%d:config=%d would spawn the corresponding target/config as done in
 * normal arcan, but through arcan-net exec with a generated keypair as a
 * source then send the source material back for it to be routed to the client
 * that is supposed to source it. We need a [resource] replacement that gets
 * resolved from the appl- specific namespace and some note that responding to
 * BCHUNK_IN etc. comes from the sink and may be a security concern.
 * We also need to mark if the new source is supposed to be [single-use] and
 * visible to anyone allowed to source, or only the target that the request is
 * possibly intended for. We also need a way to provide the set of defined
 * target/config options.
 */
	else
		A12INT_DIRTRACE("appl_runner=%s:invalid key in message", dbid.applname);

	arg_cleanup(arr);
}

/*
 * This runs in the main privileged process.
 * It routes I/O and database requests for the sandboxed worker
 * in a 1:n thread for each controller-appl process.
 */
static void* controller_runner(void* inarg)
{
	struct runner_state* runner = inarg;

/* lock until the runner state is confirmed */
	pthread_mutex_lock(&runner->lock);
	runner->alive = true;

/* new db connection as they synch over TLS, WAL is probably
 * a good idea here moreso than in regular arcan_db */
	struct arcan_dbh* tl_db =
		arcan_db_open(CFG->db_file, runner->appl->appl.name);

/* wait for the shmif setup to be completed in the client end, this is
 * potentially a priority inversion / unnecessary blocking */
	int pv;
	while ((pv = shmifsrv_poll(runner->cl)) != CLIENT_DEAD){
		if (pv == CLIENT_IDLE)
			break;
	}

	if (pv == CLIENT_DEAD){
		A12INT_DIRTRACE_LOCKED("kind=error:arcan-net:dirappl=broken");
		shmifsrv_free(runner->cl, false);
		runner->alive = false;
		pthread_mutex_unlock(&runner->lock);
		return NULL;
	}

/* create / open designated appl-log */
	if (CFG->dirsrv.appl_logpath){
		char* msg = NULL;
		if (0 < asprintf(&msg, "%s.log", runner->appl->appl.name)){
			int fd = openat(CFG->dirsrv.appl_logdfd, msg, O_RDWR | O_CREAT, 0700);
			if (-1 != fd){
				lseek(fd, 0, SEEK_END);
					shmifsrv_enqueue_event(runner->cl,
						&(struct arcan_event){
							.category = EVENT_TARGET,
							.tgt.kind = TARGET_COMMAND_BCHUNK_OUT,
							.tgt.message = ".log"
						}, fd
					);
				close(fd);
			}
			free(msg);
		}
	}

/* Ready, send the dirfd along with the name to the runner, this is where one
 * would queue up database and secondary namespaces like appl-shared. */
	send_runner_appl(runner);
	atomic_store(&runner->appl_sent, true);

/* main processing loop,
 *
 * keep running as clock for the time being, the option is to allow client
 * events to ping-wakeup or use a signalling pipe for wakeup and liveness
 */
	shmifsrv_monotonic_rebase();
	pthread_mutex_unlock(&runner->lock);

	int sv;
	while((sv = shmifsrv_poll(runner->cl)) != CLIENT_DEAD){
		struct pollfd pfd = {
			.fd = shmifsrv_client_handle(runner->cl, NULL),
			.events = POLLIN | POLLERR | POLLHUP
		};

		struct arcan_event ev;
		while (1 == shmifsrv_dequeue_events(runner->cl, &ev, 1)){

/* coalesce and process request */
			if (ev.ext.kind == EVENT_EXTERNAL_MESSAGE){
				struct arg_arr* arg;
				int err;
				if (!anet_directory_merge_multipart(&ev, &arg, NULL, &err)){
					if (err){
						A12INT_DIRTRACE("kind=error:runner_unpack=%d", err);
					}
					continue;
				}
				controller_dispatch(runner, arg, tl_db);
			}
/* Request a resource from an external oracle (ns > 1) that can resolve e.g. an
 * IPFS hash or a URL. The -identifier- is important as it is what the VM
 * runner is using to route the request back to the proper client. Another
 * complication is that .index need to be built from a glob of the
 * corresponding store. */
			else if (ev.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE)
				process_file_request(runner, &ev);
		}

		int rv = poll(&pfd, 1, -1);
		if (rv & (POLLERR | POLLHUP)){
			A12INT_DIRTRACE("appl_worker=%s:status=dead", runner->appl->appl.name);
			break;
		}
	/* Flush the 'ping' packets */
		else if (rv & POLLIN){
			uint8_t buf[256];
			read(pfd.fd, buf, 256);
		}
	}

	runner->alive = false;
	pthread_mutex_lock(&runner->lock);
		runner->appl->server_tag = NULL;
	pthread_mutex_unlock(&runner->lock);

	arcan_db_close(&tl_db);
	anet_directory_merge_multipart(NULL, NULL, NULL, NULL);
	dealloc_runner(runner);

	return NULL;
}

void anet_directory_lua_exit()
{
	lua_close(L);
	alt_nbio_release();
	L = NULL;
}

static int db_get_key(lua_State* L)
{
	const char* key = luaL_checkstring(L, 1);
	char* val = arcan_db_appl_val(DB, "a12", key);
	if (val){
		lua_pushstring(L, val);
	}
	else
		lua_pushnil(L);

	return 1;
}

static bool lookup_entrypoint(lua_State* L, const char* ep, size_t len)
{
	lua_getglobal(L, ep);

	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return false;
	}

	return true;
}

static void push_dircl(lua_State* L, struct dircl* C)
{
	struct client_userdata* ud = C->userdata;
	lua_rawgeti(L, LUA_REGISTRYINDEX, ud->client_ref);
	if (lua_type(L, -1) != LUA_TUSERDATA)
		luaL_error(L, "invalid reference in client\n");
}

extern int a12_trace_targets;
static int cfg_index(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);

	if (strcmp(key, "allow_tunnel") == 0){
		lua_pushboolean(L, CFG->dirsrv.allow_tunnel);
		return 1;
	}

	if (strcmp(key, "log_level") == 0){
		lua_pushnumber(L, a12_trace_targets);
		return 1;
	}

	luaL_error(L, "unknown key: %s, allowed: allow_tunnel, log_level\n", key);
	return 0;
}

static const char* trace_groups[] = {
	"video",
	"audio",
	"system",
	"event",
	"transfer",
	"debug",
	"missing",
	"alloc",
	"crypto",
	"vdetail",
	"binary",
	"security",
	"directory"
};

static int cfgsec_index(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);

	if (strcmp(key, "secret") == 0){
		lua_pushstring(L, CFG->meta.opts->secret);
		return 1;
	}
	if (strcmp(key, "soft_auth") == 0){
		lua_pushboolean(L, CFG->soft_auth);
		return 1;
	}
	if (strcmp(key, "rekey_bytes") == 0){
		lua_pushnumber(L, CFG->meta.opts->rekey_bytes);
	}

	luaL_error(L, "unknown key: %s, allowed: secret, soft_auth, rekey_bytes\n", key);
	return 0;
}

static bool alua_tobnumber(lua_State* L, int ind, const char* key)
{
	bool state = false;
	if (lua_type(L, ind) == LUA_TBOOLEAN){
		state = lua_toboolean(L, ind);
	}
	else if (lua_type(L, ind) == LUA_TNUMBER){
		int num = lua_tonumber(L, ind);
		if (num != 0 && num != 1)
			luaL_error(L, "%s = [0 | false | true | 1]\n", key);
		state = num == 1;
	}
	else
		luaL_error(L, "%s = [int | bool]\n", key);

	return state;
}

static int cfgsec_newindex(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);
	if (strcmp(key, "secret") == 0){
		const char* val = luaL_checkstring(L, 3);

		if (strlen(val) > 31 || !*val)
			luaL_error(L, "secret = (0 < string < 32)\n");
		snprintf(CFG->meta.opts->secret, 32, "%s", val);
	}
	else if (strcmp(key, "soft_auth") == 0){
		CFG->soft_auth = alua_tobnumber(L, 3, "soft_auth");
	}
	else if (strcmp(key, "rekey_bytes") == 0){
		CFG->meta.opts->rekey_bytes = luaL_checknumber(L, 3);
	}
	else
		luaL_error(L, "unknown key: %s, allowed: secret, soft_auth, rekey_bytes", key);

	return 0;
}

static int cfg_newindex(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);

	if (strcmp(key, "allow_tunnel") == 0){
		CFG->dirsrv.allow_tunnel = alua_tobnumber(L, 3, "allow_tunnel");
	}
	else if (strcmp(key, "flush_report") == 0){
		CFG->dirsrv.flush_on_report = alua_tobnumber(L, 3, "flush_report");
	}
	else if (strcmp(key, "directory_server") == 0){
		if (alua_tobnumber(L, 3, "directory_server")){
			CFG->meta.mode = 1; /* anet_shmif_cl, but with --directory is -l */
			CFG->meta.opts->local_role = ROLE_DIR;
		}
		else {
			CFG->meta.opts->local_role = ROLE_SINK;
		}
		CFG->meta.opts->local_role =
			alua_tobnumber(L, 3, "directory_server") ?
				ROLE_DIR : ROLE_SINK;
	}
	else if (strcmp(key, "discover_beacon") == 0){
		CFG->dirsrv.discover_beacon = alua_tobnumber(L, 3, "discover_beacon");
	}
	else if (strcmp(key, "log_level") == 0){
		if (lua_type(L, 3) == LUA_TTABLE){
			for (size_t i = 0; i < lua_rawlen(L, 3); i++){
				lua_rawgeti(L, 3, i+1);
				if (lua_type(L, -1) == LUA_TSTRING){
					const char* key = lua_tostring(L, -1);
					for (size_t j = 0; j < COUNT_OF(trace_groups); j++){
						if (strcmp(key, trace_groups[j]) == 0){
							a12_trace_targets |= 1 << j;
							break;
						}
						else if (j == COUNT_OF(trace_groups) -1){
							luaL_error(L, "log_level = ... unknown group: %s\n", key);
						}
					}
				lua_pop(L, 1);
				}
				else
					luaL_error(L, "log_level = [num] | {group1str, group2str, ...}\n");
			}
		}
		else if (lua_type(L, 3) == LUA_TNUMBER){
			a12_trace_targets = lua_tonumber(L, 3);
		}
	}
	else if (strcmp(key, "log_target") == 0){
		const char* path = lua_tostring(L, 3);
		FILE* fpek = fopen(path, "w");
		if (!fpek)
			luaL_error(L, "couldn't open (w+): config.log_target = %s\n", path);
		a12_set_trace_level(a12_trace_targets, fpek);
	}
	else if (strcmp(key, "listen_port") == 0){
		int port = lua_tonumber(L, 3);
		if (port <= 0 || port > 65535)
			luaL_error(L, "port (%d) = 0 < n < 65536\n", port);
		char port_str[6];
		snprintf(port_str, 6, "%d", port);
		CFG->meta.port = strdup(port_str);
	}
	else if (strcmp(key, "runner_process") == 0){
		CFG->dirsrv.runner_process = lua_toboolean(L, 3);
	}
	else
		luaL_error(L, "unknown key: config.%s, allowed: "
			"allow_tunnel, discover_beacon, directory_server, "
			"flush_report, log_level, log_target, listen_port, "
			"runner_process\n",
			key
		);

	return 0;
}

static struct {
	const char* key;
	char** val;
} permlut[] = {
	{.key = "source"},
	{.key = "dir"},
	{.key = "appl"},
	{.key = "resources"},
	{.key = "appl_controller"},
	{.key = "admin"},
	{.key = "monitor"},
	{.key = "applhost"},
	{.key = "appl_install"}
};

/* Map the table key indices to their corresponding keyname entries so that
 * a write into the config.permissions[key] will update the related string.
 * On newindex the old will be free()d and new strdup()ed. */
static void build_lookups(struct global_cfg* CFG)
{
	permlut[0].val = &CFG->dirsrv.allow_src;
	permlut[1].val = &CFG->dirsrv.allow_dir;
	permlut[2].val = &CFG->dirsrv.allow_appl;
	permlut[3].val = &CFG->dirsrv.allow_ares;
	permlut[4].val = &CFG->dirsrv.allow_ctrl;
	permlut[5].val = &CFG->dirsrv.allow_admin;
	permlut[6].val = &CFG->dirsrv.allow_monitor;
	permlut[7].val = &CFG->dirsrv.allow_applhost;
	permlut[8].val = &CFG->dirsrv.allow_install;
}

static int cfgperm_index(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);
	for (size_t i = 0; i < COUNT_OF(permlut); i++){
		if (strcmp(permlut[i].key, key) == 0){
			lua_pushstring(L, *permlut[i].val ? *permlut[i].val : "");
			return 1;
		}
	}

	return 0;
}

static int cfgperm_newindex(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);

	for (size_t i = 0; i < COUNT_OF(permlut); i++){
		if (strcmp(permlut[i].key, key) == 0){
			if (permlut[i].val)
				free(*permlut[i].val);
			*permlut[i].val = strdup(luaL_checkstring(L, 3));
			break;
		}
		if (i == COUNT_OF(permlut)){
			luaL_error(L, "Unknown key: permissions.%s\n", key);
		}
	}
	return 0;
}

static int cfgpath_index(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);

	if (strcmp(key, "database") == 0){
		lua_pushstring(L, CFG->db_file);
		return 1;
	}

/* both state, appl and keystore are polluting env. from the legacy/history of
 * being passed via shmif through handover execution and we lack portable
 * primitives for anything better, so re-use that */
	if (strcmp(key, "appl") == 0){
		if (!getenv("ARCAN_APPLBASEPATH"))
			lua_pushnil(L);
		else
			lua_pushstring(L, getenv("ARCAN_APPLBASEPATH"));
		return 1;
	}

	if (strcmp(key, "appl_server_data") == 0){
		if (CFG->dirsrv.appl_server_datapath)
			lua_pushstring(L, CFG->dirsrv.appl_server_datapath);
		else
			lua_pushnil(L);
		return 1;
	}

	if (strcmp(key, "appl_server") == 0){
		if (CFG->dirsrv.appl_server_path){
			lua_pushstring(L, CFG->dirsrv.appl_server_path);
		}
		else
			lua_pushnil(L);
		return 1;
	}

	if (strcmp(key, "appl_server_log") == 0){
		if (CFG->dirsrv.appl_logpath){
			lua_pushstring(L, CFG->dirsrv.appl_logpath);
		}
		else
			lua_pushnil(L);
		return 1;
	}

	if (strcmp(key, "applhost_loader") == 0){
		if (CFG->dirsrv.applhost_path){
			lua_pushstring(L, CFG->dirsrv.applhost_path);
		}
		else
			lua_pushnil(L);
		return 1;
	}

	if (strcmp(key, "keystore") == 0){
		if (INITIALIZED){
			luaL_error(L, "config.keystore read-only after init()");
			return 0;
		}
		if (!getenv("ARCAN_STATEPATH"))
			lua_pushnil(L);
		else
			lua_pushstring(L, getenv("ARCAN_STATEPATH"));
		return 1;
	}

	luaL_error(L, "unknown path: config.paths.%s, "
		"accepted: database, appl, appl_server, "
		"appl_server_log, applhost_loader, keystore, resources\n", key);

	return 0;
}

static int cfgpath_newindex(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);

	if (strcmp(key, "appl") == 0){
		const char* val = luaL_checkstring(L, 3);
		if (-1 != CFG->directory){
			close(CFG->directory);
		}
		CFG->directory = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == CFG->directory){
			luaL_error(L, "config.paths.appl = %s, can't open as directory\n", val);
		}
		fcntl(CFG->directory, F_SETFD, FD_CLOEXEC);
		setenv("ARCAN_APPLBASEPATH", val, 1);
		return 0;
	}
/* set to enable client provided appl controller updates, this is a developer
 * feature, there is a static fallback that requires an explicit synch */
	else if (strcmp(key, "appl_server_temp") == 0){
		const char* val = luaL_checkstring(L, 3);

		if (CFG->dirsrv.appl_server_temp_path){
			free(CFG->dirsrv.appl_server_temp_path);
			close(CFG->dirsrv.appl_server_temp_dfd);
		}

		int dirfd = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == dirfd)
			luaL_error(L, "config.paths.appl_server_temp = %s, can't open as directory\n", val);

		CFG->dirsrv.appl_server_temp_path = strdup(val);
		CFG->dirsrv.appl_server_temp_dfd = dirfd;
		fcntl(dirfd, F_SETFD, FD_CLOEXEC);

		return 0;
	}
	else if (strcmp(key, "applhost_loader") == 0){
		const char* val = luaL_checkstring(L, 3);
		if (CFG->dirsrv.applhost_path){
			free(CFG->dirsrv.applhost_path);
		}
		CFG->dirsrv.applhost_path = strdup(val);

		return 0;
	}
	else if (strcmp(key, "appl_server_data") == 0){
		const char* val = luaL_checkstring(L, 3);

		if (CFG->dirsrv.appl_server_datapath){
			free(CFG->dirsrv.appl_server_datapath);
			close(CFG->dirsrv.appl_server_datadfd);
		}

		int dirfd = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == dirfd)
			luaL_error(L, "config.paths.appl_server_data = %s, can't open as directory\n", val);

		CFG->dirsrv.appl_server_datapath = strdup(val);
		CFG->dirsrv.appl_server_datadfd = dirfd;
		fcntl(dirfd, F_SETFD, FD_CLOEXEC);

		return 0;
	}
	else if (strcmp(key, "appl_server") == 0){
		const char* val = luaL_checkstring(L, 3);

		if (CFG->dirsrv.appl_server_path){
			free(CFG->dirsrv.appl_server_path);
			close(CFG->dirsrv.appl_server_dfd);
		}

		int dirfd = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == dirfd)
			luaL_error(L, "config.paths.appl_server = %s, can't open as directory\n", val);

		CFG->dirsrv.appl_server_path = strdup(val);
		CFG->dirsrv.appl_server_dfd = dirfd;
		fcntl(dirfd, F_SETFD, FD_CLOEXEC);

		return 0;
	}
	else if (strcmp(key, "applhost") == 0){
	}
	else if (strcmp(key, "appl_server_log") == 0){
		const char* val = luaL_checkstring(L, 3);
		if (CFG->dirsrv.appl_logpath){
			free(CFG->dirsrv.appl_logpath);
			close(CFG->dirsrv.appl_logdfd);
		}

		CFG->dirsrv.appl_logpath = strdup(val);
		CFG->dirsrv.appl_logdfd = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == CFG->dirsrv.appl_logdfd)
			luaL_error(L, "config.paths.appl_server_log = %s, can't open as directory\n", val);
		fcntl(CFG->dirsrv.appl_logdfd, F_SETFD, FD_CLOEXEC);

		return 0;
	}
	else if (strcmp(key, "resources") == 0){
		const char* val = luaL_checkstring(L, 3);

		if (CFG->dirsrv.resource_path){
			free(CFG->dirsrv.resource_path);
			close(CFG->dirsrv.resource_dfd);
		}

		int dirfd = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == dirfd)
			luaL_error(L, "config.paths.appl_server = %s, can't open as directory\n", val);

		CFG->dirsrv.resource_path = strdup(val);
		CFG->dirsrv.resource_dfd = dirfd;
		fcntl(dirfd, F_SETFD, FD_CLOEXEC);

		return 0;
	}

/* remaining keys are read-only after init */
	if (INITIALIZED)
		luaL_error(L, "config.paths.%s, read/only after init()\n", key);

	if (strcmp(key, "database") == 0){
		const char* val = luaL_checkstring(L, 3);
		if (CFG->db_file)
			free(CFG->db_file);
		CFG->db_file = strdup(val);
	}
	else if (strcmp(key, "keystore") == 0){
		const char* val = luaL_checkstring(L, 3);
		int dirfd = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == dirfd)
			luaL_error(L, "config.paths.keystore = %s, can't open as directory\n", val);

		if (CFG->meta.keystore.directory.dirfd > 0)
			close(CFG->meta.keystore.directory.dirfd);

		CFG->meta.keystore.directory.dirfd = dirfd;
		fcntl(dirfd, F_SETFD, FD_CLOEXEC);
		setenv("ARCAN_STATEPATH", val, 1);
	}
	else {
		luaL_error(L,
			"unknown path key (%s), accepted:\n\t\n", key,
			"database, appl, appl_server, keystore, resources\n");
	}

	return 0;
}

static int dir_index(lua_State* L)
{
	return 0;
}

static int dir_newindex(lua_State* L)
{
	return 0;
}

/*
 * This is mostly the same as for the ctrl- appl version, though the uses for
 * this are more limited.
 *
 * Difference:
 *   - always global namespace (makes no sense launch ctrl specific from here)
 *   - callback handler is about the process management of the runner itself.
 */
static int dir_launchtarget(lua_State* L)
{
	const char* name = luaL_checkstring(L, 1);
	if (lua_type(L, 2) != LUA_TTABLE){
		luaL_error(L, "launch_target(name, >option table<, ...) no table provided");
	}

/*
 * size_t ind = 3;
 *
 * launch to one specific client
 * options for specifying identity, this is simpler than in the regular
 * launchtarget form as we do have access to dircl from userdata
 *
	if (lua_type(L, 3) == LUA_TUSERDATA){
		ind++;
	}
 */

	struct appl_meta appl = {0};
	struct runner_state runner = {.appl = &appl, .store_dfd = -1};
	snprintf(appl.appl.name, COUNT_OF(appl.appl.name), "%s", name);

/* runner is faked here as it doesn't come from a ctrl */
	launchtarget(&runner, DB, name, "_config", 0, NULL);
	return 0;
}

static int spawn_dirwork(lua_State* L, char* tag, char* argv[], const char* pref)
{
/* Ensure that the link_directory target is referenced in the keystore
 * and treat it as fatal if it is not. */
	uint8_t private[32];
	char* tmp;
	uint16_t tmpport;

	if (!a12helper_keystore_hostkey(tag, 0, private, &tmp, &tmpport))
		luaL_error(L, "%s: >tag=%s< not found in keystore", pref, tag);

	if (lua_type(L, 2) != LUA_TFUNCTION)
		luaL_error(L, "%s: tag, >callback< missing", pref);

/* take a reference to the callback, we bind that to the userdata for the
 * client process we create for the outbound directory connection. */
	lua_pushvalue(L, 2);
	intptr_t ref = luaL_ref(L, LUA_REGISTRYINDEX);

/* We now have enough information to spin up the worker and have it make the
 * outbound connection - this is a separate _worker.c implementation to split
 * out propagation options. This worker will use the keystore again to make the
 * actual outbound connection > then < privsep. */
	struct shmifsrv_envp env = {
		.init_w = 32,
		.init_h = 32,
		.path = CFG->path_self,
		.envv = NULL,
		.argv = argv,
		.detach = 2 | 4 | 8
	};

	int clsock;
	struct shmifsrv_client* S = shmifsrv_spawn_client(env, &clsock, NULL, 0);
	free(tag);

	if (!S){
		A12INT_DIRTRACE_LOCKED("kind=error:arcan-net:dirappl_spawn");
		luaL_unref(L, LUA_REGISTRYINDEX, ref);
		return 0;
	}

/* bind userdata similar to _lua_register and return that here, we don't have
 * an A12 state but it's only used here to extract the endpoint for (accept ->
 * build a12-state -> handover to worker) and the real remote endpoint is
 * retrieved after connecting. */
	struct dircl* cl = anet_directory_shmifsrv_thread(S, NULL, true);
	struct client_userdata* ud = lua_newuserdata(L, sizeof(struct client_userdata));

	ud->C = cl;
	cl->lua_cb = ref;
	cl->userdata = ud;
	ud->directory_link = true;

	lua_pushvalue(L, -1);
	ud->client_ref = luaL_ref(L, LUA_REGISTRYINDEX);

/* and assign the table of client actions */
	luaL_getmetatable(L, "dircl");
	lua_setmetatable(L, -2);

	return 1;
}

static int dir_refdirectory(lua_State* L)
{
	char* tag = strdup(luaL_checkstring(L, 1));
	char* argv[] = {CFG->path_self, "dirref", tag, NULL};

	return spawn_dirwork(L, tag, argv, "reference_directory");
}

static int dir_linkdirectory(lua_State* L)
{
	char* tag = strdup(luaL_checkstring(L, 1));
	char* argv[] = {CFG->path_self, "dirlink", tag, NULL};

	return spawn_dirwork(L, tag, argv, "link_directory");
}

void anet_directory_lua_event(struct dircl* C, struct dirlua_event* ev)
{
	if (C->lua_cb == LUA_NOREF)
		return;

	lua_rawgeti(L, LUA_REGISTRYINDEX, C->lua_cb);
	if (lua_type(L, -1) != LUA_TFUNCTION){
		luaL_error(L, "client-to-lua: reference is not a function");
		lua_pop(L, 1);
		return;
	}

	if (ev->kind == DIRLUA_EVENT_LOST){
		push_dircl(L, C); /* +1 */
		lua_newtable(L);
			lua_pushstring(L, "kind");
			lua_pushstring(L, "terminated");
			lua_rawset(L, -3);

			lua_pushstring(L, "last_words");
			lua_pushstring(L, ev->msg);
			lua_rawset(L, -3);

		lua_call(L, 2, 0);
	}
}

/*
 * since this is only intended for admin channel
 * there is little need for pulling in the full alt_nbio here
 */
static int dir_write(lua_State* L)
{
	struct client_userdata* ud = luaL_checkudata(L, 1, "dircl");
	if (!ud->C)
		luaL_error(L, ":write(ud) not bound to a client");

	const char* msg = luaL_checkstring(L, 2);
	if (ud->C->admin_fdout <= 0)
		luaL_error(L, ":write(ud) client does not have a write channel");

/* this is blocking, since it's an admin that is allowed */
	size_t ntw = strlen(msg) + 1;
	while (ntw){
		ssize_t nw = write(ud->C->admin_fdout, msg, ntw);
		if (-1 == nw){
			if (errno != EINTR && errno != EAGAIN)
				break;
			continue;
		}
		msg += nw;
		ntw -= nw;
	}

	lua_pushboolean(L, ntw == 0);
	return 1;
}

static int dir_endpoint(lua_State* L)
{
	struct client_userdata* ud = luaL_checkudata(L, 1, "dircl");
	if (!ud->C)
		luaL_error(L, ":write(ud) not bound to a client");

	lua_pushstring(L, ud->C->endpoint.ext.netstate.name);
	return 1;
}

static int dir_matchkeys(lua_State* L)
{
	const char* pattern = luaL_checkstring(L, 1);
	struct arcan_strarr res =
		arcan_db_applkeys(DB, "directory", pattern);

	lua_newtable(L);
	if (res.data){
		char** curr = res.data;
		size_t count = 1;

		while (*curr){
			lua_pushnumber(L, count++);
			lua_pushstring(L, *curr++);
			lua_rawset(L, -3);
		}

		arcan_mem_freearr(&res);
	}

	return 1;
}

static int dir_appllist(lua_State* L)
{
	lua_newtable(L);
	struct appl_meta* M = &CFG->dirsrv.dir;

	while (M){
		lua_pushstring(L, "id");
		lua_pushnumber(L, M->identifier);
		lua_rawset(L, -3);

		lua_pushstring(L, "name");
		lua_pushstring(L, M->appl.name);
		lua_rawset(L, -3);

		lua_pushstring(L, "timestamp");
		lua_pushnumber(L, M->update_ts);
		lua_rawset(L, -3);

		lua_pushstring(L, "runner_active");
		lua_pushboolean(L, M->server_tag != NULL);
		lua_rawset(L, -3);

		M = M->next;
	}

	return 1;
}

static int dir_flushreport(lua_State* L)
{
	const char* applname = luaL_checkstring(L, 1);
	dirsrv_flush_report(applname);
	return 0;
}

static int dir_getkey(lua_State* L)
{
	char* val = arcan_db_appl_val(DB, "directory", luaL_checkstring(L, 1));
	if (val){
		lua_pushstring(L, val);
		free(val);
	}
	else
		lua_pushnil(L);

	return 1;
}

/*
 * similar to engine/lua.c
 * but hardcoded domain
 */
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

static int dir_storekey(lua_State* L)
{
	union arcan_dbtrans_id dbid = {.applname = "directory"};
	arcan_db_begin_transaction(DB, DVT_APPL, dbid);

	if (lua_type(L, 1) == LUA_TTABLE){

		lua_pushnil(L);
		while (lua_next(L, 1) != 0){
			const char* key = lua_tostring(L, -2);
			if (!validate_key(key))
				luaL_error(L,
					"store_keys(>tbl<, %s - invalid key (alphanum, no +/_=", key);
			const char* val = lua_tostring(L, -1);
			arcan_db_add_kvpair(DB, key, val);
			lua_pop(L, 1);
		}

		arcan_db_end_transaction(DB);
		return 0;
	}

	const char* key = luaL_checkstring(L, 1);
	const char* value = luaL_checkstring(L, 2);
	arcan_db_add_kvpair(DB, key, value);
	arcan_db_end_transaction(DB);

	return 0;
}

/*
 * NBIO handlers, don't need them currently as the admin interface only uses
 * it for :writes and we clock differently
 */
static bool add_source(int fd, mode_t mode, intptr_t otag)
{
	return true;
}
static bool del_source(int fd, mode_t mode, intptr_t* out)
{
	return true;
}
static void error_nbio(lua_State* L, int fd, intptr_t tag, const char* src)
{
}

static int ctrl_dirfd(struct appl_meta* appl)
{
	if (CFG->dirsrv.appl_server_datadfd == -1)
		return -1;

	return openat(
		CFG->dirsrv.appl_server_datadfd,
		appl->appl.name,
		O_RDONLY | O_DIRECTORY
	);

	return -1;
}

void anet_directory_lua_trigger_auto(struct appl_meta* appl)
{
	lua_getglobal(L, "autostart");
	if (lua_type(L, -1) != LUA_TTABLE){
		lua_pop(L, 1);
		return;
	}

	for (size_t i = 0; i < lua_rawlen(L, -1); i++){

		lua_rawgeti(L, -1, i+1); /* TTABLE */
		const char* name = luaL_checkstring(L, -1); /* TTABLE[i+1], TTABLE */
		struct appl_meta* cur = appl;

/* this is being called in a locked state */
		while (cur){
			if (strcmp(cur->appl.name, name) == 0){

/* don't spawn multiples if there's duplicates in the table */
				if (cur->server_appl != SERVER_APPL_NONE && !cur->server_tag){
					if (!cur->server_tag){
						anet_directory_lua_spawn_runner(cur, CFG->dirsrv.runner_process);
					}
				}

				break;
			}

			cur = cur->next;
		}

		lua_pop(L, 1); /* TTABLE[i+1], TTABLE */
	}

/* -1, TTABLE */
	lua_pop(L, 1);
}

bool anet_directory_lua_init(struct global_cfg* cfg)
{
	L = luaL_newstate();
	CFG = cfg;
	build_lookups(cfg);

	if (!L){
		fprintf(stderr, "luaL_newstate() - failed\n");
		return false;
	}

	luaL_openlibs(L);

/* when a client is registered it automatically gets an nbio as well */
	alt_nbio_register(L, add_source, del_source, error_nbio);

	luaL_newmetatable(L, "dircl");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__newindex");
	lua_pushcfunction(L, dir_write);
	lua_setfield(L, -2, "write");
	lua_pushcfunction(L, dir_endpoint);
	lua_setfield(L, -2, "endpoint");
	lua_pop(L, 1);

	luaL_newmetatable(L, "cfgtbl");
	lua_pushcfunction(L, cfg_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, cfg_newindex);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);

	luaL_newmetatable(L, "cfgpermtbl");
	lua_pushcfunction(L, cfgperm_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, cfgperm_newindex);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);

	luaL_newmetatable(L, "cfgsectbl");
	lua_pushcfunction(L, cfgsec_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, cfgsec_newindex);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);

	luaL_newmetatable(L, "cfgpathtbl");
	lua_pushcfunction(L, cfgpath_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, cfgpath_newindex);
	lua_setfield(L, -2, "__newindex");
	lua_pop(L, 1);

/*
 * build "config" which will contain the current config.
 *
 * then call 'init' which lets the script in 'fn' mutate 'config',
 * open 'DB' and then expose the database accessor functions.
 */
	lua_newtable(L); /* TABLE */
	luaL_getmetatable(L, "cfgtbl");
	lua_setmetatable(L, -2);

/* add permissions table to config */
	lua_pushstring(L, "permissions"); /* TABLE(cfgtbl), STRING */
	lua_createtable(L, 0, 10); /* TABLE (cfgtbl), "permissions", TABLE */
	luaL_getmetatable(L, "cfgpermtbl");
	lua_setmetatable(L, -2);
	lua_rawset(L, -3); /* TABLE(cfgperm) */

/* add security table to config */
	lua_pushstring(L, "security"); /* TABLE(cftbl), STRING */
	lua_createtable(L, 0, 10); /* TABLE (cfgtbl), "security", TABLE */
	luaL_getmetatable(L, "cfgsectbl");
	lua_setmetatable(L, -2);
	lua_rawset(L, -3); /* TABLE(cfgtbl) */

/* add paths table to config */
	lua_pushstring(L, "paths"); /* TABLE(cfgtbl), STRING */
	lua_createtable(L, 0, 10); /* TABLE(cfgtbl), "paths", TABLE */
	luaL_getmetatable(L, "cfgpathtbl");
	lua_setmetatable(L, -2); /* TABLE(cfgtbl), "paths", TABLE(cfgpath) */
	lua_rawset(L, -3); /* TABLE(cfgtbl) */

	lua_setglobal(L, "config"); /* nil */

/* expose autostart table, when appls are scanned we will sweep it and
 * launch any present with a match in the ctrl- set that have yet to be
 * started in trigger_auto() */
	lua_newtable(L);
	lua_setglobal(L, "autostart");

/*
 * expose higher- level admin function for managing trust store, make
 * outbound connections and so on.
 */
	lua_pushcfunction(L, dir_linkdirectory);
	lua_setglobal(L, "link_directory");

	lua_pushcfunction(L, dir_refdirectory);
	lua_setglobal(L, "reference_directory");

	lua_pushcfunction(L, dir_launchtarget);
	lua_setglobal(L, "launch_target");

	lua_pushcfunction(L, dir_matchkeys);
	lua_setglobal(L, "match_keys");

	lua_pushcfunction(L, dir_storekey);
	lua_setglobal(L, "store_key");

	lua_pushcfunction(L, dir_getkey);
	lua_setglobal(L, "get_key");

	lua_pushcfunction(L, dir_flushreport);
	lua_setglobal(L, "flush_report");

	lua_pushcfunction(L, dir_appllist);
	lua_setglobal(L, "list_appl");

	if (cfg->config_file){
		int status = luaL_dofile(L, cfg->config_file);
		if (0 != status){
			const char* msg = lua_tostring(L, -1);
			fprintf(stderr, "%s: failed, %s\n", cfg->config_file, msg);
			return false;
		}

		if (lookup_entrypoint(L, "init", 4)){
			if (0 != lua_pcall(L, 0, 0, 0)){
				fprintf(stderr, "%s: failed, %s\n", cfg->config_file, lua_tostring(L, -1));
				return false;
			}
		}
	}

/*
 * we want the database open regardless to deal with keystore scripts */
	INITIALIZED = true;
	DB = arcan_db_open(cfg->db_file, NULL);
	if (!DB){
		fprintf(stderr,
			"Couldn't open database, check config.paths.database and permissions\n");
		return false;
	}

	return true;
}

bool anet_directory_lua_admin_command(struct dircl* C, const char* msg)
{
	lua_getglobal(L, "admin_command");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return false;
	}

	struct arg_arr* arg = arg_unpack(msg);

/* we are already locked here so no race-risk on trace and shouldn't use the
 * guard macro as that would deadlock */
	if (!arg){
		A12INT_DIRTRACE_LOCKED("kind=error:malformed_admin_command=%s", msg);
		lua_pop(L, 1);
		return false;
	}

/* it would be better to actually force this to use shmifpack format
 * and add the generic arg_arr to lua table here instead */
	push_dircl(L, C);

/* convert to table of tables (ignore collision handling and treat value
 * as a table in its own so the scripting side is consistent) */
	size_t pos = 0;
	lua_newtable(L);

	while (arg[pos].key != NULL){
		lua_getfield(L, -1, arg[pos].key);

/* no matching table for the key, create one and leave a ref on the stack */
		if (lua_type(L, -1) != LUA_TTABLE){
			lua_pop(L, 1);                     /* TABLE NIL */
			lua_pushstring(L, arg[pos].key);   /* TABLE STRING(key) */
			lua_newtable(L);                   /* TABLE STRING(key) TABLE */
			lua_rawset(L, -3);                 /* TABLE */
			lua_getfield(L, -1, arg[pos].key); /* TABLE TABLE */
		}

		int len = lua_rawlen(L, -1); /* get max index */
		lua_pushnumber(L, len + 1); /* TABLE TABLE INT(n) */

		if (arg[pos].value && arg[pos].value[0])
			lua_pushstring(L, arg[pos].value);
		else
			lua_pushboolean(L, true);

		/* TABLE TABLE INT(n) VAL */
		lua_rawset(L, -3); /* TABLE */
		lua_pop(L, 1);

		pos++;
	}

	arg_cleanup(arg);
	lua_call(L, 2, 0);
	return true;
}

int anet_directory_lua_filter_source(struct dircl* C, arcan_event* ev)
{
/* look for the entrypoint */
	lua_getglobal(L, "new_source");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return 0;
	}

	push_dircl(L, C); /* +1 */
	lua_pushstring(L, ev->ext.netstate.name); /* +2 : caller guarantees termination */

	switch(ev->ext.netstate.type){ /* +3 */
	case ROLE_DIR: lua_pushstring(L, "directory"); break;
	case ROLE_SOURCE:	lua_pushstring(L, "source"); break;
	case ROLE_SINK: lua_pushstring(L, "sink"); break;
	default:
		lua_pushstring(L, "unknown_role");
	break;
	}

/* script errors should perhaps be treated more leniently in the config,
 * copy patterns from arcan_lua.c if so, but for the time being be strict */
	lua_call(L, 3, 0);

	return 1;
}

struct pk_response
	anet_directory_lua_register_unknown(
	struct dircl* C, struct pk_response base, const char* pubk)
{
	lua_getglobal(L, "register_unknown");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return base;
	}

	push_dircl(L, C);  /* +1 */
	lua_call(L, 1, 1); /* accept or reject? */
	if (lua_type(L, -1) == LUA_TBOOLEAN){
		base.authentic = lua_toboolean(L, -1);
	}

	lua_pop(L, 1);
	return base;
}

static void* thread_appl_runner(void* tag)
{
	anet_directory_appl_runner();
	return NULL;
}

bool anet_directory_signal_runner(struct appl_meta* appl, int sig)
{
	struct runner_state* runner = appl->server_tag;

	if (!runner)
		return false;

	int pid;
	shmifsrv_client_handle(runner->cl, &pid);
	return kill(pid, sig) == 0;
}

void anet_directory_lua_update(struct appl_meta* appl, int newappl)
{
/* newappl contains the packed (unauthenticated) appl from an authenticated
 * source. If we have an active runner we should send the new BCHUNK_IN to the
 * unpacked directory. This is where we can support rollback to the on- disk
 * version should the new one break anything. */
	struct runner_state* runner = appl->server_tag;

/*
 * unpack: this blocks the server and is not desired in the long run.
 */
	FILE* applf = fdopen(newappl, "r");
	const char* err;

	char name[sizeof(appl->appl.name)];
	for (size_t i = 0; i < sizeof(appl->appl.name); i++){
		name[i] = appl->appl.name[i];
	}

	if (!extract_appl_pkg(applf,
		CFG->dirsrv.appl_server_temp_dfd, name, &err)){
			fclose(applf);
			A12INT_DIRTRACE_LOCKED("kind=error:dirappl_unpack=%s", err);
		return;
	}

/*
 * we don't have a running session so switching is a no-op, it'll be used on
 * next join that spawns a runner
 */
	if (!runner){
		return;
	}

/*
 * for the runner we re-send the BCHUNK_IN entrypoint with the applname,
 * that will case the lua_appl end to reseed the VM
 */
	struct arcan_event outev =
		(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
		};

	int srcdir = appl->server_appl == SERVER_APPL_TEMP ?
		CFG->dirsrv.appl_server_temp_dfd : CFG->dirsrv.appl_server_dfd;

	int dfd = openat(srcdir, name, O_RDONLY | O_DIRECTORY);

	snprintf(outev.tgt.message, sizeof(outev.tgt.message), "%s", appl->appl.name);

	pthread_mutex_lock(&runner->lock);
		shmifsrv_enqueue_event(runner->cl, &outev, dfd);
	pthread_mutex_unlock(&runner->lock);

	A12INT_DIRTRACE_LOCKED("kind=status:dirappl_update=%s", appl->appl.name);
}

bool anet_directory_lua_spawn_runner(struct appl_meta* appl, bool external)
{
	int clsock;
	struct runner_state* runner = malloc(sizeof(struct runner_state));
	*runner = (struct runner_state){.appl = appl, .store_dfd = ctrl_dirfd(appl)};

	if (external){
		char* argv[] = {CFG->path_self, "dirappl", NULL, NULL};
		struct shmifsrv_envp env = {
			.init_w = 32,
			.init_h = 32,
			.path = CFG->path_self,
			.envv = NULL,
			.argv = argv,
			.detach = 2 | 4 | 8
		};
		runner->cl = shmifsrv_spawn_client(env, &clsock, NULL, 0);
		if (!runner->cl){
			A12INT_DIRTRACE_LOCKED("kind=error:arcan-net:dirappl_spawn");
			dealloc_runner(runner);
			return false;
		}

		appl->server_tag = runner;
		pthread_mutex_init(&runner->lock, NULL);
		run_detached_thread(controller_runner, runner);

/* block until the process is spawned and the appl has been sent so we don't
 * get ordering issues with the first worker joining when the VM isn't ready */
		bool done = false;
		while(!done){
			pthread_mutex_lock(&runner->lock);
			done = atomic_load(&runner->appl_sent);
			pthread_mutex_unlock(&runner->lock);
		}
		return true;
	}

	int sv[2];
	if (-1 == socketpair(AF_UNIX, SOCK_STREAM, 0, sv)){
		A12INT_DIRTRACE_LOCKED("kind=error:socketpair.2=%d", errno);
		dealloc_runner(runner);
		return false;
	}
	int sc;
	runner->cl = shmifsrv_inherit_connection(sv[0], -1, &sc);
	if (!runner->cl){
		A12INT_DIRTRACE_LOCKED("kind=error:couldn't build preauth shmif");
		close(sv[0]);
		dealloc_runner(runner);
		return false;
	}

/*
 * Safety Note:
 * ------------
 *  Running the ctrl- appl state machine as part of the main process
 *  is intended to make debugging easier in environments that deal
 *  poorly with stepping across fork/exec.
 *
 *  To facilitate this we do some trickery with environment variables,
 *  and these will be mutated by the thread_appl_runner which is not
 *  safe in POSIX.
 */
	A12INT_DIRTRACE_LOCKED("kind=warning:unsafe_in_process_ctrl_runner");
	unsetenv("ARCAN_CONNPATH");
	char buf[8];
	snprintf(buf, 8, "%d", sv[1]);
	setenv("ARCAN_SOCKIN_FD", buf, 1);
	snprintf(buf, 8, "%d", shmifsrv_client_memory_handle(runner->cl));
	setenv("ARCAN_SOCKIN_SHMFD", buf, 1);

	run_detached_thread(thread_appl_runner, NULL);
	appl->server_tag = runner;
	pthread_mutex_init(&runner->lock, NULL);
	run_detached_thread(controller_runner, runner);

	return true;
}

static bool send_join_pair(
	struct dircl* C, struct appl_meta* appl, char* msg, char* workmsg)
{
	struct runner_state* runner = appl->server_tag;
	if (!runner){
		A12INT_DIRTRACE_LOCKED("kind=api-error:join called without runner");
		return false;
	}

/* Note:
 *
 * There is a quirk here in that the BCHUNK_IN isn't actually a new segment but
 * behaves like a named connection where the memory page needs to be read from
 * the socket.
 */
	int sv[2];
	if (-1 == socketpair(AF_UNIX, SOCK_STREAM, 0, sv)){
		A12INT_DIRTRACE_LOCKED("kind=error:socketpair.2=%d", errno);
		return false;
	}

	struct arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_BCHUNK_IN
	};
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", msg);

	pthread_mutex_lock(&runner->lock);
		shmifsrv_enqueue_event(runner->cl, &ev, sv[0]);
/* monitor doesn't result in IDENT so mark is as in-appl here */
		C->in_appl = appl->identifier;
		if (strcmp(msg, ".monitor") == 0)
			C->in_monitor = true;

	pthread_mutex_unlock(&runner->lock);

	ev = (struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_BCHUNK_IN
	};
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", workmsg);

	shmifsrv_enqueue_event(C->C, &ev, sv[1]);

	A12INT_DIRTRACE_LOCKED("kind=status:worker_join=%s", C->endpoint.ext.netstate.name);

	close(sv[0]);
	close(sv[1]);
	return true;
}

bool anet_directory_lua_monitor(struct dircl* C, struct appl_meta* appl)
{
	return send_join_pair(C, appl, ".monitor", ".monitor");
}

/* this expects the appl- lock to be in effect so we can't use INTTRACE */
bool anet_directory_lua_join(struct dircl* C, struct appl_meta* appl)
{
	char buf[sizeof(".appl-") + strlen(appl->appl.name)];
	snprintf(buf, sizeof(buf),  ".appl-%s", appl->appl.name);
	char wbuf[sizeof(".worker-") + strlen(C->identity)];
	snprintf(wbuf, sizeof(wbuf), ".worker-%s", C->identity);

	return send_join_pair(C, appl, wbuf, buf);
}

void anet_directory_lua_unregister(struct dircl* C)
{
/* protect against misuse */
	if (!C->userdata)
		return;

/* is a callback is even desired */
	lua_getglobal(L, "unregister");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return;
	}

	push_dircl(L, C); /* +1 */
	lua_call(L, 1, 0);

/* disassociate and unreference */
	struct client_userdata* ud = C->userdata;
	ud->C = NULL;
	C->userdata = NULL;

/* also shouldn't happen */
	if (ud->client_ref == LUA_NOREF)
		return;

	luaL_unref(L, LUA_REGISTRYINDEX, ud->client_ref);
	ud->client_ref = LUA_NOREF;
}

void anet_directory_lua_register(struct dircl* C)
{
	lua_getglobal(L, "register");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return;
	}

/* track a reference in the client structure, used for metatable functions */
	struct client_userdata* ud = lua_newuserdata(L, sizeof(struct client_userdata));
	ud->C = C;
	C->userdata = ud;

	lua_pushvalue(L, -1);
	ud->client_ref = luaL_ref(L, LUA_REGISTRYINDEX);

/* and assign the table of client actions */
	luaL_getmetatable(L, "dircl");
	lua_setmetatable(L, -2);

/* now it's safe to re-retrieve and call */
	lua_call(L, 1, 0);
	return;
}

void anet_directory_lua_ready(struct global_cfg* cfg)
{
	lua_getglobal(L, "ready");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return;
	}

	lua_call(L, 0, 0);
}
