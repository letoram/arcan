/* Copyright: Björn Ståhl
 * License: 3-clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: This adds a naive mapping to the TUI API for Lua scripting.
 * Simply append- the related functions to a Lua context, and you should be
 * able to open/connect using tui_open() -> context.
 *
 * TODO:
 *   [ ] detached (virtual) windows
 *   [ ] PUSH new_window
 *   [ ] nbio to bufferwnd?
 *   [ ] screencopy (src, dst, ...)
 *   [ ] tpack to buffer
 *   [ ] tunpack from buffer
 *   [ ] cross-window blit
 *   [ ] apaste/vpaste does nothing - map to bchunk_in?
 *   [ ] Hasglyph
 */

#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_listwnd.h>
#include <arcan_tui_bufferwnd.h>
#include <arcan_tui_linewnd.h>
#include <arcan_tui_readline.h>

#include <assert.h>
#include <stdbool.h>
#include <fcntl.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <errno.h>
#include <string.h>
#include <strings.h>
#include <poll.h>

#include "tui_lua.h"
#include "nbio.h"
#include "tui_popen.h"

#define TUI_METATABLE	"Arcan TUI"

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

static const uint32_t req_cookie = 0xfeed;
static struct tui_cbcfg shared_cbcfg = {};

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

/*
 * convenience macro prolog for all TUI callbacks
 */
#define SETUP_HREF(X, B) \
	struct tui_lmeta* meta = t;\
	lua_State* L = meta->lua;\
	if (meta->href == LUA_NOREF)\
		return B;\
	lua_rawgeti(L, LUA_REGISTRYINDEX, meta->href);\
	lua_getfield(L, -1, X);\
	if (lua_type(L, -1) != LUA_TFUNCTION){\
		lua_pop(L, 2);\
		return B;\
	}\
	lua_rawgeti(L, LUA_REGISTRYINDEX, meta->tui_state);\

#define END_HREF lua_pop(L, 1);

#define RUN_CALLBACK(X, Y, Z) do {\
	if (0 != lua_pcall(L, (Y), (Z), 0)){\
		luaL_error(L, lua_tostring(L, -1));\
	}\
} while(0);

static const char* udata_list[] = {
	TUI_METATABLE,
	"widget_readline",
	"widget_listview",
	"widget_bufferview",
	"nonblockIO",
	"nonblockIOs"
};

/* this limit is imposed by arcan_tui_process, more could be supported by
 * implementing the multiplexing ourselves but it is really a sign that the
 * wrong interface is used when things get this large. */
#define LIMIT_JOBS 32

/* Shared between all windows and used in process() call */
static struct {
	int fdin[LIMIT_JOBS];
	intptr_t fdin_tags[LIMIT_JOBS];
	size_t fdin_used;

	struct pollfd fdout[LIMIT_JOBS];
	intptr_t fdout_tags[LIMIT_JOBS];
	size_t fdout_used;
} nbio_jobs;

/* just used for dump_stack, pos can't be relative */
static const char* match_udata(lua_State* L, ssize_t pos){
	lua_getmetatable(L, pos);

	for (size_t i = 0; i < COUNT_OF(udata_list); i++){
		luaL_getmetatable(L, udata_list[i]);
		if (lua_rawequal(L, -1, -2)){
			lua_pop(L, 2);
			return udata_list[i];
		}
		lua_pop(L, 1);
	}

	lua_pop(L, 1);
	return NULL;
}

__attribute__((used))
static void dump_traceback(lua_State* L)
{
	lua_getglobal(L, "debug");
	lua_getfield(L, -1, "traceback");
	lua_call(L, 0, 1);
	const char* trace = lua_tostring(L, -1);
	printf("%s\n", trace);
	lua_pop(L, 1);
}

static void register_tuimeta(lua_State* L);

__attribute__((used))
static void dump_stack(lua_State* ctx)
{
	int top = lua_gettop(ctx);
	fprintf(stderr, "-- stack dump (%d)--\n", top);

	for (size_t i = 1; i <= top; i++){
		int t = lua_type(ctx, i);

		switch (t){
		case LUA_TBOOLEAN:
			fprintf(stderr, lua_toboolean(ctx, i) ? "true" : "false");
		break;
		case LUA_TSTRING:
			fprintf(stderr, "%zu\t'%s'\n", i, lua_tostring(ctx, i));
			break;
		case LUA_TNUMBER:
			fprintf(stderr, "%zu\t%g\n", i, lua_tonumber(ctx, i));
			break;
		case LUA_TUSERDATA:{
			const char* type = match_udata(ctx, i);
			if (type)
				fprintf(stderr, "%zu\tuserdata:%s\n", i, type);
			else
				fprintf(stderr, "%zu\tuserdata(unknown)\n", i);
		}
		break;
		default:
			fprintf(stderr, "%zu\t%s\n", i, lua_typename(ctx, t));
			break;
		}
	}

	fprintf(stderr, "\n");
}

/*
 * convenience macro prolog for all TUI window bound lua->c functions
 * the different versions will block based on which widget state the
 * context is in (e.g. TUI_LWNDDATA, TUI_BWNDDATA) in order to make
 * sure no data handler accidentally corrupts or interferes.
 */
#define TUI_WNDDATA	\
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);\
	if (!ib || !ib->tui || ib->widget_mode != TWND_NORMAL)\
		luaL_error(L, "window not in normal state");\

#define TUI_UDATA \
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);\
	if (!ib || !ib->tui) {\
		luaL_error(L, !ib ? "no userdata" : "no tui context"); \
	}\

#define TUI_LWNDDATA \
	struct widget_meta* meta = luaL_checkudata(L, 1, "widget_listview");\
	if (!meta || !meta->parent)\
		luaL_error(L, "listview: API error, widget metadata freed");\
	struct tui_lmeta* ib = meta->parent;\
	if (!ib || !ib->tui || ib->widget_mode != TWND_LISTWND)\
		luaL_error(L, "listview: API error, not in listview state");

#define TUI_BWNDDATA \
	struct widget_meta* meta = luaL_checkudata(L, 1, "widget_bufferview");\
	if (!meta || !meta->parent)\
		luaL_error(L, "bufferview: API error, widget metadata freed");\
	struct tui_lmeta* ib = meta->parent;\
	if (!ib || !ib->tui || ib->widget_mode != TWND_BUFWND)\
		luaL_error(L, "bufferview: API error, not in bufferview state");

#define TUI_READLINEDATA \
	struct widget_meta* meta = luaL_checkudata(L, 1, "widget_readline");\
	if (!meta || !meta->parent)\
		luaL_error(L, "widget metadata freed");\
	struct tui_lmeta* ib = meta->parent;\
	if (!ib || !ib->tui || ib->widget_mode != TWND_READLINE)\
		luaL_error(L, "window not in readline state");

static void init_lmeta(lua_State* L, struct tui_lmeta* l, struct tui_lmeta* p)
{
	*l = (struct tui_lmeta){
		.widget_closure = LUA_NOREF,
		.href = LUA_NOREF,
		.widget_state = LUA_NOREF,
		.tui_state = LUA_NOREF,
		.lua = L,
		.cwd = NULL,
		.cwd_fd = -1,
		.parent = p
	};
	l->submeta[0] = l;
	luaL_getmetatable(L, TUI_METATABLE);
	lua_setmetatable(L, -2);
}

static lua_Number luaL_optbnumber(lua_State* L, int narg, lua_Number opt)
{
	if (lua_isnumber(L, narg))
		return lua_tonumber(L, narg);
	else if (lua_isboolean(L, narg))
		return lua_toboolean(L, narg);
	else
		return opt;
}

/* chain: [label] -> x -> [u8] -> x -> [key] where (x) is a
 * return true- early out */
static bool on_label(struct tui_context* T, const char* label, bool act, void* t)
{
	SETUP_HREF("label", false);
	lua_pushstring(L, label);
	RUN_CALLBACK("label", 2, 1);
	END_HREF;
	return false;
}

static bool intblbool(lua_State* L, int ind, const char* field)
{
	lua_getfield(L, ind, field);
	bool rv = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return rv;
}

static int intblint(lua_State* L, int ind, const char* field, bool* ok)
{
	lua_getfield(L, ind, field);
	*ok = lua_isnumber(L, -1);
	int rv = lua_tointeger(L, -1);
	lua_pop(L, 1);
	return rv;
}

static struct tui_constraints get_wndhint(lua_State* L, int ind)
{
	struct tui_constraints res =
	{
		.anch_row = -1,
		.anch_col = -1,
		.max_rows = -1,
		.min_rows = -1,
		.hide = false
	};

	bool ok;
	int num = intblint(L, ind, "anchor_row", &ok);
	if (ok)
		res.anch_row = num;

	num = intblint(L, ind, "anchor_col", &ok);
	if (ok)
		res.anch_col = num;

	num = intblint(L, ind, "max_rows", &ok);
	if (ok)
		res.max_rows = num;

	num = intblint(L, ind, "min_rows", &ok);
	if (ok)
		res.min_rows = num;

	num = intblint(L, ind, "max_cols", &ok);
	if (ok)
		res.max_cols = num;

	num = intblint(L, ind, "min_cols", &ok);
	if (ok)
		res.min_cols = num;

	res.hide = intblbool(L, ind, "hidden");

	return res;
}

static bool on_u8(struct tui_context* T, const char* u8, size_t len, void* t)
{
	SETUP_HREF("utf8", false);
		lua_pushlstring(L, u8, len);
		RUN_CALLBACK("utf8", 2, 1);
		bool rv = false;
		if (lua_isnumber(L, -1))
			rv = lua_tonumber(L, -1);
		else if (lua_isboolean(L, -1))
			rv = lua_toboolean(L, -1);
		lua_pop(L, 1);
	END_HREF;
	return rv;
}

static void on_mouse(struct tui_context* T,
	bool relative, int x, int y, int modifiers, void* t)
{
	SETUP_HREF("mouse_motion",);
		lua_pushboolean(L, relative);
		lua_pushnumber(L, x);
		lua_pushnumber(L, y);
		lua_pushnumber(L, modifiers);
		RUN_CALLBACK("mouse_motion", 5, 0);
	END_HREF;
}

static void on_mouse_button(struct tui_context* T,
	int x, int y, int subid, bool active, int modifiers, void* t)
{
	SETUP_HREF("mouse_button",);
		lua_pushnumber(L, subid);
		lua_pushnumber(L, x);
		lua_pushnumber(L, y);
		lua_pushnumber(L, modifiers);
		lua_pushboolean(L, active);
		RUN_CALLBACK("mouse_button", 6, 0);
	END_HREF;
}

static void on_key(struct tui_context* T, uint32_t xkeysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	SETUP_HREF("key",);
		lua_pushnumber(L, subid);
		lua_pushnumber(L, xkeysym);
		lua_pushnumber(L, scancode);
		lua_pushnumber(L, mods);
		RUN_CALLBACK("key", 5, 0);
	END_HREF;
}

/*
 * don't forward this for now, should only really hit game devices etc.
 */
static void on_misc(struct tui_context* T, const arcan_ioevent* ev, void* t)
{
}

static void on_recolor(struct tui_context* T, void* t)
{
	SETUP_HREF("recolor",);
		RUN_CALLBACK("recolor", 1, 0);
	END_HREF;
}

static void on_reset(struct tui_context* T, int level, void* t)
{
	SETUP_HREF("reset", );
		lua_pushnumber(L, level);
		RUN_CALLBACK("reset", 2, 0);
	END_HREF;
}

static void on_state(struct tui_context* T, bool input, int fd, void* t)
{
	SETUP_HREF( (input?"state_in":"state_out"), );
		if (alt_nbio_import(L, fd, input ? O_WRONLY : O_RDONLY, NULL)){
			RUN_CALLBACK("state_inout", 2, 0);
		}
		else
			lua_pop(L, 1);
	END_HREF;
}

static void on_bchunk(struct tui_context* T,
	bool input, uint64_t size, int fd, const char* type, void* t)
{
	SETUP_HREF((input ?"bchunk_in":"bchunk_out"), );
		if (alt_nbio_import(L, fd, input ? O_WRONLY : O_RDONLY, NULL)){
			lua_pushstring(L, type);
			RUN_CALLBACK("bchunk_inout", 3, 0);
		}
		else
			lua_pop(L, 1);
		END_HREF;
}

static void on_vpaste(struct tui_context* T,
		shmif_pixel* vidp, size_t w, size_t h, size_t stride, void* t)
{
/* want to expose something like the calc-target, along with a
 * map-to-cell? */
}

static void on_apaste(struct tui_context* T,
	shmif_asample* audp, size_t n_samples, size_t frequency, size_t nch, void* t)
{
/*
 * don't have a good way to use this right now..
 */
}

static void on_tick(struct tui_context* T, void* t)
{
	SETUP_HREF("tick",);
		RUN_CALLBACK("tick", 1, 0);
	END_HREF;
}

static void on_utf8_paste(struct tui_context* T,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	SETUP_HREF("paste",);
		lua_pushlstring(L, (const char*) str, len);
		lua_pushnumber(L, cont);
		RUN_CALLBACK("paste", 3, 0);
	END_HREF;
}

