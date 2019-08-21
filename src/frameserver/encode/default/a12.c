#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include "a12.h"
#include "a12_int.h"

#include <sys/socket.h>
#include <signal.h>
#include <netdb.h>

/*
 * for each updated A/V buffer, we need to push to all connected clients,
 * so set this counter to the number of expected clients and decrement
 * when it has been processed.
 */
static volatile _Atomic int frame_waiters;

struct client {
	struct a12_state* a12;
	int socket;
};

/*
 * new client:
 * a12_build(context options);
 * -> a12_unpack(state, buf, size, TAG, on_event(wnd, int chid, event*, tag))
 * -> a12_channel_aframe
 * -> a12_channel_vframe
 */

pthread_mutex_t conn_synch = PTHREAD_MUTEX_INITIALIZER;

/*
 * Expose a shmif context in ENCODE/OUTPUT mode as a normal MEDIA/APPLICATION
 * 'client' to whatever remoting session that connected and authenticated.
 *
 * This is the opposite of how the server side works in arcan-netproxy, where
 * the listening connection behaves as a client.
 *
 * It is simpler in the sense that we typically reject subsegment and things
 * like that, 'clipboard' like operations are just done as state transfers on
 * the connection.
 */
void a12_serv_run(struct arg_arr* arg, struct arcan_shmif_cont cont)
{
	int port = 6630;
	signal(SIGPIPE, SIG_IGN);
	signal(SIGCHLD, SIG_IGN);

/* derive key from password or retrieve keypair from message loop first */

	struct arcan_event ev;
	while(arcan_shmif_wait(&cont, &ev) != 0){
		switch (ev.tgt.kind){
			case TARGET_COMMAND_STEPFRAME:
				pthread_mutex_lock(&conn_synch);
				pthread_mutex_unlock(&conn_synch);
				atomic_store(&cont.addr->vready, 0);
				atomic_store(&cont.addr->aready, 0);
			break;

			case TARGET_COMMAND_MESSAGE:
/* update / setup connection primitives, activate if deferred */
			break;

			case TARGET_COMMAND_EXIT:
				pthread_mutex_lock(&conn_synch);
/* iterate each connection and kill */
				pthread_mutex_unlock(&conn_synch);
			break;
		}
	}
}
