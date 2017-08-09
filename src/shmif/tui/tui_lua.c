/* Copyright 2017, Björn Ståhl
 * License: 3-clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: This adds a naive mapping to the TUI API for Lua scripting.
 * Simply append- the related functions to a Lua contxt, and you should be
 * able to open/connect using tui_open() -> context.
 * For more detailed examples, see shmif/tui
 *
 * Checklist:
 *   Normal drawing API: 5%
 *   Event mapping: 70%:
 *       file mapping / mutiplex missing
 *
 *   Subwindow management / support:
 *       "free" subwindow
 *       embedded subwindow
 *       popup
 *
 *   TUI extensions: 0%
 *       - custom cells:
 *                "putpixel"
 *                "buffer map"
 *                "tile map" (register pixel group as tile and ref.)
 *       - multiple screens (switching)
 *   Handover- protocol for sharing shmif- sessions
 *   TUI cleanup: 0%
 *
 * PoCs:
 */

#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

struct tui_lmeta {
	struct tui_context* tui;
	int href;
	const char* last_words;
	lua_State* lua;
};

struct tui_cattr {
	struct tui_screen_attr attr;
};

static void dump_stack(lua_State* ctx)
{
	int top = lua_gettop(ctx);
	printf("-- stack dump (%d)--\n", top);

	for (int i = 1; i <= top; i++){
		int t = lua_type(ctx, i);

		switch (t){
		case LUA_TBOOLEAN:
			printf(lua_toboolean(ctx, i) ? "true" : "false");
		break;
		case LUA_TSTRING:
			printf("%d\t'%s'\n", i, lua_tostring(ctx, i));
			break;
		case LUA_TNUMBER:
			printf("%d\t%g\n", i, lua_tonumber(ctx, i));
			break;
		default:
			printf("%d\t%s\n", i, lua_typename(ctx, t));
			break;
		}
	}

	printf("\n");
}

#define SETUP_HREF(X, B) \
	struct tui_lmeta* meta = t;\
	lua_State* L = meta->lua;\
	if (meta->href == LUA_REFNIL)\
		return B;\
	lua_rawgeti(L, LUA_REGISTRYINDEX, meta->href);\
	lua_getfield(L, -1, X);\
	if (lua_type(L, -1) != LUA_TFUNCTION){\
		lua_pop(L, 2);\
		return B;\
	}\
	lua_pushvalue(L, -2);

#define END_HREF lua_pop(L, 1);

/* chain: [label] -> x -> [u8] -> x -> [key] where (x) is a
 * return true- early out */
static bool on_label(struct tui_context* c, const char* label, bool act, void* t)
{
	SETUP_HREF("label", false);
	lua_pushboolean(L, act);
	lua_call(L, 3, 1);
	lua_pop(L, 1);
	END_HREF;
	return false;
}

static bool on_u8(struct tui_context* c, const char* u8, size_t len, void* t)
{
	SETUP_HREF("utf8", false);
		lua_pushlstring(L, u8, len);
		lua_call(L, 2, 1);
		bool rv = false;
		if (lua_isnumber(L, -1))
			rv = lua_tonumber(L, -1);
		else if (lua_isboolean(L, -1))
			rv = lua_toboolean(L, -1);
		lua_pop(L, 1);
	END_HREF;
	return rv;
}

static bool on_alabel(struct tui_context* c, const char* label,
		const int16_t* smpls, size_t n, bool rel, uint8_t datatype, void* t)
{
	return false;
}

static void on_mouse(struct tui_context* c,
	bool relative, int x, int y, int modifiers, void* t)
{
	SETUP_HREF("mouse_motion",);
		lua_pushboolean(L, relative);
		lua_pushnumber(L, x);
		lua_pushnumber(L, y);
		lua_pushnumber(L, modifiers);
		lua_call(L, 5, 0);
	END_HREF;
}

