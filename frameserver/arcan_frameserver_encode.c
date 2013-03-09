#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>

#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>

#include <libavcodec/avcodec.h>
#include <libavcodec/version.h>
#include <libavutil/opt.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#undef BADFD
#define BADFD -1

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_encode.h"
#include "arcan_frameserver_encode_presets.h"

struct {
/* IPC */
	struct frameserver_shmcont shmcont;
	struct arcan_evctx inevq;
	struct arcan_evctx outevq; /* UNUSED */
	uint8_t* vidp, (* audp);   /* precalc dstptrs into shm */
	int lastfd;        /* sent from parent */

/* Multiplexing / Output */
	AVFormatContext* fcontext;
	AVPacket packet;
	AVFrame* pframe;

/* VIDEO */
	struct SwsContext* ccontext; /* color format conversion */
	AVCodecContext* vcontext;
	AVStream* vstream;
	AVCodec* vcodec;
	uint8_t* encvbuf;
	size_t encvbuf_sz;

/* Timing (shared) */
	long long lastframe;       /* monotonic clock time-stamp */
	unsigned long framecount;  /* number of frames treated, multiply with fps */
	float fps;

/* AUDIO */
/* containers and metadata */
	AVCodecContext* acontext;
	AVCodec* acodec;
	AVStream* astream;
	int channel_layout;
	
/* needed for intermediate buffering and format conversion */
	bool float_samples;

	uint8_t* encabuf;
	off_t encabuf_ofs;
	size_t encabuf_sz;

/* needed for encode_audio frame settings */
	int aframe_smplcnt;
	size_t aframe_sz;
	unsigned long aframe_ptscnt;

} recctx = {0};

/* flush the audio buffer present in the shared memory page as quick as possible,
 * resample if necessary, then use the intermediate buffer to feed encoder */
static void flush_audbuf()
{
	size_t ntc = recctx.shmcont.addr->abufused;
	
	if (ntc + recctx.encabuf_ofs > recctx.encabuf_sz){
		ntc = recctx.encabuf_sz - recctx.encabuf_ofs;
		LOG("(encode) audio buffer overflow, consider different encoding options.\n");
	}

	memcpy(&recctx.encabuf[recctx.encabuf_ofs], recctx.audp, ntc);
	recctx.encabuf_ofs += ntc;
}

static uint8_t* s16swrconv(uint8_t* inbuf, int* size)
{
	static struct SwrContext* resampler = NULL;
	static uint8_t** resamp_outbuf = NULL;
	
	if (!resampler){
		resampler = swr_alloc_set_opts(NULL, AV_CH_LAYOUT_STEREO, recctx.acontext->sample_fmt,
			recctx.acontext->sample_rate, AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_S16, SHMPAGE_SAMPLERATE, 0, NULL);

		resamp_outbuf = av_malloc(sizeof(uint8_t*) * SHMPAGE_ACHANNELCOUNT);
		av_samples_alloc(resamp_outbuf, NULL, SHMPAGE_ACHANNELCOUNT, recctx.aframe_smplcnt, recctx.acontext->sample_fmt, 0);
		
		if (swr_init(resampler) < 0 ){
			LOG("(encode) couldn't allocate resampler, giving up.\n");
			exit(1);
		}
	}

	const uint8_t* indata[] = {inbuf, NULL};
	int rc = swr_convert(resampler, resamp_outbuf, recctx.aframe_smplcnt, indata, recctx.aframe_smplcnt);
	if (rc < 0){
		LOG("(encode) couldn't resample, giving up.\n");
		exit(1);
	}
	
	*size = av_samples_get_buffer_size(NULL, SHMPAGE_ACHANNELCOUNT, rc, recctx.acontext->sample_fmt, 0);
	return resamp_outbuf[0];
}

