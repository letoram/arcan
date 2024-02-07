/*
 * Copyright: 2018-2020, Bjorn Stahl
 * License: 3-Clause BSD
 * Description: Implements a support wrapper for the a12 function patterns used
 * to implement multiple incoming a12 clients and map to one local connection point.
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
#include <stdatomic.h>
#include <pthread.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"
#include "arcan_mem.h"

struct shmifsrv_thread_data {
	struct shmifsrv_client* C;
	struct a12_state* S;
	struct arcan_shmif_cont fake;
	struct a12helper_opts opts;

	float font_sz;
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
 *
*/
static bool spawn_thread(struct shmifsrv_thread_data* inarg);
static pthread_mutex_t giant_lock = PTHREAD_MUTEX_INITIALIZER;

static const char* last_lock;
static _Atomic volatile size_t buffer_out = 0;
static _Atomic volatile uint8_t n_segments;

#define BEGIN_CRITICAL(X, Y) do{pthread_mutex_lock(X); last_lock = Y;} while(0);
#define END_CRITICAL(X) do{pthread_mutex_unlock(X);} while(0);

/*
 * Figure out encoding parameters based on client type and buffer parameters.
 * This is the first heurstic catch-all to later feed in backpressure,
 * bandwidth and load estimation parameters.
 */
static struct a12_vframe_opts vopts_from_segment(
	struct shmifsrv_thread_data* data, struct shmifsrv_vbuffer vb)
{
/* force tpack regardless, tpack doesn't have tuning like this */
	if (vb.flags.tpack){
		a12int_trace(A12_TRACE_VIDEO, "tpack segment");
		return (struct a12_vframe_opts){
			.method = VFRAME_METHOD_TPACK_ZSTD
		};
	}

/* outsource eval */
	if (data->opts.eval_vcodec){
		return data->opts.eval_vcodec(data->S,
			shmifsrv_client_type(data->C), &vb, data->opts.tag);
	}

	return (struct a12_vframe_opts){
		.method = VFRAME_METHOD_DZSTD,
			.bias = VFRAME_BIAS_BALANCED
	};
}

extern uint8_t* arcan_base64_encode(
	const uint8_t* data, size_t inl, size_t* outl, enum arcan_memhint hint);

/*
 * the bhandler -related calls are already running inside critical as
 * they come from the data parsing itself.
 */
static void dispatch_bdata(
	struct a12_state* S, int fd, int type, struct shmifsrv_thread_data* D)
{
	struct shmifsrv_client* srv_cl = D->C;
	switch(type){
	case A12_BTYPE_STATE:
		shmifsrv_enqueue_event(srv_cl, &(struct arcan_event){
			.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_RESTORE}, fd);
	break;
/* There is a difference to the local case here in that the event which carries
 * the desired size etc. will be sent in advance, thus there will be two times
 * the number of FONTHINTS, which can result in glitches. This may cost an
 * update / redraw, but allows blocking font transfers and still maintaing the
 * right size. */
	case A12_BTYPE_FONT:
		shmifsrv_enqueue_event(srv_cl, &(struct arcan_event){
			.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_FONTHINT,
			.tgt.ioevs[1].iv = 1, .tgt.ioevs[2].fv = D->font_sz, .tgt.ioevs[3].iv = -1},
		fd);
	break;
/* the [4].iv here is an indication that the font should be appended to the
 * set used and defined by the first */
	case A12_BTYPE_FONT_SUPPL:
		shmifsrv_enqueue_event(srv_cl, &(struct arcan_event){
			.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_FONTHINT,
			.tgt.ioevs[1].iv = 1, .tgt.ioevs[2].fv = D->font_sz, .tgt.ioevs[3].iv = -1,
			.tgt.ioevs[4].iv = 1}, fd
		);
	break;
/* Another subtle difference similar to the fonthint detail is that the blob
 * here actually lacks the identifier string, even if it was set previously.
 * If that turns out to be an issue (the requirement is that client should not
 * care/trust the identifier regardless, as it is mainly used as a UI hint and
 * whatever parser should be tolerant or indicative of how it didn't understand
 * the data. Should this be too much of an issue, the transfer- token system
 * could be used to pair the event */
	case A12_BTYPE_BLOB:
		shmifsrv_enqueue_event(srv_cl, &(struct arcan_event){
				.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_BCHUNK_IN}, fd);
	break;
	default:
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:status=EBADTYPE:message=%d", type);
	break;
	}

