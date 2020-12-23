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
/* wait for incoming connection,
 * authenticate
 * run threaded (!) <-
 * this should be switch to handover exec to ourselves where we pass
 * the session key post-auth
 */
	return EXIT_FAILURE;
}
