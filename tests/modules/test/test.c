#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static int modtest(lua_State* ctx)
{
	lua_pushstring(ctx, "modtest running");
	return 1;
}

static luaL_Reg expfuns[] = {
	"test", modtest,
	NULL, NULL
};

luaL_Reg* arcan_module_init(int maj, int min, int luav)
{
	return expfuns;
}
