/* Copyright: Björn Ståhl
 * License: 3-clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: This adds a naive mapping to the TUI API for Lua scripting.
 * Simply append- the related functions to a Lua context, and you should be
 * able to open/connect using tui_open() -> context.
 *
 * TODO:
 *   [ ] blob_asio:
 *       add to wnd:process for data_handler
 *
 *   [ ] Add bufferwnd
 *   [ ] Handover exec
 *
 *   [ ] multiple windows
 *       add to wnd:process for parent
 *
 *   [ ] Scrollhint
 *   [ ] Hasglyph
 *   [ ] Window hint
 *   [ ] Handover media embed
 *   [ ] Empty states (exec_state, visibility, ...)
 */

#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_listwnd.h>
#include <arcan_tui_bufferwnd.h>
#include <arcan_tui_linewnd.h>
#include <arcan_tui_readline.h>

#include <stdbool.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <errno.h>

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
	if (!ib || !ib->tui || ib->widget_mode != TWND_NORMAL) return 0; \

#define TUI_UDATA \
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);\
	if (!ib || !ib->tui) return 0; \

#define TUI_LWNDDATA \
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);\
	if (!ib || !ib->tui || !ib->widget_mode != TWND_LINEWND) return 0; \

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
	lua_call(L, 2, 1);
	END_HREF;
	return false;
}

static bool on_u8(struct tui_context* T, const char* u8, size_t len, void* t)
{
	SETUP_HREF("utf8", false);
		lua_pushlstring(L, u8, len);
		lua_call(L, 2, 1);
		bool rv = false;
		if (lua_isnumber(L, -1))
			rv = lua_tonumber(L, -1);
		else if (lua_isboolean(L, -1))
			rv = lua_toboolean(L, -1);
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
		lua_call(L, 5, 0);
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
		lua_call(L, 5, 0);
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
		lua_call(L, 5, 0);
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
	SETUP_HREF("recolor", );
		lua_call(L, 1, 0);
	END_HREF;
}

static void on_reset(struct tui_context* T, int level, void* t)
{
	SETUP_HREF("reset", );
		lua_pushnumber(L, level);
	lua_call(L, 2, 0);
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
	lua_call(L, 2, 0);
	END_HREF;
}

static void on_bchunk(struct tui_context* T,
	bool input, uint64_t size, int fd, const char* type, void* t)
{
	SETUP_HREF((input ?"bchunk_in":"bchunk_out"), );
	add_blobio(L, t, input, fd);
	lua_pushstring(L, type);
	lua_call(L, 3, 0);

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
		lua_call(L, 1, 0);
	END_HREF;
}

static void on_utf8_paste(struct tui_context* T,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	SETUP_HREF("paste",);
		lua_pushlstring(L, (const char*) str, len);
		lua_pushnumber(L, cont);
		lua_call(L, 3, 0);
	END_HREF;
}

static void on_resized(struct tui_context* T,
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

static void on_resize(struct tui_context* T,
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
		lua_call(L, 1, 0);
		END_HREF;
		return false;
	}

/* let the caller be responsible for updating the handlers */
	struct tui_context* ctx =
		arcan_tui_setup(new, T, &shared_cbcfg, sizeof(shared_cbcfg));
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
	luaL_getmetatable(L, TUI_METATABLE);
	lua_setmetatable(L, -2);
	nud->lua = L;
	nud->last_words = NULL;
	nud->href = cb;

/* missing - attach to parent and add to its context list for processing */

	lua_call(L, 2, 0);
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
	lua_call(L, 4, 5);

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

/*
 * MISSING:
 * lcall with country/lang, expect multi-return with label, descr
 * and fill in - if no arguments returned
 */
	END_HREF;
	return gotrep;
}

static void on_geohint(struct tui_context* T, float lat,
	float longitude, float elev, const char* a3_country,
	const char* a3_language, void* t)
{
}

static bool on_substitute(struct tui_context* T,
	struct tui_cell* cells, size_t n_cells, size_t row, void* t)
{
	return false;
}

static void on_visibility(
	struct tui_context* T, bool visible, bool focus, void* t)
{
}

