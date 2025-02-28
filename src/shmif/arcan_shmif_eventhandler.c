#include <arcan_shmif.h>
#include <pthread.h>
#include "platform/shmif_platform.h"
#include "shmif_privint.h"
#include "shmif_privext.h"
#include "shmif_defimpl.h"
#include <errno.h>
#include <inttypes.h>

/*
 * Rules for compacting DISPLAYHINT events
 *  1. If dimensions have changed [!0], use new values
 *  2. Always use new hint state
 *  3. If density has changed [> 0], use new value
 *  4. If cell dimensions has changed, use new values
 *  5. Use timestamp component of new event, if it is not there
 *     force it to the process local one
*/
static inline bool merge_dh(arcan_event* new, arcan_event* old)
{
	if (new->tgt.ioevs[7].uiv != old->tgt.ioevs[7].uiv)
		return false;

	if (!new->tgt.ioevs[0].iv)
		new->tgt.ioevs[0].iv = old->tgt.ioevs[0].iv;

	if (!new->tgt.ioevs[1].iv)
		new->tgt.ioevs[1].iv = old->tgt.ioevs[1].iv;

/*
	if ((new->tgt.ioevs[2].iv & 128))
		new->tgt.ioevs[2].iv = old->tgt.ioevs[2].iv;
 */

	if (new->tgt.ioevs[3].iv < 0)
		new->tgt.ioevs[3].iv = old->tgt.ioevs[3].iv;

	if (!(new->tgt.ioevs[4].fv > 0))
		new->tgt.ioevs[4].fv = old->tgt.ioevs[4].fv;

	if (!new->tgt.ioevs[5].iv)
		new->tgt.ioevs[5].iv = old->tgt.ioevs[5].iv;

	if (!new->tgt.ioevs[6].iv)
		new->tgt.ioevs[6].iv = old->tgt.ioevs[6].iv;

	if (!new->tgt.timestamp){
		new->tgt.timestamp = arcan_timemillis();
	}

	return true;
}

static bool scan_stepframe_event(
	struct arcan_evctx*c, struct arcan_event* old, int id)
{
	if (old->tgt.ioevs[1].iv != id)
		return false;
	uint8_t cur = *c->front;

/* conservative merge on STEPFRAME so far is results from VBLANK polling only */
	while (cur != *c->back){
		struct arcan_event* ev = &c->eventbuf[cur];
		if (ev->category == EVENT_TARGET &&
			ev->tgt.kind == TARGET_COMMAND_STEPFRAME &&
			ev->tgt.ioevs[1].iv == id)
				return true;
		cur = (cur + 1) % c->eventbuf_sz;
	}
	return false;
}

/*
 * Display-events are among the most expensive and prone to backpressure,
 * so coalesce them together and merge into the latest to relieve pressure.
 */
static bool scan_display_event(struct arcan_evctx* c, struct arcan_event* old)
{
	uint8_t cur = *c->front;

	while (cur != *c->back){
		struct arcan_event* ev = &c->eventbuf[cur];
		if (ev->category == EVENT_TARGET &&
			ev->tgt.kind == old->tgt.kind && merge_dh(ev, old)){
			return true;
		}
		cur = (cur + 1) % c->eventbuf_sz;
	}

	return false;
}

static bool fd_event(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
/*
 * if we get a descriptor event that is connected to acquiring a new
 * frameserver subsegment- set up special tracking so we can retain the
 * descriptor as new signalling/socket transfer descriptor
 */
	struct shmif_hidden* private = c->priv;
	private->pev.consumed = true;
	if (dst->category == EVENT_TARGET &&
		dst->tgt.kind == TARGET_COMMAND_NEWSEGMENT){
/*
 * forward the file descriptor as well so that, in the case of a HANDOVER,
 * the parent process has enough information to forward into a new process.
 */
		dst->tgt.ioevs[0].iv = private->pseg.epipe = private->pev.fds[0];
		dst->tgt.ioevs[6].iv = private->pev.fds[1];
		snprintf(dst->tgt.message,
			sizeof(dst->tgt.message), "%d", dst->tgt.ioevs[6].iv);
		return true;
	}
/*
 * this event can swap out store access handle for sensitive material like
 * authentication and signing keys. Make sure it doesn't get forwarded.
 */
	else if (dst->category == EVENT_TARGET &&
		dst->tgt.kind == TARGET_COMMAND_DEVICE_NODE &&
		dst->tgt.ioevs[3].iv == 3){
		if (private->keystate_store)
			close(private->keystate_store);

		private->keystate_store = private->pev.fds[0];
		private->autoclean = true;
		private->pev.fds[0] = BADFD;
		return true;
	}
/*
 * otherwise we have a normal pending slot with a descriptor that
 * is inserted into the event, then set as consumed (so next call,
 * unless the descriptor is dup:ed or used, it will close
 */
	else
		dst->tgt.ioevs[0].iv = private->pev.fds[0];

	return false;
}