	close(fd);
}

static struct a12_bhandler_res incoming_bhandler(
	struct a12_state* S, struct a12_bhandler_meta md, void* tag)
{
	struct a12helper_opts* opts = tag;
	struct a12_bhandler_res res = {
		.fd = -1,
		.flag = A12_BHANDLER_DONTWANT
	};

/* early out case - on completed / on cancelled, the descriptor either
 * comes from the temp or the cache so no unlink is needed, just fwd+close */
	if (md.fd != -1){

/* these events cover only one direction, the other (_OUT, _STORE, ...)
 * requires this side to be proactive when receiving the event, forward the
 * empty output descriptor and use the bstream-queue command combined with
 * flock- excl/nonblock to figure out when done. */
		if (md.dcont && md.dcont->user &&
			!md.streaming && md.state != A12_BHANDLER_CANCELLED){
			a12int_trace(A12_TRACE_BTRANSFER,
				"kind=accept:ch=%d:stream=%"PRIu64, md.channel, md.streamid);
			dispatch_bdata(S, md.fd, md.type, md.dcont->user);
		}
/* already been dispatched as a pipe */
		else
			close(md.fd);

		return res;
	}

	bool got_checksum = false;
/* But that requires a checksum */
	for (size_t i = 0; i < 16; i++){
		if (md.checksum[i] != 0){
			got_checksum = true;
			break;
		}
	}

/* If a cache dir is provided, check against that first -
 * just do this on fonts for the time being */
	if (got_checksum && opts->bcache_dir != -1 &&
		(md.type == A12_BTYPE_FONT || md.type == A12_BTYPE_FONT_SUPPL)){
/* We got one, convert to b64 and try to open */
		size_t len;
		char* fname = (char*) arcan_base64_encode(md.checksum, 16, &len, 0);
		res.fd = openat(opts->bcache_dir, fname, O_RDONLY);

/* If it was truncated (failure on first transfer), re-attempt as new,
 * otherwise return the font as cached so the stream gets cancelled */
		if (-1 != res.fd){
			struct stat fsinf;
			if (-1 == fstat(res.fd, &fsinf) || 0 == fsinf.st_size){
				res.flag = A12_BHANDLER_NEWFD;
				a12int_trace(
					A12_TRACE_TRANSFER, "kind=font:cached=broken:create=%s", fname);
				dispatch_bdata(S, res.fd, md.type, md.dcont->user);
			}
			else{
				a12int_trace(A12_TRACE_TRANSFER, "kind=font:cached=true:name=%s", fname);
				res.flag = A12_BHANDLER_CACHED;
				dispatch_bdata(S, res.fd, md.type, md.dcont->user);
			}
			arcan_mem_free(fname);
			return res;
		}

/* otherwise, create the cache entry */
		res.fd = openat(opts->bcache_dir, fname, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
		if (-1 != res.fd){
			a12int_trace(A12_TRACE_TRANSFER, "kind=font:cached=false:create=%s", fname);
			res.flag = A12_BHANDLER_NEWFD;
			return res;
		}
		arcan_mem_free(fname);
	}

/* So the handler wants a descriptor for us to store or stream the transfer
 * into. If it is streaming, a pipe is sufficient and we can start the fwd
 * immediately. */
	if (md.streaming){
		int fd[2];
		if (-1 != pipe(fd)){
			res.flag = A12_BHANDLER_NEWFD;
			res.fd = fd[1];
			dispatch_bdata(S, res.fd, md.type, md.dcont->user);
		}
		return res;
	}

/*
 * Last case, real file with a known destination type and size. Since there is
 * a format requirement that the non-streaming type is seekable, we only have a
 * memfd- like approach if the temp-dir creation fails to work with ftruncate
 * being too large. With the glory that is overcommit and OMK, we might just
 * DGAF.
 */
/* INCOMPLETE:
 * we need a mkstemp that works with a dirfd as well and a mkdstemp for the
 * netproxy tool, so just abuse /tmp for the time being and then add them to
 * the src/platform/...
 */
	char pattern[] = {"/tmp/anetb_XXXXXX"};
	int fd = mkstemp(pattern);
	if (-1 == fd){
		a12int_trace(A12_TRACE_ALLOC, "source=btransfer:kind=eperm");
		return res;
	}

/* In patient wait for funlinkat, enjoy the race.. */
	unlink(pattern);

/* Note: the size field comes across a privilege barrier and can be > very <
 * large, possible allow an option to set an upper cap and reject single
 * transfers over a certain limit */
	if (-1 == ftruncate(fd, md.known_size)){
		a12int_trace(A12_TRACE_ALLOC, "source=btransfer:kind=enospace");
		close(fd);
	}
	else {
		res.fd = fd;
		res.flag = A12_BHANDLER_NEWFD;
	}

	return res;
}

static void setup_descriptor_store(struct shmifsrv_thread_data* data,
	struct shmifsrv_client* cl, struct arcan_event* ev)
{
	a12int_trace(A12_TRACE_MISSING, "descriptor_store_setup");
}

static void redirect_exit(
	struct shmifsrv_client* C, int level, const char* path)
{
	if (!path)
		return;