static void on_resized(struct tui_context* T,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
/* ugly little edge condition - the first on_resized will actually be called in
 * tui-setup already where we don't have the rest of the context or things
 * otherwise prepared. This will cause our TUI_UDATA etc. to fail as the tui
 * member has not yet been set. */
	SETUP_HREF("resized",);
		if (!meta->tui)
			meta->tui = T;
		lua_pushnumber(L, col);
		lua_pushnumber(L, row);
		lua_pushnumber(L, neww);
		lua_pushnumber(L, newh);
		RUN_CALLBACK("resized", 5, 0);
	END_HREF;
}

static void on_resize(struct tui_context* T,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	SETUP_HREF("resize",);
/* same as with on_resized above */
		if (!meta->tui)
			meta->tui = T;
		lua_pushnumber(L, col);
		lua_pushnumber(L, row);
		lua_pushnumber(L, neww);
		lua_pushnumber(L, newh);
		RUN_CALLBACK("resize", 5, 0);
	END_HREF;
}

static int tui_phandover(lua_State* L)
{
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);
	if (!ib->in_subwnd){
		luaL_error(L, "phandover(...) - only permitted inside subwindow closure");
	}

/* There is a mechanism missing here still for more dynamic controls
 * of a tui/shmif child. Several possible ways, all of them painful:
 *
 *    1. pack events over the SOCKIN_FD (complicates shmif)
 *
 *    2. add a tui- only channel for injecting events
 *       (this duplicates work)
 *
 *    3. shmif-server proxying
 *
 *    4. Have a 'relay' mode where handover-exec allocated windows
 *       can have events forwarded to them by the server. Basically:
 *
 *        a. EVENT_EXTERNAL_RELAYDST (token)
 *           events to 'inject' (TARGET_COMMAND_..., TARGET_IO)
 *
 * 4. Is probably the most interesting but it still forces us to expose several
 * shmif- parts all of a sudden. Thus it should probably be added on a lower
 * level, then provide methods for sending events to other windows. It would
 * also not work for handover windows that migrate to other servers.
 *
 * The relevant subset of events should be rather small though, mainly:
 *
 *   1. keyboard/analog/mouse input.
 *   2. reset-state.
 *   3. state-serialization.
 *   4. bchunk.
 */
	char** env = NULL;
	char** argv = NULL;

/* path */
	const char* path = luaL_checkstring(L, 2);

/* mode */
	const char* mode = luaL_checkstring(L, 3);

/* argv */
	if (lua_type(L, 4) == LUA_TTABLE){
		argv = tui_popen_tbltoargv(L, 4);
	}

/* env */
	if (lua_type(L, 5) == LUA_TTABLE){
		env = tui_popen_tbltoenv(L, 5);
	}

	int fds[3] = {-1, -1, -1};
	int* fds_ptr[3] = {&fds[0], &fds[1], &fds[2]};
	if (!strchr(mode, (int)'r'))
		fds_ptr[1] = NULL;

	if (!strchr(mode, (int)'w'))
		fds_ptr[0] = NULL;

	if (!strchr(mode, (int)'e'))
		fds_ptr[2] = NULL;

	pid_t pid = arcan_tui_handover_pipe(
			ib->tui, NULL, path, argv, env, fds_ptr, 3);

	ib->subwnd_handover = pid != -1;

	if (env){
		char** cur = env;
		while (*cur)
			free(*cur++);
		free(env);
	}

	if (argv){
		char** cur = argv;
		while (*cur)
			free(*cur++);
		free(argv);
	}

	ib->in_subwnd = NULL;

	if (-1 == pid)
		return 0;

/* create proxy-window and return along with requested stdio */
	alt_nbio_import(L, fds[0], O_WRONLY, NULL);
	alt_nbio_import(L, fds[1], O_RDONLY, NULL);
	alt_nbio_import(L, fds[2], O_RDONLY, NULL);
	lua_pushnumber(L, pid);

	return 4;
}

static bool on_subwindow(struct tui_context* T,
	arcan_tui_conn* new, uint32_t id, uint8_t type, void* t)
{
	id ^= req_cookie;

/* we invoke a specific closure rather than a subwindow handler (except for
 * push- segments which are ignored for now) */
	struct tui_lmeta* meta = t;
	lua_State* L = meta->lua;
	if (meta->href == LUA_NOREF)
		return false;

/* indicates that there's something wrong with the connection */
	if (id >= 8 || !(meta->pending_mask & (1 << id)))
		return false;

	intptr_t cb = meta->pending[id].id;
	meta->pending[id].id = 0;
	meta->pending_mask &= ~(1 << id);

/* indicates that something is wrong with the new_window handler */
	lua_rawgeti(L, LUA_REGISTRYINDEX, cb);
	if (lua_type(L, -1) != LUA_TFUNCTION)
		luaL_error(L, "on_subwindow() bad/broken cb-id");

	lua_rawgeti(L, LUA_REGISTRYINDEX, meta->tui_state);

/* This failure scenario is still uncertain, right now the outer shell can
 * reject any new subwindow request and we have to honor that. It is however
 * possible to create a placebo- subwindow (as used with embedding etc.) and
 * blit it / do window management locally. Such a fix is better handled in the
 * tui libraries themselves however. When that happens, this path will never
 * trigger unless for handover-allocation like scenarios. */
	if (!new){
		RUN_CALLBACK("subwindow_fail", 1, 0);
		luaL_unref(L, LUA_REGISTRYINDEX, cb);
		END_HREF;
		return false;
	}

/* let the caller be responsible for updating the handlers */
	struct tui_context* ctx =
		arcan_tui_setup(new, T, &shared_cbcfg, sizeof(shared_cbcfg));
	if (!ctx){
		RUN_CALLBACK("subwindow_setup_fail", 1, 0);
		luaL_unref(L, LUA_REGISTRYINDEX, cb);
		END_HREF;
		return true;
	}

/* build our new window */
	struct tui_lmeta* nud = lua_newuserdata(L, sizeof(struct tui_lmeta));
	if (!nud){
		RUN_CALLBACK("subwindow_ud_fail", 1, 0);
		luaL_unref(L, LUA_REGISTRYINDEX, cb);
		END_HREF;
		return true;
	}
	init_lmeta(L, nud, meta);
	nud->tui = ctx;

	if (type != TUI_WND_HANDOVER){
/* cycle- reference ourselves */
		lua_pushvalue(L, -1);
		nud->tui_state = luaL_ref(L, LUA_REGISTRYINDEX);

/* register with parent so :process() hits the right hierarchy */
		size_t wnd_i = 0;
		for (; wnd_i < SEGMENT_LIMIT; wnd_i++){
			if (!meta->subs[wnd_i]){
				meta->subs[wnd_i] = ctx;
				meta->submeta[wnd_i] = nud;
				meta->n_subs++;
				break;
			}
		}
	}
/* the check for pending-id + the check on request means that there there is a
 * fitting slot in parent[subs] - and even if there wouldn't be, it would just
 * block the implicit :process, explicit would still work. */
	else {
		meta->in_subwnd = new;
	}
	RUN_CALLBACK("subwindow_ok", 2, 0);

/* this means that the window has been handed over to a new process, it can
 * still be 'used' as a window in regards to hinting, drawing and so on, but
 * refresh and processing won't have any effect. The special case is when the
 * phandover call fails and we need to false-return so the backend cleans up */
	bool ok = true;
	if (!meta->in_subwnd && type == TUI_WND_HANDOVER){
		ok = meta->subwnd_handover;
	}
	meta->in_subwnd = NULL;

	luaL_unref(L, LUA_REGISTRYINDEX, cb);
	END_HREF;
	return ok;
}

static bool query_label(struct tui_context* T,
	size_t ind, const char* country, const char* lang,
	struct tui_labelent* dstlbl, void* t)
{
	SETUP_HREF("query_label", false);
	lua_pushnumber(L, ind+1);
	lua_pushstring(L, country);
	lua_pushstring(L, lang);
	RUN_CALLBACK("query_label", 4, 5);

	const char* msg = luaL_optstring(L, -5, NULL);
	const char* descr = luaL_optstring(L, -4, NULL);

	bool gotrep = msg != NULL;
	if (gotrep){
		snprintf(dstlbl->label, COUNT_OF(dstlbl->label), "%s", msg);
		snprintf(dstlbl->descr, COUNT_OF(dstlbl->descr), "%s", descr ? descr : "");
		dstlbl->initial = luaL_optnumber(L, -3, 0);
		dstlbl->modifiers = luaL_optnumber(L, -2, 0);
		const char* vsym = luaL_optstring(L, -1, NULL);
		if (vsym){
			snprintf((char*)dstlbl->vsym, COUNT_OF(dstlbl->vsym), "%s", vsym);
		}

		dstlbl->idatatype = 0; /* only support buttons for now */
	}
	lua_pop(L, 5);

	END_HREF;
	return gotrep;
}

static void on_geohint(struct tui_context* T, float lat,
	float longitude, float elev, const char* a3_country,
	const char* a3_language, void* t)
{
	SETUP_HREF("geohint",);
	lua_pushstring(L, a3_country);
	lua_pushstring(L, a3_language);

	lua_pushnumber(L, lat);
	lua_pushnumber(L, longitude);
	lua_pushnumber(L, elev);

	RUN_CALLBACK("geohint", 6, 0);
	END_HREF;
}

static void on_visibility(
	struct tui_context* T, bool visible, bool focus, void* t)
{
	SETUP_HREF("visibility",);
		lua_pushboolean(L, visible);
		lua_pushboolean(L, focus);
		RUN_CALLBACK("visibility", 3, 0);
	END_HREF;
}

static void on_exec_state(struct tui_context* T, int state, void* t)
{
	SETUP_HREF("exec_state",);
		switch(state){
		case 0:
		lua_pushstring(L, "resume");
		break;
		case 1:
		lua_pushstring(L, "suspend");
		break;
		case 2:
		lua_pushstring(L, "shutdown");
		break;
		default:
			lua_pop(L, 1);
			return;
		break;
		}
		RUN_CALLBACK("exec_state", 2, 0);
	END_HREF;
}

static void on_seek_absolute(struct tui_context* T, float pct, void* t)
{
	SETUP_HREF("seek_absolute", );
		lua_pushnumber(L, pct);
		RUN_CALLBACK("seek_absolute", 2, 0);
	END_HREF;
}

static void on_seek_relative(
		struct tui_context* T, ssize_t rows, ssize_t cols, void* t)
{
	SETUP_HREF("seek_relative", );
		lua_pushnumber(L, rows);
		lua_pushnumber(L, cols);
		RUN_CALLBACK("seek_relative", 3, 0);
	END_HREF;
}

static bool on_readline_filter(uint32_t ch, size_t len, void* t)
{
	struct tui_lmeta* meta = t;
	if (!meta->widget_meta || meta->widget_meta->readline.filter == LUA_NOREF){
		return true;
	}

	char buf[4];
	size_t used = arcan_tui_ucs4utf8(ch, buf);
	if (!used){
		return true;
	}

	bool res = true;
	lua_State* L = meta->lua;

/* function(self, input, strlen) -> accept or reject */
	lua_rawgeti(meta->lua,
		LUA_REGISTRYINDEX, meta->widget_meta->readline.filter);
	lua_rawgeti(meta->lua, LUA_REGISTRYINDEX, meta->widget_state);

	lua_pushlstring(L, buf, used);
	lua_pushinteger(L, len);

	if (0 != lua_pcall(L, 3, 1, 0)){
		luaL_error(L, lua_tostring(L, -1));
	}

	if (lua_type(L, -1) == LUA_TBOOLEAN){
		res = lua_toboolean(L, -1);
	}
	else if (lua_type(L, -1) == LUA_TNIL){
	}
	else
		luaL_error(L, "verify() bad return type, expected boolean");

	lua_pop(L, 1);
	return res;
}

static ssize_t on_readline_verify(
	const char* message, size_t prefix, bool suggest, void* t)
{
	struct tui_lmeta* meta = t;
	if (!meta->widget_meta || meta->widget_meta->readline.verify == LUA_NOREF){
		return -1;
	}

	lua_State* L = meta->lua;
	lua_rawgeti(meta->lua,
		LUA_REGISTRYINDEX, meta->widget_meta->readline.verify);
	lua_rawgeti(meta->lua, LUA_REGISTRYINDEX, meta->widget_state);

	ssize_t res = -1;
/* function(self, prefix, full, suggest) -> offset or accept/reject */
	lua_pushlstring(L, message, prefix);
	lua_pushstring(L, message);
	lua_pushboolean(L, suggest);

	int rv = lua_pcall(L, 4, 1, 0);
	if (0 != rv){
		luaL_error(L, lua_tostring(L, -1));
	}

/* just binary good/bad */
	if (lua_type(L, -1) == LUA_TBOOLEAN){
		if (!lua_toboolean(L, -1))
			res = 0;
	}
/* or failure offset */
	else if (lua_type(L, -1) == LUA_TNUMBER){
		res = lua_tointeger(L, -1);
		if (res < 0)
			res *= -1;
	}

	END_HREF
	return res;
}

