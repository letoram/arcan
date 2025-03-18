#ifndef HAVE_DIR_LUA_SUPPORT
#define HAVE_DIR_LUA_SUPPORT

enum {
	EP_TRIGGER_NONE      = 0,
	EP_TRIGGER_CLOCK     = 1,
	EP_TRIGGER_MESSAGE   = 2,
	EP_TRIGGER_NBIO_RD   = 3,
	EP_TRIGGER_NBIO_WR   = 4,
	EP_TRIGGER_NBIO_DATA = 5,
	EP_TRIGGER_TRACE     = 6,
	EP_TRIGGER_RESET     = 7
};

/*
 * Vendored versions of alt/alt_trace used to retain the same debug inteface
 */
#define BREAK_LIMIT 8

void dirlua_callstack_raw(lua_State* L, lua_Debug* D, int levels, FILE* out);
void dirlua_print_type(lua_State* L, int i, const char* suffix, FILE* out);
bool dirlua_monitor_command(char* cmd, lua_State* L, lua_Debug* D, FILE* out);

#endif
