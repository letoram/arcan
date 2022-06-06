/*
 * Copyright: Bjorn Stahl
 * License: 3-Clause BSD
 * Description: Implements a support wrapper for the a12 function patterns used
 * to implement a single a12- server that translated to an a12- client
 * connection. This is the dispatch function that sets up a managed loop
 * handling one client. Thread or multiprocess it.
 *
 * This is the 'real' display server local to remote proxied client, so
 * events like NEWSEGMENT etc. originate here.
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <pthread.h>
#include <semaphore.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"

/* [THREADING]
 * Same strategy as with a12-helper-srv, we have one main thread that deals with
 * the socket-in/-out, then we have a processing thread per segment that deals
 * with the normal event loop and its translation.
 */
/* could've gone with an allocation bitmap, not worth the extra effort though*/

#define BEGIN_CRITICAL(X, Y) do{pthread_mutex_lock(&((X)->giant_lock)); (X)->last_lock = Y;} while(0);
#define END_CRITICAL(X) do{pthread_mutex_unlock(&(X)->giant_lock);} while(0);

struct cl_state{
	int kill_fd;
	pthread_mutex_t giant_lock;

	volatile _Atomic uint8_t n_segments;
	const char* last_lock;
	volatile _Atomic uint8_t alloc[256];
	_Atomic size_t buffer_out;
};

int get_free_id(struct cl_state* state)
{
	for (int i = 0; i < 256; i++)
		if (!atomic_load(&state->alloc[i]))
			return i;

	return -1;
}

bool spawn_thread(struct a12_state* S,
	struct cl_state* cl, struct arcan_shmif_cont* c, uint8_t chid);

static void on_cl_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM,
			"ignore incoming event (%s) on unknown context, channel: %d",
			arcan_shmif_eventstr(ev, NULL, 0), chid
		);
		return;
	}
/* should not really receive descriptors this way (client forwarding to server,
 * all these are pushed from the server stage or should be locally blocked) */
	if (arcan_shmif_descrevent(ev)){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:status=EINVAL:message=incoming descr- event ignored");
	}
	else {
		a12int_trace(A12_TRACE_EVENT,
			"client event: %s on ch %d", arcan_shmif_eventstr(ev, NULL, 0), chid);

/* REGISTER event is special as this is what will trigger the type, it is here
 * we inject that we come from a networked origin so that the WM can apply its
 * policies properly */
		arcan_shmif_enqueue(cont, ev);

		if (ev->category == EVENT_EXTERNAL && ev->ext.kind == EVENT_EXTERNAL_REGISTER){
			arcan_shmif_enqueue(cont, &(struct arcan_event){
				.category = EVENT_EXTERNAL,
				.ext.kind = EVENT_EXTERNAL_PRIVDROP,
				.ext.privdrop = {
					.networked = true
				}
			});
		}
	}
}

struct shmif_thread_data {
	struct arcan_shmif_cont* C;
	struct a12_state* S;
	struct cl_state* state;
	uint8_t chid;
};