static void on_exec_state(struct tui_context* T, int state, void* t)
{
/*
 * Context has changed liveness state
 * 0 : normal operation
 * 1 : suspend state, execution should be suspended, next event will
 *     exec_state into normal or terminal state
 * 2 : terminal state, context is dead
 */
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

static int intblint(lua_State* L, int ind, const char* field)
{
	lua_getfield(L, ind, field);
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
	break;
	case TWND_LINEWND:
/* arcan_tui_linewnd_release(M->tui); */
	break;
	default:
	break;
	}

	M->widget_mode = TWND_NORMAL;
	if (M->widget_closure){
		luaL_unref(L, LUA_REGISTRYINDEX, M->widget_closure);
		M->widget_closure = LUA_NOREF;
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

	attr->custom_id = intblint(L, ind, "id");

	attr->fg = attr->fb = attr->fr = 0;
	attr->bg = attr->bb = attr->br = 0;

	int val = intblint(L, ind, "fc");
	if (-1 != val){
		attr->aflags |= TUI_ATTR_COLOR_INDEXED;
		attr->fc[0] = (uint8_t) val;
		attr->bc[0] = (uint8_t) intblint(L, ind, "bc");
	}
	else {
		attr->fr = (uint8_t) intblint(L, ind, "fr");
		attr->fg = (uint8_t) intblint(L, ind, "fg");
		attr->fb = (uint8_t) intblint(L, ind, "fb");
		attr->br = (uint8_t) intblint(L, ind, "br");
		attr->bg = (uint8_t) intblint(L, ind, "bg");
		attr->bb = (uint8_t) intblint(L, ind, "bb");
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
	TUI_WNDDATA;
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

static int wnd_scroll(lua_State* L)
{
	TUI_WNDDATA;
	int steps = luaL_checknumber(L, 2);
	if (steps > 0)
		arcan_tui_scroll_down(ib->tui, steps);
	else
		arcan_tui_scroll_up(ib->tui, -steps);
	return 0;
}

static int scrollhint(lua_State* L)
{
	TUI_WNDDATA;
/* MISSING */
	return 0;
}

static int screen_dimensions(lua_State* L)
{
	TUI_WNDDATA;
	size_t rows, cols;
	arcan_tui_dimensions(ib->tui, &rows, &cols);
	lua_pushnumber(L, cols);
	lua_pushnumber(L, rows);
	return 2;
}

static int erase_region(lua_State* L)
{
	TUI_WNDDATA;
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

static int erase_screen(lua_State* L)
{
	TUI_WNDDATA;
	bool prot = luaL_optbnumber(L, 2, false);
	arcan_tui_erase_screen(ib->tui, prot);
	return 0;
}

static int cursor_to(lua_State* L)
{
	TUI_WNDDATA;
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
	*meta = (struct tui_lmeta){0};

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
		.substitute = on_substitute,
		.visibility = on_visibility,
		.exec_state = on_exec_state,
		.cli_command = on_cli_command,
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
	TUI_WNDDATA;
	arcan_tui_destroy(ib->tui, luaL_optstring(L, 2, NULL));
	ib->tui = NULL;

	lua_rawgeti(L, LUA_REGISTRYINDEX, ib->href);
	lua_getfield(L, -1, "destroy");
	if (lua_type(L, -1) != LUA_TFUNCTION){
		lua_pop(L, 2);
		return 0;
	}\
	lua_pushvalue(L, -3);
	lua_call(L, 1, 0);

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
	if (ib->href != LUA_REFNIL){
		luaL_unref(L, LUA_REGISTRYINDEX, ib->href);
		ib->href = LUA_REFNIL;
	}

	return 0;
}

static int settbl(lua_State* L)
{
	TUI_WNDDATA;
	if (ib->href != LUA_REFNIL){
		luaL_unref(L, LUA_REGISTRYINDEX, ib->href);
		ib->href = LUA_REFNIL;
	}

	luaL_checktype(L, 2, LUA_TTABLE);
	ib->href = luaL_ref(L, LUA_REGISTRYINDEX);
	printf("handle table updated to: %lld\n", ib->href);

	return 0;
}

static int setident(lua_State* L)
{
	TUI_WNDDATA;
	const char* ident = luaL_optstring(L, 2, "");
	arcan_tui_ident(ib->tui, ident);
	return 0;
}

static int setcopy(lua_State* L)
{
	TUI_WNDDATA;
	const char* pstr = luaL_optstring(L, 2, "");
	lua_pushboolean(L, arcan_tui_copy(ib->tui, pstr));
	return 1;
}

static int reqwnd(lua_State* L)
{
	TUI_WNDDATA;

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
	TUI_WNDDATA;
/* FIXME: mouse forward, either grab value or toggle */
	return 0;
}

static int process(lua_State* L)
{
	TUI_WNDDATA;

	int timeout = luaL_optnumber(L, 2, -1);

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
				lua_pcall(L, 1, 0, 0);
			}
		}
		break;
		case TWND_BUFWND:
		break;
		case TWND_READLINE:
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
	TUI_WNDDATA;
	size_t x, y;
	arcan_tui_cursorpos(ib->tui, &x, &y);
	lua_pushnumber(L, x);
	lua_pushnumber(L, y);
	return 2;
}

static int write_tou8(lua_State* L)
{
	TUI_WNDDATA;
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
	TUI_WNDDATA;
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
	TUI_WNDDATA;
	arcan_tui_reset(ib->tui);
	return 0;
}

static int color_get(lua_State* L)
{
	TUI_WNDDATA;
	uint8_t dst[3] = {128, 128, 128};
	arcan_tui_get_color(ib->tui, luaL_checknumber(L, 2), dst);
	lua_pushnumber(L, dst[0]);
	lua_pushnumber(L, dst[1]);
	lua_pushnumber(L, dst[2]);
	return 3;
}

static int set_flags(lua_State* L)
{
	TUI_WNDDATA;
	arcan_tui_set_flags(ib->tui, luaL_checknumber(L, 2));
	return 0;
}

static int color_set(lua_State* L)
{
	TUI_WNDDATA;
	uint8_t dst[3] = {
		luaL_checknumber(L, 3),
		luaL_checknumber(L, 4),
		luaL_checknumber(L, 5)
	};
	arcan_tui_set_color(ib->tui, luaL_checknumber(L, 2), dst);
	return 0;
}

static int alert(lua_State* L)
{
	TUI_WNDDATA;
	arcan_tui_message(ib->tui, TUI_MESSAGE_ALERT, luaL_checkstring(L, 2));
	return 0;
}

static int notification(lua_State* L)
{
	TUI_WNDDATA;
	arcan_tui_message(ib->tui, TUI_MESSAGE_NOTIFICATION, luaL_checkstring(L, 2));
	return 0;
}

static int failure(lua_State* L)
{
	TUI_WNDDATA;
	arcan_tui_message(ib->tui, TUI_MESSAGE_FAILURE, luaL_checkstring(L, 2));
	return 0;
}

static int refresh(lua_State* L)
{
	TUI_WNDDATA;

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

static int request_io(lua_State* L)
{
	TUI_WNDDATA;
	const char* input = luaL_optstring(L, 2, "");
	const char* output = luaL_optstring(L, 3, "");
	arcan_tui_announce_io(ib->tui, true, input, output);
	return 0;
}

static int statesize(lua_State* L)
{
	TUI_WNDDATA;
	size_t state_sz = luaL_checknumber(L, 2);
	arcan_tui_statesize(ib->tui, state_sz);
	return 0;
}

static int revertwnd(lua_State* L)
{
	TUI_WNDDATA;
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

static int listwnd(lua_State* L)
{
	TUI_WNDDATA;

/* normally just drop whatever previous state we were in */
	revert(L, ib);

/* label, attributes (), tag (just index),
 * then on refresh we need to call listwnd_status and
		struct tui_list_entry* ent;
		if (arcan_tui_listwnd_status(tui, &ent)){
	 * use that to trigger the callback. */

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

#undef TUI_WNDDATA

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
		{"process", process},
		{"refresh", refresh},
		{"write", writeu8},
		{"write_to", write_tou8},
		{"set_handlers", settbl},
		{"update_identity", setident},
		{"mouse_forward", setmouse},
		{"set_default", defattr},
		{"reset", reset},
		{"to_clipboard", setcopy},
		{"cursor_pos", getcursor},
		{"new_window", reqwnd},
		{"erase", erase_screen},
		{"erase_region", erase_region},
		{"scroll", wnd_scroll},
		{"scrollhint", scrollhint},
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
		{"revert", revertwnd},
		{"set_list", listwnd},
/* set_buffer
 * readline
 */

/* MISSING:
 * getxy,
 * writestr,
 */
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
		{"alternate", TUI_ALTERNATE}
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
}

int
luaopen_arcantui(lua_State* L)
{
	struct luaL_Reg luaarcantui[] = {
		{"APIVersion", apiversion},
		{"APIVersionString", apiversionstr},
		{"open", tui_open},
		{"get_attribute", tui_attr},
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