static int on_cli_command(struct tui_context* T,
	const char** const argv, size_t n_elem, int command,
	const char** feedback, size_t* n_results)
{
/*
 * This is used for interactive CLI UI integration.
 *
 * [argv] is a NULL terminated array of the on-going / current set of arguments.
 *
 * Command MUST be one out of:
 * TUI_CLI_BEGIN,
 * TUI_CLI_EVAL,
 * TUI_CLI_COMMIT,
 * TUI_CLI_CANCEL
 *
 * The return value MUST be one out of:
 * TUI_CLI_ACCEPT,
 * TUI_CLI_SUGGEST,
 * TUI_CLI_REPLACE,
 * TUI_CLI_INVALID
 *
 * The callee retains ownership of feedback results, but the results should
 * be remain valid until the next EVAL, COMMIT or CANCEL.
 *
 * A response to EVAL may be ACCEPT if the command is acceptible as is, or
 * SUGGEST if there is a set of possible completion options that expand on
 * the current stack or REPLACE if there is a single commit chain that can
 * replace the stack.
 *
 * If the response is to SUGGEST, the FIRST feedback item refers to the
 * last item in argv, set that to an empty string. The remaining feedback
 * items refer to possible additional items to [argv].
 */
	return TUI_CLI_INVALID;
}

static void add_attr_tbl(lua_State* L, struct tui_screen_attr attr)
{
	lua_newtable(L);

/* key-integer value */
#define SET_KIV(K, V) do { lua_pushstring(L, K); \
	lua_pushnumber(L, V); lua_rawset(L, -3); } while (0)

#define SET_BIV(K, V) do { lua_pushstring(L, K); \
	lua_pushboolean(L, V); lua_rawset(L, -3); } while (0)

	if (attr.aflags & TUI_ATTR_COLOR_INDEXED){
		SET_KIV("fc", attr.fc[0]);
		SET_KIV("bc", attr.bc[0]);
	}
	else {
		SET_KIV("fr", attr.fr);
		SET_KIV("fg", attr.fg);
		SET_KIV("fb", attr.fb);
		SET_KIV("br", attr.br);
		SET_KIV("bg", attr.bg);
		SET_KIV("bb", attr.bb);
	}

	SET_BIV("bold", attr.aflags & TUI_ATTR_BOLD);
	SET_BIV("italic", attr.aflags & TUI_ATTR_ITALIC);
	SET_BIV("inverse", attr.aflags & TUI_ATTR_INVERSE);
	SET_BIV("underline", attr.aflags & TUI_ATTR_UNDERLINE);
	SET_BIV("underline_alt", attr.aflags & TUI_ATTR_UNDERLINE_ALT);
	SET_BIV("protect", attr.aflags & TUI_ATTR_PROTECT);
	SET_BIV("blink", attr.aflags & TUI_ATTR_BLINK);
	SET_BIV("strikethrough", attr.aflags & TUI_ATTR_STRIKETHROUGH);
	SET_BIV("break", attr.aflags & TUI_ATTR_SHAPE_BREAK);
	SET_BIV("border_right", attr.aflags & TUI_ATTR_BORDER_RIGHT);
	SET_BIV("border_down", attr.aflags & TUI_ATTR_BORDER_DOWN);
	SET_KIV("id", attr.custom_id);

#undef SET_KIV
#undef SET_BIV
}

static void free_history(struct widget_meta* m)
{
	if (!m->readline.history)
		return;

	for (size_t i = 0; i < m->readline.history_sz; i++){
		free(m->readline.history[i]);
	}

	free(m->readline.history);
	m->readline.history = NULL;
}

static void free_suggest(struct widget_meta* m)
{
	if (!m->readline.suggest)
		return;

	for (size_t i = 0; i < m->readline.suggest_sz; i++){
		free(m->readline.suggest[i]);
	}

	free(m->readline.suggest);
	m->readline.suggest = NULL;
}

static void revert(lua_State* L, struct tui_lmeta* M)
{
	switch (M->widget_mode){
	case TWND_NORMAL:
	break;
	case TWND_LISTWND:
		arcan_tui_listwnd_release(M->tui);
		if (M->widget_meta){
			free(M->widget_meta->listview.ents);
			M->widget_meta->listview.ents = NULL;
		}
	break;
	case TWND_BUFWND:
		arcan_tui_bufferwnd_release(M->tui);
		if (M->widget_meta){
			free(M->widget_meta->bufferview.buf);
			M->widget_meta->bufferview.buf = NULL;
		}
	break;
	case TWND_READLINE:
		arcan_tui_readline_release(M->tui);
		if (M->widget_meta){
			struct widget_meta* wm = M->widget_meta;

			if (wm->readline.verify){
				luaL_unref(L, LUA_REGISTRYINDEX, wm->readline.verify);
				M->widget_meta->readline.verify = LUA_NOREF;
			}
			if (wm->readline.filter){
				luaL_unref(L, LUA_REGISTRYINDEX, wm->readline.filter);
				M->widget_meta->readline.filter = LUA_NOREF;
			}

/* There might be a case for actually not freeing the history in the case
 * where we build another readline, and in that case also allow appending
 * the current history buffer. The reason for that is simply that setting
 * history is O(n) and converting to-from Lua space into a string table. */
			free_history(wm);
			free_suggest(wm);
		}
	break;
	case TWND_LINEWND:
/* arcan_tui_linewnd_release(M->tui); */
	break;
	default:
	break;
	}

	M->widget_mode = TWND_NORMAL;
	if (M->widget_meta){
		M->widget_meta->parent = NULL;
		M->widget_meta = NULL;
	}
	if (M->widget_closure != LUA_NOREF){
		luaL_unref(L, LUA_REGISTRYINDEX, M->widget_closure);
		M->widget_closure = LUA_NOREF;
	}
	if (M->widget_state != LUA_NOREF){
		luaL_unref(L, LUA_REGISTRYINDEX, M->widget_state);
		M->widget_state = LUA_NOREF;
	}
}

static void apply_table(lua_State* L, int ind, struct tui_screen_attr* attr)
{
	attr->aflags = 0;
	attr->aflags |= TUI_ATTR_BOLD * intblbool(L, ind, "bold");
	attr->aflags |= TUI_ATTR_UNDERLINE * intblbool(L, ind, "underline");
	attr->aflags |= TUI_ATTR_ITALIC * intblbool(L, ind, "italic");
	attr->aflags |= TUI_ATTR_INVERSE * intblbool(L, ind, "inverse");
	attr->aflags |= TUI_ATTR_UNDERLINE * intblbool(L, ind, "underline");
	attr->aflags |= TUI_ATTR_UNDERLINE_ALT * intblbool(L, ind, "underline_alt");
	attr->aflags |= TUI_ATTR_PROTECT * intblbool(L, ind, "protect");
	attr->aflags |= TUI_ATTR_BLINK * intblbool(L, ind, "blink");
	attr->aflags |= TUI_ATTR_STRIKETHROUGH * intblbool(L, ind, "strikethrough");
	attr->aflags |= TUI_ATTR_SHAPE_BREAK * intblbool(L, ind, "break");

	bool ok;
	attr->custom_id = intblint(L, ind, "id", &ok);

	attr->fg = attr->fb = attr->fr = 0;
	attr->bg = attr->bb = attr->br = 0;

	int val = intblint(L, ind, "fc", &ok);
	if (-1 != val && ok){
		attr->aflags |= TUI_ATTR_COLOR_INDEXED;
		attr->fc[0] = (uint8_t) val;
		attr->bc[0] = (uint8_t) intblint(L, ind, "bc", &ok);
	}
	else {
		intblint(L, ind, "fr", &ok);
		if (ok){
			attr->fr = (uint8_t) intblint(L, ind, "fr", &ok);
			attr->fg = (uint8_t) intblint(L, ind, "fg", &ok);
			attr->fb = (uint8_t) intblint(L, ind, "fb", &ok);
		}
		else {
			attr->fr = attr->fg = attr->fb = 196;
		}

		intblint(L, ind, "br", &ok);
		if (ok){
			attr->br = (uint8_t) intblint(L, ind, "br", &ok);
			attr->bg = (uint8_t) intblint(L, ind, "bg", &ok);
			attr->bb = (uint8_t) intblint(L, ind, "bb", &ok);
		}
	}
}

static int tui_attr(lua_State* L)
{
	struct tui_screen_attr attr = {
		.fr = 128, .fg = 128, .fb = 128
	};
	int ci = 1;

/* use context as base for color lookup */
	if (lua_type(L, ci) == LUA_TUSERDATA){
		struct tui_lmeta* ib = luaL_checkudata(L, ci++, TUI_METATABLE);
		arcan_tui_get_color(ib->tui, TUI_COL_PRIMARY, attr.fc);
		arcan_tui_get_color(ib->tui, TUI_COL_BG, attr.bc);
		ci++;
	}

	if (lua_type(L, ci) == LUA_TTABLE)
		apply_table(L, ci, &attr);

	add_attr_tbl(L, attr);

	return 1;
}

static int defattr(lua_State* L)
{
	TUI_UDATA;
	if (lua_istable(L, 2)){
		struct tui_screen_attr rattr = {};
		apply_table(L, 2, &rattr);
		add_attr_tbl(L,
			arcan_tui_defattr(ib->tui, &rattr));
	}
	else
		add_attr_tbl(L, arcan_tui_defcattr(ib->tui, TUI_COL_TEXT));

	return 1;
}

static int wnd_scroll(lua_State* L)
{
	TUI_UDATA;
	int steps = luaL_checkinteger(L, 2);
	if (steps > 0)
		arcan_tui_scroll_down(ib->tui, steps);
	else
		arcan_tui_scroll_up(ib->tui, -steps);
	return 0;
}

static int screen_dimensions(lua_State* L)
{
	TUI_UDATA;
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);
	lua_pushnumber(L, cols);
	lua_pushnumber(L, rows);
	return 2;
}

static int erase_region(lua_State* L)
{
	TUI_UDATA;
	size_t x1 = luaL_checkinteger(L, 2);
	size_t y1 = luaL_checkinteger(L, 3);
	size_t x2 = luaL_checkinteger(L, 4);
	size_t y2 = luaL_checkinteger(L, 5);
	bool prot = luaL_optbnumber(L, 6, false);
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);

	if (x1 < x2 && y1 < y2 && x1 < cols && y1 < rows)
		arcan_tui_erase_region(ib->tui, x1, y1, x2,  y2, prot);

	return 0;
}

static int erase_screen(lua_State* L)
{
	TUI_UDATA;
	bool prot = luaL_optbnumber(L, 2, false);
	arcan_tui_erase_screen(ib->tui, prot);
	return 0;
}

static int cursor_to(lua_State* L)
{
	TUI_UDATA;
	int x = luaL_checkinteger(L, 2);
	int y = luaL_checkinteger(L, 3);
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);

	if (x >= 0 && y >= 0 && x < cols && y < rows)
		arcan_tui_move_to(ib->tui, x, y);

	return 0;
}

static void synch_wd(struct tui_lmeta* md)
{
/* first time allocation */
	if (!md->cwd){
		md->cwd_sz = PATH_MAX + 1;
		md->cwd = malloc(md->cwd_sz);
		if (!md->cwd){
			return;
		}
	}

/* reallocate / grow until we fit */
	while (NULL == getcwd(md->cwd, md->cwd_sz)){
		switch(errno){
		case ENAMETOOLONG:
			free(md->cwd);
			md->cwd_sz *= 2;
			md->cwd = malloc(md->cwd_sz);
			if (!md->cwd)
				return;
		break;
		case EACCES:
			snprintf(md->cwd, md->cwd_sz, "[access denied]");
		break;
		case EINVAL:
			snprintf(md->cwd, md->cwd_sz, "[invalid]");
		break;
		default:
			return;
		break;
/* might be dead directory or EPERM */
		}
	}
}

static int tui_wndhint(lua_State* L)
{
	TUI_UDATA;
	int tbli = 2;

	struct tui_lmeta* parent = NULL;
	if (lua_type(L, 2) == LUA_TUSERDATA){
		parent = luaL_checkudata(L, 2, TUI_METATABLE);
		tbli = 3;
	}

	struct tui_constraints cons = {0};
	if (lua_type(L, tbli) == LUA_TTABLE){
		cons = get_wndhint(L, tbli);
	}

/* this is treated as non-mutable and set on window request */
	cons.embed = ib->embed;
	arcan_tui_wndhint(ib->tui, parent ? parent->tui : NULL, cons);
	return 0;
}

static int tui_chdir(lua_State* L)
{
	TUI_UDATA;

/* first need to switch to ensure we have that of the window */
	int status = 0;

	if (-1 != ib->cwd_fd || -1 == fchdir(ib->cwd_fd))
		chdir(ib->cwd);

/* if the user provides a string, chdir to that */
	const char* wd = luaL_optstring(L, 2, NULL);
	if (wd)
		status = chdir(wd);

/* now update the string cache */
	synch_wd(ib);
	lua_pushstring(L, ib->cwd ? ib->cwd : "[unknown]");
	if (-1 == status){
		lua_pushstring(L, strerror(errno));
		return 2;
	}

/* synch a dirfd so that when different file calls are called on different
 * windows, they don't race against renames/moves */
	else {
		if (-1 != ib->cwd_fd)
			close(ib->cwd_fd);

		ib->cwd_fd = open(".", O_RDONLY | O_DIRECTORY);
	}

	return 1;
}

