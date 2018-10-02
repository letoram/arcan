/* Copyright 2017, Björn Ståhl
 * License: 3-clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: This adds a naive mapping to the TUI API for Lua scripting.
 * Simply append- the related functions to a Lua context, and you should be
 * able to open/connect using tui_open() -> context.
 * For more detailed examples, see shmif/tui and a patched version of the
 * normal Lua CLI in tools/ltui
 *
 * TODO:
 * ONGOING: FINISH TUI -> SUBWINDOW MAPPING!
 *
 * map display constants and flags:
 * TUI_INSERT_MODE
 * TUI_AUTO_WRAP
 * TUI_REL_ORIGIN
 * TUI_INVERSE
 * TUI_HIDE_CURSOR,
 * TUI_FIXED_POS,
 * TUI_ALTERNATE
 *
 * + modifiers
 *
 * + viewport (positioning) :
 *   TUI_NORMAL
 *   TUI_FOCUS
 *   TUI_HIDDEN
 */

/*
 * ADVANCED MISSING
 * [ - map_external (maybe shmif-server only?),
 *   - map_exec ( execute binary with listening properties bound to an id )
 *   - redirect_external ( forward new connection primitives )
 *   - route_target( set id as event recipient, options of possible
 *     escape symbols or if io, mouse and misc should be mapped or only some)
 *   - request_subwnd( "type" )
 *   - shaping / language related attr ( format break option with new format- code)
 *   - identity and configuration keys
 *   - labelhints
 *   - state and file-types
 *   wndalign ( src, tgt, ...) (can say something like half-size, quarter-size)
 *   + clipboard
 */

#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "tui_lua.h"

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
	if (meta->href == LUA_REFNIL)\
		return B;\
	lua_rawgeti(L, LUA_REGISTRYINDEX, meta->href);\
	lua_getfield(L, -1, X);\
	if (lua_type(L, -1) != LUA_TFUNCTION){\
		lua_pop(L, 2);\
		return B;\
	}\
	lua_pushvalue(L, -3);

#define END_HREF lua_pop(L, 1);

/*
 * convenience macro prolog for all TUI window bound lua->c functions
 */
#define TUI_UDATA	\
	struct tui_lmeta* ib = luaL_checkudata(L, 1, "tui_main"); \
	if (!ib || !ib->tui) return 0; \

/*
 * version of luaL_checknumber that accepts true/false as numbers
 */
