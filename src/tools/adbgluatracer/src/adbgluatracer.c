#define _POSIX_C_SOURCE 200812L
#define _GNU_SOURCE

#include <threads.h>
#include <dlfcn.h>
#include <lualib.h>
#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_listwnd.h>
#include <arcan_tui_bufferwnd.h>
#include <stdlib.h>
#include <errno.h>
#include "../../../shmif/arcan_shmif_debugif.h"

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

enum LuaQuery {
	LQ_DONE,
	LQ_GC_STAT,
	LQ_GLOBAL_LIST,
	LQ_GLOBAL_SHOW,
};

enum TracerView {
	TV_NONE,
	TV_MAIN,
	TV_GC,
	TV_GLOBAL_LIST,
	TV_GLOBAL_SHOW,
};

struct LuaTraceCtx {
	struct arcan_shmif_cont cont;
	enum TracerView tv;
	enum TracerView last_tv;
	size_t tv_tag;


// Lua thread synchronisation primitives
	cnd_t lua_cnd;
	mtx_t lua_mtx;

// Lua thread input
	int lua_query;
	char* global_key;

// Lua thread output
	int gccount;
	size_t n_globals;
	int globals_capacity;
	struct tui_list_entry* globals_list;
	char** globals_keys;
	char* value;
	size_t value_len;
	size_t value_capacity;
};

static struct LuaTraceCtx lua_trace_ctx = { 0 };

static void set_value_buffer_size(size_t len)
{
	lua_trace_ctx.value_len = len;
	if (len < lua_trace_ctx.value_capacity) return;

	free(lua_trace_ctx.value);

	unsigned int v = len + 1;
	v--;
	v |= v >> 1;
	v |= v >> 2;
	v |= v >> 4;
	v |= v >> 8;
	v |= v >> 16;
	v++;
	lua_trace_ctx.value_capacity = v;

	lua_trace_ctx.value = malloc((len + 1) * sizeof(char));
}

static void lua_list_globals(lua_State *L)
{
	int i = 0;
	int n_globals = 0;

	lua_pushnil(L);
	while (lua_next(L, LUA_GLOBALSINDEX) != 0) {
		n_globals++;
		lua_pop(L, 1);
	}

	for (int j=0; j<lua_trace_ctx.n_globals; j++) {
		free(lua_trace_ctx.globals_keys[j]);
		free(lua_trace_ctx.globals_list[j].label);
	}
	if (n_globals > lua_trace_ctx.globals_capacity) {
		free(lua_trace_ctx.globals_list);
		free(lua_trace_ctx.globals_keys);
		lua_trace_ctx.globals_list = malloc(n_globals * sizeof(struct tui_list_entry));
		lua_trace_ctx.globals_keys = malloc(n_globals * sizeof(char*));
		lua_trace_ctx.globals_capacity = n_globals;
	}
	lua_trace_ctx.n_globals = n_globals;

	lua_pushnil(L);
	while (lua_next(L, LUA_GLOBALSINDEX) != 0) {
		size_t len;
		const char* key;
		if (lua_type(L, -2) == LUA_TSTRING) {
			key = lua_tolstring(L, -2, &len);
			lua_trace_ctx.globals_list[i].attributes = 0;
			lua_trace_ctx.globals_keys[i] = malloc((len + 1) * sizeof(char));
			strncpy(lua_trace_ctx.globals_keys[i], key, len + 1);
		} else {
			key = lua_typename(L, lua_type(L, -2));
			len = strlen(key);
			lua_trace_ctx.globals_list[i].attributes = LIST_PASSIVE;
			lua_trace_ctx.globals_keys[i] = 0;
		}

		size_t label_len = len + 12 + 1;
		const char* value_type = lua_typename(L, lua_type(L, -1));

		lua_trace_ctx.globals_list[i].shortcut = NULL;
		lua_trace_ctx.globals_list[i].indent = 0;
		lua_trace_ctx.globals_list[i].tag = i;
		lua_trace_ctx.globals_list[i].label = malloc(label_len * sizeof(char));
		snprintf(lua_trace_ctx.globals_list[i].label, label_len, "[%10s]%s",
			value_type, key);

		lua_pop(L, 1);
		i++;
	}
}