static int tui_open(lua_State* L)
{
	const char* title = luaL_checkstring(L, 1);
	const char* ident = luaL_checkstring(L, 2);

	arcan_tui_conn* conn = arcan_tui_open_display(title, ident);
/* will be GCd */
	if (!conn){
		lua_pop(L, 1);
		return 0;
	}

	return ltui_inherit(L, conn) ? 1 : 0;
}

struct tui_context*
ltui_inherit(lua_State* L, arcan_tui_conn* conn)
{
	register_tuimeta(L);

	struct tui_lmeta* meta = lua_newuserdata(L, sizeof(struct tui_lmeta));
	if (!meta){
		return NULL;
	}
	init_lmeta(L, meta, NULL);
	lua_pushvalue(L, -1);
	meta->tui_state = luaL_ref(L, LUA_REGISTRYINDEX);
	synch_wd(meta);

/* Hook up the tui/callbacks, these forward into a handler table
 * that the user provide a reference to. */
	shared_cbcfg = (struct tui_cbcfg){
		.query_label = query_label,
		.input_label = on_label,
		.input_mouse_motion = on_mouse,
		.input_mouse_button = on_mouse_button,
		.input_utf8 = on_u8,
		.input_key = on_key,
		.input_misc = on_misc,
		.state = on_state,
		.bchunk = on_bchunk,
		.vpaste = on_vpaste,
		.apaste = on_apaste,
		.tick = on_tick,
		.utf8 = on_utf8_paste,
		.resize = on_resize,
		.resized = on_resized,
		.subwindow = on_subwindow,
		.recolor = on_recolor,
		.reset = on_reset,
		.geohint = on_geohint,
		.visibility = on_visibility,
		.exec_state = on_exec_state,
		.cli_command = on_cli_command,
		.seek_absolute = on_seek_absolute,
		.seek_relative = on_seek_relative,
		.tag = meta
	};
	meta->href = LUA_NOREF;

/*
 * get a reference to the callback table so we can extract it from
 * shmif/tui callbacks and reach the right context/userdata
 */
	if (lua_type(L, 3) == LUA_TTABLE){
		lua_getfield(L, 3, "handlers");
		if (lua_type(L, -1) == LUA_TTABLE){
			meta->href = luaL_ref(L, LUA_REGISTRYINDEX);
		}
		else{
			lua_pop(L, 1);
			return NULL;
		}
	}

/* display cleanup is now in the hand of _setup */
	meta->tui = arcan_tui_setup(conn, NULL, &shared_cbcfg, sizeof(shared_cbcfg));
	if (!meta->tui){
		lua_pop(L, 1);
		return NULL;
	}

	return meta->tui;
}

/* plug any holes by moving left, then reducing n_subs */
static void compact(struct tui_lmeta* ib)
{
	for (size_t i = 1; i < ib->n_subs+1;){
		if (ib->subs[i]){
			i++;
			continue;
		}

		memmove(
			&ib->submeta[i  ],
			&ib->submeta[i+1],
			sizeof(void*) * (SEGMENT_LIMIT - i)
		);

		memmove(
			&ib->subs[i  ],
			&ib->subs[i+1],
			sizeof(void*) * (SEGMENT_LIMIT - i)
		);

		ib->n_subs--;
	}
}

static int tuiclose(lua_State* L)
{
	TUI_UDATA;
	revert(L, ib);

	arcan_tui_destroy(ib->tui, luaL_optstring(L, 2, NULL));
	ib->tui = NULL;
	luaL_unref(L, LUA_REGISTRYINDEX, ib->tui_state);
	ib->tui_state = LUA_NOREF;

/* deregister from parent list of subs by finding and compacting */
	if (ib->parent){
		for (size_t i = 1; i < ib->parent->n_subs+1; i++){
			if (ib->parent->submeta[i] == ib){
				ib->parent->submeta[i] = NULL;
				ib->parent->subs[i] = NULL;
				break;
			}
		}
		compact(ib->parent);
	}

	if (ib->href != LUA_NOREF){
		lua_rawgeti(L, LUA_REGISTRYINDEX, ib->href);
		lua_getfield(L, -1, "destroy");

		if (lua_type(L, -1) != LUA_TFUNCTION){
			lua_pop(L, 2);
			return 0;
		}

		lua_pushvalue(L, -3);
		RUN_CALLBACK("destroy", 1, 0);
	}

	return 0;
}

static int collect(lua_State* L)
{
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);
	if (!ib)
		return 0;

	if (ib->tui){
		arcan_tui_destroy(ib->tui, NULL);
		ib->tui = NULL;
	}

	if (ib->href != LUA_NOREF){
		luaL_unref(L, LUA_REGISTRYINDEX, ib->href);
		ib->href = LUA_NOREF;
	}

	free(ib->cwd);
	ib->cwd = NULL;

	if (-1 != ib->cwd_fd){
		close(ib->cwd_fd);
		ib->cwd_fd = -1;
	}

	return 0;
}

static int settbl(lua_State* L)
{
	TUI_UDATA;
	if (ib->href != LUA_NOREF){
		luaL_unref(L, LUA_REGISTRYINDEX, ib->href);
		ib->href = LUA_NOREF;
	}

	luaL_checktype(L, 2, LUA_TTABLE);
	ib->href = luaL_ref(L, LUA_REGISTRYINDEX);

	return 0;
}

static int setident(lua_State* L)
{
	TUI_UDATA;
	const char* ident = luaL_optstring(L, 2, "");
	arcan_tui_ident(ib->tui, ident);
	return 0;
}

static int setcopy(lua_State* L)
{
	TUI_UDATA;
	const char* pstr = luaL_optstring(L, 2, "");
	lua_pushboolean(L, arcan_tui_copy(ib->tui, pstr));
	return 1;
}

static int reqwnd(lua_State* L)
{
	TUI_UDATA;

	struct tui_subwnd_req meta =
	{
		.rows = 0,
		.cols = 0,
		.hint = 0, /* TUIWND_SPLIT_(LEFT, RIGHT, TOP, BOTTOM) _JOIN_, TAB, EMBED */
	};

	const char* type = luaL_optstring(L, 2, "tui");
	int ind;
	intptr_t ref = LUA_NOREF;
	if ( (ind = 2, lua_isfunction(L, 2)) || (ind = 3, lua_isfunction(L, 3)) ){
		lua_pushvalue(L, ind);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	else
		luaL_error(L, "new_window(type, >closure<, ...) closure missing");

	const char* hintstr = NULL;

	while(++ind <= lua_gettop(L)){
		if (lua_type(L, ind) == LUA_TNUMBER){
			if (!meta.rows)
				meta.rows = lua_tonumber(L, ind);
			else if (!meta.cols)
				meta.cols = lua_tonumber(L, ind);
			else
				luaL_error(L,
					"new_window(type, closure, >w, h<, [hint]) number argument overflow ");
		}
		else if (lua_type(L, ind) == LUA_TSTRING){
			if (hintstr)
				luaL_error(L,
					"new_window(type, closure, [w, h], hint) hint argument overflow");

			hintstr = lua_tostring(L, ind);
		}
		else
			luaL_error(L,
				"new_window(type, closure, >...<) unexpected argument type");
	}

	if (hintstr){
		if (strcmp(hintstr, "split") == 0){
			meta.hint = TUIWND_SPLIT_NONE;
		}
		else if (strcmp(hintstr, "split-l") == 0){
			meta.hint = TUIWND_SPLIT_LEFT;
		}
		else if (strcmp(hintstr, "split-r") == 0){
			meta.hint = TUIWND_SPLIT_RIGHT;
		}
		else if (strcmp(hintstr, "split-t") == 0){
			meta.hint = TUIWND_SPLIT_TOP;
		}
		else if (strcmp(hintstr, "split-d") == 0){
			meta.hint = TUIWND_SPLIT_DOWN;
		}
		else if (strcmp(hintstr, "join-l") == 0){
			meta.hint = TUIWND_JOIN_LEFT;
		}
		else if (strcmp(hintstr, "join-r") == 0){
			meta.hint = TUIWND_JOIN_RIGHT;
		}
		else if (strcmp(hintstr, "join-t") == 0){
			meta.hint = TUIWND_JOIN_TOP;
		}
		else if (strcmp(hintstr, "join-d") == 0){
			meta.hint = TUIWND_JOIN_DOWN;
		}
		else if (strcmp(hintstr, "tab") == 0){
			meta.hint = TUIWND_TAB;
		}
		else if (strcmp(hintstr, "embed") == 0){
			meta.hint = TUIWND_EMBED;
		}
		else
			luaL_error(L,"new_window(..., >hint<) "
				"unknown hint (split-(tldr), join-(tldr), tab or embed");
	}

	int tui_type = TUI_WND_TUI;
	if (strcmp(type, "popup") == 0)
		tui_type = TUI_WND_POPUP;
	else if (strcmp(type, "handover") == 0)
		tui_type = TUI_WND_HANDOVER;

	if (ib->pending_mask == 255){
		lua_pushboolean(L, false);
		return 1;
	}

/* if an options table is provided, we switch to subwnd_ext,
 * with hint (split-[dir], or join-[dir], or tab or embed)
 * + rows and columns */

/* use a xor cookie and an index as part of the request so that we can match an
 * incoming window to one of our previous requests, there might be multiple
 * in-flight. */
	int bitind = ffs(~(ib->pending_mask)) - 1;
	ib->pending[bitind].id = ref;
	ib->pending[bitind].hint = meta.hint;
	ib->pending_mask |= 1 << bitind;
	lua_pushboolean(L, true);
	arcan_tui_request_subwnd_ext(ib->tui,
		tui_type, (uint32_t) bitind ^ req_cookie, meta, sizeof(meta));

	return 1;
}

static int alive(lua_State* L)
{
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);
	if (!ib){
		luaL_error(L, !ib ? "no userdata" : "no tui context");
	}
	lua_pushboolean(L, ib->tui != NULL);
	return 1;
}

/* correlate a bitmap of indices to the map of file descriptors to uintptr_t
 * tags, collect them in a set and forward to alt_nbio */
static void run_bitmap(lua_State* L, int map)
{
	uintptr_t set[32];
	int count = 0;
	while (ffs(map) && count < 32){
		int pos = ffs(map)-1;
		map &= ~(1 << pos);
		set[count++] = nbio_jobs.fdin_tags[pos];
	}
	for (int i = 0; i < count; i++){
		alt_nbio_data_in(L, set[i]);
	}
}

static void run_sub_bitmap(struct tui_lmeta* ib, int map)
{
/* note that the first 'sub' is actually the primary and ignored here */
	int count = 0;
	while (ffs(map) && count < 32){
		int pos = ffs(map) - 1;
		map &= ~(1 << pos);
		if (pos){
			ib->subs[pos] = NULL;
			ib->submeta[pos] = NULL;
		}
	}
	compact(ib);
}

static void run_outbound_pollset(lua_State* L)
{
	intptr_t set[32];
	int count = 0;
	int pv;

/* just take each poll result that actually says something, add to set
 * and forward - just as with run_bitmap chances are the alt_nbio call
 * will queue/dequeue so cache on stack */
	if ((pv = poll(nbio_jobs.fdout, nbio_jobs.fdout_used, 0)) > 0){
		for (size_t i = 0; i < nbio_jobs.fdout_used && pv; i++){
			if (nbio_jobs.fdout[i].revents){
				set[count++] = nbio_jobs.fdout_tags[i];
				pv--;
			}
		}
	}

	for (int i = 0; i < count; i++){
		alt_nbio_data_out(L, set[i]);
	}
}

static void process_widget(lua_State* L, struct tui_lmeta* T)
{
	if (!T->widget_mode)
		return;

	switch(T->widget_mode){
	case TWND_LISTWND:{
		struct tui_list_entry* ent;
		if (arcan_tui_listwnd_status(T->tui, &ent)){
			lua_rawgeti(L, LUA_REGISTRYINDEX, T->widget_closure);
			if (ent){
				lua_pushnumber(L, ent->tag);
			}
			else {
				lua_pushnil(L);
			}
			revert(L, T);
			RUN_CALLBACK("listwnd_ok", 1, 0);
		}
	}
	break;
	case TWND_BUFWND:{
		int sc = arcan_tui_bufferwnd_status(T->tui);
		lua_rawgeti(L, LUA_REGISTRYINDEX, T->widget_closure);
		lua_rawgeti(L, LUA_REGISTRYINDEX, T->widget_state);
		if (sc == 1)
			return;
		if (sc == 0){
			lua_pushlstring(L,
				(char*) T->widget_meta->bufferview.buf,
				T->widget_meta->bufferview.sz
			);
		}
		else if (sc == -1){
			lua_pushnil(L);
		}
		revert(L, T);
		RUN_CALLBACK("bufferview_ok", 2, 0);
	}

	break;
	case TWND_READLINE:{
		char* buf;
		int sc = arcan_tui_readline_finished(T->tui, &buf);
		if (sc){
			lua_rawgeti(L, LUA_REGISTRYINDEX, T->widget_closure);
			lua_rawgeti(L, LUA_REGISTRYINDEX, T->widget_state);
			if (buf){
				lua_pushstring(L, buf);
			}
			else {
				lua_pushnil(L);
			}
/* Restore the context to its initial state so that the closure is allowed to
 * request a new readline request. Revert will actually free buf. */
			revert(L, T);
			RUN_CALLBACK("readline_ok", 2, 0);
		}
	}
	break;
	default:
	break;
	}
}