	struct arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_DEVICE_NODE,
		.tgt.ioevs[0].iv = -1,
		.tgt.ioevs[1].iv = level,
/* this will ignore the GUID setting */
		};

	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", path);
	shmifsrv_enqueue_event(C, &ev, -1);
	a12int_trace(A12_TRACE_EVENT, "kind=redirect:destination=%s", path);
}

/*
 * [THREADING]
 * Called from within a _lock / _unlock block
 */
static void on_srv_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct shmifsrv_thread_data* data = tag;
	if (!cont){
		a12int_trace(A12_TRACE_SYSTEM, "kind=error:type=EINVALCH:val=%d", chid);
		return;
	}
	struct shmifsrv_client* srv_cl = data->C;

/*
 * cache this so we can re-inject on font hints where there is a descriptor as
 * that is delivered as a sideband via btransfer
 */
	if (ev->category == EVENT_TARGET && ev->tgt.kind == TARGET_COMMAND_FONTHINT){
		data->font_sz = ev->tgt.ioevs[2].fv;
		ev->tgt.ioevs[1].iv = 0;
		ev->tgt.ioevs[0].iv = -1;

/* mask continuation entirely */
		if (ev->tgt.ioevs[4].iv)
			return;
	}

/*
 * when activated (and we have another possible known connection point)
 * set that as the client fallback, so that we can do both explicit
 * migration and crash recovery
 */
	if (data->opts.devicehint_cp && chid == 0 &&
		ev->category == EVENT_TARGET && ev->tgt.kind == TARGET_COMMAND_ACTIVATE){
		a12int_trace(A12_TRACE_EVENT,
			"kind=activate:fallback_to:%s", data->opts.devicehint_cp);
		struct arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_DEVICE_NODE,
			.tgt.ioevs[0].iv = -1,
			.tgt.ioevs[1].iv = 4 /* fallback */
		};

		snprintf(ev.tgt.message,
			COUNT_OF(ev.tgt.message), "%s", data->opts.devicehint_cp);
		shmifsrv_enqueue_event(srv_cl, &ev, -1);
	}

	a12int_trace(A12_TRACE_EVENT,
		"kind=forward:chid=%d:eventstr=%s", chid, arcan_shmif_eventstr(ev, NULL, 0));

/*
 * Some events are valuable to intercept and tweak:
 *
 * EXIT - unconditional termination is problematic, if we have a local connection-
 * point defined already, it is better to send the window there for the primary
 * segment.
 *
 * The thing is, we can't guarantee that the EXIT event will arrive if the
 * channel is forcibly closed etc. so it also needs to be accounted for later
 */
 	if (data->opts.redirect_exit && chid == 0 &&
		ev->category == EVENT_TARGET && ev->tgt.kind == TARGET_COMMAND_EXIT){
		redirect_exit(srv_cl, 2, data->opts.redirect_exit);
		return;
	}