static lua_Number luaL_checkbnumber(lua_State* L, int narg)
{
	lua_Number d = lua_tonumber(L, narg);
	if (d == 0 && !lua_isnumber(L, narg)){
		if (!lua_isboolean(L, narg))
			luaL_typerror(L, narg, "number or boolean");
		else
			d = lua_toboolean(L, narg);
	}
	return d;
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
		lua_pushnumber(L, x);
		lua_pushnumber(L, y);
		lua_pushnumber(L, modifiers);
		lua_call(L, 5, 0);
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

static void on_recolor(struct tui_context* c, void* t)
{
	SETUP_HREF("recolor", );
		lua_call(L, 1, 0);
	END_HREF;
}

static void on_reset(struct tui_context* c, int level, void* t)
{
	SETUP_HREF("reset", );
		lua_pushnumber(L, level);
	lua_call(L, 2, 0);
}

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

bool on_draw(struct tui_context* c, tui_pixel* vidp,
	uint8_t custom_id, size_t ystep_index, uint8_t cell_yofs,
	uint8_t cell_w, uint8_t cell_h, size_t cols,
	bool invalidated, void* t)
{
/* need special code here to interface with shmif-server instead,
 * possibly as a support library */
	return false;
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

static void on_resized(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	SETUP_HREF("resized",);
		lua_pushnumber(L, col);
		lua_pushnumber(L, row);
		lua_pushnumber(L, neww);
		lua_pushnumber(L, newh);
		lua_call(L, 5, 0);
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

static bool on_subwindow(struct tui_context* c,
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
/* FIXME: get Lua function */

/* pcall and deref */
	if (!new){
		lua_call(L, 1, 0);
		END_HREF;
		return false;
	}

/* let the caller be responsible for updating the handlers */
	struct tui_settings cfg = arcan_tui_defaults(new, meta->tui);
	struct tui_context* ctx =
		arcan_tui_setup(new, &cfg, &shared_cbcfg, sizeof(shared_cbcfg));
	if (!ctx){
		lua_call(L, 1, 0);
		END_HREF;
		return true;
	}

	struct tui_lmeta* nud = lua_newuserdata(L, sizeof(struct tui_lmeta));
	if (!nud){
		lua_call(L, 1, 0);
		END_HREF;
		return true;
	}

	nud->tui = ctx;
	luaL_getmetatable(L, "tui_main");
	lua_setmetatable(L, -2);
	nud->lua = L;
	nud->last_words = NULL;
	nud->href = cb;

	lua_call(L, 2, 0);
	END_HREF;
	return true;
}

static bool query_label(struct tui_context* ctx,
	size_t ind, const char* country, const char* lang,
	struct tui_labelent* dstlbl, void* t)
{
	SETUP_HREF("query_label", false);

/*
 * lcall with country/lang, expect multi-return with label, descr
 * and fill in - if no arguments returned
 */
	return false;
	END_HREF;
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

static void add_attr_tbl(lua_State* L, struct tui_screen_attr attr)
{
	lua_newtable(L);

/* key-integer value */
#define SET_KIV(K, V) do { lua_pushstring(L, K); \
	lua_pushnumber(L, V); lua_rawset(L, -3); } while (0)

#define SET_BIV(K, V) do { lua_pushstring(L, K); \
	lua_pushboolean(L, V); lua_rawset(L, -3); } while (0)

	SET_KIV("fr", attr.fr); SET_KIV("fg", attr.fg); SET_KIV("fb", attr.fb);
	SET_KIV("br", attr.br); SET_KIV("bg", attr.bg); SET_KIV("bb", attr.bb);
	SET_BIV("bold", attr.bold); SET_BIV("underline", attr.underline);
	SET_BIV("protect", attr.protect); SET_BIV("blink", attr.blink);
	SET_BIV("strikethrough", attr.strikethrough);
	SET_BIV("break", attr.shape_break); SET_KIV("id", attr.custom_id);

#undef SET_KIV
#undef SET_BIV
}

static void apply_table(lua_State* L, int ind, struct tui_screen_attr* attr)
{
	attr->bold = intblbool(L, ind, "bold");
	attr->underline = intblbool(L, ind, "underline");
	attr->italic = intblbool(L, ind, "italic");
	attr->inverse = intblbool(L, ind, "inverse");
	attr->protect = intblbool(L, ind, "protect");
	attr->strikethrough = intblbool(L, ind, "strikethrough");
	attr->custom_id = intblint(L, ind, "id");

/* shape break should really cover more, i.e. language, ... */
	attr->shape_break = intblint(L, ind, "shape_break");

	attr->fr = intblint(L, ind, "fr");
	attr->fg = intblint(L, ind, "fg");
	attr->fb = intblint(L, ind, "fb");
	attr->br = intblint(L, ind, "br");
	attr->bg = intblint(L, ind, "bg");
	attr->bb = intblint(L, ind, "bb");
}

static int tui_attr(lua_State* L)
{
	struct tui_screen_attr attr = {
		.fr = 128, .fg = 128, .fb = 128
	};
	int ci = 1;

/* use context as base for color lookup */
	if (lua_type(L, ci) == LUA_TUSERDATA){
		struct tui_lmeta* ib = luaL_checkudata(L, ci++, "tui_main");
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
		add_attr_tbl(L, arcan_tui_defattr(ib->tui, NULL));

	return 1;
}

static int set_tabstop(lua_State* L)
{
	TUI_UDATA;
	int col = luaL_optnumber(L, 2, -1);
	int row = luaL_optnumber(L, 3, -1);

	if (row != -1 || col != -1){
		size_t x, y;
		arcan_tui_cursorpos(ib->tui, &x, &y);
		arcan_tui_move_to(ib->tui, row != -1 ? row : y, col != -1 ? col : x);
		arcan_tui_set_tabstop(ib->tui);
		arcan_tui_move_to(ib->tui, x, y);
	}
	else
		arcan_tui_set_tabstop(ib->tui);
	return 0;
}

static int insert_lines(lua_State* L)
{
	TUI_UDATA;
	int n_lines = luaL_checknumber(L, 2);
	if (n_lines > 0)
		arcan_tui_insert_lines(ib->tui, n_lines);
	return 0;
}

static int delete_lines(lua_State* L)
{
	TUI_UDATA;
	int n_lines = luaL_checknumber(L, 2);

	if (n_lines > 0)
		arcan_tui_delete_lines(ib->tui, n_lines);
	return 0;
}

static int insert_chars(lua_State* L)
{
	TUI_UDATA;
	int n_chars = luaL_checknumber(L, 2);
	if (n_chars > 0)
		arcan_tui_insert_chars(ib->tui, n_chars);
	return 0;
}

static int delete_chars(lua_State* L)
{
	TUI_UDATA;
	int n_chars = luaL_checknumber(L, 2);
	if (n_chars > 0)
		arcan_tui_delete_chars(ib->tui, n_chars);
	return 0;
}

static int wnd_scroll(lua_State* L)
{
	TUI_UDATA;
	int steps = luaL_checknumber(L, 2);
	if (steps > 0)
		arcan_tui_scroll_down(ib->tui, steps);
	else
		arcan_tui_scroll_up(ib->tui, -steps);
	return 0;
}

static int reset_tabs(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_reset_all_tabstops(ib->tui);
	return 0;
}

static int scrollhint(lua_State* L)
{
	TUI_UDATA;
/*	int steps = luaL_checknumber(L, 2);
 *	arcan_tui_scrollhint(ib->tui, steps);
 */
	return 0;
}

static int cursor_tab(lua_State* L)
{
	TUI_UDATA;
	int tabs = 1;
	if (lua_type(L, 2) == LUA_TNUMBER){
		tabs = lua_tonumber(L, 2);
	}
	if (tabs > 0)
		arcan_tui_tab_right(ib->tui, tabs);
	else
		arcan_tui_tab_left(ib->tui, -tabs);
	return 0;
}

static int cursor_steprow(lua_State* L)
{
	TUI_UDATA;
	int n = luaL_optnumber(L, 2, 1);
	bool scroll = luaL_optbnumber(L, 3, 0);
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);

	if (n < 0)
		arcan_tui_move_up(ib->tui, -n, scroll);
	else
		arcan_tui_move_down(ib->tui, n, scroll);

	return 0;
}

static int cursor_stepcol(lua_State* L)
{
	TUI_UDATA;
	int n = luaL_optnumber(L, 2, 1);
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);

	if (n < 0)
		arcan_tui_move_left(ib->tui, -n);
	else
		arcan_tui_move_right(ib->tui, n);

	return 0;
}

static int screen_margins(lua_State* L)
{
	TUI_UDATA;
	int top = luaL_checknumber(L, 2);
	int bottom = luaL_checknumber(L, 3);
	arcan_tui_set_margins(ib->tui, top, bottom);
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

static int invalidate(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_invalidate(ib->tui);
	return 0;
}

static int erase_region(lua_State* L)
{
	TUI_UDATA;
	size_t x1 = luaL_checknumber(L, 2);
	size_t y1 = luaL_checknumber(L, 3);
	size_t x2 = luaL_checknumber(L, 4);
	size_t y2 = luaL_checknumber(L, 5);
	bool prot = luaL_optbnumber(L, 6, false);
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);

	if (x1 < x2 && y1 < y2 && x1 < cols && y1 < rows)
		arcan_tui_erase_region(ib->tui, x1, y1, x2,  y2, prot);

	return 0;
}

static int erase_line(lua_State* L)
{
	TUI_UDATA;
	bool prot = luaL_optbnumber(L, 2, false);
	arcan_tui_erase_current_line(ib->tui, prot);
	return 0;
}

static int erase_screen(lua_State* L)
{
	TUI_UDATA;
	bool prot = luaL_optbnumber(L, 2, false);
	arcan_tui_erase_screen(ib->tui, prot);
	return 0;
}

static int erase_scrollback(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_erase_sb(ib->tui);
	return 0;
}

static int erase_home_to_cursor(lua_State* L)
{
	TUI_UDATA;
	bool prot = luaL_optbnumber(L, 2, false);
	arcan_tui_erase_home_to_cursor(ib->tui, prot);
	return 0;
}

static int erase_cursor_screen(lua_State* L)
{
	TUI_UDATA;
	bool prot = luaL_optbnumber(L, 2, false);
	arcan_tui_erase_cursor_to_screen(ib->tui, prot);
	return 0;
}

static int cursor_to(lua_State* L)
{
	TUI_UDATA;
	int x = luaL_checknumber(L, 2);
	int y = luaL_checknumber(L, 3);
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

/* Hook up the tui/callbacks, these forward into a handler table
 * that the user provide a reference to. */
	shared_cbcfg = (struct tui_cbcfg){
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
		.resize = on_resize,
		.resized = on_resized,
		.subwindow = on_subwindow,
		.recolor = on_recolor,
		.draw_call = on_draw,
		.reset = on_reset,
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
	meta->tui = arcan_tui_setup(conn,
		&cfg, &shared_cbcfg, sizeof(shared_cbcfg));
	if (!meta->tui){
		lua_pop(L, 1);
		return 0;
	}

	return 1;
}

bool write_reset = false;
static int refresh(lua_State* L)
{
	TUI_UDATA;
	int rc = arcan_tui_refresh(ib->tui);
	write_reset = false;
	lua_pushnumber(L, rc);
	return 1;
}

static int valid_flag(lua_State* L, int ind)
{
	return 0;
}

static int screen_alloc(lua_State* L)
{
	TUI_UDATA;
	lua_pushnumber(L, arcan_tui_alloc_screen(ib->tui));
	return 0;
}

static int screen_delete(lua_State* L)
{
	TUI_UDATA;
	unsigned screen = luaL_checknumber(L, 2);
	arcan_tui_delete_screen(ib->tui, screen);
	return 0;
}

static int screen_switch(lua_State* L)
{
	TUI_UDATA;
	unsigned screen = luaL_checknumber(L, 2);
	arcan_tui_switch_screen(ib->tui, screen);
	return 0;
}

static int tuiclose(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_destroy(ib->tui, luaL_optstring(L, 2, NULL));
	ib->tui = NULL;
	return 0;
}

static int collect(lua_State* L)
{
	struct tui_lmeta* ib = luaL_checkudata(L, 1, "tui_main");
	if (!ib)
		return 0;

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
	intptr_t ref = LUA_REFNIL;
	if ( (ind = 2, lua_isfunction(L, 2)) || (ind = 3, lua_isfunction(L, 3)) ){
		lua_pushvalue(L, ind);
		luaL_ref(L, LUA_REGISTRYINDEX);
	}
	else
		lua_error(L);

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

static int setmouse(lua_State* L)
{
	TUI_UDATA;
/* FIXME: mouse forward, either grab value or toggle */
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
	if (!write_reset){
		write_reset = true;
	}
	struct tui_screen_attr* attr = NULL;
	struct tui_screen_attr mattr = {};
	size_t len;

	size_t x = luaL_checknumber(L, 2);
	size_t y = luaL_checknumber(L, 3);
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
	arcan_tui_reset(ib->tui);
	return 0;
}

static int color_get(lua_State* L)
{
	TUI_UDATA;
	uint8_t dst[3] = {128, 128, 128};
	arcan_tui_get_color(ib->tui, luaL_checknumber(L, 2), dst);
	lua_pushnumber(L, dst[0]);
	lua_pushnumber(L, dst[1]);
	lua_pushnumber(L, dst[2]);
	return 3;
}

static int set_flags(lua_State* L)
{
	TUI_UDATA;
	arcan_tui_set_flags(ib->tui, luaL_checknumber(L, 2));
	return 0;
}

static int color_set(lua_State* L)
{
	TUI_UDATA;
	uint8_t dst[3] = {
		luaL_checknumber(L, 3),
		luaL_checknumber(L, 4),
		luaL_checknumber(L, 5)
	};
	arcan_tui_set_color(ib->tui, luaL_checknumber(L, 2), dst);
	return 0;
}

#undef TUI_UDATA

/*
 * constants needed:
 *  - screen mode
 */

#define REGISTER(X, Y) lua_pushcfunction(L, Y); lua_setfield(L, -2, X);
void tui_lua_expose(lua_State* L)
{
	lua_pushstring(L, "tui_open");
	lua_pushcclosure(L, tui_open, 1);
	lua_setglobal(L, "tui_open");

	lua_pushstring(L, "tui_attr");
	lua_pushcclosure(L, tui_attr, 1);
	lua_setglobal(L, "tui_attr");

	luaL_newmetatable(L, "tui_main");
	lua_pushvalue(L, -1); // tui_index_get);
	lua_setfield(L, -2, "__index");
	lua_pushvalue(L, -1); // tui_index_set);
	lua_setfield(L, -2, "__newindex");
	lua_pushcfunction(L, collect);
	lua_setfield(L, -2, "__gc");

	REGISTER("refresh", refresh);
	REGISTER("process", process);
	REGISTER("write", writeu8);
	REGISTER("write_to", write_tou8);
	REGISTER("set_handlers", settbl);
	REGISTER("update_ident", setident);
	REGISTER("mouse_forward", setmouse);
	REGISTER("set_default_attr", defattr);
	REGISTER("reset", reset);
	REGISTER("to_clipboard", setcopy);
	REGISTER("cursor_pos", getcursor);
	REGISTER("new_window", reqwnd);
	REGISTER("set_tabstop", set_tabstop);
	REGISTER("insert_lines", insert_lines);
	REGISTER("delete_lines", delete_lines);
	REGISTER("insert_empty", insert_chars);
	REGISTER("erase_cells", delete_chars);
	REGISTER("erase_current_line", erase_line);
	REGISTER("erase_screen", erase_screen);
	REGISTER("erase_cursor_to_screen", erase_cursor_screen);
	REGISTER("erase_home_to_cursor", erase_home_to_cursor);
	REGISTER("erase_scrollback", erase_scrollback);
	REGISTER("erase_region", erase_region);
	REGISTER("scroll", wnd_scroll);
	REGISTER("scrollhint", scrollhint);
	REGISTER("cursor_tab", cursor_tab);
	REGISTER("cursor_to", cursor_to);
	REGISTER("cursor_step_col", cursor_stepcol);
	REGISTER("cursor_step_row", cursor_steprow);
	REGISTER("set_margins", screen_margins);
	REGISTER("dimensions", screen_dimensions);
	REGISTER("invalidate", invalidate);
	REGISTER("close", tuiclose);
	REGISTER("switch_screen", screen_switch);
	REGISTER("delete_screen", screen_delete);
	REGISTER("alloc_screen", screen_alloc);
	REGISTER("get_color", color_get);
	REGISTER("set_color", color_set);
	REGISTER("set_flags", set_flags);

/*
	{"", TUI_INSERT_MODE},
	{"", TUI_REL_ORIGIN},
	{"", TUI_INVERSE},
	{"", TUI_FIXED_POS},
*/
	struct { const char* key; int val; } flagtbl[] = {
		{"auto_wrap", TUI_AUTO_WRAP},
		{"hide_cursor", TUI_HIDE_CURSOR},
		{"alternate", TUI_ALTERNATE}
	};

	lua_newtable(L);
	for (size_t i = 0; i < COUNT_OF(flagtbl); i++){
		lua_pushstring(L, flagtbl[i].key);
		lua_pushnumber(L, flagtbl[i].val);
		lua_rawset(L, -3);
	}
	lua_setglobal(L, "tui_flags");

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
	{"reference", TUI_COL_REFERENCE}
	};

	lua_newtable(L);
	for (size_t i = 0; i < COUNT_OF(coltbl); i++){
		lua_pushstring(L, coltbl[i].key);
		lua_pushnumber(L, coltbl[i].val);
		lua_rawset(L, -3);
	}
	lua_setglobal(L, "tui_color");

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

/* make the table bidirectional */
	lua_newtable(L);
	for (size_t i = 0; i < COUNT_OF(symtbl); i++){
		lua_pushstring(L, &symtbl[i].key[5]);
		lua_pushnumber(L, symtbl[i].val);
		lua_rawset(L, -3);
		lua_pushnumber(L, symtbl[i].val);
		lua_pushstring(L, &symtbl[i].key[5]);
		lua_rawset(L, -3);
	}

	lua_setglobal(L, "tuik");
	lua_pop(L, 1);
}
