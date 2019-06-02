#include <arcan_shmif.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <stdatomic.h>
#include <pthread.h>

#include "a12_int.h"
#include "a12.h"
#include "a12_helper.h"

struct shmifsrv_thread_data {
	struct shmifsrv_client* C;
	struct a12_state* S;
	int kill_fd;
	uint8_t chid;
};

/* [THREADING]
 * We use a giant lock (a12 not liking multiple- call into via threading, mostly
 * due to the buffer function and the channel- state tracker, not impossible just
 * easier to solve like this).
 *
 * The buffer-out is simply a way for the main feed thread to forward the current
 * pending buffer output
 */
static bool spawn_thread(
struct a12_state* S, struct shmifsrv_client* C, uint8_t chid, int kill_fd);
static pthread_mutex_t giant_lock = PTHREAD_MUTEX_INITIALIZER;
static const char* last_lock;
_Atomic volatile size_t buffer_out = 0;

#define BEGIN_CRITICAL(X, Y) do{pthread_mutex_lock(X); last_lock = Y;} while(0);
#define END_CRITICAL(X) do{pthread_mutex_unlock(X);} while(0);

/*
 * Figure out encoding parameters based on client type and buffer parameters.
 * This is the first heurstic catch-all to later feed in backpressure,
 * bandwidth and load estimation parameters.
 */
static struct a12_vframe_opts vopts_from_segment(
	struct shmifsrv_client* C, struct shmifsrv_vbuffer vb)
{
	switch (shmifsrv_client_type(C)){
	case SEGID_LWA:
		a12int_trace(A12_TRACE_VIDEO, "lwa -> h264, balanced");
		return (struct a12_vframe_opts){
			.method = VFRAME_METHOD_H264,
			.bias = VFRAME_BIAS_BALANCED
		};
	case SEGID_GAME:
		a12int_trace(A12_TRACE_VIDEO, "game -> h264, latency");
		return (struct a12_vframe_opts){
			.method = VFRAME_METHOD_H264,
			.bias = VFRAME_BIAS_LATENCY
		};
	break;
	case SEGID_MEDIA:
		a12int_trace(A12_TRACE_VIDEO, "game -> h264, quality");
		return (struct a12_vframe_opts){
			.method = VFRAME_METHOD_H264,
			.bias = VFRAME_BIAS_QUALITY
		};
	break;
	case SEGID_CURSOR:
		a12int_trace(A12_TRACE_VIDEO, "cursor -> normal (raw/png/...)");
		return (struct a12_vframe_opts){
			.method = VFRAME_METHOD_NORMAL
		};
	break;
	case SEGID_REMOTING:
	case SEGID_VM:
	default:
		a12int_trace(A12_TRACE_VIDEO,
			"default (%d) -> dpng", shmifsrv_client_type(C));
		return (struct a12_vframe_opts){
			.method = VFRAME_METHOD_DPNG
		};
	break;
	}
}

/*
 * [THREADING]
 * Called from within a _lock / _unlock block
 */
static void on_srv_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct a12_state* S = tag;
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM, "serv-event without context on channel");
		return;
	}
	struct shmifsrv_client* srv_cl = (struct shmifsrv_client*) cont->user;

	a12int_trace(A12_TRACE_EVENT,
		"client event: %s on ch %d", arcan_shmif_eventstr(ev, NULL, 0), chid);

	if (ev->category != EVENT_TARGET || ev->tgt.kind != TARGET_COMMAND_NEWSEGMENT){
		shmifsrv_enqueue_event(srv_cl, ev, -1);
		return;
	}

/* we use a 'not so nice' hack here and decode the new segment dimensions
 * from redefintion of the NEWSEGMENT event where also provide w / h */
	struct shmifsrv_client* cl = shmifsrv_send_subsegment(
		srv_cl, ev->tgt.ioevs[2].iv, 32, 32, chid, ev->tgt.ioevs[3].uiv);

/* tear-down the channel on the other side, fail to allocate */
	if (!cl){
		a12_set_channel(S, chid);
		a12_channel_close(S);
		return;
	}

}

static void on_audio_cb(shmif_asample* buf,
	size_t n_samples,  unsigned channels, unsigned rate, void* tag)
{
	struct a12_state* S = tag;
	a12_channel_aframe(S, buf, n_samples,
		(struct a12_aframe_cfg){
			.channels = channels,
			.samplerate = rate
		},
		(struct a12_aframe_opts){
			.method = AFRAME_METHOD_RAW
		}
	);
}