/*
 * NEWEVENT - necessary, need to map to new channels.
 */
	if (ev->category != EVENT_TARGET || ev->tgt.kind != TARGET_COMMAND_NEWSEGMENT){
		if (!srv_cl){
			a12int_trace(A12_TRACE_SYSTEM, "kind=error:type=EINVAL:val=%d", chid);
		}
		else{
/* The descriptor events are more complicated as they can be either incoming or
 * outgoing. When we talk _STORE or BCHUNK_OUT events arriving here, they won't
 * actually have a descriptor with them, we need to create the temp. resource,
 * add the descriptor and then a12_enqueue_bstream accordingly. In addition,
 * we actually need to pair the token that was added in the descriptor slot so
 * the other side know where to dump it into */
			if (arcan_shmif_descrevent(ev)){
				if (ev->tgt.kind == TARGET_COMMAND_STORE ||
					ev->tgt.kind == TARGET_COMMAND_BCHUNK_OUT){
					a12int_trace(A12_TRACE_BTRANSFER, "kind=status:message=outgoing_bchunk");
					setup_descriptor_store(data, srv_cl, ev);
				}
				else
					shmifsrv_enqueue_event(srv_cl, ev, ev->tgt.ioevs[0].iv);
			}
			else
				shmifsrv_enqueue_event(srv_cl, ev, -1);
		}
		return;
	}

/* First we need a copy of the current processing thread structure */
	struct shmifsrv_thread_data* new_data =
		malloc(sizeof(struct shmifsrv_thread_data));
	if (!new_data){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:type=ENOMEM:src_ch=%d:dst_ch=%d", chid, ev->tgt.ioevs[0].iv);
		a12_set_channel(data->S, chid);
		a12_channel_close(data->S);
		return;
	}
	*new_data = *data;

/* Then we forward the subsegment to the local client */
	new_data->chid = ev->tgt.ioevs[0].iv;
	new_data->C = shmifsrv_send_subsegment(
		srv_cl, ev->tgt.ioevs[2].iv, 0, 32, 32, chid, ev->tgt.ioevs[3].uiv);

/* That can well fail (descriptors etc.) */
	if (!new_data->C){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:type=ENOSRVMEM:src_ch=%d:dst_ch=%d", chid, ev->tgt.ioevs[0].iv);
		free(new_data);
		a12_set_channel(data->S, chid);
		a12_channel_close(data->S);
	}

/* Attach to a new processing thread, and tie this channel to the 'fake'
 * segment that we only use to extract back the events and so on to for now,
 * when we deal with 'output' segments as well, this is where we'd need to do
 * the encoding dance */
	new_data->fake.user = new_data;
	a12_set_destination(data->S, &new_data->fake, new_data->chid);

	if (!spawn_thread(new_data)){
		a12int_trace(A12_TRACE_SYSTEM,
			"kind=error:type=ENOTHRDMEM:src_ch=%d:dst_ch=%d", chid, ev->tgt.ioevs[0].iv);
		free(new_data);
		a12_set_channel(data->S, chid);
		a12_channel_close(data->S);
		return;
	}

	a12int_trace(A12_TRACE_ALLOC,
		"kind=new_channel:src_ch=%d:dst_ch=%d", chid, (int)new_data->chid);
}

