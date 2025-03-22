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
	int entrypoint;
	bool lock;
	bool stepreq;
	bool dumppause;
	bool error;
	bool transaction;

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

struct dirlua_monitor_state* dirlua_monitor_getstate();

bool dirlua_monitor_command(char* cmd, lua_State* L, lua_Debug* D, FILE* out);

#endif