static void* client_thread(void* inarg)
{
	struct shmifsrv_thread_data* data = inarg;
	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	struct pollfd pfd = {
		.fd = shmifsrv_client_handle(data->C), .events = POLLIN | errmask
	};

/* the ext-io thread might be sleeping waiting for input, when we finished
 * one pass/burst and know there is queued data to be sent, wake it up */
	bool dirty = false;
	for(;;){
		if (dirty){
			write(data->kill_fd, &data->chid, 1);
			dirty = false;
		}

		if (-1 == poll(&pfd, 1, 4)){
			if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
				break;
		}

		if (pfd.revents & errmask){
			break;
		}

		struct arcan_event ev;

		while (shmifsrv_dequeue_events(data->C, &ev, 1)){
			if (arcan_shmif_descrevent(&ev)){
				a12int_trace(A12_TRACE_MISSING, "ignoring descriptor passing event");
				continue;
			}

/* server-consumed or should be forwarded? */
			BEGIN_CRITICAL(&giant_lock, "client_event");
				if (shmifsrv_process_event(data->C, &ev)){
					a12int_trace(A12_TRACE_EVENT,
						"consumed: %s", arcan_shmif_eventstr(&ev, NULL, 0));
				}
				else {
					a12int_trace(A12_TRACE_EVENT,
						"forward: %s", arcan_shmif_eventstr(&ev, NULL, 0));
					a12_set_channel(data->S, data->chid);
					a12_channel_enqueue(data->S, &ev);
					dirty = true;
				}
			END_CRITICAL(&giant_lock);
		}

		int pv;
		while ((pv = shmifsrv_poll(data->C)) != CLIENT_NOT_READY){
/* Dead client, send the close message and that should cascade down the rest
 * and kill relevant sockets. */
			if (pv == CLIENT_DEAD){
				BEGIN_CRITICAL(&giant_lock, "client_death");
					a12_set_channel(data->S, data->chid);
					a12_channel_close(data->S);
					write(data->kill_fd, &data->chid, 1);
					a12int_trace(A12_TRACE_SYSTEM, "client died");
				END_CRITICAL(&giant_lock);
				goto out;
			}

/* the shared buffer_out marks if we should wait a bit before releasing the
 * client as to not keep oversaturating with incoming video frames, we could
 * threshold this to something more reasonable, or better yet, track the
 * trending curve and time-delay and use that to adjust the encoding parameters */
			if (pv & CLIENT_VBUFFER_READY){
				if (atomic_load(&buffer_out) > 0){
					break;
				}

/* two option, one is to map the dma-buf ourselves and do the readback, or with
 * streams map the stream and convert to h264 on gpu, but easiest now is to
 * just reject and let the caller do the readback. this is currently done by
 * default in shmifsrv.*/
				a12int_trace(A12_TRACE_VDETAIL, "video-buffer");
				struct shmifsrv_vbuffer vb = shmifsrv_video(data->C);
				BEGIN_CRITICAL(&giant_lock, "video-buffer");
					a12_channel_vframe(data->S, &vb, vopts_from_segment(data->C, vb));
					dirty = true;
				END_CRITICAL(&giant_lock);

/* the other part is to, after a certain while of VBUFFER_READY but not any
 * buffer- out space, track if any of our segments have focus, if so, inject it
 * anyhow (should help responsiveness), increase video compression time-
 * tradeoff and defer the step stage so the client gets that we are limited */
				shmifsrv_video_step(data->C);
			}

/* send audio anyway, as not all clients are providing audio and there is less
 * tricks that can be applied from the backpressured client, dynamic resampling
 * and heavier compression is an option here as well though */
			if (pv & CLIENT_ABUFFER_READY){
				a12int_trace(A12_TRACE_AUDIO, "audio-buffer");
				BEGIN_CRITICAL(&giant_lock, "audio_buffer");
					shmifsrv_audio(data->C, on_audio_cb, data->S);
					dirty = true;
				END_CRITICAL(&giant_lock);
			}
		}

	}

out:
/* only shut-down everything on the primary- segment failure */
	if (data->chid == 0 && data->kill_fd != -1)
		close(data->kill_fd);

	free(inarg);
	return NULL;
}

static bool spawn_thread(
	struct a12_state* S, struct shmifsrv_client* C, uint8_t chid, int kill_fd)
{
	struct shmifsrv_thread_data* data = malloc(sizeof(struct shmifsrv_thread_data));
	if (!data){
		a12int_trace(A12_TRACE_ALLOC, "could not setup thread data");
		return false;
	}

