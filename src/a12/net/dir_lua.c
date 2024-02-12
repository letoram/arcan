#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <errno.h>
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>

#include "../a12.h"
#include "../../engine/arcan_mem.h"
#include "../../engine/arcan_db.h"
#include "nbio.h"

#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>

#include "anet_helper.h"
#include "directory.h"

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

static lua_State* L;
static struct arcan_dbh* DB;
static struct global_cfg* CFG;
static bool INITIALIZED;

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
/* should probably bind C to userdata, retain the tag in dircl and
 * use that to recall the same reference until it's gone */
	lua_newtable(L);
	luaL_getmetatable(L, "dircl");
	lua_setmetatable(L, -2);
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
	else
		luaL_error(L, "unknown key: config.%s, allowed: "
			"allow_tunnel, directory_server, log_level, log_target, listen_port\n", key);

	return 0;
}

static bool got_permlut;
static struct {
	const char* key;
	char** val;
} permlut[] = {
	{.key = "source"},
	{.key = "dir"},
	{.key = "appl"},
	{.key = "resources"}
};

static void build_lookups(struct global_cfg* CFG)
{
	permlut[0].val = &CFG->dirsrv.allow_src;
	permlut[1].val = &CFG->dirsrv.allow_dir;
	permlut[2].val = &CFG->dirsrv.allow_appl;
	permlut[3].val = &CFG->dirsrv.allow_ares;
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

	if (strcmp(key, "appl") == 0){
		if (!getenv("ARCAN_APPLBASEPATH"))
			lua_pushnil(L);
		else
			lua_pushstring(L, getenv("ARCAN_APPLBASEPATH"));
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
		"accepted: database, appl, appl_server, appl_server_log, keystore, resources\n", key);

	return 0;
}

static int cfgpath_newindex(lua_State* L)
{
	const char* key = luaL_checkstring(L, 2);

/* both state, appl and keystore are polluting env. from the legacy/history of
 * being passed via shmif through handover execution and we lack portable
 * primitives for anything better, so re-use that */
	if (strcmp(key, "appl") == 0){
		const char* val = luaL_checkstring(L, 3);
		if (-1 != CFG->directory){
			close(CFG->directory);
		}
		CFG->directory = open(val, O_RDONLY | O_DIRECTORY);
		if (-1 == CFG->directory){
			luaL_error(L, "config.paths.appl = %s, can't open as directory\n", val);
		}
		CFG->dirsrv.flag_rescan = 1;
		setenv("ARCAN_APPLBASEPATH", val, 1);
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
		return 0;
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

	luaL_newmetatable(L, "dircl");
	lua_pushcfunction(L, dir_index);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, dir_newindex);
	lua_setfield(L, -2, "__newindex");
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

int anet_directory_lua_filter_source(struct dircl* C, arcan_event* ev)
{
/* look for the entrypoint */
	lua_getglobal(L, "new_source");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return 0;
	}

/* call event + type into it */
	push_dircl(L, C);
	lua_pushstring(L, ev->ext.netstate.name); /* caller guarantees termination */
	if (ev->ext.netstate.type == ROLE_DIR)
		lua_pushstring(L, "directory");
	else if (ev->ext.netstate.type == ROLE_SOURCE)
		lua_pushstring(L, "source");
	else if (ev->ext.netstate.type == ROLE_SINK)
		lua_pushstring(L, "sink");

/* script errors should perhaps be treated more leniently in the config,
 * copy patterns from arcan_lua.c if so, but for the time being be strict */
	lua_call(L, 3, 0);

	return 1;
}

struct pk_response
	anet_directory_lua_register_unknown(struct dircl* C, struct pk_response base)
{
	lua_getglobal(L, "register_unknown");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return base;
	}

	push_dircl(L, C);
	lua_call(L, 1, 1);
	if (lua_type(L, -1) == LUA_TBOOLEAN){
		base.authentic = lua_toboolean(L, -1);
	}

	lua_pop(L, 1);
	return base;
}