static void add_segment(struct shmif_thread_data* data, arcan_event* ev)
{
/* THREAD-CRITICAL */
	BEGIN_CRITICAL(data->state, "add-segment");
/* hit the 256 window / client limit? just ignore, shmif will cleanup */
		int chid = get_free_id(data->state);
		if (-1 == chid)
			goto out;

		int segkind = ev->tgt.ioevs[2].iv;
		int cookie = ev->tgt.ioevs[3].iv;

/* send the channel command before actually activating the thread so we don't
 * risk any ordering issues (thread-preempt -> write before new) */
		a12int_trace(A12_TRACE_ALLOC, "kind=segment:chid=%d:stage=open", chid);
		a12_channel_new(data->S, chid, segkind, cookie);

/* temporary on-stack store, real will be alloc:ed in spawn thread */
		a12int_trace(A12_TRACE_ALLOC, "kind=segment:chid=%d:stage=acquire", chid);
		struct arcan_shmif_cont cont =
			arcan_shmif_acquire(data->C, NULL, segkind, 0);

		if (!cont.addr){
			a12int_trace(A12_TRACE_SYSTEM, "kind=segment:status=EINVAL:chid=%d", chid);
			a12_set_channel(data->S, chid);
			a12_channel_close(data->S);
			goto out;
		}

/*
 * for quick testing allocations
		shmif_pixel *px = cont.vidp;
		for (size_t i = 0; i < cont.w * cont.h; i++)
			px[i] = SHMIF_RGBA(64, 92, 0, 255);
		arcan_shmif_signal(&cont, SHMIF_SIGVID);
 */
		atomic_store(&data->state->alloc[chid], 1);

		if (!spawn_thread(data->S, data->state, &cont, chid)){
			a12int_trace(A12_TRACE_SYSTEM, "kind=thread:status=EBADTHRD:chid=%d", chid);
			a12_set_channel(data->S, chid);
			a12_channel_close(data->S);
			arcan_shmif_drop(&cont);
			atomic_store(&data->state->alloc[chid], 0);
			goto out;
		}

/* A12- OUT: this will send the command to the other side that we have a
 * new segment that may provide or receive data */
		a12int_trace(A12_TRACE_ALLOC, "kind=segment:status=assigned:chid=%d", chid);

/* END OF THREAD-CRITICAL */
out:
	END_CRITICAL(data->state);
}

static bool dispatch_event(struct shmif_thread_data* data, arcan_event* ev)
{
	bool dirty = false;

/* the normal descriptor events are consumed in the a12_channel_enqueue
 * which also takes the job of calling the a12_enqueue_bstream */
	if (ev->category == EVENT_TARGET &&
		ev->tgt.kind == TARGET_COMMAND_NEWSEGMENT){
		add_segment(data, ev);
		return true;
	}

/*
 * This is hairier than one might thing, as there is a distinction between
 * 'local' and 'remote' display server switching. For the 'local' case, we
 * can simply switch migrate the proxy-shmif-client connection to that one
 * and mask it.
 *
 * For the 'remote' and 'fallback' sides, it gets hairier as the inherited
 * connection primitive would then principally make this act as a bouncer,
 * with implications that are ... complex .. to foresee.
 *
 * Thus, for the time being, we mask out the device-node hints and let the
 * shmif-srv/local-client do their own injection / redirection.
 */
	if (ev->category == EVENT_TARGET &&
		ev->tgt.kind == TARGET_COMMAND_DEVICE_NODE){
		return false;
	}

/* we ignore sending the _shutdown command here as the next _poll will fail -1
 * cause the loop to end and the normal _shutdown _close */
	if (ev->category == EVENT_TARGET &&
		ev->tgt.kind == TARGET_COMMAND_EXIT){
		return false;
	}

	BEGIN_CRITICAL(data->state, "process-event");
		a12int_trace(A12_TRACE_EVENT,
			"kind=enqueue:event=%s", arcan_shmif_eventstr(ev, NULL, 0));
		a12_set_channel(data->S, data->chid);
		a12_channel_enqueue(data->S, ev);
		dirty = true;
	END_CRITICAL(data->state);

	return dirty;
}

static void* client_thread(void* inarg)
{
	struct shmif_thread_data* data = inarg;
	arcan_event newev;

	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[2] = {
		{.fd = data->C->epipe, POLLIN | errmask},
		{.fd = data->state->kill_fd, errmask}
	};

/* normal "block then flush" style loop */
	for(;;){

/* break out and clean-up on pollset error */
		if (
				((-1 == poll(fds, 2, -1) && (errno != EAGAIN || errno != EINTR))) ||
				(fds[0].revents & errmask) || (fds[1].revents & errmask)
		){
				break;
		}

		bool dirty = false;
		int pv;
		while((pv = arcan_shmif_poll(data->C, &newev) > 0))
			dirty |= dispatch_event(data, &newev);

/* and ping or die */
		if (dirty){
			if (-1 == write(data->state->kill_fd, &data->chid, 1))
				break;
		}

		if (pv < 0)
			break;
	}

/* free channel resources */
	BEGIN_CRITICAL(data->state, "client-death");
		a12_set_channel(data->S, data->chid);
		a12_channel_shutdown(data->S, "");
		write(data->state->kill_fd, &data->chid, 1);
		a12_channel_close(data->S);
		arcan_shmif_drop(data->C);

/* and if the primary dies, all die */
		if (data->chid == 0)
			close(data->state->kill_fd);

/* finally release the allocation, this will cause the main thread to
 * stop spinning, ultimately killing data->S */
		atomic_store(&data->state->alloc[data->chid], 0);
		atomic_fetch_sub(&data->state->n_segments, 1);
	END_CRITICAL(data->state);

	free(data->C);
	free(data);
	return NULL;
}