static void on_mouse_button(struct tui_context* c,
	int x, int y, int subid, bool active, int modifiers, void* t)
{
	SETUP_HREF("mouse_button",);
		lua_pushnumber(L, subid);
		lua_pushboolean(L, active);
		lua_pushnumber(L, x);
		lua_pushnumber(L, y);
		lua_pushnumber(L, modifiers);
		lua_call(L, 6, 0);
	END_HREF;
}

static void on_key(struct tui_context* c, uint32_t xkeysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	SETUP_HREF("key",);
		lua_pushnumber(L, subid);
		lua_pushnumber(L, xkeysym);
		lua_pushnumber(L, scancode);
		lua_pushnumber(L, mods);
		lua_call(L, 5, 0);
	END_HREF;
}

/*
 * don't forward this for now, should only really hit game devices etc.
 */
static void on_misc(struct tui_context* c, const arcan_ioevent* ev, void* t)
{
}

/*
 * need file/asynch like behavior from libuv, possibly through lanes
 *
 * need:
 *  - splice behavior
 *  -
 */
static void on_state(struct tui_context* c, bool input, int fd, void* t)
{
	SETUP_HREF( (input?"state_in":"state_out"), );

	int fd2 = arcan_shmif_dupfd(fd, -1, true);
	if (-1 == fd2){
		lua_pop(L, 1);
		END_HREF;
		return;
	}

	FILE** pf = (FILE**) lua_newuserdata(L, sizeof(FILE*));
	luaL_getmetatable(L, LUA_FILEHANDLE);
	lua_setmetatable(L, -2);
	*pf = fdopen(fd2, input ? "r" : "w");
	lua_call(L, 2, 0);

	END_HREF;
}

static void on_bchunk(struct tui_context* c,
	bool input, uint64_t size, int fd, void* t)
{
/* same as on_state */
}

static void on_vpaste(struct tui_context* c,
		shmif_pixel* vidp, size_t w, size_t h, size_t stride, void* t)
{
/* want to expose something like the calc-target, along with a
 * map-to-cell? */
}

static void on_apaste(struct tui_context* c,
	shmif_asample* audp, size_t n_samples, size_t frequency, size_t nch, void* t)
{
/*
 * don't have a good way to use this right now..
 */
}

static void on_tick(struct tui_context* c, void* t)
{
	SETUP_HREF("tick",);
		lua_call(L, 1, 0);
	END_HREF;
}

static void on_utf8_paste(struct tui_context* c,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	SETUP_HREF("paste",);
		lua_pushlstring(L, (const char*) str, len);
		lua_pushnumber(L, cont);
		lua_call(L, 3, 0);
	END_HREF;
}

static void on_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	SETUP_HREF("resize",);
		lua_pushnumber(L, col);
		lua_pushnumber(L, row);
		lua_pushnumber(L, neww);
		lua_pushnumber(L, newh);
		lua_call(L, 5, 0);
	END_HREF;
}

static void on_subwindow(struct tui_context* c,
	enum ARCAN_SEGID type, uint32_t id, struct arcan_shmif_cont* cont, void* tag)
{
/*
 * Lookup tui context and pending request based on ID,
 * if found, bind to a new _tui setup and emit - on failure,
 * emit the same. Need an explicit GC release as well..
 */
}

static bool query_label(struct tui_context* ctx,
	size_t ind, const char* country, const char* lang,
	struct tui_labelent* dstlbl)
{
/*
 * labels are part of an option table that is part of the initial lua
 * setup (options table)
 */
	return false;
}