static void on_audio_cb(shmif_asample* buf,
	size_t n_samples,  unsigned channels, unsigned rate, void* tag)
{
	return;
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
	struct pollfd pfd[2] = {
		{ .fd = shmifsrv_client_handle(data->C, NULL), .events = POLLIN | errmask },
		{ .fd = data->kill_fd, errmask }
	};

/* enable encoded video passthrough */
	shmifsrv_client_protomask(data->C, SHMIF_META_VENC);

/* We don't have a monitorable trigger for inbound video/audio frames, so some
 * timeout is in order for the time being. It might be useful to add that kind
 * of signalling to shmif though */
	size_t poll_step = 4;

/* the ext-io thread might be sleeping waiting for input, when we finished
 * one pass/burst and know there is queued data to be sent, wake it up */
	bool dirty = false;
	redirect_exit(data->C, 4, data->opts.redirect_exit);

	for(;;){
		if (dirty){
			write(data->kill_fd, &data->chid, 1);
			dirty = false;
		}

		if (-1 == poll(pfd, 2, poll_step)){
			if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
				a12int_trace(A12_TRACE_SYSTEM,
					"kind=error:status=EPOLL:message=%s", strerror(errno));
				break;
			}
		}

/* kill socket or poll socket died */
		if ((pfd[0].revents & errmask) || (pfd[1].revents & errmask)){
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=error:status=EBADFD:client=%d:killsig=%d", pfd[0].revents, pfd[1].revents);
			break;
		}

		struct arcan_event ev;

		while (shmifsrv_dequeue_events(data->C, &ev, 1)){
			if (arcan_shmif_descrevent(&ev)){
				a12int_trace(A12_TRACE_SYSTEM,
					"kind=error:status=EINVAL:message=client->server descriptor event");
				continue;
			}

/* server-consumed or should be forwarded? */
			BEGIN_CRITICAL(&giant_lock, "client_event");
				if (shmifsrv_process_event(data->C, &ev)){
					a12int_trace(A12_TRACE_EVENT,
						"kind=consumed:channel=%d:eventstr=%s",
						data->chid, arcan_shmif_eventstr(&ev, NULL, 0)
					);
				}
				else {
					a12_set_channel(data->S, data->chid);
					a12int_trace(A12_TRACE_EVENT, "kind=forward:channel=%d:eventstr=%s",
						data->chid, arcan_shmif_eventstr(&ev, NULL, 0));
					a12_channel_enqueue(data->S, &ev);
					dirty = true;
				}
			END_CRITICAL(&giant_lock);
		}

		int pv;
		while (
			(pv = shmifsrv_poll(data->C)) !=
				CLIENT_NOT_READY && pv != CLIENT_IDLE){
/* Dead client, send the close message and that should cascade down the rest
 * and kill relevant sockets. */
			if (pv == CLIENT_DEAD){
				a12int_trace(A12_TRACE_EVENT, "client=dead");
				goto out;
			}

/* the shared buffer_out marks if we should wait a bit before releasing the
 * client as to not keep oversaturating with incoming video frames, we could
 * threshold this to something more reasonable, or just have two congestion
 * levels, one for focused channel and one lower for the rest */
			if (pv & CLIENT_VBUFFER_READY){
				if (atomic_load(&buffer_out) > 0){
					break;
				}

/* check the congestion window - there are many more options for congestion
 * control here, and the tuning is not figured out. One venue would be to
 * track which channel has a segment with focus, and prioritise those higher. */
				struct a12_iostat stat = a12_state_iostat(data->S);
				struct shmifsrv_vbuffer vb = shmifsrv_video(data->C);

				if (data->opts.vframe_block &&
					stat.vframe_backpressure >= data->opts.vframe_soft_block){

/* the soft block caps at ~20% of buffer difs for large buffers, the other
 * option is to have aggregation and dirty rectangles here, then invalidate if
 * they accumulate to cover all */
					size_t px_c = vb.w * vb.h;
					size_t reg_c =
						(vb.region.x2 - vb.region.x1) * (vb.region.y2 - vb.region.y1);
					bool allow_soft = vb.flags.subregion &&
						(reg_c < px_c) && ((float)reg_c / (float)px_c) <= 0.2;

					if (stat.vframe_backpressure >= data->opts.vframe_block && !allow_soft){
						a12int_trace(A12_TRACE_VDETAIL,
							"vbuffer=defer:congestion=%zu:soft=%zu:limit=%zu",
							stat.vframe_backpressure, data->opts.vframe_soft_block,
							data->opts.vframe_block
						);
						break;
					}
				}

/* two option, one is to map the dma-buf ourselves and do the readback, or with
 * streams map the stream and convert to h264 on gpu, but easiest now is to
 * just reject and let the caller do the readback. this is currently done by
 * default in shmifsrv.*/
				BEGIN_CRITICAL(&giant_lock, "video-buffer");
					a12_set_channel(data->S, data->chid);

/* vopts_from_segment here lets the caller pick compression parameters (coarse),
 * including the special 'defer this frame until later' */
					a12_channel_vframe(data->S, &vb, vopts_from_segment(data, vb));
					dirty = true;
				END_CRITICAL(&giant_lock);
				stat = a12_state_iostat(data->S);
				a12int_trace(A12_TRACE_VDETAIL,
					"vbuffer=release:time_ms=%zu:time_ms_px=%.4f:congestion=%zu",
					stat.ms_vframe, stat.ms_vframe_px,
					stat.vframe_backpressure
				);

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
					a12_set_channel(data->S, data->chid);
					shmifsrv_audio(data->C, on_audio_cb, data->S);
					dirty = true;
				END_CRITICAL(&giant_lock);
			}
		}

	}

