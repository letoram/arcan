/*
 * Set of wrappers and support functions for improving tracing,
 * handling context crashes and recovery and so on.
 */
#ifndef HAVE_ALT_SUPPORT
#define HAVE_ALT_SUPPORT

/*
 * Each function that crosses the LUA->C barrier has a LUA_TRACE macro
 * reference first to allow quick build-time interception.
 */
#ifdef LUA_TRACE_STDERR
#define LUA_TRACE(fsym) fprintf(stderr, "(%lld:%s)->%s\n", \
	arcan_timemillis(), luactx.lastsrc, fsym);

/*
 * This trace function scans the stack and writes the information about
 * calls to a CSV file (arcan.trace): function;timestamp;type;type
 * This is useful for benchmarking / profiling / test coverage and
 * hardening.
 */
#elif defined(LUA_TRACE_COVERAGE)
#define LUA_TRACE(fsym) trace_coverage(fsym, ctx);

#else
#define LUA_TRACE(fsym)
#endif

#ifndef LUA_ETRACE
#define LUA_ETRACE(fsym,reason, X){ return X; }
#endif

#ifndef LUA_DEPRECATE
#define LUA_DEPRECATE(fsym) \
	arcan_warning("%s, DEPRECATED, discontinue "\
	"the use of this function immediately as it is slated for removal.\n", fsym);
#endif

/*
 * namespaces permitted to be searched for regular resource lookups
 */
#ifndef DEFAULT_USERMASK
#define DEFAULT_USERMASK \
	(RESOURCE_APPL | RESOURCE_APPL_SHARED | RESOURCE_APPL_TEMP | RESOURCE_NS_USER)
#endif

#ifndef CAREFUL_USERMASK
#define CAREFUL_USERMASK \
	(RESOURCE_APPL | RESOURCE_APPL_SHARED | RESOURCE_APPL_TEMP | RESOURCE_SYS_SCRIPTS)
#endif

#ifndef MODULE_USERMASK
#define MODULE_USERMASK \
	(RESOURCE_SYS_LIBS)
#endif

#define STRJOIN2(X) #X
#define STRJOIN(X) STRJOIN2(X)
#define LINE_TAG STRJOIN(__LINE__)

static void set_tblstr(lua_State* ctx,
	const char* k, const char* v, int top, size_t k_sz, size_t v_sz)
{
	lua_pushlstring(ctx, k, k_sz);
	lua_pushlstring(ctx, v, v_sz);
	lua_rawset(ctx, top);
}

static void set_tbldynstr(lua_State* ctx,
	const char* k, const char* v, int top, size_t k_sz)
{
	lua_pushlstring(ctx, k, k_sz);
	lua_pushstring(ctx, v);
	lua_rawset(ctx, top);
}

static void set_tblnum(
	lua_State* ctx, const char* k, double v, int top, size_t k_sz)
{
	lua_pushlstring(ctx, k, k_sz);
	lua_pushnumber(ctx, v);
	lua_rawset(ctx, top);
}

static void set_tblbool(lua_State* ctx, char* k, bool v, int top, size_t k_sz)
{
	lua_pushlstring(ctx, k, k_sz);
	lua_pushboolean(ctx, v);
	lua_rawset(ctx, top);
}

#define tblstr(L, K, V, T) set_tblstr(L, (K), (V), (T),\
	((sizeof(K)/sizeof(char))-1),\
	((sizeof(V)/sizeof(char))-1)\
)
#define tbldynstr(L, K, V, T) set_tbldynstr(L, (K), (V), (T), (sizeof(K)/sizeof(char))-1)
#define tblnum(L, K, V, T) set_tblnum(L, (K), (V), (T), (sizeof(K)/sizeof(char))-1)
#define tblbool(L, K, V, T) set_tblbool(L, (K), (V), (T), (sizeof(K)/sizeof(char))-1)


/* a type-cohersion variant that accepts both bool and if (0) style
 * argument passing for functions. */
lua_Number luaL_checkbnumber(lua_State* L, int narg);
lua_Number luaL_optbnumber(lua_State* L, int narg, lua_Number opt);

/* used as a lua_call wrapper that provides different error handling, ... */
void alt_call(lua_State*,
	int kind, uintptr_t kind_tag, int args, int retc, const char* src);
void alt_fatal(const char* msg, ...);

/* apply the appl prefix, find the corresponding global function in the
 * lua state object and add to the stack as a step to calling it.
 *
 * returns true if the function was added to the stack, false if it does
 * not exist. */
bool alt_lookup_entry(lua_State*, const char* fun, size_t len);

/* prepare the referenced context by setting up crash/error handlers */
void alt_setup_context(lua_State*, const char* applname);

/* apply the script encoded into arcan_bootstrap.h to the provided context */
void alt_apply_ban(lua_State*);

#endif