static bool fetch_check(void* t)
{
	return shmif_platform_check_alive((struct arcan_shmif_cont*) t);
}

/*
 * reset pending- state tracking
 */
void shmifint_consume_pending(struct arcan_shmif_cont* c)
{
	struct shmif_hidden* P = c->priv;
	if (!P->pev.consumed)
		return;

	debug_print(
		DETAILED, c, "acquire: %s",
		arcan_shmif_eventstr(&P->pev.ev, NULL, 0)
	);

	if (BADFD != P->pseg.epipe){
/*
 * Special case, the parent explicitly pushed a debug segment that was not
 * mapped / accepted by the client. Then we take it upon ourselves to add
 * another debugging interface that redirects STDERR to TUI, eventually also
 * setting up support for attaching gdb or lldb, or providing sense_mem style
 * sampling
 */
#ifdef SHMIF_DEBUG_IF
		if (P->pev.gotev &&
			P->pev.ev.category == EVENT_TARGET &&
			P->pev.ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT &&
			P->pev.ev.tgt.ioevs[2].iv == SEGID_DEBUG){
			debug_print(DETAILED, c, "debug subsegment received");

/* want to let the debugif do initial registration */
			struct arcan_shmif_cont pcont =
				arcan_shmif_acquire(c, NULL, SEGID_DEBUG, SHMIF_NOREGISTER);

			if (pcont.addr){
				if (!arcan_shmif_debugint_spawn(&pcont, NULL, NULL))
					arcan_shmif_drop(&pcont);
				return;
			}
		}
#endif
		if (P->pev.gotev &&
			P->pev.ev.category == EVENT_TARGET &&
			P->pev.ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT &&
			P->pev.ev.tgt.ioevs[2].iv == SEGID_ACCESSIBILITY){
			struct arcan_shmif_cont pcont =
				arcan_shmif_acquire(c, NULL, SEGID_ACCESSIBILITY, 0);
			if (pcont.addr){
				if (!arcan_shmif_a11yint_spawn(&pcont, c))
					arcan_shmif_drop(&pcont);
				return;
			}
		}

		close(P->pseg.epipe);
		P->pseg.epipe = BADFD;
		debug_print(DETAILED, c, "closing unhandled subsegment descriptor");
	}

	if (BADFD != P->pev.fds[0]){
		close(P->pev.fds[0]);
		if (P->pev.handedover){
			debug_print(DETAILED, c,
				"closing descriptor (%d:handover)", P->pev.fds[0]);
		}
		else
			debug_print(DETAILED, c,
				"closing descriptor (%d)", P->pev.fds[0]);
	}

	if (BADFD != P->pev.fds[1]){
		close(P->pev.fds[1]);
		debug_print(DETAILED, c,
			"closing secondary descriptor (%d:mem)", P->pev.fds[1]);
	}

	P->pev.fds[0] = P->pev.fds[1] = BADFD;
	P->pev.gotev = false;
	P->pev.consumed = false;
	P->pev.handedover = false;
}

/*
 * shorter handling cycle for automated paused state with partial buffering,
 * true if the event was consumed, false if it should be forwarded.
 */
static bool pause_evh(struct arcan_shmif_cont* c,
	struct shmif_hidden* priv, arcan_event* ev)
{
	if (ev->category != EVENT_TARGET)
		return true;