static void encode_audio(bool flush)
{
	AVCodecContext* ctx = recctx.acontext;
	AVFrame* frame;
	bool forcetog = false;
	int numf, got_packet = false;
	off_t base = 0;

/* encode as many frames as possible from the intermediate buffer */
	while(base + recctx.aframe_sz <= recctx.encabuf_ofs){
		AVPacket pkt = {0};
		av_init_packet(&pkt);
		frame = avcodec_alloc_frame();

#if LIBAVCODEC_VERSION_MAJOR > 53
		frame->channel_layout = ctx->channel_layout;
#endif
		
		int buffer_sz;

forceencode:
/* convert to _FLT format before passing on */
		frame->nb_samples     = recctx.aframe_smplcnt;
		frame->pts            = recctx.aframe_ptscnt;
		recctx.aframe_ptscnt += recctx.aframe_smplcnt;

		uint8_t* ptr = s16swrconv(recctx.encabuf + base, &buffer_sz);

		base += recctx.aframe_sz >> 1;
	
		if ( avcodec_fill_audio_frame(frame, SHMPAGE_ACHANNELCOUNT, ctx->sample_fmt, ptr, buffer_sz, 0) < 0 ){
			LOG("(encode) couldn't fill target audio frame.\n");
			exit(1);
		}
		
		int rv = avcodec_encode_audio2(ctx, &pkt, frame, &got_packet);

		if (0 != rv && !flush){
			LOG("(encode) : encode_audio, couldn't encode, giving up.\n");
			exit(1);
		}

		if (got_packet){
			if (pkt.pts != AV_NOPTS_VALUE)
				pkt.pts = av_rescale_q(pkt.pts, ctx->time_base, recctx.astream->time_base);

			if (pkt.dts != AV_NOPTS_VALUE)
				pkt.dts = av_rescale_q(pkt.dts, ctx->time_base, recctx.astream->time_base);

			if (pkt.duration > 0)
				pkt.duration = av_rescale_q(pkt.duration, ctx->time_base, recctx.astream->time_base);

			pkt.stream_index = recctx.astream->index;
			
			if (0 != av_interleaved_write_frame(recctx.fcontext, &pkt) && !flush){
				LOG("(encode) : encode_audio, write_frame failed, giving up.\n");
				exit(1);
			}
		}

	}

/* for the flush case, we may have a little bit of buffer left,
 * CODEC_CAP_DELAY = pframe can be NULL and encode audio is used to flush
 * CODEC_CAP_SMALL_LAST_FRAME or CODEC_CAP_VARIABLE_FRAME_SIZE = we can the last few buffer bytes can be stored as well otherwise
 * those will be discarded */
	if (flush){
/* setup a partial new frame with as many samples as we can fit, change the expected "frame size" to match
 * and then re-use the encode / conversion code */
		if (!forcetog &&
			((ctx->flags & CODEC_CAP_SMALL_LAST_FRAME) > 0 || (ctx->flags & CODEC_CAP_VARIABLE_FRAME_SIZE) > 0)){
			recctx.aframe_sz = recctx.encabuf_ofs - base;
			frame = avcodec_alloc_frame();
#if LIBAVCODEC_VERSION_MAJOR > 53
			frame->channel_layout = ctx->channel_layout;
#endif

			forcetog = true;
			goto forceencode;
		}

		if ( (ctx->flags & CODEC_CAP_DELAY) > 0 ){
			int gotpkt;
			do {
				AVPacket flushpkt = {0};
				av_init_packet(&flushpkt);
				if (0 == avcodec_encode_audio2(ctx, &flushpkt, NULL, &gotpkt)){
					av_interleaved_write_frame(recctx.fcontext, &flushpkt);
				}
			} while (gotpkt);
		}

		return;
	}

/* slide the intermediate buffer offsets */
	if (base < recctx.encabuf_ofs)
		memmove(recctx.encabuf, (uint8_t*) (recctx.encabuf) + base, recctx.encabuf_ofs - base);

	recctx.encabuf_ofs -= base;
}