static int process(lua_State* L)
{
	TUI_UDATA;

	int timeout = luaL_optnumber(L, 2, -1);
	struct tui_process_res res;

repoll:
	res = arcan_tui_process(
		ib->subs, ib->n_subs+1, nbio_jobs.fdin, nbio_jobs.fdin_used, timeout);

/* if there are bad contexts, the descriptors won't get their time */
	if (res.errc == TUI_ERRC_BAD_CTX){
		if (ib->n_subs){
			run_sub_bitmap(ib, res.bad);
			compact(ib);
		}

		if (1 & res.bad){
			lua_pushboolean(L, false);
			lua_pushstring(L, "primary context terminated");
			return 2;
		}

		goto repoll;
	}

/* Only care about bad vs ok, nbio will do the rest. For both inbound and
 * outbound job triggers we need to first cache the tags on the stack, then
 * trigger the nbio as nbio_jobs may be modified from the nbio_data call */
	if (nbio_jobs.fdin_used && (res.bad || res.ok)){
		run_bitmap(L, res.ok);
		run_bitmap(L, res.bad);
	}

/* _process only multiplexes on inbound so we need to flush outbound as well */
	if (nbio_jobs.fdout_used){
		run_outbound_pollset(L);
	}

/* don't know which contexts that actually had updates as that goes straight
 * through the vtables, enumerate all used */
	for (size_t i = 0; i < ib->n_subs + 1; i++){
		struct tui_cbcfg out;
		if (arcan_tui_update_handlers(ib->subs[i], NULL, &out, sizeof(out))){
			process_widget(L, ib->submeta[i]);
		}
	}

	if (res.errc == TUI_ERRC_OK){
		lua_pushboolean(L, true);
		return 1;
	}

	lua_pushboolean(L, false);
	switch (res.errc){
	case TUI_ERRC_BAD_ARG:
		lua_pushliteral(L, "bad argument");
	break;
	case TUI_ERRC_BAD_FD:
		lua_pushliteral(L, "bad descriptor in set");
	break;
	case TUI_ERRC_BAD_CTX:
		lua_pushliteral(L, "broken context");
	break;
	default:
		lua_pushliteral(L, "unexpected return");
	break;
	}

	return 2;
}

static int getcursor(lua_State* L)
{
	TUI_UDATA;
	size_t x, y;
	arcan_tui_cursorpos(ib->tui, &x, &y);
	lua_pushnumber(L, x);
	lua_pushnumber(L, y);
	return 2;
}

static int write_tou8(lua_State* L)
{
	TUI_UDATA;
	struct tui_screen_attr* attr = NULL;
	struct tui_screen_attr mattr = {};
	size_t len;

	size_t x = luaL_checkinteger(L, 2);
	size_t y = luaL_checkinteger(L, 3);
	size_t ox, oy;
	arcan_tui_cursorpos(ib->tui, &ox, &oy);
	const char* buf =	luaL_checklstring(L, 4, &len);

	if (lua_type(L, 5) == LUA_TTABLE){
		apply_table(L, 5, &mattr);
		attr = &mattr;
	}

	arcan_tui_move_to(ib->tui, x, y);

	lua_pushboolean(L,
		arcan_tui_writeu8(ib->tui, (uint8_t*)buf, len, attr));

	arcan_tui_cursorpos(ib->tui, &ox, &oy);
	lua_pushinteger(L, ox);
	lua_pushinteger(L, oy);

	return 3;
}

static int writeu8(lua_State* L)
{
	TUI_UDATA;
	struct tui_screen_attr* attr = NULL;
	struct tui_screen_attr mattr = {};
	size_t len;

	const char* buf =	luaL_checklstring(L, 2, &len);

	if (lua_type(L, 3) == LUA_TTABLE){
		apply_table(L, 3, &mattr);
		attr = &mattr;
	}

	lua_pushboolean(L,
		arcan_tui_writeu8(ib->tui, (uint8_t*)buf, len, attr));
	return 1;
}

static int reset(lua_State* L)
{
	TUI_UDATA;
	revert(L, ib);
	arcan_tui_reset(ib->tui);
	return 0;
}

static int color_get(lua_State* L)
{
	TUI_UDATA;
	uint8_t dst[3] = {128, 128, 128};
	arcan_tui_get_color(ib->tui, luaL_checkinteger(L, 2), dst);
	lua_pushnumber(L, dst[0]);
	lua_pushnumber(L, dst[1]);
	lua_pushnumber(L, dst[2]);
	return 3;
}

static int set_flags(lua_State* L)
{
	TUI_UDATA;
	uint32_t flags = TUI_ALTERNATE;

	for (size_t i = 2; i <= lua_gettop(L); i++){
		uint32_t val = luaL_checkinteger(L, i);
		if (val && (val & (val - 1)) == 0){
			flags |= val;
		}
		else {
			luaL_error(L, "bad flag value (2^n, n >= 1)");
		}
	}

	arcan_tui_set_flags(ib->tui, flags);
	return 0;
}

static int color_set(lua_State* L)
{
	TUI_UDATA;
	uint8_t dst[3] = {
		luaL_checkinteger(L, 3),
		luaL_checkinteger(L, 4),
		luaL_checkinteger(L, 5)
	};
	arcan_tui_set_color(ib->tui, luaL_checkinteger(L, 2), dst);
	return 0;
}

static int alert(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_message(ib->tui, TUI_MESSAGE_ALERT, luaL_checkstring(L, 2));
	return 0;
}

static int notification(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_message(ib->tui, TUI_MESSAGE_NOTIFICATION, luaL_checkstring(L, 2));
	return 0;
}

static int failure(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_message(ib->tui, TUI_MESSAGE_FAILURE, luaL_checkstring(L, 2));
	return 0;
}

static int refresh_node(struct tui_lmeta* t)
{
	int rc = arcan_tui_refresh(t->tui);
	for (size_t i = 0; i < t->n_subs; i++){
		refresh_node(t->submeta[i+1]);
	}
	return rc;
}

static int refresh(lua_State* L)
{
	TUI_UDATA;

/* recurse is opt-out as it masks the return-code of refresh, though with the
 * suggested main-loop this does not really matter */
	bool recurse = true;
	if (lua_type(L, 2) == LUA_TBOOLEAN && !lua_toboolean(L, 2))
		recurse = false;

	int rc;
	if (!recurse)
		rc = arcan_tui_refresh(ib->tui);
	else
		rc = refresh_node(ib);

	lua_pushnumber(L, rc);
	return 1;
}

static int announce_io(lua_State* L)
{
	TUI_WNDDATA;
	const char* input = luaL_optstring(L, 2, "");
	const char* output = luaL_optstring(L, 3, "");
	arcan_tui_announce_io(ib->tui, false, input, output);
	return 0;
}

static int resetlabels(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_reset_labels(ib->tui);
	return 0;
}

static int request_io(lua_State* L)
{
	TUI_UDATA;
	const char* input = luaL_optstring(L, 2, "");
	const char* output = luaL_optstring(L, 3, "");
	arcan_tui_announce_io(ib->tui, true, input, output);
	return 0;
}

static int statesize(lua_State* L)
{
	TUI_UDATA;
	size_t state_sz = luaL_checkinteger(L, 2);
	arcan_tui_statesize(ib->tui, state_sz);
	return 0;
}

static int contentsize(lua_State* L)
{
	TUI_UDATA;
	size_t row_ofs = luaL_checkinteger(L, 2);
	size_t row_tot = luaL_checkinteger(L, 3);
	size_t col_ofs = luaL_optinteger(L, 4, 0);
	size_t col_tot = luaL_optinteger(L, 5, 0);
	arcan_tui_content_size(ib->tui, row_ofs, row_tot, col_ofs, col_tot);
	return 0;
}

static int revertwnd(lua_State* L)
{
	TUI_UDATA;
	revert(L, ib);
	return 0;
}

static void extract_listent(lua_State* L, struct tui_list_entry* base, size_t i)
{
	int attr = 0;
	if (intblbool(L, -1, "checked")){
		attr |= LIST_CHECKED;
	}

	if (intblbool(L, -1, "has_sub")){
		attr |= LIST_HAS_SUB;
	}

	if (intblbool(L, -1, "separator")){
		attr |= LIST_SEPARATOR;
	}

	if (intblbool(L, -1, "passive")){
		attr |= LIST_PASSIVE;
	}

	if (intblbool(L, -1, "itemlabel")){
		attr |= LIST_LABEL;
	}

	if (intblbool(L, -1, "hidden")){
		attr |= LIST_HIDE;
	}

	base[i] = (struct tui_list_entry){
		.indent = 0,
		.attributes = attr,
		.tag = i+1
	};

	bool ok;
	int iv = intblint(L, -1, "indent", &ok);
	if (ok)
		base[i].indent = (uint8_t) iv;

	lua_getfield(L, -1, "label");
	base[i].label = strdup(luaL_checkstring(L, -1));
	lua_pop(L, 1);
	lua_getfield(L, -1, "shortcut");
	base[i].shortcut = strdup(luaL_optstring(L, -1, ""));
	lua_pop(L, 1);
}

static int readline(lua_State* L)
{
	TUI_WNDDATA;
	revert(L, ib);
	ssize_t ofs = 2;

	struct tui_readline_opts opts = {
		.anchor_row = 0,
		.n_rows = 1,
		.margin_left = 0,
		.margin_right = 0,
		.allow_exit = false,
		.mask_character = 0,
		.multiline = false,
		.filter_character = on_readline_filter,
		.verify = on_readline_verify,
		.tab_completion = true,
		.mouse_forward = false
	};

	if (!lua_isfunction(L, ofs) || lua_iscfunction(L, ofs)){
		luaL_error(L, "readline(closure, [table]) - missing closure");
	}

/* 1. build new reference table with right metatable */
	struct widget_meta* meta = lua_newuserdata(L, sizeof(struct widget_meta));
	if (!meta)
		luaL_error(L, "couldn't allocate userdata");

	*meta = (struct widget_meta){
		.readline = {
			.verify = LUA_NOREF,
			.filter = LUA_NOREF
		}
	};

	int tbl = ofs+1;
/* 2. extract all supported options from table */
	if (lua_type(L, tbl) == LUA_TTABLE){
		bool ok;
		int vl = intblint(L, tbl, "anchor", &ok);
		if (ok)
			opts.anchor_row = vl;
		vl = intblint(L, tbl, "rows", &ok);
		if (ok)
			opts.n_rows = vl;
		vl = intblint(L, tbl, "margin_left", &ok);
		if (ok && vl >= 0)
			opts.margin_left = abs(vl);
		vl = intblint(L, tbl, "margin_right", &ok);
		if (ok && vl >= 0)
			opts.margin_right = abs(vl);
		if (intblbool(L, tbl, "cancellable"))
			opts.allow_exit = true;
		if (intblbool(L, tbl, "multiline"))
			opts.multiline = true;
		if (intblbool(L, tbl, "tab_input"))
			opts.tab_completion = false;
		if (intblbool(L, tbl, "forward_mouse"))
			opts.mouse_forward = true;
		lua_getfield(L, tbl, "mask_character");
		if (lua_isstring(L, -1)){
			arcan_tui_utf8ucs4(lua_tostring(L, -1), &opts.mask_character);
		}
		lua_pop(L, 1);
		lua_getfield(L, tbl, "verify");
		if (lua_isfunction(L, -1) && !lua_iscfunction(L, -1)){
			meta->readline.verify = luaL_ref(L, LUA_REGISTRYINDEX);
		}
		else
			lua_pop(L, 1);
		lua_getfield(L, tbl, "filter");
		if (lua_isfunction(L, -1) && !lua_iscfunction(L, -1)){
			meta->readline.filter = luaL_ref(L, LUA_REGISTRYINDEX);
		}
		else
			lua_pop(L, 1);
	}

/* 3. grab closure, set as widget */
	lua_pushvalue(L, ofs);
	ib->widget_closure = luaL_ref(L, LUA_REGISTRYINDEX);

	ib->widget_mode = TWND_READLINE;
	meta->parent = ib;
	ib->widget_meta = meta;

	luaL_getmetatable(L, "widget_readline");
	lua_setmetatable(L, -2);

/* 4. activate the widget - note that this will actually run callbacks
 *    and they would assume that it is the window that is supposed to
 *    be matched
 */
	lua_pushvalue(L, -4);

	arcan_tui_readline_setup(ib->tui, &opts, sizeof(opts));
	lua_pop(L, 1);

/* 5. save a reference to the widget context in order to forward it in
 *    callback handlers later
 */
	lua_pushvalue(L, -1);
	ib->widget_state = luaL_ref(L, LUA_REGISTRYINDEX);

	return 1;
}