	bool rv = true;
	if (ev->tgt.kind == TARGET_COMMAND_UNPAUSE ||
		ev->tgt.kind == TARGET_COMMAND_RESET)
		priv->paused = false;
	else if (ev->tgt.kind == TARGET_COMMAND_EXIT){
		priv->alive = false;
		rv = false;
	}
	else if (ev->tgt.kind == TARGET_COMMAND_DISPLAYHINT){
		merge_dh(ev, &priv->dh);
		priv->dh = *ev;
		priv->ph |= 1;
	}

/*
 * theoretical race here is not possible with kms/ks being pulled resulting
 * in either end of epipe being closed and broken socket
 */
	else if (ev->tgt.kind == TARGET_COMMAND_FONTHINT){
		priv->fh.category = EVENT_TARGET;
		priv->fh.tgt.kind = TARGET_COMMAND_FONTHINT;

/* received event while one already pending? don't leak descriptor */
		if (ev->tgt.ioevs[1].iv != 0){
			if (priv->fh.tgt.ioevs[0].iv != BADFD)
				close(priv->fh.tgt.ioevs[0].iv);
			shmif_platform_fetchfds(
				c->epipe, &priv->fh.tgt.ioevs[0].iv, 1, true, fetch_check, c);
		}

		if (ev->tgt.ioevs[2].fv > 0.0)
			priv->fh.tgt.ioevs[2].fv = ev->tgt.ioevs[2].fv;
		if (ev->tgt.ioevs[3].iv > -1)
			priv->fh.tgt.ioevs[3].iv = ev->tgt.ioevs[3].iv;

/* set the bit to indicate we need to return this event */
		priv->ph |= 2;
	}
	return rv;
}

/* this one is really terrible and unfortunately very central
 * subject to a long refactoring of its own, points to keep in check:
 *  - blocking or nonblocking (coming from wait or poll)
 *  - paused state (only accept UNPAUSE)
 *  - crashed or connection terminated
 *  - pairing fd and event for descriptor events
 *  - cleanup of pending resources not consumed by client
 *  - merging event storms (pending hint, ph)
 *  - key state transitions:
 *    - switch devices
 *    - migration
 */
int shmifint_process_events(
	struct arcan_shmif_cont* c, struct arcan_event* dst, bool blocking, bool upret)
{
reset:
	if (!dst || !c->addr)
		return -1;

	struct shmif_hidden* P = c->priv;
	struct arcan_evctx* ctx = &P->inev;
	bool noks = false;
	int rv = 0;

/* we have a RESET delay-slot:ed, that takes priority. This is where it would
 * be useful to actually track acquired secondaries as they might not have
 * guardthreads to unlock. */
	if (P->ph & 4){
		*dst = P->fh;
		P->paused = false;
		rv = 1;
		P->ph = 0;
		goto done;
	}