out:
	BEGIN_CRITICAL(&giant_lock, "client_death");
		a12_set_channel(data->S, data->chid);
		a12_channel_close(data->S);
		write(data->kill_fd, &data->chid, 1);
		a12int_trace(A12_TRACE_SYSTEM, "client died");
	END_CRITICAL(&giant_lock);

/* only shut-down everything on the primary- segment failure */
	if (data->chid == 0 && data->kill_fd != -1)
		close(data->kill_fd);

/* don't kill the shmifsrv client session for the primary one */
	if (data->chid != 0){
		shmifsrv_free(data->C, SHMIFSRV_FREE_NO_DMS);
	}

	atomic_fetch_sub(&n_segments, 1);

	free(inarg);
	return NULL;
}

static bool spawn_thread(struct shmifsrv_thread_data* inarg)
{
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	atomic_fetch_add(&n_segments, 1);

	if (-1 == pthread_create(&pth, &pthattr, client_thread, inarg)){
		BEGIN_CRITICAL(&giant_lock, "cleanup-spawn");
			atomic_fetch_sub(&n_segments, 1);
			a12int_trace(A12_TRACE_ALLOC, "could not spawn thread");
			free(inarg);
		END_CRITICAL(&giant_lock);
		return false;
	}

	return true;
}

void a12helper_a12cl_shmifsrv(struct a12_state* S,
	struct shmifsrv_client* C, int fd_in, int fd_out, struct a12helper_opts opts)
{
	uint8_t* outbuf = NULL;
	size_t outbuf_sz = 0;

/* tie an empty context as channel destination, we use this as a type- wrapper
 * for the shmifsrv_client now, this logic is slightly different on the
 * shmifsrv_client side. */
	struct arcan_shmif_cont fake = {};
	a12_set_destination(S, &fake, 0);
	a12_set_bhandler(S, incoming_bhandler, &opts);

	int pipe_pair[2];
	if (-1 == pipe(pipe_pair))
		return;

/*
 * Spawn the processing- thread that will take care of a shmifsrv_client
 */
	struct shmifsrv_thread_data* arg;
	arg = malloc(sizeof(struct shmifsrv_thread_data));
	if (!arg){
		close(pipe_pair[0]);
		close(pipe_pair[1]);
		return;
	}

/*
 * the kill_fd will be shared among the other segments, so it is only
 * here where there is reason to clean it up like this
 */
	*arg = (struct shmifsrv_thread_data){
		.C = C,
		.S = S,
		.kill_fd = pipe_pair[1],
		.opts = opts,
		.chid = 0
	};
	if (!spawn_thread(arg)){
		close(pipe_pair[0]);
		close(pipe_pair[1]);
		return;
	}
	fake.user = arg;

/* Socket in/out liveness, buffer flush / dispatch */
	size_t n_fd = 2;
	static const short errmask = POLLERR | POLLNVAL | POLLHUP;
	struct pollfd fds[3] = {
		{	.fd = fd_in, .events = POLLIN | errmask},
		{ .fd = pipe_pair[0], .events = POLLIN | errmask},
		{ .fd = fd_out, .events = POLLOUT | errmask}
	};

/* flush authentication leftovers */
	a12_unpack(S, NULL, 0, arg, on_srv_event);

	uint8_t inbuf[9000];
	while(a12_ok(S) && -1 != poll(fds, n_fd, -1)){

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
				a12_unpack(S, inbuf, nr, arg, on_srv_event);
			END_CRITICAL(&giant_lock);
		}

		if (!outbuf_sz){
			BEGIN_CRITICAL(&giant_lock, "get-buffer");
				outbuf_sz = a12_flush(S, &outbuf, 0);
			END_CRITICAL(&giant_lock);
		}
		n_fd = outbuf_sz > 0 ? 3 : 2;
	}

	if (opts.bcache_dir > 0)
		close(opts.bcache_dir);

	a12int_trace(A12_TRACE_SYSTEM, "(srv) shutting down connection");
	close(pipe_pair[0]);
	while(atomic_load(&n_segments) > 0){}
	if (!a12_free(S)){
		a12int_trace(A12_TRACE_ALLOC, "error cleaning up a12 context");
	}

/* only the primary segment left, we will try and migrate that one,
 * sending the DEVICE_NODE migrate event and performing a non-dms drop */
	redirect_exit(C, 2, opts.redirect_exit);
}