static int readline_region(lua_State* L)
{
	TUI_READLINEDATA;

	size_t x1 = luaL_checkinteger(L, 2);
	size_t y1 = luaL_checkinteger(L, 3);
	size_t x2 = luaL_checkinteger(L, 4);
	size_t y2 = luaL_checkinteger(L, 5);

	arcan_tui_readline_region(ib->tui, x1, y1, x2, y2);

	return 0;
}

static int bufferwnd_seek(lua_State* L)
{
	TUI_BWNDDATA;
	size_t pos = luaL_checkinteger(L, 2);
	arcan_tui_bufferwnd_seek(ib->tui, pos);
	return 0;
}

static int bufferwnd_tell(lua_State* L)
{
	TUI_BWNDDATA;
	size_t pos = arcan_tui_bufferwnd_tell(ib->tui, NULL);
	lua_pushinteger(L, pos);
	return 1;
}

/* input_buffer, closure, [options] */
static int bufferwnd(lua_State* L)
{
	TUI_WNDDATA;
	revert(L, ib);

/* the default prefs for the bufferwnd should really be something that should
 * be configurable for the widget in general and rarely forwarded here. */
	struct tui_bufferwnd_opts opts =
	{
		.read_only = true,
		.allow_exit = true,
		.hide_cursor = false,
		.view_mode = BUFFERWND_VIEW_UTF8, /* ASCII, HEX, HEX_DETAIL */
		.wrap_mode = BUFFERWND_WRAP_ACCEPT_LF, /* ACCEPT_LF, ACCEPT_CR_LF */
		.color_mode = BUFFERWND_COLOR_NONE, /* PALETTE, CUSTOM */
		.hex_mode = BUFFERWND_HEX_BASIC, /* _ASCII, ANNOTATE, META */
		.offset = 0, /* just affects presentation */
		.commit = NULL,
		.custom_attr = NULL /*T, tag, bytev, pos, *ch, *attr */
	};

	if (lua_type(L, 2) != LUA_TSTRING){
		luaL_error(L, "bufferview(wnd, >string<, closure, opts - missing data string");
	}

	if (!lua_isfunction(L, 3) || lua_iscfunction(L, 3)){
		luaL_error(L, "bufferview(wnd, string, >closure<, opts - missing closure");
	}

	if (lua_istable(L, 4)){
		if (intblbool(L, 4, "hex")){
			opts.view_mode = BUFFERWND_VIEW_HEX;
			opts.hex_mode = BUFFERWND_HEX_BASIC;
		}
		if (intblbool(L, 4, "hex_detail")){
			opts.view_mode = BUFFERWND_VIEW_HEX_DETAIL;
			opts.hex_mode = BUFFERWND_HEX_ASCII;
		}
		if (intblbool(L, 4, "hex_detail_meta")){
			opts.view_mode = BUFFERWND_VIEW_HEX_DETAIL;
			opts.hex_mode = BUFFERWND_HEX_META;
		}
		if (!intblbool(L, 4, "read_only")){
			opts.read_only = false;
		}
		if (intblbool(L, 4, "block_exit")){
			opts.allow_exit = false;
		}
		if (intblbool(L, 4, "hide_cursor")){
			opts.hide_cursor = true;
		}
		if (intblbool(L, 4, "ignore_lf")){
			opts.wrap_mode = BUFFERWND_WRAP_ALL;
		}
	}

/* build new reference table with right metatable */
	struct widget_meta* meta = lua_newuserdata(L, sizeof(struct widget_meta));
	if (!meta)
		luaL_error(L, "couldn't allocate userdata");

	*meta = (struct widget_meta){
		.parent = ib
	};

	size_t len;
	const char* buf = luaL_checklstring(L, 2, &len);
	meta->bufferview.buf = malloc(len);
	if (!meta->bufferview.buf)
		luaL_error(L, "bufferview buffer allocation failure");
	memcpy(meta->bufferview.buf, buf, len);
	meta->bufferview.sz = len;

	ib->widget_mode = TWND_BUFWND;
	ib->widget_meta = meta;

	lua_pushvalue(L, 3);
	ib->widget_closure = luaL_ref(L, LUA_REGISTRYINDEX);

	lua_pushvalue(L, 1);
	arcan_tui_bufferwnd_setup(ib->tui,
		meta->bufferview.buf, meta->bufferview.sz, &opts, sizeof(opts));
	lua_pop(L, 1);

	lua_pushvalue(L, -1);
	ib->widget_state = luaL_ref(L, LUA_REGISTRYINDEX);

	return 1;
}

static void table_to_list(lua_State* L, struct widget_meta* M, int ind)
{
	int nelems = lua_rawlen(L, ind);
	if (nelems <= 0){
		luaL_error(L, "listview(table, closure) - table has 0 elements");
	}

	if (M->listview.ents){
		free(M->listview.ents);
		M->listview.ents = NULL;
	}

	struct tui_list_entry* tmplist =
		malloc(sizeof(struct tui_list_entry) * nelems);

	if (!tmplist)
		luaL_error(L, "listview(table, closure) - couldn't store table");

	for (size_t i = 0; i < nelems; i++){
		lua_rawgeti(L, 2, i+1);
		extract_listent(L, tmplist, i);
		lua_pop(L, 1);
	}

	M->listview.ents = tmplist;
	M->listview.n_ents = nelems;
}

static int listwnd(lua_State* L)
{
	TUI_WNDDATA;

/* normally just drop whatever previous state we were in */
	revert(L, ib);

/* take input table and closure */
	if (lua_type(L, 2) != LUA_TTABLE){
		luaL_error(L, "listview(table, closure) - missing table");
	}

	if (!lua_isfunction(L, 3) || lua_iscfunction(L, 3)){
		luaL_error(L, "listview(table, closure) - missing closure function");
	}

/* build new reference table with right metatable */
	struct widget_meta* meta = lua_newuserdata(L, sizeof(struct widget_meta));
	if (!meta)
		luaL_error(L, "couldn't allocate userdata");

	luaL_getmetatable(L, "widget_listview");
	lua_setmetatable(L, -2);
	*meta = (struct widget_meta){
		.parent = ib
	};

/* convert table members to initial list */
	table_to_list(L, meta, 2);

	ib->widget_mode = TWND_LISTWND;
	ib->widget_meta = meta;
	lua_pushvalue(L, 3);
	ib->widget_closure = luaL_ref(L, LUA_REGISTRYINDEX);

/* switch mode and build return- userdata */
	lua_pushvalue(L, 1);
	arcan_tui_listwnd_setup(ib->tui, meta->listview.ents, meta->listview.n_ents);
	lua_pop(L, 1);

	lua_pushvalue(L, -1);
	ib->widget_state = luaL_ref(L, LUA_REGISTRYINDEX);
	return 1;
}

static ssize_t utf8len(const char* msg)
{
	ssize_t res = 0;
	uint32_t tmp;
	while (*msg){
		ssize_t step = arcan_tui_utf8ucs4(msg, &tmp);
		if (step < 0)
			return step;
		msg += step;
		res++;
	}
	return res;
}

static int utf8length(lua_State* L)
{
	size_t ci = 1;
	if (lua_type(L, ci) == LUA_TUSERDATA){
		ci++;
	}
	const char* msg = luaL_checkstring(L, ci);
	lua_pushinteger(L, utf8len(msg));
	return 1;
}

static int readline_prompt(lua_State* L)
{
	TUI_READLINEDATA
	struct tui_screen_attr rattr =
		arcan_tui_defcattr(ib->tui, TUI_COL_LABEL);

/* need to store the prompt somewhere in ib, and free it after */
	size_t n_cells = 1;
	struct tui_cell* prompt = NULL;

	if (lua_type(L, 2) == LUA_TTABLE){
		size_t nelem = lua_rawlen(L, 2);
		size_t ltot = 0;

/* find each string */
		for (size_t i = 1; i <= nelem; i++){
			lua_rawgeti(L, 2, i);
			if (lua_type(L, -1) == LUA_TTABLE){
				lua_pop(L, 1);
			}
			else if (lua_type(L, -1) == LUA_TSTRING){
				const char* msg = lua_tostring(L, -1);
				ssize_t len = utf8len(msg);
				if (-1 == len)
					luaL_error(L, "invalid utf8 string in prompt");
				ltot += len;
				lua_pop(L, 1);
			}
			else
				luaL_error(L, "(attr-table or string) expected in prompt table");
		}

/* do it all again */
		n_cells = ltot + 1;
		prompt = malloc(n_cells * sizeof(struct tui_cell));
		size_t celli = 0;
		for (size_t i = 1; i <= nelem; i++){
			lua_rawgeti(L, 2, i);

/* this time around, update the attribute definition for each table */
			if (lua_type(L, -1) == LUA_TTABLE){
				apply_table(L, -1, &rattr);
				lua_pop(L, 1);
			}
			else if (lua_type(L, -1) == LUA_TSTRING){
				const char* msg = lua_tostring(L, -1);
				while (*msg){
					prompt[celli] = (struct tui_cell){
						.attr = rattr
					};
					msg += arcan_tui_utf8ucs4(msg, &prompt[celli].ch);
					celli++;
				}
				lua_pop(L, 1);
			}
		}

		prompt[celli] = (struct tui_cell){0};
	}
	else if (lua_type(L, 2) == LUA_TSTRING){
		const char* msg = lua_tostring(L, 2);
		ssize_t len = utf8len(msg);
		if (-1 == len)
			luaL_error(L, "invalid utf8 string in prompt");

		n_cells = len + 1;
		prompt = malloc(n_cells * sizeof(struct tui_cell));

		for (size_t i = 0; i < n_cells - 1; i++){
			prompt[i] = (struct tui_cell){};
			msg += arcan_tui_utf8ucs4(msg, &prompt[i].ch);
			prompt[i].attr = rattr;
		}
		prompt[n_cells-1] = (struct tui_cell){};
	}
	else
		luaL_error(L, "expected table or string");

/* Same trap as elsewhere - when the callback is invoked, it will likely
 * trigger redraw / recolor that will chain into the outer implementation. */
	arcan_tui_readline_prompt(ib->tui, prompt);

	return 0;
}

static int readline_suggest(lua_State* L)
{
	TUI_READLINEDATA

	size_t count = 0;
	char** new_suggest = NULL;
	size_t index = 2;

	if (lua_type(L, 2) == LUA_TBOOLEAN){
		arcan_tui_readline_autosuggest(ib->tui, lua_toboolean(L, 2));
		return 0;
	}

	if (lua_type(L, index) != LUA_TTABLE){
		luaL_error(L, "suggest(table) - missing table");
	}

	ssize_t nelem = lua_rawlen(L, index);
	if (nelem < 0){
		luaL_error(L, "suggest(table) - negative length");
	}

	if (nelem){
		new_suggest = malloc(nelem * sizeof(char*));
		if (!new_suggest){
			luaL_error(L, "set_suggest(alloc) - out of memory");
		}
		for (size_t i = 0; i < (size_t) nelem; i++){
			lua_rawgeti(L, 2, i+1);
			if (lua_type(L, -1) != LUA_TSTRING)
				luaL_error(L, "set_suggest - expected string in suggest");
			new_suggest[i] = strdup(lua_tostring(L, -1));
			count++;
			lua_pop(L, 1);
		}
	}

	free_suggest(meta);
	const char* mode = luaL_optstring(L, index + 1, "word");
	int mv = READLINE_SUGGEST_WORD;
	if (strcasecmp(mode, "insert") == 0){
		mv = READLINE_SUGGEST_INSERT;
	}
	else if (strcasecmp(mode, "word") == 0){
		mv = READLINE_SUGGEST_WORD;
	}
	else if (strcasecmp(mode, "substitute") == 0){
		mv = READLINE_SUGGEST_SUBSTITUTE;
	}
	else
		luaL_error(L, "set_suggest(str:mode) expected insert, word or substitute");

	meta->readline.suggest = new_suggest;
	meta->readline.suggest_sz = count;
	arcan_tui_readline_suggest(
		meta->parent->tui, mv, (const char**) new_suggest, count);

	const char* prefix = luaL_optstring(L, index + 2, NULL);
	const char* suffix = luaL_optstring(L, index + 3, NULL);
	arcan_tui_readline_suggest_fix(
		meta->parent->tui, prefix, suffix);

	return 0;
}

static int readline_set(lua_State* L)
{
	TUI_READLINEDATA
	const char* msg = luaL_checkstring(L, 2);
	if (strlen(msg) == 0)
		arcan_tui_readline_set(ib->tui, NULL);
	else
		arcan_tui_readline_set(ib->tui, msg);

	return 0;
}

static int readline_autocomplete(lua_State* L)
{
	TUI_READLINEDATA
	const char* msg = luaL_checkstring(L, 2);
	if (strlen(msg) == 0)
		arcan_tui_readline_autocomplete(ib->tui, NULL);
	else{
		arcan_tui_readline_autocomplete(ib->tui, msg);
	}
	return 0;
}

