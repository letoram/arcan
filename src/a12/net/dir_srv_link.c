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

struct queue_item {
	uint16_t identifier; /* slot identifier as per the state received */
	uint8_t name[16];    /* track the name just to not have to sweep index */
	bool appl;           /* do we need the appl- slot? */
	bool ctrl;           /* do we need the ctrl- slot? */
	bool download;       /* download OR upload, both doesn't make sense */
	struct queue_item* next;
};

static struct {
	struct arcan_shmif_cont shmif_parent_process;
	struct a12_state* active_client_state;
	struct appl_meta* local_index;
	struct ioloop_shared* ioloop_shared;
	struct queue_item* queue;
} G;

static struct a12_state trace_state = {.tracetag = "link"};

#define TRACE(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	struct a12_state* S = &trace_state;\
		a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	} while (0);

static void synch_local_directory(struct appl_meta* first)
{
	if (G.local_index){

	}
	G.local_index = first;
}

static void remote_dir_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{

}

static void
	local_dir_event(struct ioloop_shared* S, bool ok)
{
	struct arcan_event ev;
	int pv;

	while ((pv = arcan_shmif_poll(&S->shmif, &ev)) > 0){
/* BCHUNKSTATE for updating appl index is the main one here */
	}

	if (-1 == pv){
		S->shutdown = true;
	}
}

/* different to dir_srv_worker any shared secret is passed as process spawn to
 * match other arcan-net use. we use COREOPT to pass any config options for how
 * to deal with repository synch. */
static bool wait_for_activation()
{
	struct arcan_event ev;

	while (arcan_shmif_wait(&G.shmif_parent_process, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_BCHUNK_IN){
			if (strcmp(ev.tgt.message, ".appl-index") == 0){
				struct appl_meta* first = dir_unpack_index(ev.tgt.ioevs[0].iv);
				if (!first){
					arcan_shmif_last_words(&G.shmif_parent_process, "activation: broken index");
					return false;
				}
				synch_local_directory(first);
			}
		}
		else if (ev.tgt.kind == TARGET_COMMAND_ACTIVATE)
			return true;
	}

	arcan_shmif_last_words(&G.shmif_parent_process, "no activation");
	return false;
}

/* We have received a full remote directory - we need to interleave this with
 * our own index to the one we are exporting in the parent process. There are
 * many nuances to this, one is if it is a source/sink/directory or appl.
 *
 * For sources / sinks we announce them as new sources and namespaced so that
 * any diropen request goes through us.
 *
 * For appls there is both the controller side and the client side bundles to
 * consider. Normally a client wouldn't have access to the controller side,
 * but that is necessary for directories in a unified namespace to work.
 *
 * Directories in a referential one simply needs to tunnel MESSAGES and file
 * transfers so that they route to the server that actually runs it.
 *
 * Directories in a unified one needs to have our end spin up an appl-runner
 * and proxy join/leave/bchunk/messages.
 *
 * The implementation here is currently naive when it comes to handling
 * collisions. A proper approach would be to have signatures (pending) and make
 * sure that it is the same source that has signed that owns the name but the
 * protocol currently lack the mechanisms (REKEY for setting signing key and
 * recovery key for rotating them).
 */
static bool remote_directory_receive(
	struct ioloop_shared* I, struct appl_meta* dir)
{
	size_t i = 0;
	TRACE("remote_index");

/* sweep each, see if we find matching name in the currently set index - if we
 * are referential we just need to save / store the index so that we can
 * forward it. */
	while (dir){
		TRACE("id=%"PRIu16":size=%"PRIu64":name=%s%s%s",
			dir->identifier, dir->buf_sz, dir->appl.name,
			dir->appl.short_descr[0] ? ":description=" : "",
			dir->appl.short_descr[0] ? dir->appl.short_descr : ""
		);
		dir = dir->next;
	}

/* always keep-alive */
	return true;
}

static void remote_directory_discover(struct a12_state* S,
	uint8_t type, const char* petname, uint8_t state,
	uint8_t pubk[static 32], uint16_t ns, void* tag)
{
	bool found = state == 1 || state == 2;
	a12int_trace(A12_TRACE_DIRECTORY,
		"remote_discover:%s:name=%s:type=%d",
		found ? "found" : "lost", petname, type);
}

int anet_directory_link(
	const char* keytag,
	struct anet_options* netcfg,
	struct anet_dirsrv_opts srvcfg)
{
/* first connect to parent so we can communicate failure through last_words */
	struct arg_arr* args;
	G.shmif_parent_process =
		arcan_shmif_open(SEGID_NETWORK_SERVER, shmifopen_flags, &args);

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
		arcan_shmif_last_words(&G.shmif_parent_process, conn.errmsg);
		return EXIT_FAILURE;
	}

	if (a12_remote_mode(conn.state) != ROLE_DIR){
		arcan_shmif_last_words(&G.shmif_parent_process, "remote not a directory");
		shutdown(conn.fd, SHUT_RDWR);
		return EXIT_FAILURE;
	}

/* now we can privsep, wait with unveil paths until we can test the behaviour
 * against existing directory file descriptors */
	arcan_shmif_privsep(&G.shmif_parent_process, SHMIF_PLEDGE_PREFIX, NULL, 0);
	TRACE("notice=prisep-set");

	G.active_client_state = conn.state;
	a12_trace_tag(conn.state, "dir_link");

	if (!wait_for_activation()){
		shutdown(conn.fd, SHUT_RDWR);
		return EXIT_FAILURE;
	}

/* propagating messages to / from all local runners and forwarding into the
 * directory network will need a different structure routing or pay for a shmif
 * state + thread for each runner we need to route messages through. */
	struct directory_meta dm =
	{
		.S = conn.state,
		.C = &G.shmif_parent_process
	};

	struct ioloop_shared ioloop =
	{
		.S = conn.state,
		.fdin = conn.fd,
		.fdout = conn.fd,
		.userfd = G.shmif_parent_process.epipe,
		.userfd2 = -1,
		.on_event = remote_dir_event,
		.on_userfd = local_dir_event,
		.on_directory = remote_directory_receive,
		.lock = PTHREAD_MUTEX_INITIALIZER,
		.cbt = &dm
	};

	G.shmif_parent_process.user = &dm;

	a12_set_destination_raw(conn.state, 0,
		(struct a12_unpack_cfg){
			.on_discover = remote_directory_discover,
			.on_discover_tag = &ioloop
		}, sizeof(struct a12_unpack_cfg)
	);

/* request dirlist and subscribe to notifications */
	a12int_request_dirlist(conn.state, true);

	G.ioloop_shared = &ioloop;
	anet_directory_ioloop(&ioloop);

	arcan_shmif_drop(&G.shmif_parent_process);

	return EXIT_SUCCESS;
}
