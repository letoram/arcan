#include <arcan_shmif.h>
#include "shmif_platform.h"
#include <pthread.h>
#include "../shmif_privint.h"

#ifdef __LINUX
#include <sys/inotify.h>
static bool notify_wait(const char* cpoint)
{
/* if we get here we really shouldnt be at the stage of a broken connpath,
 * and if we are the connect loop won't do much of anything */
	char buf[256];
	int len = arcan_shmif_resolve_connpath(cpoint, buf, 256);
	if (len <= 0)
		return false;

/* path in abstract namespace or non-absolute */
	if (buf[0] != '/')
		return false;

/* strip down to the path itself */
	size_t pos = strlen(buf);
	while(pos > 0 && buf[pos] != '/')
		pos--;

	if (!pos)
		return false;

	buf[pos] = '\0';

	int notify = inotify_init1(IN_CLOEXEC);
	if (-1 == notify)
		return false;

/* watch the path for changes */
	if (-1 == inotify_add_watch(notify, buf, IN_CREATE)){
		close(notify);
		return false;
	}

/* just wait for something, the path shouldn't be particularly active */
	struct inotify_event ev;
	read(notify, &ev, sizeof(ev));

	close(notify);
	return true;
}
#endif

static bool scan_exit_event(struct arcan_evctx* c)
{
	uint8_t cur = *c->front;
	while (cur != *c->back){
		struct arcan_event* ev = &c->eventbuf[cur];
		if (
			ev->category == EVENT_TARGET &&
			ev->tgt.kind == TARGET_COMMAND_EXIT
		)
			return true;

		cur = (cur + 1) % c->eventbuf_sz;
	}

	return false;
}

static void scan_device_node_event(struct shmif_hidden* P, struct arcan_evctx* c)
{
	uint8_t cur = *c->front;

	while (cur != *c->back){
		struct arcan_event* ev = &c->eventbuf[cur];
		if (
			ev->category == EVENT_TARGET &&
			ev->tgt.kind == TARGET_COMMAND_DEVICE_NODE &&
			ev->tgt.ioevs[1].iv == 4) /* set alt-conn */
		{
			if (P->alt_conn)
				free(P->alt_conn);
			P->alt_conn = NULL;
			if (ev->tgt.message[0])
				P->alt_conn = strdup(ev->tgt.message);
		}
		cur = (cur + 1) % c->eventbuf_sz;
	}
}

enum shmif_migrate_status shmif_platform_fallback(
	struct arcan_shmif_cont* C, const char* cpoint, bool force)
{
/* sleep - retry connect loop */
	enum shmif_migrate_status sv;
	struct shmif_hidden* P = C->priv;
	int oldfd = C->epipe;

/* we are actually told to exit, so collapse back to eventloop */
	if (scan_exit_event(&P->inev))
		return SHMIF_MIGRATE_NOCON;

/* there might be a newer altcon in the queue as well, so check that first */
	scan_device_node_event(P, &P->inev);

/* parent can pull dms explicitly */
	if (force){
		if ((P->flags & SHMIF_NOAUTO_RECONNECT)
			|| shmif_platform_check_alive(C) || P->output)
			return SHMIF_MIGRATE_NOCON;
	}

/* CONNECT_LOOP style behavior on force */
	const char* current = cpoint;

	while ((sv = arcan_shmif_migrate(C, current, NULL)) == SHMIF_MIGRATE_NOCON){
		if (!force)
			break;

/* try to return to the last known connection point after a few tries */
		else if (current == cpoint && P->alt_conn)
			current = P->alt_conn;
		else
			current = cpoint;

/* if there is a poll mechanism to use, go for it, otherwise fallback to a
 * timesleep - special cases include a12://, non-linux, ... */
#ifdef __LINUX
		if (!(strlen(cpoint) > 6 &&
			strncmp(cpoint, "a12://", 6) == 0) && notify_wait(cpoint))
				continue;
		else
#endif
		arcan_timesleep(100);
	}

	switch (sv){
/* dealt with above already */
	case SHMIF_MIGRATE_NOCON:
	break;
	case SHMIF_MIGRATE_BAD_SOURCE:
/* this means that multiple threads tried to migrate at the same time,
 * and we come from one that isn't the primary one */
		return sv;
	break;
	case SHMIF_MIGRATE_BADARG:
		debug_print(FATAL, c, "recovery failed, broken path / key");
	break;
	case SHMIF_MIGRATE_TRANSFER_FAIL:
		debug_print(FATAL, c, "migration failed on setup");
	break;

/* set a reset event in the "to be dispatched next dequeue" slot, it would be
 * nice to have a sneakier way of injecting events into the normal dequeue
 * process to use as both inter-thread and MiM. Clear any pending descriptor as
 * it will be useless. */
	case SHMIF_MIGRATE_OK:
		if (P->ph & 2){
			if (P->fh.tgt.ioevs[0].iv != BADFD){
				close(P->fh.tgt.ioevs[0].iv);
				P->fh.tgt.ioevs[0].iv = BADFD;
				P->ph = 0;
			}
		}

		P->ph |= 4;
		P->fh = (struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_RESET,
			.tgt.ioevs[0].iv = 3,
			.tgt.ioevs[1].iv = oldfd
		};
	break;
	}

	return sv;
}