void encode_video(bool flush)
{
	uint8_t* srcpl[4] = {recctx.vidp, NULL, NULL, NULL};
	int srcstr[4] = {0, 0, 0, 0};
	srcstr[0] = recctx.vcontext->width * 4;

/* the main problem here is that the source material may encompass many framerates, in fact, even be variable (!)
 * the samplerate we're running with that is of interest. Thus compare the current time against the next expected time-slots,
 * if we're running behind, just repeat the last frame N times as to not get out of synch with possible audio. */
	double mspf = 1000.0 / recctx.fps;
	double thresh = mspf;
	long long encb    = arcan_timemillis(); 
	long long cft     = encb - recctx.lastframe; /* assumed >= 0 */
	long long nf      = round( mspf * (double)recctx.framecount );
	long long delta   = cft - nf;
	unsigned fc       = 1;

/* ahead by too much? just wait */
	if (delta < -thresh)
		return;

/* running behind, need to repeat a frame */
	if ( delta > thresh )
		fc += 1 + floor( delta / mspf);

/* notify parent so a decision can be made as if to reset and change encoding options */
	if (fc > 1){
		LOG("(encode) jitter: %lld, current time :%lld, ideal: %lld\n", delta, cft, nf);
		arcan_event ev = {.kind = EVENT_FRAMESERVER_DROPPEDFRAME, .category = EVENT_FRAMESERVER};
		arcan_event_enqueue(&recctx.outevq, &ev);
	}

	int rv = sws_scale(recctx.ccontext, (const uint8_t* const*) srcpl, srcstr, 0,
		recctx.vcontext->height, recctx.pframe->data, recctx.pframe->linesize);

/* might repeat the number of frames in order to compensate for poor frame sampling alignment */
	while (fc--){
		AVCodecContext* ctx = recctx.vcontext;
		AVPacket pkt = {0};
		int got_outp = false;
		recctx.framecount++;
	
		av_init_packet(&pkt);
		recctx.pframe->pts = recctx.framecount;

/* don't build / link to older versions */
#if LIBAVCODEC_VERSION_MAJOR < 53
		extern char* dated_ffmpeg_refused_old_build[-1];
#endif 

#if LIBAVCODEC_VERSION_MAJOR >= 54
		int rs = avcodec_encode_video2(recctx.vcontext, &pkt, flush ? NULL : recctx.pframe, &got_outp);

		if (rs < 0 && !flush) {
			LOG("(encode) -- encode_video failed, terminating.\n");
			exit(1);
		}

		if (got_outp){
			if (pkt.pts != AV_NOPTS_VALUE)
				pkt.pts = av_rescale_q(pkt.pts, ctx->time_base, recctx.vstream->time_base);

			if (pkt.dts != AV_NOPTS_VALUE)
				pkt.dts = av_rescale_q(pkt.dts, ctx->time_base, recctx.vstream->time_base);

			if (ctx->coded_frame->key_frame)
				pkt.flags |= AV_PKT_FLAG_KEY;

			if (pkt.dts > pkt.pts){
				LOG("(encode) dts > pts, clipping.\n");
				pkt.dts = pkt.pts - 1;
			}
			
			pkt.stream_index = recctx.vstream->index;

			if (av_interleaved_write_frame(recctx.fcontext, &pkt) != 0 && !flush){
				LOG("(encode) -- writing encoded video failed, terminating.\n");
				exit(1);
			}
		}
	}
/* deprecated API, forced to use with older version though. No note on how large outb is supposed to be (seriously) */
#else
		static uint8_t* outb  = NULL;
		static size_t outb_sz = 0;
		static long int dtsc = 0;
	
		if (!outb){
		outb_sz = avpicture_get_size(PIX_FMT_YUV420P, recctx.vcontext->width, recctx.vcontext->height);
		outb = malloc(outb_sz);
		if (!outb)
			exit(1);
		}

		int sz = avcodec_encode_video(recctx.vcontext, outb, outb_sz, flush ? NULL : recctx.pframe);

		if (sz >= 0){
			pkt.pts = recctx.framecount;

			if (ctx->coded_frame->pts != AV_NOPTS_VALUE)
				pkt.pts = av_rescale_q(ctx->coded_frame->pts, ctx->time_base, recctx.vstream->time_base);

/* don't want an onslaught of warnings here */
			static bool flagged = false;
			if (dtsc > pkt.dts && !flagged){
				LOG("(encode) -- improper PTS/DTS behavior, likely caused by an ffmpeg bug. Upgrade your libraries or try a different codec/container.\n");
				flagged = true;
			}
			else
				pkt.dts = pkt.pts;
			
			if (ctx->coded_frame->key_frame)
				pkt.flags |= AV_PKT_FLAG_KEY;

			pkt.stream_index = recctx.vstream->index;
			pkt.data = outb;
			pkt.size = sz;

			if (av_interleaved_write_frame(recctx.fcontext, &pkt) != 0 && !flush){
				LOG("(encode) -- writing encoded video failed, terminating.\n");
				exit(1);
			}
		}
	}