static bool intblbool(lua_State* ctx, int ind, const char* field)
{
	lua_getfield(ctx, ind, field);
	bool rv = lua_toboolean(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}

static int intblint(lua_State* ctx, int ind, const char* field)
{
	lua_getfield(ctx, ind, field);
	int rv = lua_tointeger(ctx, -1);
	lua_pop(ctx, 1);
	return rv;
}

static void apply_table(lua_State* L, int ind, struct tui_screen_attr* attr)
{
	attr->bold = intblbool(L, ind, "bold");
	attr->underline = intblbool(L, ind, "underline");
	attr->italic = intblbool(L, ind, "italic");
	attr->inverse = intblbool(L, ind, "inverse");
	attr->protect = intblbool(L, ind, "protect");
	attr->blink = intblbool(L, ind, "blink");
	attr->strikethrough = intblbool(L, ind, "strikethrough");
	attr->custom_id = intblint(L, ind, "id");
}

static int tui_cattr(lua_State* L)
{
	struct tui_screen_attr attr = {
		.fr = 255,
		.fg = 255,
		.fb = 255
	};

	if (lua_type(L, 1) == LUA_TTABLE)
		apply_table(L, 1, &attr);

	struct tui_cattr* cattr = lua_newuserdata(L, sizeof(struct tui_cattr));
	if (!cattr)
		return 0;

	cattr->attr = attr;
	luaL_getmetatable(L, "tui_cattr");
	lua_setmetatable(L, -2);

	return 1;
}

static int setattr(lua_State* L)
{
/* 1. if userdata: check metatable for tui cattr
 * 2. if table, run decode on attr and replace current */
	return 0;
}

static int tui_open(lua_State* L)
{
	const char* title = luaL_checkstring(L, 1);
	const char* ident = luaL_checkstring(L, 2);

	struct tui_lmeta* meta = lua_newuserdata(L, sizeof(struct tui_lmeta));
	if (!meta){
		return 0;
	}

	arcan_tui_conn* conn = arcan_tui_open_display(title, ident);
/* will be GCd */
	if (!conn){
		lua_pop(L, 1);
		return 0;
	}

/* set the TUI api table to our metadata */
	luaL_getmetatable(L, "tui_main");
	lua_setmetatable(L, -2);

/* reference the lua context as part of the tag that is tied to the
 * shmif/tui context struct so we can reach lua from callbacks */
	meta->lua = L;
	meta->last_words = NULL;

	struct tui_settings cfg = arcan_tui_defaults(conn, NULL);

/* FIXME: modify cfg with custom table */
	if (lua_type(L, 3) == LUA_TTABLE){
	}

/* Hook up the tui/callbacks, these forward into a handler table
 * that the user provide a reference to. */
	struct tui_cbcfg cbcfg = {
		.query_label = query_label,
		.input_label = on_label,
		.input_alabel = on_alabel,
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
		.resized = on_resize,
		.subwindow = on_subwindow,
		.tag = meta
	};
	meta->href = LUA_REFNIL;

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
			return 0;
		}
	}

/* display cleanup is now in the hand of _setup */
	meta->tui = arcan_tui_setup(&conn, &cfg, &cbcfg, sizeof(cbcfg));
	if (!meta->tui){
		lua_pop(L, 1);
		return 0;
	}

	return 1;
}

/*
 * convenience macro prolog for all TUI window bound lua->c functions
 */
#define TUI_UDATA	\
	struct tui_lmeta* ib = luaL_checkudata(L, 1, "tui_main"); \
	if (!ib || !ib->tui) return 0; \

static int refresh(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_refresh(ib->tui);
	return 0;
}

static int valid_flag(lua_State* L, int ind)
{
	return 0;
}

/* map to the screen attribute bitfield */
static int tui_index_get(lua_State* L)
{
	TUI_UDATA;
	int id;

	printf("index get\n");
	if (lua_type(L, 1) == LUA_TSTRING && (id = valid_flag(L, 1))){

	}

	return 0;
}

static int tui_index_set(lua_State* L)
{
	TUI_UDATA;
	int id;

	printf("index set\n");
	if (lua_type(L, 1) == LUA_TSTRING && (id = valid_flag(L, 1)) && (
		lua_type(L, 2) == LUA_TNUMBER || lua_type(L, 2) == LUA_TBOOLEAN)){

	}
	return 0;
}

