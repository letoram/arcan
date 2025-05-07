#ifndef HAVE_DIR_LUA_SUPPORT
#define HAVE_DIR_LUA_SUPPORT

#define ENTRYPOINT_COUNT 14
enum {
	EP_TRIGGER_NONE      = 0,
	EP_TRIGGER_MAIN      = 1,
	EP_TRIGGER_CLOCK     = 2,
	EP_TRIGGER_MESSAGE   = 3,
	EP_TRIGGER_NBIO_RD   = 4,
	EP_TRIGGER_NBIO_WR   = 5,
	EP_TRIGGER_NBIO_DATA = 6,
	EP_TRIGGER_TRACE     = 7,
	EP_TRIGGER_RESET     = 8,
	EP_TRIGGER_JOIN      = 9,
	EP_TRIGGER_LEAVE     = 10,
	EP_TRIGGER_INDEX     = 11,
	EP_TRIGGER_LOAD      = 12,
	EP_TRIGGER_STORE     = 13,
	EP_TRIGGER_LIMIT     = ENTRYPOINT_COUNT
};

/*
 * Vendored versions of alt/alt_trace used to retain the same debug inteface
 */
#define BREAK_LIMIT 8

struct dirlua_monitor_state {
	struct {
		struct {
			size_t line;
			char* file;
		} bpt;

		int type;
	} breakpoints[BREAK_LIMIT];

	size_t n_breakpoints;
	bool in_breakpoint_set;
	int hook_mask;
	bool lock;
	bool stepreq;
	bool dumppause;
	bool error;
	bool transaction;

	char* out_buf;
	size_t out_sz;
	FILE* out;
	struct arcan_shmif_cont* C;
};

void dirlua_callstack_raw(lua_State* L, lua_Debug* D, int levels, FILE* out);
void dirlua_dumpstack_raw(lua_State* L, FILE* out);
void dirlua_print_type(lua_State* L, int i, const char* suffix, FILE* out);

/* allocate and set the thread-local state for the monitor commands, normally
 * this only runs in a discrete process with a single thread but for the 'ease
 * of troubleshooting' mode it can be a discrete thread instead and then we do
 * not want potentially different monitors on different controllers to fight.
 * */
void dirlua_monitor_allocstate(struct arcan_shmif_cont* C);
void dirlua_monitor_releasestate(struct lua_State* L);
bool dirlua_setup_entrypoint(struct lua_State* L, int ep);
size_t dirlua_monitor_flush(char** out_buf);

void dirlua_pcall_prefix(struct lua_State* L, const char* name);
void dirlua_pcall(
	struct lua_State* L, int nargs, int nret, int(*panic)(lua_State*L));

struct dirlua_monitor_state* dirlua_monitor_getstate();
void dirlua_monitor_watchdog(lua_State* L, lua_Debug* D);
bool dirlua_monitor_command(char* cmd, lua_State* L, lua_Debug* D);

#endif