#endif 
}

void arcan_frameserver_stepframe(bool flush)
{
	flush_audbuf();
	recctx.shmcont.addr->abufused = 0;

/* just empty all buffers into the stream */
	if (flush){
		if (recctx.acontext)
			encode_audio(flush);

		encode_video(flush);
		return;
	}

/* calculate this first so we don't overstep audio/video interleaving */
	double vpts;
	if (recctx.vstream)
		vpts = recctx.vstream->pts.val * (float)recctx.vstream->time_base.num / (float)recctx.vstream->time_base.den;
	else
		vpts = 0.0;

/* interleave audio / video */
		while(recctx.astream && recctx.encabuf_ofs >= recctx.aframe_sz){
			double apts = recctx.astream->pts.val * (float)recctx.astream->time_base.num / (float)recctx.astream->time_base.den;

			if (apts < vpts || recctx.astream->pts.val == AV_NOPTS_VALUE){
				encode_audio(flush);
			}
			else
				break;
		}

	if (recctx.vstream)
		encode_video(flush);

/* acknowledge that a frame has been consumed, then return to polling events */
	arcan_sem_post(recctx.shmcont.vsem);
}

static void encoder_atexit()
{
	if (!recctx.fcontext)
		return;

	if (recctx.lastfd != BADFD){
		arcan_frameserver_stepframe(true);

		if (recctx.fcontext)
			av_write_trailer(recctx.fcontext);
	}
}