static int readline_history(lua_State* L)
{
	TUI_READLINEDATA

	size_t count = 0;
	char** new_history = NULL;
	if (lua_type(L, 2) != LUA_TTABLE){
		luaL_error(L, "set_history(table) - missing table");
	}

	ssize_t nelem = lua_rawlen(L, 2);
	if (nelem < 0){
		luaL_error(L, "set_history(table) - negative length");
	}

	if (nelem){
		new_history = malloc(nelem * sizeof(char*));
		if (!new_history){
			luaL_error(L, "set_history(alloc) - out of memory");
		}
		for (size_t i = 0; i < (size_t) nelem; i++){
			lua_rawgeti(L, 2, i+1);
			if (lua_type(L, -1) != LUA_TSTRING)
				luaL_error(L, "set_history - expected string in history");
			new_history[i] = strdup(lua_tostring(L, -1));
			count++;
			lua_pop(L, 1);
		}
	}

	free_history(meta);
	meta->readline.history = new_history;
	meta->readline.history_sz = count;
	arcan_tui_readline_history(
		meta->parent->tui, (const char**) new_history, count);

	return 0;
}

static int listwnd_pos(lua_State* L)
{
	TUI_LWNDDATA

	int new = luaL_optinteger(L, 2, -1);
	if (new > 0)
		arcan_tui_listwnd_setpos(ib->tui, new);

/* to be coherent with lua semantics, we stick to 1- indexed */
	ssize_t pos = arcan_tui_listwnd_tell(ib->tui);
	lua_pushnumber(L, pos+1);

	return 1;
}

static int listwnd_update(lua_State* L)
{
	TUI_LWNDDATA
	int pos = luaL_checknumber(L, 2);
	if (pos <= 0 || pos >= meta->listview.n_ents)
		luaL_error(L, "listview:update(index, tbl) - index out of bounds");

	pos--;

	if (lua_type(L, 3) != LUA_TTABLE){
		luaL_error(L, "listview:update(index, tbl) - tbl argument bad / missing");
	}

	lua_pushvalue(L, 3);
	extract_listent(L, meta->listview.ents, pos);
	lua_pop(L, 1);

	arcan_tui_listwnd_dirty(ib->tui);
	return 0;
}

static int
apiversion(lua_State *L)
{
	lua_newtable(L);
	lua_pushinteger(L, 1);
	lua_setfield(L, -2, "major");
	lua_pushinteger(L, 0);
	lua_setfield(L, -2, "minor");
	lua_pushinteger(L, 0);
	lua_setfield(L, -2, "micro");
	return 1;
}

static int
apiversionstr(lua_State* L)
{
	lua_pushstring(L, "1.0.0");
	return 1;
}

static int
tui_tostring(lua_State* L)
{
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);
	if (!ib || !ib->tui){
		lua_pushstring(L, "tui(closed)");
	}
	else
		switch (ib->widget_mode){
		case TWND_READLINE:
			lua_pushstring(L, "tui(readline)");
		break;
		case TWND_BUFWND:
			lua_pushstring(L, "tui(bufferview)");
		break;
		case TWND_LINEWND:
			lua_pushstring(L, "tui(listview)");
		break;
		default:
			lua_pushstring(L, "tui(window)");
		break;
		}

	return 1;
}

static int utf8step(lua_State* L)
{
/* byte position search based on start of string > 0 */
	size_t ci = 1;
	if (lua_type(L, ci) == LUA_TUSERDATA){
		ci++;
	}
	const char* msg = luaL_checkstring(L, ci);
	ssize_t step = luaL_optnumber(L, ci+1, 1);
	ssize_t ofs = luaL_optnumber(L, ci+2, 1) - 1; /* maintain lua 1-index */
	ssize_t len = strlen(msg);

	if (!len || ofs > len || ofs < 0){
		lua_pushnumber(L, -1);
		return 1;
	}

/* are we not aligned? */
	while ((msg[ofs] & 0xc0) == 0x80){
		ofs = ofs - 1;
		if (ofs < 0){
			lua_pushnumber(L, -1);
			return 1;
		}
	}

	ssize_t sign = (ssize_t)(step > 0) - (step < 0);
	ssize_t ns = sign * step;

	while (ofs >= 0 && ofs < len && ns){
		ofs += sign;
		while ((msg[ofs] & 0xc0) == 0x80 && ofs < len && ofs >= 0){
			ofs += sign;
		}
		ns -= sign;
	}

	if (ns)
		lua_pushnumber(L, -1);
	else
		lua_pushnumber(L, ofs+1);

	return 1;
}

static bool queue_nbio(int fd, mode_t mode, intptr_t tag)
{
/* need to add to pollset for the appropriate tui context */
	if (fd == -1)
		return false;

/* before queueing a dequeue on the same descriptor will have
 * been called so we can be certain there are no duplicates */

/* need to split read/write so we can use the regular tui multiplex */
	if (mode == O_RDWR || mode == O_RDONLY){
		if (nbio_jobs.fdin_used >= LIMIT_JOBS)
			return false;

		nbio_jobs.fdin[nbio_jobs.fdin_used] = fd;
		nbio_jobs.fdin_tags[nbio_jobs.fdin_used] = tag;
		nbio_jobs.fdin_used++;
	}

	if (mode == O_RDWR || mode == O_WRONLY){
		if (nbio_jobs.fdout_used >= LIMIT_JOBS)
			return false;

		nbio_jobs.fdout[nbio_jobs.fdout_used].fd = fd;
		nbio_jobs.fdout[nbio_jobs.fdout_used].events = POLLOUT | POLLERR | POLLHUP;
		nbio_jobs.fdout_tags[nbio_jobs.fdout_used] = tag;
		nbio_jobs.fdout_used++;
	}

	return true;
}

static bool dequeue_nbio(int fd, intptr_t* tag)
{
	bool found = false;

	for (size_t i = 0; i < nbio_jobs.fdin_used; i++){
		if (nbio_jobs.fdin[i] == fd){
			memmove(
				&nbio_jobs.fdin[i],
				&nbio_jobs.fdin[i+1],
				(nbio_jobs.fdin_used - i) * sizeof(int)
			);
			nbio_jobs.fdin_used--;
			found = true;
			break;
		}
	}

	for (size_t i = 0; i < nbio_jobs.fdout_used; i++){
		if (nbio_jobs.fdout[i].fd == fd){
			memmove(
				&nbio_jobs.fdout[i],
				&nbio_jobs.fdout[i+1],
				(nbio_jobs.fdout_used - i) * sizeof(struct pollfd)
			);
			nbio_jobs.fdout_used--;
			found = true;
			break;
		}
	}

	return found;
}

static int tui_fopen(lua_State* L)
{
	TUI_UDATA;

	const char* name = luaL_checkstring(L, 2);
	const char* mode = luaL_optstring(L, 3, "r");
	mode_t omode = O_RDONLY;
	int flags = 0;

/* prefer descriptor based reference / swapping, but if that is not
 * possible, simply switch to last known */
	if (-1 != ib->cwd_fd || -1 == fchdir(ib->cwd_fd))
		chdir(ib->cwd);

	if (strcmp(mode, "r") == 0)
		omode = O_RDONLY;
	else if (strcmp(mode, "w") == 0){
		omode = O_WRONLY;
		flags = O_CREAT;
	}
	else
		luaL_error(L, "unsupported file mode, expected 'r' or 'w'");

	int fd = openat(ib->cwd_fd, name, omode | flags, 0600);

	if (-1 == fd){
		lua_pushboolean(L, false);
		return 1;
	}

	alt_nbio_import(L, fd, omode, NULL);
	return 1;
}

static int tui_fbond(lua_State* L)
{
	TUI_UDATA;
	struct nonblock_io** src = luaL_checkudata(L, 2, "nonblockIO");
	struct nonblock_io** dst = luaL_checkudata(L, 3, "nonblockIO");

	if (!*src){
		luaL_error(L, "trying to use a closed source blobio");
	}

	if (!*dst){
		luaL_error(L, "trying to use a closed destination blobio");
	}

	struct nonblock_io* sio = *src;
	struct nonblock_io* dio = *dst;

	if (sio->mode == O_WRONLY){
		luaL_error(L, "source is write-only");
	}

	if (dio->mode == O_RDONLY){
		luaL_error(L, "destination is read-only");
	}

/* running out of descriptors is quite possible */
	int pair[2];
	if (-1 == pipe(pair)){
		lua_pushboolean(L, false);
		return 1;
	}

/* extract the descriptors and clean everything else up, but leave
 * the actual cleanup to the tui_bgcopy call */
	int fdin = sio->fd;
	int fdout = dio->fd;

	sio->fd = -1;
	dio->fd = -1;
	alt_nbio_close(L, src);
	alt_nbio_close(L, dst);

	fcntl(pair[0], F_SETFD, fcntl(pair[0], F_GETFD) | FD_CLOEXEC);
	fcntl(pair[1], F_SETFD, fcntl(pair[0], F_GETFD) | FD_CLOEXEC);

	struct nonblock_io* ret;
	alt_nbio_import(L, pair[0], O_RDONLY, &ret);
	if (ret)
		arcan_tui_bgcopy(ib->tui, fdin, fdout, pair[1], 0);
	return 1;
}

static int tui_getenv(lua_State* L)
{
	size_t ci = 1;
	if (lua_type(L, ci) == LUA_TUSERDATA){
		ci++;
	}
	const char* key = luaL_optstring(L, ci, NULL);
	if (key){
		const char* val = getenv(key);
		if (val)
			lua_pushstring(L, val);
		else
			lua_pushnil(L);
		return 1;
	}

	extern char** environ;
	size_t pos = 0;
	lua_newtable(L);
	while (environ[pos]){
		char* key = environ[pos];
		char* val = strchr(key, '=');
		if (val){
			size_t len = (uintptr_t)val - (uintptr_t)key;
			lua_pushlstring(L, key, len);
			lua_pushstring(L, &val[1]);
		}
		else {
			lua_pushstring(L, environ[pos]);
			lua_pushboolean(L, true);
		}
		lua_rawset(L, -3);
		pos++;
	}
	return 1;
}

static int popen_wrap(lua_State* L)
{
	TUI_UDATA;

	if (-1 != ib->cwd_fd || -1 == fchdir(ib->cwd_fd))
		chdir(ib->cwd);

	return tui_popen(L);
}

