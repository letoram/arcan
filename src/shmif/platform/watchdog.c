#include "arcan_shmif.h"
#include <pthread.h>
#include "shmif_platform.h"
#include "shmif_privint.h"
#include <signal.h>
#include <sys/socket.h>
#include <errno.h>
#include <unistd.h>

/*
 * Watchdog conditions:
 *  1. is there a monitoring pid set that we tie lifecycle to?
 *  2. is there a socket we can poke to see if it has been shutdown?
 *  3. is there a context- local 'dead man switch'?
 *  4. shared memory page 'dead man switch'
 *
 * Watchdog controls:
 *  There is a set of semaphores to fire (unlock) when any of the
 *  triggers are activated.
 *
 *  there is a function pointer used as a callback to be notified if
 *  the watchdog is activated.
 */
static inline bool parent_alive(struct shmif_hidden* gs)
{
	/* for authoritative connections, a parent monitoring pid is set. */
	if (gs->guard.parent > 0){
		if (-1 == kill(gs->guard.parent, 0))
			return false;
	}

/* peek the socket (if it exists) and see if we get an error back */
	if (-1 != gs->guard.parent_fd){
		unsigned char ch;

		if (-1 == recv(gs->guard.parent_fd, &ch, 1, MSG_PEEK | MSG_DONTWAIT)
			&& (errno != EWOULDBLOCK && errno != EAGAIN))
			return false;
	}

	return true;
}

/* This act as our safeword (or well safebyte), if either party for _any_reason
 * decides that it is not worth going the dms (dead man's switch) is pulled.
 *
 * Then we release the different semaphores (audio, video, event) regardless of
 * their state to ensure that any thread in _wait, _signal gets released and
 * the next call into shmif would fail. */
static void* watchdog(void* gs)
{
	struct shmif_hidden* gstr = gs;

	while (gstr->guard.active){
		if (!parent_alive(gstr)){
			volatile uint8_t* dms;

/* guard synch mutex only protects the structure itself, it is not loaded or
 * checked between every shmif-operation */
			pthread_mutex_lock(&gstr->guard.synch);

/* setting the dms here practically doesn't imply that the sem_post on wakeup
 * set won't run again from a delayed dms write, the dms set action here is for
 * any others that might monitor the segment */
			if ((dms = atomic_load(&gstr->guard.dms)))
				*dms = false;

			atomic_store(&gstr->guard.local_dms, false);

/* other threads might be locked on semaphores, so wake them up, and force them
 * to re-examine the dms from being released */
			for (size_t i = 0; i < COUNT_OF(gstr->guard.semset); i++){
				if (gstr->guard.semset[i])
					arcan_sem_post(gstr->guard.semset[i]);
			}

			gstr->guard.active = false;

/* same as everywhere else, implementation need to allow unlock to destroy */
			pthread_mutex_unlock(&gstr->guard.synch);
			pthread_mutex_destroy(&gstr->guard.synch);

/* also shutdown the socket, should unlock any blocking I/O stage (IB so other
 * mechanisms are in place as well, mainly fdpassing.c having a timeout on the
 * socket */
			shutdown(gstr->guard.parent_fd, SHUT_RDWR);
			debug_print(FATAL, NULL, "guard thread activated, shutting down");

			if (gstr->guard.exitf)
				gstr->guard.exitf(EXIT_FAILURE);

			goto done;
		}

		sleep(1);
	}

done:
	return NULL;
}

bool shmif_platform_check_alive(struct arcan_shmif_cont* C)
{
	if (!C->priv->alive ||
		!atomic_load(&C->priv->guard.local_dms) || !C->addr->dms)
		return false;

	return true;
}

void shmif_platform_guard_resynch(
	struct arcan_shmif_cont* C, int parent_pid, int parent_fd)
{
	if (!C->priv->guard.active)
		return;

	atomic_store(&C->priv->guard.dms, (uint8_t*) &C->addr->dms);
	C->priv->guard.parent_fd = parent_fd;
	C->priv->guard.parent = parent_pid;
}

void shmif_platform_guard_lock(struct arcan_shmif_cont* C)
{
	if (C->priv->guard.active)
		pthread_mutex_lock(&C->priv->guard.synch);
}

void shmif_platform_guard_unlock(struct arcan_shmif_cont* C)
{
	if (C->priv->guard.active)
		pthread_mutex_unlock(&C->priv->guard.synch);
}

void shmif_platform_guard_release(struct arcan_shmif_cont* C)
{
	if (!C->priv->guard.active){
		free(C->priv);
		return;
	}

	atomic_store(&C->priv->guard.dms, 0);
	C->priv->guard.active = false;
}

void shmif_platform_guard(struct arcan_shmif_cont* C, struct watchdog_config CFG)
{
	struct shmif_hidden* P = C->priv;

	if (P->guard.active)
		return;

	P->guard.local_dms = true;
	P->guard.semset[0] = CFG.audio;
	P->guard.semset[1] = CFG.video;
	P->guard.semset[2] = CFG.event;
	P->guard.parent = CFG.parent_pid;
	P->guard.parent_fd = CFG.parent_fd;
	P->guard.exitf = CFG.exitf;
	atomic_store(&P->guard.dms, (uint8_t*) &C->addr->dms);

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_mutex_init(&P->guard.synch, NULL);

/* failure means loss of functionality but not a terminal condition */
	P->guard.active = true;
	if (-1 == pthread_create(&pth, &pthattr, watchdog, P)){
		P->guard.active = false;
	}
}
