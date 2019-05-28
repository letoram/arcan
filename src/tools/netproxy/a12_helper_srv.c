#include <arcan_shmif.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>

#include "a12_int.h"
#include "a12.h"
#include "a12_helper.h"

static const short c_inev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
static const short c_outev = POLLOUT | POLLERR | POLLNVAL | POLLHUP;

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

int a12helper_poll_triple(int fd_shmif, int fd_in, int fd_out, int timeout)
{
/* 1. setup a12 in connect mode, _open */
	struct pollfd fds[3] = {
		{ .fd = fd_shmif, .events = c_inev },
		{	.fd = fd_in, .events = c_inev },
		{ .fd = fd_out, .events = c_outev }
	};
	size_t n_fds = 3;

/* only poll or out if we have something to write */
	if (fd_out == -1)
		n_fds = 2;

/* posix 'should' allow the same descriptor used multiple times, but the
 * support seems to be somewhat varying */
	if (fd_in == fd_out){
		n_fds = 2;
		fds[1].events |= c_outev;
	}

	int sv = poll(fds, n_fds, timeout);
	if (sv < 0){
		if (sv == -1 && errno != EAGAIN && errno != EINTR){
			a12int_trace(A12_TRACE_SYSTEM, "poll failure: %s", strerror(errno));
			return -1;
		}
	}

	if (fds[0].revents & (POLLERR | POLLNVAL | POLLHUP)){
		a12int_trace(A12_TRACE_SYSTEM, "shmif descriptor died");
		return -1;
	}

	if (fds[1].revents & (POLLERR | POLLNVAL | POLLHUP)){
		a12int_trace(A12_TRACE_SYSTEM, "incoming descriptor died");
		return -1;
	}

	if (fd_out != -1 && fd_in != fd_out &&
		(fds[2].revents & (POLLERR | POLLNVAL | POLLHUP))){
		a12int_trace(A12_TRACE_SYSTEM, "outgoing descriptor died");
		return -1;
	}

	int res = 0;
	if (fds[0].revents & POLLIN)
		res |= A12HELPER_POLL_SHMIF;

	if (fds[1].revents & POLLIN)
		res |= A12HELPER_DATA_IN;

	if (fd_in == fd_out && (fds[1].revents & POLLOUT))
		res |= A12HELPER_WRITE_OUT;
	else if (fd_out != -1 && (fds[2].revents & POLLOUT))
		res |= A12HELPER_WRITE_OUT;

	return res;
}

static void on_srv_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct shmifsrv_client* cs = tag;
	a12int_trace(A12_TRACE_EVENT,
		"client event: %s on ch %d", arcan_shmif_eventstr(ev, NULL, 0), chid);

/*
	if (!cont){
		a12int_trace(A12_TRACE_MISSING, "spawn new subsegment, map to %d", chid);
		return;
	}
 */

/* note, this needs to be able to buffer etc. to handle a client that has
 * a saturated event queue ... */
	shmifsrv_enqueue_event(cs, ev, -1);
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

void a12helper_a12cl_shmifsrv(struct a12_state* S,
	struct shmifsrv_client* C, int fd_in, int fd_out, struct a12helper_opts opts)
{

	uint8_t* outbuf;
	size_t outbuf_sz = 0;
	int status;

/* missing: this doesn't actually invoke timer ticks etc. */

	while (-1 != (status = a12helper_poll_triple(
		shmifsrv_client_handle(C), fd_in, outbuf_sz ? fd_out : -1, 4))){

/* first, flush current outgoing and/or swap buffers */
		if (status & A12HELPER_WRITE_OUT){
			if (outbuf_sz || (outbuf_sz = a12_flush(S, &outbuf))){
				ssize_t nw = write(fd_out, outbuf, outbuf_sz);
				a12int_trace(
					A12_TRACE_TRANSFER, "send %zd (left %zu) bytes", nw, outbuf_sz);

				if (nw > 0){
					outbuf += nw;
					outbuf_sz -= nw;
				}
			}
		}

/* then read and unpack incoming data */
		if (status & A12HELPER_DATA_IN){
			uint8_t inbuf[9000];
			ssize_t nr = read(fd_in, inbuf, 9000);
			if (-1 == nr && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
				a12int_trace(A12_TRACE_SYSTEM, "data-in, error: %s", strerror(errno));
				break;
			}

			a12int_trace(A12_TRACE_TRANSFER, "unpack %zd bytes", nr);
			a12_unpack(S, inbuf, nr, C, on_srv_event);
		}

/* always poll shmif- when we are here */
		struct arcan_event ev;
		while (shmifsrv_dequeue_events(C, &ev, 1)){
			if (arcan_shmif_descrevent(&ev)){
				a12int_trace(A12_TRACE_MISSING, "ignoring descriptor passing event");
			}
			else if (!shmifsrv_process_event(C, &ev)){
				a12int_trace(A12_TRACE_EVENT,
					"forward: %s", arcan_shmif_eventstr(&ev, NULL, 0));
				a12_channel_enqueue(S, &ev);
			}
			else
				a12int_trace(A12_TRACE_EVENT,
					"consumed: %s", arcan_shmif_eventstr(&ev, NULL, 0));
		}

		int pv;
		while ((pv = shmifsrv_poll(C)) != CLIENT_NOT_READY){
			if (pv == CLIENT_DEAD){
/* FIXME: shmif-client died, send disconnect packages so we do this cleanly */
				a12int_trace(A12_TRACE_SYSTEM, "client died");
				goto out;
			}

/* This one is subtle! we actually defer the frame release until anything pending
 * has been flushed. This is not the right solution when there is big items from
 * state and so on in flight. The real mechanism here could/should be able to
 * take type into account and balance queue and encoding parameters based on net-
 * load */
			if (pv & CLIENT_VBUFFER_READY){
				if (outbuf_sz){
					a12int_trace(A12_TRACE_VDETAIL,
						"video-buffer, but %zu bytes pending\n", outbuf_sz);
					break;
				}

/* two option, one is to map the dma-buf ourselves and do the readback, or with
 * streams map the stream and convert to h264 on gpu, but easiest now is to
 * just reject and let the caller do the readback. this is currently done by
 * default in shmifsrv.*/
				a12int_trace(A12_TRACE_VDETAIL, "video-buffer");
				struct shmifsrv_vbuffer vb = shmifsrv_video(C);
				a12_channel_vframe(S, &vb, vopts_from_segment(C, vb));
				shmifsrv_video_step(C);
			}

/* the previous mentioned problem also means that audio can saturate video
 * processing, both need to go through the same conductor- kind of analysis */
			if (pv & CLIENT_ABUFFER_READY){
				a12int_trace(A12_TRACE_AUDIO, "audio-buffer");
				shmifsrv_audio(C, on_audio_cb, S);
			}
		}

/* recheck for an output- buffer */
		if (!outbuf_sz){
			outbuf_sz = a12_flush(S, &outbuf);
			if (outbuf_sz)
				a12int_trace(A12_TRACE_TRANSFER, "pass over, got: %zu left", outbuf_sz);
		}
	}

out:
#ifdef DUMP_IN
	fclose(fpek_in);
#endif
	a12int_trace(A12_TRACE_SYSTEM, "(srv) shutting down connection");
}