bool anet_directory_lua_join(struct dircl* C, struct appl_meta* appl)
{
	struct shmifsrv_client* runner = appl->server_tag;

/* no active runner, launch */
	if (!runner){
		char* argv[] = {CFG->path_self, "dirappl", NULL, NULL};
		struct shmifsrv_envp env = {
			.path = CFG->path_self,
			.envv = NULL,
			.argv = argv,
			.detach = 2 | 4 | 8
		};

/* open the directory to the server appl */
		int clsock;
		runner = shmifsrv_spawn_client(env, &clsock, NULL, 0);
		if (!runner){
			a12int_trace(
				A12_TRACE_DIRECTORY, "kind=error:arcan-net:dirappl_spawn");
			return false;
		}
		int pid;
		shmifsrv_client_handle(runner, &pid);
		a12int_trace(
				A12_TRACE_DIRECTORY,
				"kind=status:arcan-ent:dirappl=%s:pid=%d", appl->appl.name, pid);

/* wait for the shmif setup to be completed in the client end, this is
 * potentially a priority inversion / unnecessary blocking */
		int pv;
		while ((pv = shmifsrv_poll(runner)) != CLIENT_DEAD){
			if (pv == CLIENT_IDLE)
				break;
		}

		if (pv == CLIENT_DEAD){
			a12int_trace(
				A12_TRACE_DIRECTORY, "kind=error:arcan-net:dirappl=broken");
			shmifsrv_free(runner, false);
			return false;
		}

/* create / open designated appl-log */
		if (CFG->dirsrv.appl_logpath){
			char* msg;
			if (0 < asprintf(&msg, "%s.log", appl->appl.name)){
				int fd = openat(CFG->dirsrv.appl_logdfd, msg, O_RDWR | O_CREAT, 0700);
				if (-1 != fd){
					lseek(fd, 0, SEEK_END);
						shmifsrv_enqueue_event(runner, &(struct arcan_event){
						.category = EVENT_TARGET,
						.tgt.kind = TARGET_COMMAND_BCHUNK_OUT,
						.tgt.message = ".log"
					}, fd);
					close(fd);
				}
				free(msg);
			}
		}

/* Ready, send the dirfd along with the name to the runner, this is where one
 * would queue up database and secondary namespaces like appl-shared. */
		struct arcan_event outev =
		(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
		};
		int dfd = openat(
			CFG->dirsrv.appl_server_dfd, appl->appl.name, O_RDONLY | O_DIRECTORY);
		snprintf(outev.tgt.message, sizeof(outev.tgt.message), "%s", appl->appl.name);
		shmifsrv_enqueue_event(runner, &outev, dfd);
 	}

/* send the server-end to the appl-runner which will shmifsrv_inherit, when
 * that happens the other end of the socket will send the shmif primitives to
 * the worker. */
	int sv[2];
	if (-1 == socketpair(AF_UNIX, SOCK_STREAM, 0, sv)){
		a12int_trace(A12_TRACE_DIRECTORY, "kind=error:socketpair.2=%d", errno);
		shmifsrv_free(runner, true);
		return false;
	}

	shmifsrv_enqueue_event(runner, &(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
			.tgt.message = ".worker"
	}, sv[0]);

	shmifsrv_enqueue_event(C->C, &(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_NEWSEGMENT,
	}, sv[1]);

	a12int_trace(A12_TRACE_DIRECTORY,
		"kind=status:worker_join=%s", C->endpoint.ext.netstate.name);
	close(sv[0]);
	close(sv[1]);

	appl->server_tag = runner;
	return true;
}

void anet_directory_lua_register(struct dircl* C)
{
	lua_getglobal(L, "register");
	if (!lua_isfunction(L, -1)){
		lua_pop(L, 1);
		return;
	}

	push_dircl(L, C);
	lua_call(L, 1, 0);
	return;
}
