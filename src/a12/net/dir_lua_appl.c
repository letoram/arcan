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
#include <unistd.h>
#include <fcntl.h>

static lua_State* L;
static struct arcan_shmif_cont SHMIF;

void anet_directory_appl_runner()
{
	struct arg_arr* args;
	SHMIF = arcan_shmif_open(
		SEGID_NETWORK_SERVER,
		SHMIF_ACQUIRE_FATALFAIL |
		SHMIF_NOACTIVATE |
		SHMIF_DISABLE_GUARD |
		SHMIF_NOREGISTER,
		&args
	);

	struct arcan_event ev;
	while (arcan_shmif_wait(&SHMIF, &ev)){
/* BCHUNKSTATE for the directory descriptor, message for the applname */
		if (ev.category != EVENT_TARGET)
			continue;
	}

	L = luaL_newstate();
}