static void lua_show_global(lua_State *L)
{
	lua_getglobal(L, lua_trace_ctx.global_key);

	const char* value;
	const char* pointer_type;
	int type = lua_type(L, -1);

	switch (type) {
		case LUA_TNIL:
			set_value_buffer_size(3);
			snprintf(lua_trace_ctx.value, lua_trace_ctx.value_capacity, "nil");
			break;
		case LUA_TBOOLEAN:
			if (lua_toboolean(L, -1)) {
				set_value_buffer_size(4);
				snprintf(lua_trace_ctx.value, lua_trace_ctx.value_capacity, "true");
			} else {
				set_value_buffer_size(5);
				snprintf(lua_trace_ctx.value, lua_trace_ctx.value_capacity, "false");
			}

			break;
		case LUA_TNUMBER:
			lua_pushvalue(L, -1);
			value = lua_tolstring(L, -1, &lua_trace_ctx.value_len);
			set_value_buffer_size(lua_trace_ctx.value_len);
			strncpy(lua_trace_ctx.value, value, lua_trace_ctx.value_capacity);
			lua_pop(L, 1);
			break;
		case LUA_TSTRING:
			value = lua_tolstring(L, -1, &lua_trace_ctx.value_len);
			set_value_buffer_size(lua_trace_ctx.value_len);
			strncpy(lua_trace_ctx.value, value, lua_trace_ctx.value_capacity);
			break;
		case LUA_TLIGHTUSERDATA:
		case LUA_TTABLE:
		case LUA_TFUNCTION:
		case LUA_TUSERDATA:
		case LUA_TTHREAD:
			pointer_type = lua_typename(L, type);
			set_value_buffer_size(32);
			lua_trace_ctx.value_len =
				snprintf(lua_trace_ctx.value, lua_trace_ctx.value_capacity, "%s#%p",
				         pointer_type, lua_topointer(L, -1));
			break;
	}

	lua_pop(L, 1);
}

static void line_hook(lua_State *L, lua_Debug *ar)
{
	if (LQ_DONE) return;
	mtx_lock(&lua_trace_ctx.lua_mtx);

	switch (lua_trace_ctx.lua_query) {
		case LQ_DONE:
			break;
		case LQ_GC_STAT:
			lua_trace_ctx.gccount = lua_gc(L, LUA_GCCOUNT, 0);
			break;
		case LQ_GLOBAL_SHOW:
			lua_show_global(L);
			break;
		case LQ_GLOBAL_LIST:
			lua_list_globals(L);
			break;
	};

	lua_trace_ctx.lua_query = LQ_DONE;
	mtx_unlock(&lua_trace_ctx.lua_mtx);
	cnd_signal(&lua_trace_ctx.lua_cnd);
};

static enum TracerView tracer_view_global_list(void* tui, enum TracerView last_tv, size_t* pos, size_t* tag)
{
	if (last_tv == TV_MAIN) {
		mtx_lock(&lua_trace_ctx.lua_mtx);
		lua_trace_ctx.lua_query = LQ_GLOBAL_LIST;
		cnd_wait(&lua_trace_ctx.lua_cnd, &lua_trace_ctx.lua_mtx);
		mtx_unlock(&lua_trace_ctx.lua_mtx);
	}

	if (last_tv != TV_GLOBAL_LIST) {
		arcan_tui_ident(tui, "Global variables");
		arcan_tui_listwnd_setup(tui, lua_trace_ctx.globals_list, lua_trace_ctx.n_globals);
		arcan_tui_listwnd_setpos(tui, *pos);
	}

	struct tui_list_entry* ent = NULL;
	if (!arcan_tui_listwnd_status(tui, &ent)) return TV_GLOBAL_LIST;

	*pos = arcan_tui_listwnd_tell(tui);
	arcan_tui_listwnd_release(tui);

	if (ent) {
		*tag = ent->tag;
		return TV_GLOBAL_SHOW;
	} else {
		*tag = 0;
		*pos = 0;
		return TV_MAIN;
	}
}

static enum TracerView tracer_view_global_show(void* tui, enum TracerView last_tv, size_t tag)
{
	mtx_lock(&lua_trace_ctx.lua_mtx);
	lua_trace_ctx.lua_query = LQ_GLOBAL_SHOW;
	lua_trace_ctx.global_key = lua_trace_ctx.globals_keys[tag];
	cnd_wait(&lua_trace_ctx.lua_cnd, &lua_trace_ctx.lua_mtx);
	mtx_unlock(&lua_trace_ctx.lua_mtx);
	printf("[%ld : %ld] \"%s\"\n", lua_trace_ctx.value_len, lua_trace_ctx.value_capacity, lua_trace_ctx.value);

	if (last_tv == TV_GLOBAL_SHOW) {
		if (arcan_tui_bufferwnd_status(tui) != 1) {
			arcan_tui_bufferwnd_release(tui);
			return TV_GLOBAL_LIST;
		}

		arcan_tui_bufferwnd_synch(tui, (uint8_t*)lua_trace_ctx.value,
		                          lua_trace_ctx.value_len, 0);
		return TV_GLOBAL_SHOW;
	} else {
		struct tui_bufferwnd_opts opts = {
			.read_only = true,
			.view_mode = BUFFERWND_VIEW_ASCII,
			.allow_exit = true,
		};
		arcan_tui_ident(tui, lua_trace_ctx.globals_list[tag].label);
		arcan_tui_bufferwnd_setup(tui, (uint8_t*)lua_trace_ctx.value,
		                          lua_trace_ctx.value_len, &opts, sizeof(opts));
		return TV_GLOBAL_SHOW;
	}
}

