/*
 * Slightly modified version of src/platform/posix/glob.c
 * Main changes being namespacing stripped away in favour of full paths
 * and only asynch interface presented.
 */
#include <arcan_shmif.h>
#include <arcan_tui.h>

#include <fcntl.h>
#include <glob.h>
#include <math.h>
#include <pthread.h>
#include <errno.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <poll.h>

#include "tui_lua.h"
#include "nbio.h"
#include "tui_popen.h"
#include "tui_lua_glob.h"

struct glob_arg {
	char* basename;
	int fdout;
};

#define TUI_UDATA \
	struct tui_lmeta* ib = luaL_checkudata(L, 1, TUI_METATABLE);\
	if (!ib || !ib->tui) {\
		luaL_error(L, !ib ? "no userdata" : "no tui context"); \
	}\

static bool dump_to_pipe(char* base, int fd)
{
	size_t ntw = strlen(base)+1;

	while (ntw){
		ssize_t nw = write(fd, base, ntw);
		if (-1 == nw){
			if (errno == EAGAIN || errno == EINTR)
				continue;

			if (errno == EWOULDBLOCK){
				struct pollfd pfd = {
					.fd = fd,
					.events = POLLHUP | POLLNVAL | POLLOUT
				};
				poll(&pfd, 1, -1);
				continue;
			}

			return false;
		}
		else {
			base += nw;
			ntw -= nw;
		}
	}

	return true;
}

static void* glob_full(void* arg)
{
	struct glob_arg* garg = arg;
	glob_t res = {0};

	if ( glob(garg->basename, 0, NULL, &res) == 0 ){
		char** beg = res.gl_pathv;

		while(*beg){
			if (!dump_to_pipe(*beg, garg->fdout)){
				break;
			}
			beg++;
		}

		globfree(&res);
	}

	if (-1 != garg->fdout){
		close(garg->fdout);
	}

	free(garg->basename);

	return NULL;
}

static void setup_globthread(
	struct glob_arg garg, int* dfd, void* (*fptr)(void*))
{
	struct glob_arg *ptr = malloc(sizeof(struct glob_arg));
	*ptr = garg;

	int pair[2];
	if (-1 == pipe(pair)){
		*dfd = -1;
		return;
	}
	for (size_t i = 0; i < 2; i++){ /* osx doesn't have pipe2 */
		fcntl(pair[i], F_SETFL, O_NONBLOCK);
		fcntl(pair[i], F_SETFD, FD_CLOEXEC);
	}

	*dfd = pair[0];
	ptr->fdout = pair[1];

	pthread_t globth;
	pthread_attr_t globth_attr;
	pthread_attr_init(&globth_attr);
	pthread_attr_setdetachstate(&globth_attr, PTHREAD_CREATE_DETACHED);

	if (0 != pthread_create(&globth, &globth_attr, fptr, (void*) ptr)){
		close(pair[0]);
		close(pair[1]);
		*dfd = -1;
		free(ptr);
	}

	pthread_attr_destroy(&globth_attr);
}

int tui_glob(lua_State* L)
{
	TUI_UDATA;

	struct glob_arg garg = {
		.basename = strdup(luaL_checkstring(L, 2)),
		.fdout = -1
	};

	int fd;
	setup_globthread(garg, &fd, glob_full);

	if (fd != -1){
		struct nonblock_io* dst;
		alt_nbio_import(L, fd, O_RDONLY, &dst, NULL);
	}
	else
		lua_pushnil(L);

	return 1;
}