	*data = (struct shmifsrv_thread_data){
		.C = C,
		.S = S,
		.kill_fd = kill_fd,
		.chid = chid
	};

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

	if (-1 == pthread_create(&pth, &pthattr, client_thread, data)){
		a12int_trace(A12_TRACE_ALLOC, "could not spawn thread");
		free(data);
		return false;
	}

	return true;
}

void a12helper_a12cl_shmifsrv(struct a12_state* S,
	struct shmifsrv_client* C, int fd_in, int fd_out, struct a12helper_opts opts)
{
	uint8_t* outbuf;
	size_t outbuf_sz = 0;

/* tie an empty context as channel destination, we use this as a type- wrapper
 * for the shmifsrv_client now, this logic is slightly different on the
 * shmifsrv_client side. */
	struct arcan_shmif_cont fake = {
		.user = C
	};
	a12_set_destination(S, &fake, 0);

	int pipe_pair[2];
	if (-1 == pipe(pipe_pair))
		return;

/*
 * Spawn the processing- thread that will take care of a shmifsrv_client
 */
	if (!spawn_thread(S, C, 0, pipe_pair[1]))
		return;

/*
 * Socket in/out liveness, buffer flush / dispatch
 */
	size_t n_fd = 2;
	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[3] = {
		{	.fd = fd_in, .events = POLLIN | errmask},
		{ .fd = pipe_pair[0], .events = POLLIN | errmask},
		{ .fd = fd_out, .events = POLLOUT | errmask}
	};

	uint8_t inbuf[9000];
	while(-1 != poll(fds, n_fd, -1)){

/* death by poll? */
		if ((fds[0].revents & errmask) ||
				(fds[1].revents & errmask) ||
				(n_fd == 3 && (fds[2].revents & errmask))){
			break;
		}

/* flush wakeup data from threads */
		if (fds[1].revents){
			if (a12_trace_targets & A12_TRACE_TRANSFER){
				BEGIN_CRITICAL(&giant_lock, "flush-iopipe");
					a12int_trace(
						A12_TRACE_TRANSFER, "client thread wakeup");
				END_CRITICAL(&giant_lock);
			}

			read(fds[1].fd, inbuf, 9000);
		}

/* pending out, flush or grab next out buffer */
		if (n_fd == 3 && (fds[2].revents & POLLOUT) && outbuf_sz){
			ssize_t nw = write(fd_out, outbuf, outbuf_sz);

			if (a12_trace_targets & A12_TRACE_TRANSFER){
				BEGIN_CRITICAL(&giant_lock, "buffer-send");
				a12int_trace(
					A12_TRACE_TRANSFER, "send %zd (left %zu) bytes", nw, outbuf_sz);
				END_CRITICAL(&giant_lock);
			}

			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}
		}

/* then read and unpack incoming data, note that in the on_srv_event handler
 * we ALREADY HOLD THE LOCK so it is a deadlock condition to try and lock there */
		if (fds[0].revents & POLLIN){
			ssize_t nr = recv(fd_in, inbuf, 9000, 0);
			if (-1 == nr && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
				if (a12_trace_targets & A12_TRACE_SYSTEM){
					BEGIN_CRITICAL(&giant_lock, "data error");
						a12int_trace(A12_TRACE_SYSTEM, "data-in, error: %s", strerror(errno));
					END_CRITICAL(&giant_lock);
				}
				break;
			}
	/* pollin- says yes, but recv says no? */
			if (nr == 0){
				BEGIN_CRITICAL(&giant_lock, "socket closed");
				a12int_trace(A12_TRACE_SYSTEM, "data-in, other side closed connection");
				END_CRITICAL(&giant_lock);
				break;
			}

			BEGIN_CRITICAL(&giant_lock, "unpack-event");
				a12int_trace(A12_TRACE_TRANSFER, "unpack %zd bytes", nr);
				a12_unpack(S, inbuf, nr, S, on_srv_event);
			END_CRITICAL(&giant_lock);
		}

		if (!outbuf_sz){
			BEGIN_CRITICAL(&giant_lock, "get-buffer");
				outbuf_sz = a12_flush(S, &outbuf);
			END_CRITICAL(&giant_lock);
		}
		n_fd = outbuf_sz > 0 ? 3 : 2;
	}

#ifdef DUMP_IN
	fclose(fpek_in);
#endif
	a12int_trace(A12_TRACE_SYSTEM, "(srv) shutting down connection");
}