bool spawn_thread(struct a12_state* S,
	struct cl_state* cl, struct arcan_shmif_cont* c, uint8_t chid)
{
	struct shmif_thread_data* data = malloc(sizeof(struct shmif_thread_data));
	if (!data){
		a12int_trace(A12_TRACE_ALLOC, "could not setup thread data");
		return false;
	}

/* alloc/copy context to heap block in order to pass into thread */
	struct arcan_shmif_cont* cont = malloc(sizeof(struct arcan_shmif_cont));
	if (!cont){
		free(data);
		a12int_trace(A12_TRACE_ALLOC, "could not setup content copy");
		return false;
	}
	*cont = *c;
	*data = (struct shmif_thread_data){
		.C = cont,
		.S = S,
		.state = cl,
		.chid = chid
	};

	a12_set_destination(S, cont, chid);

/* and detach, cleanup is up to each thread */
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	atomic_fetch_add(&cl->n_segments, 1);

	if (-1 == pthread_create(&pth, &pthattr, client_thread, data)){
		BEGIN_CRITICAL(cl, "cleanup-spawn");
			atomic_fetch_sub(&cl->n_segments, 1);
			a12_set_channel(S, chid);
			a12_channel_close(S);
			a12int_trace(A12_TRACE_ALLOC, "could not spawn thread");
		END_CRITICAL(cl);
		free(data);
		free(cont);
		return false;
	}

	return true;
}

static void auth_handler(struct a12_state* S, void* tag)
{
	S->on_auth = NULL;
	struct arcan_shmif_cont* C = tag;
	spawn_thread(S, C->user, C, 0);
}

int a12helper_a12srv_shmifcl(
	struct arcan_shmif_cont* prealloc,
	struct a12_state* S, const char* cp, int fd_in, int fd_out)
{
	if (!cp)
		cp = getenv("ARCAN_CONNPATH");
	else
		setenv("ARCAN_CONNPATH", cp, 1);

	if (!cp && !prealloc){
		a12int_trace(A12_TRACE_SYSTEM, "No connection point was specified");
		return -ENOENT;
	}

	struct cl_state cl = {
		.giant_lock = PTHREAD_MUTEX_INITIALIZER,
	};

/* primary segment is created without any type or activation, as it is the
 * remote client event that will map those events, defer thread-spawn until
 * authentication is completed */
	a12int_trace(A12_TRACE_ALLOC, "kind=segment:status=opening:chid=0");
	struct arcan_shmif_cont cont = prealloc ? *prealloc :
		arcan_shmif_open(SEGID_UNKNOWN, SHMIF_NOACTIVATE, NULL);

	if (!cont.addr){
		a12int_trace(A12_TRACE_SYSTEM, "Couldn't connect to an arcan display server");
		return -ENOENT;
	}

	int pipe_pair[2];
	if (-1 == pipe(pipe_pair))
		return -EINVAL;

/* preset channel 0 to primary, it will close the kill_fd write end */
	atomic_store(&cl.alloc[0], 1);
	cl.kill_fd = pipe_pair[1];
	cont.user = &cl;

