#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include "../a12.h"
#include "directory.h"

#include <lualib.h>
#include <lauxlib.h>

static lua_State* L;

void anet_directory_lua_init(const char* dbfile)
{
/* open or create db-file, use as generic K/V store */
}

void anet_directory_lua_register(struct dircl* C)
{
/* attach our own state */
/* find user-script based on salted kPub */
}

void anet_directory_lua_bchunk_completion(struct dircl* C, bool ok)
{
/* The bchunk can be either in the user-domain (and apply to that script)
 * or in the appl specific store. For the domain side, this is to allow
 * a private appl agnostic store, comparable to resources. */
}

void anet_directory_lua_leave(struct dircl* C)
{
/* allow for cleanup or backup of previous blocks */
}