static void register_tuimeta(lua_State* L)
{
	struct luaL_Reg tui_methods[] = {
		{"alive", alive},
		{"process", process},
		{"refresh", refresh},
		{"write", writeu8},
		{"write_to", write_tou8},
		{"set_handlers", settbl},
		{"update_identity", setident},
		{"set_default", defattr},
		{"reset", reset},
		{"reset_labels", resetlabels},
		{"to_clipboard", setcopy},
		{"cursor_pos", getcursor},
		{"new_window", reqwnd},
		{"erase", erase_screen},
		{"erase_region", erase_region},
		{"scroll", wnd_scroll},
		{"cursor_to", cursor_to},
		{"dimensions", screen_dimensions},
		{"close", tuiclose},
		{"get_color", color_get},
		{"set_color", color_set},
		{"set_flags", set_flags},
		{"announce_io", announce_io},
		{"request_io", request_io},
		{"alert", alert},
		{"notification", notification},
		{"failure", failure},
		{"state_size", statesize},
		{"content_size", contentsize},
		{"revert", revertwnd},
		{"listview", listwnd},
		{"bufferview", bufferwnd},
		{"readline", readline},
		{"utf8_step", utf8step},
		{"utf8_len", utf8length},
		{"popen", popen_wrap},
		{"pwait", tui_pid_status},
		{"psignal", tui_pid_signal},
		{"phandover", tui_phandover},
		{"fopen", tui_fopen},
		{"bgcopy", tui_fbond},
		{"getenv", tui_getenv},
		{"chdir", tui_chdir},
		{"hint", tui_wndhint},
	};

	/* will only be set if it does not already exist */
	if (luaL_newmetatable(L, TUI_METATABLE)){
		for (size_t i = 0; i < sizeof(tui_methods)/sizeof(tui_methods[0]); i++){
			lua_pushcfunction(L, tui_methods[i].func);
			lua_setfield(L, -2, tui_methods[i].name);
		}

		lua_pushvalue(L, -1); // tui_index_get);
		lua_setfield(L, -2, "__index");
		lua_pushvalue(L, -1); // tui_index_set);
		lua_setfield(L, -2, "__newindex");
		lua_pushcfunction(L, collect);
		lua_setfield(L, -2, "__gc");
		lua_pushcfunction(L, tui_tostring);
		lua_setfield(L, -2, "__tostring");

		alt_nbio_register(L, queue_nbio, dequeue_nbio);
	}
	lua_pop(L, 1);

	struct { const char* key; int val; } flagtbl[] = {
		{"auto_wrap", TUI_AUTO_WRAP},
		{"hide_cursor", TUI_HIDE_CURSOR},
/*	{"alternate", TUI_ALTERNATE}, intentionally omitted - only support alt */
		{"mouse", TUI_MOUSE},
		{"mouse_full", TUI_MOUSE_FULL}
	};

	lua_pushliteral(L, "flags");
	lua_newtable(L);
	for (size_t i = 0; i < COUNT_OF(flagtbl); i++){
		lua_pushstring(L, flagtbl[i].key);
		lua_pushnumber(L, flagtbl[i].val);
		lua_rawset(L, -3);
	}
	lua_settable(L, -3);

	lua_pushliteral(L, "attr");
	lua_pushcfunction(L, tui_attr);
	lua_settable(L, -3);

	struct { const char* key; int val; } coltbl[] = {
	{"primary", TUI_COL_PRIMARY},
	{"secondary", TUI_COL_SECONDARY},
	{"background", TUI_COL_BG},
	{"text", TUI_COL_TEXT},
	{"cursor", TUI_COL_CURSOR},
	{"altcursor", TUI_COL_ALTCURSOR},
	{"highlight", TUI_COL_HIGHLIGHT},
	{"label", TUI_COL_LABEL},
	{"warning", TUI_COL_WARNING},
	{"error", TUI_COL_ERROR},
	{"alert", TUI_COL_ALERT},
	{"inactive", TUI_COL_INACTIVE},
	{"reference", TUI_COL_REFERENCE},
	{"ui", TUI_COL_UI},
	};
	lua_pushliteral(L, "colors");
	lua_newtable(L);
	for (size_t i = 0; i < COUNT_OF(coltbl); i++){
		lua_pushstring(L, coltbl[i].key);
		lua_pushnumber(L, coltbl[i].val);
		lua_rawset(L, -3);
	}
	lua_settable(L, -3);

	struct { const char* key; int val; } symtbl[] = {
	{"TUIK_UNKNOWN", TUIK_UNKNOWN},
	{"TUIK_FIRST", TUIK_FIRST},
	{"TUIK_BACKSPACE", TUIK_BACKSPACE},
	{"TUIK_TAB", TUIK_TAB},
	{"TUIK_CLEAR", TUIK_CLEAR},
	{"TUIK_RETURN", TUIK_RETURN},
	{"TUIK_PAUSE", TUIK_PAUSE},
	{"TUIK_ESCAPE", TUIK_ESCAPE},
	{"TUIK_SPACE", TUIK_SPACE},
	{"TUIK_EXCLAIM", TUIK_EXCLAIM},
	{"TUIK_QUOTEDBL", TUIK_QUOTEDBL},
	{"TUIK_HASH", TUIK_HASH},
	{"TUIK_DOLLAR", TUIK_DOLLAR},
	{"TUIK_0", TUIK_0},
	{"TUIK_1", TUIK_1},
	{"TUIK_2", TUIK_2},
	{"TUIK_3", TUIK_3},
	{"TUIK_4", TUIK_4},
	{"TUIK_5", TUIK_5},
	{"TUIK_6", TUIK_6},
	{"TUIK_7", TUIK_7},
	{"TUIK_8", TUIK_8},
	{"TUIK_9", TUIK_9},
	{"TUIK_MINUS", TUIK_MINUS},
	{"TUIK_EQUALS", TUIK_EQUALS},
	{"TUIK_A", TUIK_A},
  {"TUIK_B", TUIK_B},
	{"TUIK_C", TUIK_C},
	{"TUIK_D", TUIK_D},
	{"TUIK_E", TUIK_E},
	{"TUIK_F", TUIK_F},
	{"TUIK_G", TUIK_G},
	{"TUIK_H", TUIK_H},
	{"TUIK_I", TUIK_I},
	{"TUIK_J", TUIK_J},
	{"TUIK_K", TUIK_K},
	{"TUIK_L", TUIK_L},
	{"TUIK_M", TUIK_M},
	{"TUIK_N", TUIK_N},
	{"TUIK_O", TUIK_O},
	{"TUIK_P", TUIK_P},
	{"TUIK_Q", TUIK_Q},
	{"TUIK_R", TUIK_R},
	{"TUIK_S", TUIK_S},
	{"TUIK_T", TUIK_T},
	{"TUIK_U", TUIK_U},
	{"TUIK_V", TUIK_V},
	{"TUIK_W", TUIK_W},
	{"TUIK_X", TUIK_X},
	{"TUIK_Y", TUIK_Y},
	{"TUIK_Z", TUIK_Z},
	{"TUIK_LESS", TUIK_LESS},
	{"TUIK_KP_LEFTBRACE", TUIK_KP_LEFTBRACE},
	{"TUIK_KP_RIGHTBRACE", TUIK_KP_RIGHTBRACE},
	{"TUIK_KP_ENTER", TUIK_KP_ENTER},
	{"TUIK_LCTRL", TUIK_LCTRL},
	{"TUIK_SEMICOLON", TUIK_SEMICOLON},
	{"TUIK_APOSTROPHE", TUIK_APOSTROPHE},
	{"TUIK_GRAVE", TUIK_GRAVE},
	{"TUIK_LSHIFT", TUIK_LSHIFT},
	{"TUIK_BACKSLASH", TUIK_BACKSLASH},
	{"TUIK_COMMA", TUIK_COMMA},
	{"TUIK_PERIOD", TUIK_PERIOD},
	{"TUIK_SLASH", TUIK_SLASH},
	{"TUIK_RSHIFT", TUIK_RSHIFT},
	{"TUIK_KP_MULTIPLY", TUIK_KP_MULTIPLY},
	{"TUIK_LALT", TUIK_LALT},
	{"TUIK_CAPSLOCK", TUIK_CAPSLOCK},
	{"TUIK_F1", TUIK_F1},
	{"TUIK_F2", TUIK_F2},
	{"TUIK_F3", TUIK_F3},
	{"TUIK_F4", TUIK_F4},
	{"TUIK_F5", TUIK_F5},
	{"TUIK_F6", TUIK_F6},
	{"TUIK_F7", TUIK_F7},
	{"TUIK_F8", TUIK_F8},
	{"TUIK_F9", TUIK_F9},
	{"TUIK_F10", TUIK_F10},
	{"TUIK_NUMLOCKCLEAR", TUIK_NUMLOCKCLEAR},
	{"TUIK_SCROLLLOCK", TUIK_SCROLLLOCK},
	{"TUIK_KP_0", TUIK_KP_0},
	{"TUIK_KP_1", TUIK_KP_1},
	{"TUIK_KP_2", TUIK_KP_2},
	{"TUIK_KP_3", TUIK_KP_3},
	{"TUIK_KP_4", TUIK_KP_4},
	{"TUIK_KP_5", TUIK_KP_5},
	{"TUIK_KP_6", TUIK_KP_6},
	{"TUIK_KP_7", TUIK_KP_7},
	{"TUIK_KP_8", TUIK_KP_8},
	{"TUIK_KP_9", TUIK_KP_9},
	{"TUIK_KP_MINUS", TUIK_KP_MINUS},
	{"TUIK_KP_PLUS", TUIK_KP_PLUS},
	{"TUIK_KP_PERIOD", TUIK_KP_PERIOD},
	{"TUIK_INTERNATIONAL1", TUIK_INTERNATIONAL1},
	{"TUIK_INTERNATIONAL2", TUIK_INTERNATIONAL2},
	{"TUIK_F11", TUIK_F11},
	{"TUIK_F12", TUIK_F12},
	{"TUIK_INTERNATIONAL3", TUIK_INTERNATIONAL3},
	{"TUIK_INTERNATIONAL4", TUIK_INTERNATIONAL4},
	{"TUIK_INTERNATIONAL5", TUIK_INTERNATIONAL5},
	{"TUIK_INTERNATIONAL6", TUIK_INTERNATIONAL6},
	{"TUIK_INTERNATIONAL7", TUIK_INTERNATIONAL7},
	{"TUIK_INTERNATIONAL8", TUIK_INTERNATIONAL8},
	{"TUIK_INTERNATIONAL9", TUIK_INTERNATIONAL9},
	{"TUIK_RCTRL", TUIK_RCTRL},
	{"TUIK_KP_DIVIDE", TUIK_KP_DIVIDE},
	{"TUIK_SYSREQ", TUIK_SYSREQ},
	{"TUIK_RALT", TUIK_RALT},
	{"TUIK_HOME", TUIK_HOME},
	{"TUIK_UP", TUIK_UP},
	{"TUIK_PAGEUP", TUIK_PAGEUP},
	{"TUIK_LEFT", TUIK_LEFT},
	{"TUIK_RIGHT", TUIK_RIGHT},
	{"TUIK_END", TUIK_END},
	{"TUIK_DOWN", TUIK_DOWN},
	{"TUIK_PAGEDOWN", TUIK_PAGEDOWN},
	{"TUIK_INSERT", TUIK_INSERT},
	{"TUIK_DELETE", TUIK_DELETE},
	{"TUIK_LMETA", TUIK_LMETA},
	{"TUIK_RMETA", TUIK_RMETA},
	{"TUIK_COMPOSE", TUIK_COMPOSE},
	{"TUIK_MUTE", TUIK_MUTE},
	{"TUIK_VOLUMEDOWN", TUIK_VOLUMEDOWN},
	{"TUIK_VOLUMEUP", TUIK_VOLUMEUP},
	{"TUIK_POWER", TUIK_POWER},
	{"TUIK_KP_EQUALS", TUIK_EQUALS},
	{"TUIK_KP_PLUSMINUS", TUIK_KP_PLUSMINUS},
	{"TUIK_LANG1", TUIK_LANG1},
	{"TUIK_LANG2", TUIK_LANG2},
	{"TUIK_LANG3", TUIK_LANG3},
	{"TUIK_LGUI", TUIK_LGUI},
	{"TUIK_RGUI", TUIK_RGUI},
	{"TUIK_STOP", TUIK_STOP},
	{"TUIK_AGAIN", TUIK_AGAIN}
	};

/* push the keyboard symbol table as both b = a and a = b */
	lua_pushliteral(L, "keys");
	lua_newtable(L);
	for (size_t i = 0; i < COUNT_OF(symtbl); i++){
		lua_pushstring(L, &symtbl[i].key[5]);
		lua_pushnumber(L, symtbl[i].val);
		lua_rawset(L, -3);
		lua_pushnumber(L, symtbl[i].val);
		lua_pushstring(L, &symtbl[i].key[5]);
		lua_rawset(L, -3);
	}
	lua_settable(L, -3);

	struct { const char* key; int val; } modtbl[] = {
		{"LSHIFT", TUIM_LSHIFT},
		{"RSHIFT", TUIM_RSHIFT},
		{"SHIFT", TUIM_LSHIFT | TUIM_RSHIFT},
		{"LCTRL", TUIM_LCTRL},
		{"RCTRL", TUIM_RCTRL},
		{"CTRL", TUIM_LCTRL | TUIM_RCTRL},
		{"LALT", TUIM_LALT},
		{"RALT", TUIM_RALT},
		{"ALT", TUIM_LALT | TUIM_RALT},
		{"LMETA", TUIM_LMETA},
		{"RMETA", TUIM_RMETA},
		{"META", TUIM_LMETA | TUIM_RMETA},
		{"REPEAT", TUIM_REPEAT}
	};

  lua_pushliteral(L, "modifiers");
	lua_newtable(L);
	for (size_t i = 0; i < COUNT_OF(modtbl); i++){
		lua_pushstring(L, modtbl[i].key);
		lua_pushnumber(L, modtbl[i].val);
		lua_rawset(L, -3);
	}
	lua_settable(L, -3);

	if (luaL_newmetatable(L, "widget_readline")){
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, readline_prompt);
		lua_setfield(L, -2, "set_prompt");
		lua_pushcfunction(L, readline_history);
		lua_setfield(L, -2, "set_history");
		lua_pushcfunction(L, readline_suggest);
		lua_setfield(L, -2, "suggest");
		lua_pushcfunction(L, readline_set);
		lua_setfield(L, -2, "set");
		lua_pushcfunction(L, readline_region);
		lua_setfield(L, -2, "bounding_box");
		lua_pushcfunction(L, readline_autocomplete);
		lua_setfield(L, -2, "autocomplete");
	}
	lua_pop(L, 1);

	if (luaL_newmetatable(L, "widget_listview")){
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, listwnd_pos);
		lua_setfield(L, -2, "position");
		lua_pushcfunction(L, listwnd_update);
		lua_setfield(L, -2, "update");
	}
	lua_pop(L, 1);

/* The synch etc. functions are not really needed, revert + setup again works
 * as we don't have shared buffers between Lua and C. */
	if (luaL_newmetatable(L, "widget_bufferview")){
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, bufferwnd_seek);
		lua_setfield(L, -2, "seek");
		lua_pushcfunction(L, bufferwnd_tell);
		lua_setfield(L, -2, "position");
	}
	lua_pop(L, 1);
}

int
luaopen_arcantui(lua_State* L)
{
	struct luaL_Reg luaarcantui[] = {
		{"APIVersion", apiversion},
		{"APIVersionString", apiversionstr},
		{"open", tui_open},
	};

	lua_newtable(L);
	for (size_t i = 0; i < sizeof(luaarcantui)/sizeof(luaarcantui[0]); i++){
		lua_pushstring(L, luaarcantui[i].name);
		lua_pushcfunction(L, luaarcantui[i].func);
		lua_settable(L, -3);
	}

	lua_pushliteral(L, "_COPYRIGHT");
	lua_pushliteral(L, "Copyright (C) Bjorn Stahl");
	lua_settable(L, -3);
	lua_pushliteral(L, "_DESCRIPTION");
	lua_pushliteral(L, "TUI API for Arcan");
	lua_settable(L, -3);
	lua_pushliteral(L, "_VERSION");
	lua_pushliteral(L, "arcantuiapi 1.0.0");
	lua_settable(L, -3);

	register_tuimeta(L);

	return 1;
}