static bool setup_ffmpeg_encode(const char* resource)
{
	struct frameserver_shmpage* shared = recctx.shmcont.addr;
	assert(shared);

	static bool initialized = false;

	if (shared->storage.w % 2 != 0 || shared->storage.h % 2 != 0){
		LOG("(encode) -- source image format (%dx%d) must be evenly disible by 2.\n",
			shared->storage.w, shared->storage.h);

		return false;
	}

	if (!initialized){
		avcodec_register_all();
		av_register_all();
		initialized = true;
	}

/* codec stdvals, these may be overridden by the codec- options,
 * mostly used as hints to the setup- functions from the presets.* files */
	unsigned vbr = 0, abr = 0, samplerate = SHMPAGE_SAMPLERATE, channels = 2;
	bool noaudio = false, stream_outp = false;
	float fps    = 25;

	struct arg_arr* args = arg_unpack(resource);
	const char (* vck) = NULL, (* ack) = NULL, (* cont) = NULL, (* streamdst) = NULL;

	const char* val;
	if (arg_lookup(args, "vbitrate", 0, &val)) vbr = strtoul(val, NULL, 10) * 1024;
	if (arg_lookup(args, "abitrate", 0, &val)) abr = strtoul(val, NULL, 10) * 1024;
	if (arg_lookup(args, "vpreset",  0, &val)) vbr = ( (vbr = strtoul(val, NULL, 10)) > 10 ? 10 : vbr);
	if (arg_lookup(args, "apreset",  0, &val)) abr = ( (abr = strtoul(val, NULL, 10)) > 10 ? 10 : abr);
	if (arg_lookup(args, "fps", 0, &val)) fps = strtof(val, NULL);
	if (arg_lookup(args, "noaudio", 0, &val)) noaudio = true;
	
	arg_lookup(args, "vcodec", 0, &vck);
	arg_lookup(args, "acodec", 0, &ack);
	arg_lookup(args, "container", 0, &cont);

/* sanity- check decoded values */
	if (fps < 4 || fps > 60){
			LOG("(encode:%s) -- bad framerate (fps) argument, defaulting to 25.0fps\n", resource);
			fps = 25;
	}

	LOG("(encode) -- Avcodec version: %d.%d\n", LIBAVCODEC_VERSION_MAJOR, LIBAVCODEC_VERSION_MINOR);
	LOG("(encode:args) -- Parsing complete, values:\nvcodec: (%s:%f fps @ %d %s), acodec: (%s:%d rate %d %s), container: (%s)\n",
			vck?vck:"default",  fps, vbr, vbr <= 10 ? "qual.lvl" : "b/s", ack?ack:"default", samplerate, abr, abr <= 10 ? "qual.lvl" : "b/s", cont?cont:"default");

/* overrides some of the other options to provide RDP output etc. */
	if (cont && strcmp(cont, "stream") == 0){
		avformat_network_init();
		stream_outp = true;
		cont = "stream";

		if (!arg_lookup(args, "streamdst", 0, &streamdst) || strncmp("rtmp://", streamdst, 7) != 0){
			printf("arg lookup failed, %s\n", streamdst ? streamdst : "NULL");
			LOG("(encode:args) -- Streaming requested, but no valid streamdst set, giving up.\n");
			return false;
		}
	}
	
/* locate codecs and containers */
	struct codec_ent muxer = encode_getcontainer(cont, recctx.lastfd, streamdst);
	struct codec_ent video = encode_getvcodec(vck, muxer.storage.container.format->flags);
	struct codec_ent audio = encode_getacodec(ack, muxer.storage.container.format->flags);
	unsigned contextc      = 0; /* track of which ID the next stream has */

	if (!video.storage.container.context){
		LOG("(encode) -- No valid output container found, aborting.\n");
		return false;
	}
	
	if (!video.storage.video.codec && !audio.storage.audio.codec){
		LOG("(encode) -- No valid video or audio setup found, aborting.\n");
		return false;
	}

/* some feasible combination found, prepare memory page */
	frameserver_shmpage_calcofs(shared, &(recctx.vidp), &(recctx.audp) );

	if (video.storage.video.codec){
		unsigned width  = shared->storage.w;
		unsigned height = shared->storage.h;

		if ( video.setup.video(&video, width, height, fps, vbr, stream_outp) ){
			recctx.encvbuf_sz = width * height * 4;
			recctx.encvbuf    = av_malloc(recctx.encvbuf_sz);
			recctx.ccontext   = sws_getContext(width, height, PIX_FMT_RGBA, width, height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);

			recctx.vstream = av_new_stream(muxer.storage.container.context, contextc++);
			recctx.vcodec  = video.storage.video.codec;
			recctx.vcontext= video.storage.video.context;
			recctx.pframe  = video.storage.video.pframe;

			recctx.vstream->codec = recctx.vcontext;
			recctx.fps = fps;

			LOG("(encode) -- Video encoder setup. %dx%d@%f fps using %s\n", width, height, fps, video.name ? video.name : "(unknown)");
		}
	}

	if (!noaudio && video.storage.audio.codec){
		if ( audio.setup.audio(&audio, channels, samplerate, abr) ){
			recctx.encabuf_sz     = SHMPAGE_AUDIOBUF_SIZE * 2;
			recctx.encabuf_ofs    = 0;
			recctx.encabuf        = av_malloc(recctx.encabuf_sz);

			recctx.astream        = av_new_stream(muxer.storage.container.context, contextc++);
			recctx.acontext       = audio.storage.audio.context;
			recctx.acodec         = audio.storage.audio.codec;
			recctx.astream->codec = recctx.acontext;

/* feeding audio encoder by this much each time,
 * frame_size = number of samples per frame, might need to supply the encoder with a fixed amount, each sample covers n channels.
 * aframe_sz is based on S16LE 2ch stereo as this is aligned to the INPUT data, for float conversion, we need to double afterwards
 */

			if ( (recctx.acodec->capabilities & CODEC_CAP_VARIABLE_FRAME_SIZE) > 0){
				recctx.aframe_smplcnt = recctx.acontext->frame_size ? recctx.acontext->frame_size : round( samplerate / fps );
			}
			else {
				recctx.aframe_smplcnt = recctx.acontext->frame_size;
				LOG("(encode) audio: variable size capabilities, codec frame size: %d\n", recctx.acontext->frame_size);
			}

			recctx.aframe_sz = recctx.aframe_smplcnt * SHMPAGE_ACHANNELCOUNT * av_get_bytes_per_sample(recctx.acontext->sample_fmt);
			LOG("(encode) audio: bytes per sample: %d, samples per frame: %d\n", av_get_bytes_per_sample( recctx.acontext->sample_fmt ), recctx.aframe_smplcnt);
		}
	}

/* lastly, now that all streams are added, write the header */
	recctx.fcontext = muxer.storage.container.context;
	muxer.setup.muxer(&muxer);

/* signal that we are ready to receive video frames */
	arcan_sem_post(recctx.shmcont.vsem);
	return true;
}