	if (P->support_window_hook){
		P->support_window_hook(c, SUPPORT_EVENT_POLL);
	}

/* Select few events has a special queue position and can be delivered 'out of
 * order' from normal affairs. This is needed for displayhint/fonthint in WM
 * cases where a connection may be suspended for a long time and normal system
 * state (move window between displays, change global fonts) may be silently
 * ignored, when we actually want them delivered immediately upon UNPAUSE */
	if (!P->paused && P->ph){
		if (P->ph & 1){
			P->ph &= ~1;
			*dst = P->dh;
			rv = 1;
			goto done;
		}
		else if (P->ph & 2){
			*dst = P->fh;
			P->pev.consumed = dst->tgt.ioevs[0].iv != BADFD;
			P->pev.fds[0] = dst->tgt.ioevs[0].iv;
			P->ph &= ~2;
			rv = 1;
			goto done;
		}
		else{
			P->ph = 0;
			rv = 1;
			*dst = P->fh;
			goto done;
		}
	}

/* clean up any pending descriptors, as the client has a short frame to
 * directly use them or at the very least dup() to safety */
	shmifint_consume_pending(c);

/*
 * fetchfd also pumps 'got event' pings that we send in order to portably I/O
 * multiplex in the eventqueue, see arcan/ source for frameserver_pushevent
 */
checkfd:
	do {
		errno = 0;
		if (BADFD == P->pev.fds[0]){
			shmif_platform_fetchfds(c->epipe, P->pev.fds, 2, blocking, fetch_check, c);
		}

		if (P->pev.gotev){
			if (blocking){
				debug_print(DETAILED, c, "waiting for parent descriptor");
			}

			if (P->pev.fds[0] != BADFD){
				if (fd_event(c, dst) && P->autoclean){
					P->autoclean = false;
					shmifint_consume_pending(c);
				}
				else
					rv = 1;
			}
			else if (blocking){
				debug_print(INFO, c, "failure on blocking fd-wait: %s, %s",
					strerror(errno), arcan_shmif_eventstr(&P->pev.ev, NULL, 0));
				if (!errno || errno == EAGAIN)
					continue;
			}

			goto done;
		}
	} while (P->pev.gotev && shmif_platform_check_alive(c));

/* atomic increment of front -> event enqueued, other option in this sense
 * would be to have a poll that provides the pointer, and a step that unlocks */
	if (*ctx->front != *ctx->back){
		*dst = ctx->eventbuf[ *ctx->front ];

/*
 * memset to 0xff for easier visibility on debugging)
 */
		memset(&ctx->eventbuf[ *ctx->front ], 0xff, sizeof (struct arcan_event));
		*ctx->front = (*ctx->front + 1) % ctx->eventbuf_sz;

/* Unless mask is set, paused won't be changed so that is ok. This has the
 * effect of silently discarding events if the server acts in a weird way
 * (pause -> do things -> unpause) but that is the expected behavior, with
 * the exception of DISPLAYHINT, FONTHINT and EXIT */
		if (P->paused){
			if (pause_evh(c, P, dst))
				goto reset;
			rv = 1;
			noks = dst->category == EVENT_TARGET
				&& dst->tgt.kind == TARGET_COMMAND_EXIT;
			goto done;
		}

		if (dst->category == EVENT_TARGET)
			switch (dst->tgt.kind){

/* Ignore displayhints if there are newer ones in the queue. This pattern can
 * be re-used for other events, should it be necessary, the principle is that
 * if there is a serious cost involved for a state change that will be
 * overridden with something in the queue, use this mechanism. Cannot be applied
 * to descriptor- carrying events as more state tracking is needed. */
			case TARGET_COMMAND_DISPLAYHINT:
				if (!P->valid_initial && scan_display_event(ctx, dst))
					goto reset;
			break;

			case TARGET_COMMAND_STEPFRAME:
				if (scan_stepframe_event(ctx, dst, 2) || scan_stepframe_event(ctx, dst, 3))
					goto reset;
			break;

/* automatic pause switches to pause_ev, which only supports subset */
			case TARGET_COMMAND_PAUSE:
				if ((P->flags & SHMIF_MANUAL_PAUSE) == 0){
				P->paused = true;
				goto reset;
			}
			break;

			case TARGET_COMMAND_UNPAUSE:
				if ((P->flags & SHMIF_MANUAL_PAUSE) == 0){
/* used when enqueue:ing while we are asleep */
					if (upret)
						return 0;
					P->paused = false;
					goto reset;
				}
				break;

			case TARGET_COMMAND_BUFFER_FAIL:
/* we can't call bufferfail immediately from here as that would pull in a
 * dependency to shmifext which in turn pulls in GL libraries and so on. */
				debug_print(INFO, c, "buffer-fail, accelerated handle passing rejected");
				c->privext->state_fl = STATE_NOACCEL;
				goto reset;
			break;

			case TARGET_COMMAND_EXIT:
/* While tempting to run _drop here to prevent caller from leaking resources,
 * we can't as the event- loop might be running in a different thread than A/V
 * updating. _drop would modify the context in ways that would break, and we
 * want consistent behavior between threadsafe- and non-threadsafe builds. */
				P->alive = false;
				noks = true;
			break;

/* fonthint is different in the sense that the descriptor is not always
 * mandatory, it is conditional on one of the ioevs (as there might not be an
 * interest to override default font */
			case TARGET_COMMAND_FONTHINT:
				if (dst->tgt.ioevs[1].iv == 1){
					P->pev.ev = *dst;
					P->pev.gotev = true;
					goto checkfd;
				}
				else
					dst->tgt.ioevs[0].iv = BADFD;
			break;

/* similar to fonthint but uses different descriptor- indicator field, more
 * complex rules for if we should forward or handle ourselves. If it's about
 * switching or defining render node for handle passing, then we need to
 * forward as the client need to rebuild its context. */
			case TARGET_COMMAND_DEVICE_NODE:{
				if (P->log_event){
					log_print("(@%"PRIxPTR"<-)%s",
						(uintptr_t) c, arcan_shmif_eventstr(dst, NULL, 0));
				}

				int iev = dst->tgt.ioevs[1].iv;
				if (iev == 4){
/* replace slot with message, never forward, if message is not set - drop */
					if (P->alt_conn){
						free(P->alt_conn);
						P->alt_conn = NULL;
					}

/* if we're provided with a guid, keep it to be used on a possible migrate */
					uint64_t guid[2] = {
						((uint64_t)dst->tgt.ioevs[2].uiv)|
						((uint64_t)dst->tgt.ioevs[3].uiv << 32),
						((uint64_t)dst->tgt.ioevs[4].uiv)|
						((uint64_t)dst->tgt.ioevs[5].uiv << 32)
					};

					if ( (guid[0] || guid[1]) &&
						(P->guid[0] != guid[0] && P->guid[1] != guid[1] )){
						P->guid[0] = guid[0];
						P->guid[1] = guid[1];
					}

					if (dst->tgt.message[0])
						P->alt_conn = strdup(dst->tgt.message);

/* for a state store we also need to fetch the descriptor, and this should
 * ideally already be pending because for the 'force' mode the DMS will be
 * pulled and futex regions triggered */
					goto reset;
				}
				else if (iev == 1){
/* other ones are ignored for now, require cooperation with shmifext */
					if (dst->tgt.ioevs[3].iv == 3){
						P->pev.ev = *dst;
						P->pev.gotev = true;
						goto checkfd;
					}
				}
/* event that request us to switch connection point */
				else if (iev > 1 && iev <= 3){
					if (dst->tgt.message[0] == '\0'){
						P->pev.ev = *dst;
						P->pev.gotev = true;
						goto checkfd;
					}
/* try to migrate automatically, but ignore on failure */
					else {
						if (shmif_platform_fallback(c,
							dst->tgt.message, false) != SHMIF_MIGRATE_OK){
							rv = 0;
							goto done;
						}
						else
							goto reset;
					}
				}
				else
					goto reset;
			}
			break;

/* Events that require a handle to be tracked (and possibly garbage collected
 * if the caller does not handle it) should be added here. Then the event will
 * be deferred until we have received a handle and the specific handle will be
 * added to the actual event. */
			case TARGET_COMMAND_NEWSEGMENT:
				P->autoclean = !!(dst->tgt.ioevs[5].iv);

/* fallthrough behavior is expected */
			case TARGET_COMMAND_STORE:
			case TARGET_COMMAND_RESTORE:
			case TARGET_COMMAND_BCHUNK_IN:
			case TARGET_COMMAND_BCHUNK_OUT:
				debug_print(DETAILED, c,
					"got descriptor event (%s)", arcan_shmif_eventstr(dst, NULL, 0));
				P->pev.gotev = true;
				P->pev.ev = *dst;
				goto checkfd;
			default:
			break;
			}

		rv = 1;
	}
/* a successful migrate will delay-slot the RESET event, so in that case
 * go back to reset and have that activate */
	else if (!shmif_platform_check_alive(c)){
		if (shmif_platform_fallback(c, P->alt_conn, true) == SHMIF_MIGRATE_OK)
			goto reset;
		goto done;
	}

/* Need to constantly pump the event socket for incoming descriptors and
 * caller- mandated polling, as the order between event and descriptor is
 * not deterministic */
	else if (blocking && shmif_platform_check_alive(c))
		goto checkfd;

done:
	return shmif_platform_check_alive(c) || noks ? rv : -1;
}