static int collect(lua_State* L)
{
	TUI_UDATA;
	if (ib->tui){
		arcan_tui_destroy(ib->tui, ib->last_words);
		ib->tui = NULL;
	}
	if (ib->href != LUA_REFNIL){
		lua_unref(L, ib->href);
		ib->href = LUA_REFNIL;
	}

	return 0;
}

static int settbl(lua_State* L)
{
	TUI_UDATA;
	if (ib->href != LUA_REFNIL){
		lua_unref(L, ib->href);
		ib->href = LUA_REFNIL;
	}

	luaL_checktype(L, 2, LUA_TTABLE);

	return 0;
}

static int setident(lua_State* L)
{
	TUI_UDATA;
	const char* ident = luaL_optstring(L, 1, "");
	arcan_tui_ident(ib->tui, ident);
	return 0;
}

static int setcopy(lua_State* L)
{
	TUI_UDATA;
	const char* pstr = luaL_optstring(L, 1, "");
	lua_pushboolean(L, arcan_tui_copy(ib->tui, pstr));
	return 1;
}

static int reqwnd(lua_State* L)
{
	TUI_UDATA;
/* const char* type = luaL_optstring(L, 1, "tui");
 * 1. check for valid subtypes
 * 2. request REGISTRY entry for function
 * 3. use that entry as ID so we can pair when we come back,
 * 4. forward to request subwnd, then do the rest in the eventhandler,
 * 5. map the new TUI as the right subtype, and grab the right metatable */
	return 0;
}

static int setmouse(lua_State* L)
{
	TUI_UDATA;
/* mouse forward, either grab value or toggle */
	return 0;
}

static int process(lua_State* L)
{
	TUI_UDATA;

	int timeout = luaL_optnumber(L, 2, -1);
/* FIXME: if arg-2 is table, sweep and build descriptor table,
 * and use the last integer as timeout */

/*
 * FIXME: use a bitmap to track multiple allocations
 */
/*	struct tui_process_res res = */
		arcan_tui_process(&ib->tui, 1, NULL, 0, timeout);

/*
 * FIXME: extract / translate error code and result-sets
 */

	lua_pushboolean(L, true);
	return 1;
}

static int reset(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_reset(ib->tui);
	return 0;
}

#undef TUI_UDATA

/*
 * constants needed:
 *  - screen mode
 *  - color groups:
 *    fg, bg, button, light, dark, mid, text, base,
 *    midlight, brigtTxt, buttonTxt, shadow, highlight,
 *    highlight text, link, link visited
 */

#define REGISTER(X, Y) lua_pushcfunction(L, Y); lua_setfield(L, -2, X);
void tui_lua_expose(lua_State* L)
{
	lua_pushstring(L, "tui_open");
	lua_pushcclosure(L, tui_open, 1);
	lua_setglobal(L, "tui_open");

	lua_pushstring(L, "tui_cattr");
	lua_pushcclosure(L, tui_cattr, 1);
	lua_setglobal(L, "tui_cattr");

	luaL_newmetatable(L, "tui_cattr");
	lua_pop(L, 1);

	luaL_newmetatable(L, "tui_main");
	lua_pushvalue(L, -1); // tui_index_get);
	lua_setfield(L, -2, "__index");
	lua_pushvalue(L, -1); // tui_index_set);
	lua_setfield(L, -2, "__newindex");
	lua_pushcfunction(L, collect);
	lua_setfield(L, -2, "__gc");

	REGISTER("refresh", refresh);
	REGISTER("process", process);
	REGISTER("set_handlers", settbl);
	REGISTER("change_ident", setident);
	REGISTER("mouse_forward", setmouse);
	REGISTER("set_attr", setattr);
	REGISTER("reset", reset);
	REGISTER("to_clipboard", setcopy);

	lua_pop(L, 1);
}