	uint8_t inbuf[9000];
	uint8_t* outbuf = NULL;
	size_t outbuf_sz = 0;
	a12int_trace(A12_TRACE_SYSTEM, "got proxy connection, waiting for source");

/* Hook authentication so that we can spawn the primary processing thread
 * unless the context comes pre-authentication, then spawn immediately. */
	if (a12_auth_state(S) == AUTH_FULL_PK)
		spawn_thread(S, cont.user, &cont, 0);
	else {
		S->on_auth = auth_handler;
		S->auth_tag = &cont;
	}

/*
 * Socket in/out liveness, buffer flush / dispatch
 */
	size_t n_fd = 2;
	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[3] = {
		{.fd = fd_in,        .events = POLLIN  | errmask},
		{.fd = pipe_pair[0], .events = POLLIN  | errmask},
		{.fd = fd_out,       .events = POLLOUT | errmask}
	};

/* flush any left overs from authentication */
	a12_unpack(S, NULL, 0, NULL, on_cl_event);

	while(a12_ok(S) && -1 != poll(fds, n_fd, -1)){
		if (
			(fds[0].revents & errmask) ||
			(fds[1].revents & errmask) ||
			(n_fd == 3 && fds[1].revents & errmask)){
			break;
		}

	/* flush wakeup data from threads */
		if (fds[1].revents){
			if (a12_trace_targets & A12_TRACE_TRANSFER){
				BEGIN_CRITICAL(&cl, "flush-iopipe");
					a12int_trace(
						A12_TRACE_TRANSFER, "client thread wakeup");
				END_CRITICAL(&cl);
			}

			read(fds[1].fd, inbuf, 9000);
		}

/* pending out, flush or grab next out buffer */
		if (n_fd == 3 && (fds[2].revents & POLLOUT) && outbuf_sz){
			ssize_t nw = write(fd_out, outbuf, outbuf_sz);

			if (a12_trace_targets & A12_TRACE_TRANSFER){
				BEGIN_CRITICAL(&cl, "buffer-out");
					a12int_trace(
						A12_TRACE_TRANSFER, "send %zd (left %zu) bytes", nw, outbuf_sz);
				END_CRITICAL(&cl);
			}

			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}
		}

/* grab the lock from the other threads, unpack the data (which in turn will
 * trigger on_cl_event, the lock is held while that happens */
		if (fds[0].revents & POLLIN){
			ssize_t nr = recv(fd_in, inbuf, 9000, 0);
			if (-1 == nr && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
				BEGIN_CRITICAL(&cl, "read-buffer");
					a12int_trace(A12_TRACE_SYSTEM, "failed to read from input: %d", errno);
				END_CRITICAL(&cl);
				break;
			}
/* we are not really interested in the 'half-open' scenario as the session is
 * interactive by defintion, so it is reasonably safe to just break here and
 * close the synchronization pipe */
			else if (0 == nr){
				BEGIN_CRITICAL(&cl, "read-buffer");
					a12int_trace(A12_TRACE_SYSTEM, "other side closed the connection");
				END_CRITICAL(&cl);
				break;
			}

			BEGIN_CRITICAL(&cl, "unpack-buffer");
				a12int_trace(A12_TRACE_BTRANSFER, "unpack %zd bytes", nr);
				a12_unpack(S, inbuf, nr, NULL, on_cl_event);
			END_CRITICAL(&cl);
		}

/* refill outgoing buffer if there is something left, better heuristics can be
 * applied here and set A12_FLUSH_CHONLY or NOBLOB depending on channel state */
		if (!outbuf_sz){
			BEGIN_CRITICAL(&cl, "step-buffer");
				outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);
			END_CRITICAL(&cl);
		}

/* poll accordingly */
		n_fd = outbuf_sz > 0 ? 3 : 2;
	}

/* things died before authenticating, drop the context */
	if (S->on_auth){
		arcan_shmif_drop(&cont);
	}

/* just spin until the rest understand, would look better as a join loop with
 * the chid- being read from the ipc pipe */
	close(pipe_pair[0]);
	while(atomic_load(&cl.n_segments) > 0){}

	if (!a12_free(S)){
		a12int_trace(A12_TRACE_ALLOC, "error cleaning up a12 context");
	}

	return 0;
}
