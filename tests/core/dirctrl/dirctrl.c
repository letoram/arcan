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
#include "a12.h"
#include "anet_helper.h"
#include "directory.h"

static struct global_cfg CFG = {0};

int main(int argc, char** argv)
{
	if (argc != 3){
		fprintf(stderr, "Use: dirctrl /path/to/config.lua applname\n");
		return EXIT_FAILURE;
	}

/* load all the config options from the same format as the regular server would */
	CFG.config_file = argv[1];
	anet_directory_lua_init(&CFG);
	a12_set_trace_level(A12_TRACE_DIRECTORY, stdout);

	if (getenv("ARCAN_CONNPATH")){
/* this should have regular tracing, force-reload, inspect state, ...
 * since we have lua linked in anyway might as well use those bindings and
 * pull in lash through it */
		fprintf(stderr, "spawn testing TUI\n");
	}

/* the config_file is responsible for actually getting the dirfd to the
 * server_appl, and the controller_thread will send it upon initialising the
 * connection based on the name */
	struct appl_meta appl = {0};
	snprintf(appl.appl.name, sizeof(appl.appl.name), "%s", argv[2]);

	if (!anet_directory_lua_spawn_runner(&appl, false)){
		fprintf(stderr, "Couldn't spawn appl-runner\n");
		return EXIT_FAILURE;
	}

/* tui processing loop goes here */
	while(1){
		sleep(1);
	}

	return EXIT_SUCCESS;
}
