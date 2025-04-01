/*
 * specialised dir_srv_worker that only deals with maintaining an uplink
 * the 'link' can come in two forms:
 *     "unified" which transparently provides a single global namespace
 *     "referential" which only tracks and caches but provides a hierarchical
 *     namespace through the petname we bind to.
 *
 * this should synchronise:
 *      - appl + ctrl packages
 *      - applgroup messages (parent act as router rather than us joining
 *                            every applgroup directly)
 *
 * relay store access (for unified namespace)
 * relay trust (with TTL for key so the 'owner' revokes)
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <ftw.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <inttypes.h>
#include <stdint.h>
#include <signal.h>
#include <pthread.h>

#include "../a12.h"
#include "../a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"
#include "directory.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>

static int shmifopen_flags =
			SHMIF_ACQUIRE_FATALFAIL |
			SHMIF_NOACTIVATE |
			SHMIF_NOAUTO_RECONNECT |
			SHMIF_NOREGISTER |
			SHMIF_SOCKET_PINGEVENT;

static struct arcan_shmif_cont shmif_parent_process;
static struct a12_state* active_client_state;
static struct appl_meta* pending_index;
static struct ioloop_shared* ioloop_shared;

static void remote_dir_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{

}

static void
	local_dir_event(struct ioloop_shared* S, bool ok)
{

}

/* different to dir_srv_worker any shared secret is passed as process spawn
 * to match other arcan-net use */
static bool wait_for_activation()
{
	struct arcan_event ev;

	while (arcan_shmif_wait(&shmif_parent_process, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_BCHUNK_IN){
			if (strcmp(ev.tgt.message, ".appl-index") == 0){
/* this code should be shared with regular _worker, when we get the index from
 * the remote directory we compare to the state we track here, if it's newer
 * we retrieve and 'upload' to parent and if it's older we push our local one.
 *
 * if we act as a hierarchical namespace we forward the remote index upwards
 * and just retrieve / cache when needed */
			}
		}
		else if (ev.tgt.kind == TARGET_COMMAND_ACTIVATE)
			return true;
	}

	return false;
}

int anet_directory_link(
	const char* keytag,
	struct anet_options* netcfg,
	struct anet_dirsrv_opts srvcfg)
{
/* first connect to parent so we can communicate failure through last_words */
	struct arg_arr* args;
	shmif_parent_process = arcan_shmif_open(SEGID_NETWORK_SERVER, shmifopen_flags, &args);

/* now make the outbound connection through the keytag, there might be a case
 * for using tag + explicit host when coming from discover though it's better
 * to have discover results modify the keystore. The other option would be to
 * perform authentication in the parent and transfer the authenticated socket
 * and state here. */

/* the context options have already been set to
 *     .local_role = ROLE_DIR
 *     .pk_lookup  = to match the default
 * with trust options etc. as part of the command-line parsing.
 */
	netcfg->retry_count = 0;
	netcfg->key = keytag;
	netcfg->opts->allow_directory_link = true;

	struct anet_cl_connection conn = anet_cl_setup(netcfg);
	if (conn.errmsg || !conn.state){
		arcan_shmif_last_words(&shmif_parent_process, conn.errmsg);
		return EXIT_FAILURE;
	}

	if (a12_remote_mode(conn.state) != ROLE_DIR){
		arcan_shmif_last_words(&shmif_parent_process, "remote not a directory");
		shutdown(conn.fd, SHUT_RDWR);
		return EXIT_FAILURE;
	}

/* now we can privsep, wait with unveil paths until we can test the behaviour
 * against existing directory file descriptors */
	arcan_shmif_privsep(&shmif_parent_process, SHMIF_PLEDGE_PREFIX, NULL, 0);
	a12int_trace(A12_TRACE_DIRECTORY, "notice=prisep-set");

	if (!wait_for_activation()){
		arcan_shmif_last_words(&shmif_parent_process, "no activation");
		shutdown(conn.fd, SHUT_RDWR);
		return EXIT_FAILURE;
	}

/* propagating messages to / from all local runners and forwarding into the
 * directory network will need a different structure routing or pay for a shmif
 * state + thread for each runner we need to route messages through. */
	active_client_state = conn.state;
	struct directory_meta dm =
	{
		.S = conn.state,
		.C = &shmif_parent_process
	};

	struct ioloop_shared ioloop =
	{
		.S = conn.state,
		.fdin = conn.fd,
		.fdout = conn.fd,
		.userfd = shmif_parent_process.epipe,
		.on_event = remote_dir_event,
		.on_userfd = local_dir_event,
		.lock = PTHREAD_MUTEX_INITIALIZER,
		.cbt = &dm
	};

	shmif_parent_process.user = &dm;

	ioloop_shared = &ioloop;
	anet_directory_ioloop(&ioloop);

	arcan_shmif_drop(&shmif_parent_process);

	return EXIT_SUCCESS;
}
