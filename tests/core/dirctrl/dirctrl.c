#include <arcan_shmif.h>
#include <fcntl.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>
#include <pthread.h>
#include "platform.h"

static struct global_cfg CFG = {0};

int main(int argc, char** argv)
{
	if (argc != 2){
		fprintf(stderr, "Use: dirctrl /path/to/config.lua applname");
		return EXIT_FAILURE;
	}

/* load all the config options from the same format as the regular server would */
	CFG.config_file = argv[1];
	anet_directory_lua_init(&CFG);

/* fire up the shmifsrv connection, get the descriptor, forward it in env.
 * and set ARCAN_SOCKIN_FD to the socket so shmif_open will work. This really
 * need an option for in-process connections that doesn't use env to lookup
 * k/vs.
 * unsetenv("ARCAN_CONNPATH")
 *
 * spawn thread and put that to anet_directory_appl_runner()
 */

/* to continue we need to refactor dir_lua.c to split out the process spawning
 * part and forward to our connection. */

	return EXIT_SUCCESS;
}
