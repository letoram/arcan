/*
 * the constraints of the lua bindings are lesser than running inside
 * arcan, so just define simpler placeholders
 */
#include <string.h>

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#define LUA_ETRACE(fsym,reason, X){ return X; }
#define LUA_TRACE(X)

#define STRJOIN2(X) #X
#define STRJOIN(X) STRJOIN2(X)
#define LINE_TAG STRJOIN(__LINE__)

static void arcan_mem_free(void* f)
{
	free(f);
}

#define ARCAN_MEM_BZERO 1
#define ARCAN_MEM_BINDING 0
#define ARCAN_MEMALIGN_NATURAL 0
#define CB_SOURCE_NONE 0
lua_Number luaL_optbnumber(lua_State* L, int narg, lua_Number opt)
{
	if (lua_isnumber(L, narg))
		return lua_tonumber(L, narg);
	else if (lua_isboolean(L, narg))
		return lua_toboolean(L, narg);
	else
		return opt;
}

static void* arcan_alloc_mem(size_t sz, int type, int hint, int align)
{
	void* res = malloc(sz);
	if (res && (hint & ARCAN_MEM_BZERO)){
		memset(res, '\0', sz);
	}
	return res;
}

static void alt_call(lua_State* L,
	int kind, uintptr_t kind_tag, int args, int retc, const char* src)
{
	lua_call(L, args, retc);
}

#define arcan_fatal(...) do {\
	fprintf(stderr, __VA_ARGS__);\
	exit(EXIT_FAILURE);\
}while (0);

#define arcan_warning(...) do {\
	fprintf(stderr, __VA_ARGS__);\
} while (0);

#define RESOURCE_APPL_TEMP 1
#define RESOURCE_NS_USER 2
#define ARES_FILE 0
#define DEFAULT_USERMASK 2

static char* arcan_expand_resource(const char* prefix, int ns)
{
	return prefix ? strdup(prefix) : NULL;
}

static char* arcan_find_resource(const char* prefix, int ns, int kind, int* dfd)
{
	char* res = arcan_expand_resource(prefix, ns);
	if (!res)
		return NULL;

	return res;
}
