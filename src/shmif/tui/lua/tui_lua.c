/* Copyright: Björn Ståhl
 * License: 3-clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: This adds a naive mapping to the TUI API for Lua scripting.
 * Simply append- the related functions to a Lua context, and you should be
 * able to open/connect using tui_open() -> context.
 *
 * TODO:
 *   [ ] add blob-io from arcan
 *   [ ] add bgcopy with signalling
 *   [ ] handover exec on new window
 *   [ ] arcan_tui_wndhint support
 *
 *   [ ] Add bufferwnd
 *
 *   [ ] multiple windows
 *       add to wnd:process for parent
 *       allow extended form with window creation hints
 *
 *   [ ] apaste/vpaste does nothing - map to bchunk_in?
 *   [ ] Hasglyph
 *   [ ] Handover media embed
 */

#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_listwnd.h>
#include <arcan_tui_bufferwnd.h>
#include <arcan_tui_linewnd.h>
#include <arcan_tui_readline.h>

#include <assert.h>
#include <stdbool.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <errno.h>
#include <string.h>
#include <strings.h>

#include "tui_lua.h"

#define TUI_METATABLE	"Arcan TUI"

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

static const uint32_t req_cookie = 0xfeedface;
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
	"blob_asio"
};

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

static void register_tuimeta(lua_State* L);
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
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);\
	if (!ib || !ib->tui || ib->widget_mode != TWND_LINEWND)\
		luaL_error(L, "window not in linewnd state");

#define TUI_BUFWNDDATA \
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);\
	if (!ib || !ib->tui || ib->widget_mode != TWND_BUFWND)\
		luaL_error(L, "window not in bufferwnd state");

#define TUI_READLINEDATA \
	struct widget_meta* meta = luaL_checkudata(L, 1, "widget_readline");\
	if (!meta || !meta->parent)\
		luaL_error(L, "widget metadata freed");\
	struct tui_lmeta* ib = meta->parent;\
	if (!ib || !ib->tui || ib->widget_mode != TWND_READLINE)\
		luaL_error(L, "window not in readline state");