static enum TracerView tracer_view_gc(void* tui, enum TracerView last_tv)
{
	mtx_lock(&lua_trace_ctx.lua_mtx);
	lua_trace_ctx.lua_query = LQ_GC_STAT;
	cnd_wait(&lua_trace_ctx.lua_cnd, &lua_trace_ctx.lua_mtx);
	mtx_unlock(&lua_trace_ctx.lua_mtx);

	char buf[64];
	snprintf(buf, COUNT_OF(buf), "GC usage: %d kB",
		lua_trace_ctx.gccount);

	if (last_tv == TV_GC) {
		if (arcan_tui_bufferwnd_status(tui) != 1) {
			arcan_tui_bufferwnd_release(tui);
			return TV_MAIN;
		}

		arcan_tui_bufferwnd_synch(tui, (uint8_t*)buf, strlen(buf), 0);
	} else {
		struct tui_bufferwnd_opts opts = {
			.read_only = true,
			.view_mode = BUFFERWND_VIEW_ASCII,
			.allow_exit = true,
		};
		arcan_tui_ident(tui, "GC stats");
		arcan_tui_bufferwnd_setup(tui, (uint8_t*)buf, strlen(buf), &opts, sizeof(opts));
	}

	return TV_GC;
}

static enum TracerView tracer_view_main(void* tui, enum TracerView last_tv, size_t* pos)
{
	enum MenuEntry {
		ME_GLOBALS,
		ME_GC,
	};

	struct tui_list_entry lents[] = {
		{
			.label = "Global variables",
			.tag = ME_GLOBALS,
		},
		{
			.label = "GC stats",
			.tag = ME_GC,
		},
	};

	if (last_tv != TV_MAIN) {
		arcan_tui_ident(tui, "Lua tracer");
		arcan_tui_listwnd_setup(tui, lents, COUNT_OF(lents));
		arcan_tui_listwnd_setpos(tui, *pos);
	}

	struct tui_list_entry* ent = NULL;
	if (!arcan_tui_listwnd_status(tui, &ent)) return TV_MAIN;

	arcan_tui_listwnd_release(tui);

	if (!ent) return TV_NONE;

	switch (ent->tag) {
		case ME_GLOBALS:
			*pos = 0;
			return TV_GLOBAL_LIST;
		case ME_GC:
			*pos = 1;
			return TV_GC;
		default:
			return TV_MAIN;
	}
}

static void process_handler(void* tui, void* tag)
{
	lua_State **lua_ctx = dlsym(RTLD_DEFAULT, "main_lua_context");
	if (!lua_ctx) return;
	lua_sethook(*lua_ctx, &line_hook, LUA_MASKLINE, 0);

	cnd_init(&lua_trace_ctx.lua_cnd);
	mtx_init(&lua_trace_ctx.lua_mtx, mtx_plain);

	enum TracerView last_tv = TV_NONE;
	enum TracerView tv = TV_MAIN;
	size_t tv_pos = 0;
	size_t tv_tag = 0;

	for (;;) {
		struct tui_process_res res = arcan_tui_process((struct tui_context**)&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK) {
			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL) {
				break;
			}
		}

		enum TracerView tmp_tv = tv;
		switch (tv) {
			case TV_MAIN:
				tv = tracer_view_main(tui, last_tv, &tv_pos);
				break;
			case TV_GC:
				tv = tracer_view_gc(tui, last_tv);
				break;
			case TV_GLOBAL_LIST:
				tv = tracer_view_global_list(tui, last_tv, &tv_pos, &tv_tag);
				break;
			case TV_GLOBAL_SHOW:
				tv = tracer_view_global_show(tui, last_tv, tv_tag);
				break;
			case TV_NONE:
				return;
		}
		last_tv = tmp_tv;
	}
}

void __attribute__((constructor)) adbgluatracer_setup()
{
	struct arg_arr* args;
	unsetenv("LD_PRELOAD");

	struct arcan_shmif_cont ct = arcan_shmif_open(SEGID_TUI, 0, &args);

	arcan_shmif_debugint_spawn(&ct, NULL,
		&(struct debugint_ext_resolver){
		.handler = process_handler,
		.label = "Lua tracer",
		.tag = NULL
	});

	lua_trace_ctx.cont = ct;
}

void __attribute__((destructor)) adbgluatracer_teardown()
{
/* something less crude than this would be nice */
	while (arcan_shmif_debugint_alive()) {
		sleep(1);
	}
}
