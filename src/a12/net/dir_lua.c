#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <lualib.h>
#include <lauxlib.h>
#include <pthread.h>

#include "../a12.h"
#include "../../engine/arcan_mem.h"
#include "../../engine/arcan_db.h"
#include "nbio.h"

#include "directory.h"

static lua_State* L;
static struct arcan_dbh* DB;

void anet_directory_lua_exit()
{
	lua_close(L);
	alt_nbio_release();
	L = NULL;
}

void anet_directory_lua_init(const char* fn)
{
	L = luaL_newstate();
	DB = arcan_db_open(fn, NULL);
}

/* build a lua context for the client or attach to a specific one for an appl */
void anet_directory_lua_register(struct dircl* C, const char* appl)
{
	if (appl){
/* send message or spawn appl-runner */
	}
	else {
		C->script_state = L;
	}
}

/* filter list of available appls before passing to user */
bool anet_directory_lua_filter_dirlist(
	struct dircl* C, char* list, size_t list_sz,
	char** out_list, size_t out_sz)
{
	return false;
}

/* for post-transfer completion hooks to perform atomic rename / fileswaps etc. */
void anet_directory_lua_bchunk_completion(struct dircl* C, bool ok)
{
	if (!C->script_state)
		return;
}

/* type sets resource type and domain (current appl, server-shared, user-state) */
int anet_directory_lua_bchunk_req(struct dircl* C, int type, const char* name)
{
	return -1;
}

void anet_directory_lua_unregister(struct dircl* C, const char* appl)
{
	if (appl){

	}
	else {
		C->script_state = NULL;
	}
}