#ifdef _WIN32
#include <io.h>
#endif

void arcan_frameserver_ffmpeg_encode(const char* resource, const char* keyfile)
{
/* setup shmpage etc. resolution etc. is already in place thanks to the parent */
	recctx.shmcont = frameserver_getshm(keyfile, true);
	struct frameserver_shmpage* shared = recctx.shmcont.addr;
	frameserver_shmpage_setevqs(recctx.shmcont.addr, recctx.shmcont.esem, &(recctx.inevq), &(recctx.outevq), false);
	recctx.lastfd = BADFD;
	atexit(encoder_atexit);

	while (true){
		arcan_errc evstat;

/* fail here means there's something wrong with frameserver - main app connection */
		arcan_event* ev = arcan_event_poll(&recctx.inevq, &evstat);
		if (evstat != ARCAN_OK)
			break;

		if (ev){
			switch (ev->kind){

/* nothing happens until the first FDtransfer, and consequtive ones should really only be "useful" in streaming
 * situations, and perhaps not even there, so consider that scenario untested */
				case TARGET_COMMAND_FDTRANSFER:
					if (recctx.lastfd != BADFD)
						arcan_frameserver_stepframe(true); /* flush */

/* regular file_handle abstraction with the readhandle actually returns a HANDLE on win32,
 * since that's currently not very workable with avformat (it seems, hard to judge with that "API")
 * we covert that to a regular POSIX file handle */
					recctx.lastframe = arcan_timemillis();

#ifdef _WIN32
					recctx.lastfd = _open_osfhandle( (intptr_t) frameserver_readhandle(ev), _O_APPEND);
#else
					recctx.lastfd = frameserver_readhandle(ev);
#endif
					if (!setup_ffmpeg_encode(resource))
						return;
				break;

				case TARGET_COMMAND_STEPFRAME:
					if (recctx.lastfd != BADFD)
						arcan_frameserver_stepframe(false);
				break;

				case TARGET_COMMAND_STORE:
					return;
				break;
			}
		}

		arcan_timesleep(1);
	}
}