static void init_lmeta(struct tui_lmeta* l)
{
	*l = (struct tui_lmeta){
		.widget_closure = LUA_NOREF,
		.href = LUA_NOREF,
		.widget_state = LUA_NOREF,
		.tui_state = LUA_NOREF
	};
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
		RUN_CALLBACK("mouse_button", 5, 0);
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

static int blob_close(lua_State* L)
{
	struct blobio_meta* ib = luaL_checkudata(L, 1, "blob_asio");
	if (ib->closed){
		luaL_error(L, "close() on already closed blob");
		return 0;
	}

	ib->closed = true;
	close(ib->fd);
	return 0;
}

static int blob_datahandler(lua_State* L)
{
/* two possible options, one is to set a lstring as the buffer to write and
 * we take care of everything - though be mindful about GC and keep a reference
 * until that happens.
 *
 * second is to add a callback handler and invoke that as part of wnd:process
 */
	return 0;
}

static void add_blobio(lua_State* L, struct tui_lmeta* M, bool input, int fd)
{
	struct blobio_meta* meta = lua_newuserdata(L, sizeof(struct blobio_meta));
	*meta = (struct blobio_meta){
		.fd = fd,
		.input = input,
		.owner = M
	};
	luaL_getmetatable(L, "blob_asio");
	lua_setmetatable(L, -2);
}

static void on_state(struct tui_context* T, bool input, int fd, void* t)
{
	SETUP_HREF( (input?"state_in":"state_out"), );
	add_blobio(L, t, input, fd);
	RUN_CALLBACK("state_inout", 2, 0);
	END_HREF;
}

static void on_bchunk(struct tui_context* T,
	bool input, uint64_t size, int fd, const char* type, void* t)
{
	SETUP_HREF((input ?"bchunk_in":"bchunk_out"), );
	add_blobio(L, t, input, fd);
	lua_pushstring(L, type);
	RUN_CALLBACK("bchunk_inout", 3, 0);

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
		lua_pushnumber(L, col);
		lua_pushnumber(L, row);
		lua_pushnumber(L, neww);
		lua_pushnumber(L, newh);
		RUN_CALLBACK("resize", 5, 0);
	END_HREF;
}

static bool on_subwindow(struct tui_context* T,
	arcan_tui_conn* new, uint32_t id, uint8_t type, void* t)
{
	SETUP_HREF("subwindow",false);
	id ^= req_cookie;

/* indicates that there's something wrong with the connection */
	if (id >= 8 || !(meta->pending_mask & (1 << id)))
		return false;

	intptr_t cb = meta->pending[id];
	meta->pending[id] = 0;
	meta->pending_mask &= ~(1 << id);

/* pcall and deref */
	if (!new){
		RUN_CALLBACK("subwindow_fail", 1, 0);
		END_HREF;
		return false;
	}

/* let the caller be responsible for updating the handlers */
	struct tui_context* ctx =
		arcan_tui_setup(new, T, &shared_cbcfg, sizeof(shared_cbcfg));
	if (!ctx){
		RUN_CALLBACK("subwindow_setup_fail", 1, 0);
		END_HREF;
		return true;
	}

	struct tui_lmeta* nud = lua_newuserdata(L, sizeof(struct tui_lmeta));
	if (!nud){
		RUN_CALLBACK("subwindow_ud_fail", 1, 0);
		END_HREF;
		return true;
	}

	init_lmeta(nud);
	nud->tui = ctx;
	luaL_getmetatable(L, TUI_METATABLE);
	lua_setmetatable(L, -2);
	nud->lua = L;
	nud->last_words = NULL;
	nud->href = cb;

/* missing - attach to parent and add to its context list for processing */
	RUN_CALLBACK("subwindow_ok", 2, 0);
	END_HREF;
	return true;
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
	printf("call over, rv: %d\n", rv);
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
		if (res > 0)
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
	break;
	case TWND_BUFWND:
		arcan_tui_bufferwnd_release(M->tui);
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
	int steps = luaL_checkint(L, 2);
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
	size_t x1 = luaL_checkint(L, 2);
	size_t y1 = luaL_checkint(L, 3);
	size_t x2 = luaL_checkint(L, 4);
	size_t y2 = luaL_checkint(L, 5);
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
	int x = luaL_checkint(L, 2);
	int y = luaL_checkint(L, 3);
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);

	if (x >= 0 && y >= 0 && x < cols && y < rows)
		arcan_tui_move_to(ib->tui, x, y);

	return 0;
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
	init_lmeta(meta);
	lua_pushvalue(L, -1);
	meta->tui_state = luaL_ref(L, LUA_REGISTRYINDEX);

/* set the TUI api table to our metadata */
	luaL_getmetatable(L, TUI_METATABLE);
	lua_setmetatable(L, -2);

/* reference the lua context as part of the tag that is tied to the
 * shmif/tui context struct so we can reach lua from callbacks */
	meta->lua = L;
	meta->last_words = NULL;

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

static int tuiclose(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_destroy(ib->tui, luaL_optstring(L, 2, NULL));
	ib->tui = NULL;
	luaL_unref(L, LUA_REGISTRYINDEX, ib->tui_state);
	ib->tui_state = LUA_NOREF;

	lua_rawgeti(L, LUA_REGISTRYINDEX, ib->href);
	lua_getfield(L, -1, "destroy");
	if (lua_type(L, -1) != LUA_TFUNCTION){
		lua_pop(L, 2);
		return 0;
	}\
	lua_pushvalue(L, -3);
	RUN_CALLBACK("destroy", 1, 0);

	return 0;
}

static int collect(lua_State* L)
{
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);
	if (!ib)
		return 0;

	if (ib->tui){
		arcan_tui_destroy(ib->tui, ib->last_words);
		ib->tui = NULL;
	}
	if (ib->href != LUA_NOREF){
		luaL_unref(L, LUA_REGISTRYINDEX, ib->href);
		ib->href = LUA_NOREF;
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

	const char* type = luaL_optstring(L, 2, "tui");
	int ind;
	intptr_t ref = LUA_NOREF;
	if ( (ind = 2, lua_isfunction(L, 2)) || (ind = 3, lua_isfunction(L, 3)) ){
		lua_pushvalue(L, ind);
		luaL_ref(L, LUA_REGISTRYINDEX);
	}
	else
		luaL_error(L, "no closure provided");

	int tui_type = TUI_WND_TUI;
	if (strcmp(type, "popup") == 0)
		tui_type = TUI_WND_POPUP;
	else if (strcmp(type, "handover") == 0)
		tui_type = TUI_WND_HANDOVER;

	if (ib->pending_mask == 255){
		lua_pushboolean(L, false);
		return 1;
	}

	int bitind = ffs(ib->pending_mask) - 1;
	ib->pending[bitind] = ref;
	ib->pending_mask |= 1 << bitind;
	lua_pushboolean(L, true);
	arcan_tui_request_subwnd(ib->tui, tui_type, (uint32_t) bitind ^ req_cookie);

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

static int process(lua_State* L)
{
	TUI_UDATA;

	int timeout = luaL_optnumber(L, 2, -1);

	if (0)
		dump_stack(L);

/* FIXME: extend processing set with children, pull in table of file,
 *        extract their descriptor sets and poll, set results.
 *        lua_getfield(L, LUA_REGISTRYINDEX, LUA_FILEHANDLE ->
 *                     getmetatable etc.) */

	struct tui_process_res res =
		arcan_tui_process(ib->subs, ib->n_subs+1, NULL, 0, timeout);

	if (ib->widget_mode){
		switch(ib->widget_mode){
		case TWND_LISTWND:{
			struct tui_list_entry* ent;
			if (arcan_tui_listwnd_status(ib->tui, &ent)){
				lua_rawgeti(L, LUA_REGISTRYINDEX, ib->widget_closure);
				if (ent){
					lua_pushnumber(L, ent->tag);
				}
				else {
					lua_pushnil(L);
				}
				revert(L, ib);
				RUN_CALLBACK("listwnd_ok", 2, 0);
			}
		}
		break;
		case TWND_BUFWND:
		break;
		case TWND_READLINE:{
			char* buf;
			int sc = arcan_tui_readline_finished(ib->tui, &buf);
			if (sc){
				lua_rawgeti(L, LUA_REGISTRYINDEX, ib->widget_closure);
				lua_rawgeti(L, LUA_REGISTRYINDEX, ib->href);
				if (buf){
					lua_pushstring(L, buf);
				}
				else {
					lua_pushnil(L);
				}
/* Restore the context to its initial state so that the closure is allowed to
 * request a new readline request. Revert will actually free buf. */
				revert(L, ib);
				RUN_CALLBACK("readline_ok", 2, 0);
			}
		}
		break;
		default:
		break;
		}
	}

/*
 * FIXME: extract / translate error code and result-sets
 */
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

	size_t x = luaL_checkint(L, 2);
	size_t y = luaL_checkint(L, 3);
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

	arcan_tui_move_to(ib->tui, ox, oy);

	return 1;
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
	arcan_tui_get_color(ib->tui, luaL_checkint(L, 2), dst);
	lua_pushnumber(L, dst[0]);
	lua_pushnumber(L, dst[1]);
	lua_pushnumber(L, dst[2]);
	return 3;
}

static int set_flags(lua_State* L)
{
	TUI_UDATA;
	uint32_t flags = TUI_ALTERNATE;

	for (size_t i = 2; i < lua_gettop(L); i++){
		uint32_t val = luaL_checkint(L, i);
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
		luaL_checkint(L, 3),
		luaL_checkint(L, 4),
		luaL_checkint(L, 5)
	};
	arcan_tui_set_color(ib->tui, luaL_checkint(L, 2), dst);
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

static int refresh(lua_State* L)
{
	TUI_UDATA;
/* primary blocks processing on failure */
	int rc = arcan_tui_refresh(ib->tui);
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
	size_t state_sz = luaL_checkint(L, 2);
	arcan_tui_statesize(ib->tui, state_sz);
	return 0;
}

static int contentsize(lua_State* L)
{
	TUI_UDATA;
	size_t row_ofs = luaL_checkint(L, 2);
	size_t row_tot = luaL_checkint(L, 3);
	size_t col_ofs = luaL_optint(L, 4, 0);
	size_t col_tot = luaL_optint(L, 5, 0);
	arcan_tui_content_size(ib->tui, row_ofs, row_tot, col_ofs, col_tot);
	return 0;
}

static int revertwnd(lua_State* L)
{
	TUI_UDATA;
	revert(L, ib);
	return 0;
}

static void tbl_to_list(lua_State* L, struct tui_list_entry* base, size_t i)
{
	base[i] = (struct tui_list_entry){
		.label = "hi",
		.shortcut = "a",
		.indent = 0,
		.attributes = 0, /* CHECKED, HAS_SUB, SEPARATOR, PASSIVE, LABEL, HIDE */
		.tag = i
	};
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
		.verify = on_readline_verify
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

static int listwnd(lua_State* L)
{
	TUI_WNDDATA;

/* normally just drop whatever previous state we were in */
	revert(L, ib);

/* take input table and closure */
	if (lua_type(L, 2) != LUA_TTABLE){
		luaL_error(L, "set_list(table, closure) - missing table");
	}

	if (!lua_isfunction(L, 3) || lua_iscfunction(L, 3)){
		luaL_error(L, "set_list(table, closure) - missing closure function");
	}

	int nelems = lua_rawlen(L, 2);
	if (nelems <= 0){
		luaL_error(L, "set_list(table, clousure) - table has 0 elements");
	}

	struct tui_list_entry* tmplist = malloc(
		sizeof(struct tui_list_entry) * nelems);

	for (size_t i = 0; i < nelems; i++){
		lua_rawgeti(L, 2, i+1);
		tbl_to_list(L, tmplist, i);
		lua_pop(L, 1);
	}

	arcan_tui_listwnd_setup(ib->tui, tmplist, nelems);
	ib->widget_mode = TWND_LISTWND;
	ib->tmplist = tmplist;

	lua_pushvalue(L, 3);
	ib->widget_closure = luaL_ref(L, LUA_REGISTRYINDEX);

	return 0;
}

static ssize_t utf8len(const char* msg)
{
	ssize_t res = 0;
	uint32_t tmp;
	while (*msg){
		ssize_t step = arcan_tui_utf8ucs4(msg, &tmp);
		if (-1 == step)
			return -1;
		msg += step;
		res++;
	}
	return res;
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
	if (lua_type(L, 2) != LUA_TTABLE){
		luaL_error(L, "suggest(table) - missing table");
	}

	ssize_t nelem = lua_rawlen(L, 2);
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
	meta->readline.suggest = new_suggest;
	meta->readline.history_sz = count;
	arcan_tui_readline_suggest(
		meta->parent->tui, (const char**) new_suggest, count);

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
		{"set_list", listwnd},
		{"readline", readline},
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

/* used for blob-state handlers */
	luaL_newmetatable(L, "blob_asio");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, blob_close);
	lua_setfield(L, -2, "close");
	lua_pushcfunction(L, blob_close);
	lua_setfield(L, -2, "_gc");
	lua_pushcfunction(L, blob_datahandler);
	lua_setfield(L, -2, "data_handler");
	lua_pop(L, 1);

/* the tui-readline widget return */
	luaL_newmetatable(L, "widget_readline");
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
	lua_pushcfunction(L, readline_autocomplete);
	lua_setfield(L, -2, "autocomplete");
	lua_pop(L, 1);

/*
	luaL_newmetatable(L, "listwnd");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, listwnd_seek);
 */
}

int
luaopen_arcantui(lua_State* L)
{
	struct luaL_Reg luaarcantui[] = {
		{"APIVersion", apiversion},
		{"APIVersionString", apiversionstr},
		{"open", tui_open},
		{"attr", tui_attr},
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
