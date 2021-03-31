/*
 * This is just re-using the same code-paths as in arcan-net with a different
 * routine to argument parsing and debug output.
 *
 * What it needs 'extra' is basically a rendezvous / dictionary server used for
 * local / p2p service exchange to learn of keys.
 *
 * Another worthwhile distinction is that remoting and encode also provides
 * some a12 client/server functionality, but those are for working with
 * 'composited' desktops, while this one is between arcan clients across a12.
 */

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include "a12.h"
#include "../../util/anet_helper.h"

int afsrv_netcl(struct arcan_shmif_cont* c, struct arg_arr* args)
{

	return EXIT_FAILURE;
}

int afsrv_netsrv(struct arcan_shmif_cont* c, struct arg_arr* args)
{
	return EXIT_FAILURE;
}
