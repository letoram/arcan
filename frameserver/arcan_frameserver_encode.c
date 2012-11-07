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
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#undef BADFD
#define BADFD -1

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_encode.h"
#include "arcan_frameserver_encode_presets.h"

/* although there's a libswresampler already "handy", speex is used
 * (a) for the simple relief in not having to deal with more ffmpeg "APIs"
 * and (b) for future VoIP features */
#include "resampler/speex_resampler.h"

/* audb contains a list of audio buffers each push,
 * each of these have an associated samplerate and mixweight
 * each deviation from the expected samplerate gets a resampler allocated */
struct resampler {
	arcan_aobj_id source;
	float weight;

	SpeexResamplerState* resampler;

	struct resampler* next;
};

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

/* samplerate conversions */
	struct resampler* resamplers;

/* needed for intermediate buffering and format conversion */
	bool float_samples, float_planar;

	uint8_t* encabuf;
	float* encfbuf;
	off_t encabuf_ofs;
	size_t encabuf_sz;

/* needed for encode_audio frame settings */
	int aframe_smplcnt;
	size_t aframe_sz;
	unsigned long aframe_cnt;

} ffmpegctx = {0};

static struct resampler* grab_resampler(arcan_aobj_id id, unsigned samplerate, unsigned channels)
{
/* no resampler setup, allocate */
	struct resampler* res = ffmpegctx.resamplers;
	struct resampler** ip = &ffmpegctx.resamplers;

	while (res){
		if (res->source == id)
			return res;

		if (res->next == NULL)
			ip = &res->next;

		res = res->next;
	}

/* no match, allocate */
	res = *ip = av_malloc( sizeof(struct resampler) );
	res->next = NULL;

	int errc;
	res->resampler = speex_resampler_init(channels, samplerate, ffmpegctx.acontext->sample_rate, 7, &errc);
	res->weight = 1.0;
	res->source = id;

	return res;
}

/* flush the audio buffer present in the shared memory page as quick as possible,
 * resample if necessary, then use the intermediate buffer to feed encoder */
static void flush_audbuf()
{
	size_t cur_sz = ffmpegctx.shmcont.addr->abufused;
	uint8_t* audb = ffmpegctx.audp;
	uint16_t* auds16b = (uint16_t*) ffmpegctx.encabuf; /* alignment guaranteed by calcofs */

	unsigned hdr[5] = {/* src */ 0, /* size_t */ 0, /* samplerate */ 0, /* channels */ 0, 0/* 0xfeedface */};

/* plow through the number of available bytes, these will be gone when stepframe is completed */
	while(cur_sz > sizeof(hdr) && ffmpegctx.encabuf_ofs < ffmpegctx.encabuf_sz){
		memcpy(&hdr, audb, sizeof(hdr));
		assert(hdr[4] == 0xfeedface);
		audb += sizeof(hdr);
		struct resampler* rsmp = grab_resampler(hdr[0], hdr[2], hdr[3]);

/* parent guarantees stereo, SINT16LE, size in bytes, so 4 bytes per sample but resampler
 * takes channels into account and wants the in count to be samples per channel (so half again) */
		unsigned inlen = hdr[1] >> 2;

/* same samplerate, no conversion needed, just push */
		if (hdr[2] == ffmpegctx.acontext->sample_rate){
			memcpy(&ffmpegctx.encabuf[ffmpegctx.encabuf_ofs], audb, hdr[1]);
			ffmpegctx.encabuf_ofs += hdr[1];
		}
/* pass through speex resampler before pushing, no mixing of channels happen here */
		else {
			size_t out_sz     = inlen << 2;
			unsigned int outc = out_sz;

/* note the quirk that outc first represents the size of the buffer, THEN after resampling, it's the number of samples */
			speex_resampler_process_interleaved_int(rsmp->resampler, (const spx_int16_t*) audb, &inlen, (spx_int16_t*) &ffmpegctx.encabuf[ffmpegctx.encabuf_ofs], &outc);
			ffmpegctx.encabuf_ofs += outc << 2;
		}

		audb += hdr[1];
		cur_sz -= hdr[1] + sizeof(hdr);
	}

}

static void encode_audio(bool flush)
{
	AVCodecContext* ctx = ffmpegctx.acontext;
	AVFrame* frame;
	bool forcetog = false;
	int numf, got_packet = false;
	off_t base = 0;

/* encode as many frames as possible from the intermediate buffer */
	while(base + ffmpegctx.aframe_sz <= ffmpegctx.encabuf_ofs){
		AVPacket pkt = {0};
		av_init_packet(&pkt);
		frame = avcodec_alloc_frame();

		frame->nb_samples     = ffmpegctx.aframe_smplcnt;
		frame->pts            = ffmpegctx.aframe_cnt;
		frame->channel_layout = ctx->channel_layout;
		ffmpegctx.aframe_cnt += ffmpegctx.aframe_smplcnt;

forceencode:
/* convert to _FLT format before passing on */
		if (ffmpegctx.float_samples){
/* usually not kosher, but addr will be aligned here */
			int16_t* addr = (int16_t*) &ffmpegctx.encabuf[base];
			memset(ffmpegctx.encfbuf, 0xaa, ffmpegctx.aframe_sz * 2);

			if (ffmpegctx.float_planar)
				for (int i = 0, j = 0; i < frame->nb_samples * 2; i+=2, j++){
					ffmpegctx.encfbuf[j] = (float)(addr[i]) / 32767.0; 
					ffmpegctx.encfbuf[frame->nb_samples - 1+ j] = (float)(addr[i+1]) / 32767.0;
				}
			else for (int i = 0; i < frame->nb_samples * 2; i++)
				ffmpegctx.encfbuf[i] = (float)(addr[i]) / 32767.0f;

			avcodec_fill_audio_frame(frame, 2, ctx->sample_fmt, (uint8_t*) ffmpegctx.encfbuf, ffmpegctx.aframe_sz * 2, 1);
		}
		else
			avcodec_fill_audio_frame(frame, 2, ctx->sample_fmt, ffmpegctx.encabuf + base, ffmpegctx.aframe_sz, 1);

		int rv = avcodec_encode_audio2(ctx, &pkt, frame, &got_packet);
		if (0 != rv && !flush){
			LOG("arcan_frameserver(encode) : encode_audio, couldn't encode, giving up.\n");
			exit(1);
		}

		if (got_packet){
			if (pkt.pts != AV_NOPTS_VALUE)
				pkt.pts = av_rescale_q(pkt.pts, ctx->time_base, ffmpegctx.astream->time_base);

			if (pkt.dts != AV_NOPTS_VALUE)
				pkt.dts = av_rescale_q(pkt.dts, ctx->time_base, ffmpegctx.astream->time_base);

			if (pkt.duration > 0)
				pkt.duration = av_rescale_q(pkt.duration, ctx->time_base, ffmpegctx.astream->time_base);

			pkt.stream_index = ffmpegctx.astream->index;

			if (0 != av_interleaved_write_frame(ffmpegctx.fcontext, &pkt) && !flush){
				LOG("arcan_frameserver(encode) : encode_audio, write_frame failed, giving up.\n");
				exit(1);
			}
		}

		base += ffmpegctx.aframe_sz;
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
			ffmpegctx.aframe_sz = ffmpegctx.encabuf_ofs - base;
			frame = avcodec_alloc_frame();
			frame->nb_samples = ffmpegctx.aframe_sz / 2;
			frame->pts = ffmpegctx.aframe_cnt;
			frame->channel_layout = ctx->channel_layout;

			forcetog = true;
			goto forceencode;
		}

		if ( (ctx->flags & CODEC_CAP_DELAY) > 0 ){
			int gotpkt;
			do {
				AVPacket flushpkt = {0};
				av_init_packet(&flushpkt);
				if (0 == avcodec_encode_audio2(ctx, &flushpkt, NULL, &gotpkt)){
					av_interleaved_write_frame(ffmpegctx.fcontext, &flushpkt);
				}
			} while (gotpkt);
		}

		return;
	}

/* slide the intermediate buffer offsets */
	if (base < ffmpegctx.encabuf_ofs)
		memmove(ffmpegctx.encabuf, (uint8_t*) (ffmpegctx.encabuf) + base, ffmpegctx.encabuf_ofs - base);

	ffmpegctx.encabuf_ofs -= base;
}

void encode_video(bool flush)
{
	uint8_t* srcpl[4] = {ffmpegctx.vidp, NULL, NULL, NULL};
	int srcstr[4] = {0, 0, 0, 0};
	srcstr[0] = ffmpegctx.vcontext->width * 4;

/* the main problem here is that the source material may encompass many framerates, in fact, even be variable (!)
 * the samplerate we're running with that is of interest. Thus compare the current time against the next expected time-slots,
 * if we're running behind, just repeat the last frame N times as to not get out of synch with possible audio. */
	double mspf = 1000.0 / ffmpegctx.fps;
	double thresh = mspf * 0.5;
	long long encb    = frameserver_timemillis();
	long long cft     = encb - ffmpegctx.lastframe; /* assumed >= 0 */
	long long nf      = round( mspf * (double)ffmpegctx.framecount );
	long long delta   = cft - nf;
	unsigned fc       = 1;

/* ahead by too much? just wait */
	if (delta < -thresh)
		return;

/* running behind, need to repeat a frame */
	if ( delta > thresh )
		fc += 1 + floor( delta / mspf);

	if (fc > 1){
		LOG("arcan_frameserver(encode) jitter: %lld, current time :%lld, ideal: %lld\n", delta, cft, nf);
	}

	int rv = sws_scale(ffmpegctx.ccontext, (const uint8_t* const*) srcpl, srcstr, 0,
		ffmpegctx.vcontext->height, ffmpegctx.pframe->data, ffmpegctx.pframe->linesize);

/* might repeat the number of frames in order to compensate for poor frame sampling alignment */
	while (fc--){
		AVCodecContext* ctx = ffmpegctx.vcontext;
		AVPacket pkt = {0};
		int got_outp = false;
		ffmpegctx.framecount++;
	
		av_init_packet(&pkt);
		ffmpegctx.pframe->pts = ffmpegctx.framecount;

		int rs = avcodec_encode_video2(ffmpegctx.vcontext, &pkt, flush ? NULL : ffmpegctx.pframe, &got_outp);

		if (rs < 0 && !flush) {
			LOG("arcan_frameserver(encode) -- encode_video failed, terminating.\n");
			exit(1);
		}

		if (got_outp){
			if (pkt.pts != AV_NOPTS_VALUE)
				pkt.pts = av_rescale_q(pkt.pts, ctx->time_base, ffmpegctx.vstream->time_base);

			if (pkt.dts != AV_NOPTS_VALUE)
				pkt.dts = av_rescale_q(pkt.dts, ctx->time_base, ffmpegctx.vstream->time_base);

			if (ctx->coded_frame->key_frame)
				pkt.flags |= AV_PKT_FLAG_KEY;

			pkt.stream_index = ffmpegctx.vstream->index;

			if (av_interleaved_write_frame(ffmpegctx.fcontext, &pkt) != 0 && !flush){
				LOG("arcan_frameserver(encode) -- writing encoded video failed, terminating.\n");
				exit(1);
			}
		}

	}

}

void arcan_frameserver_stepframe(bool flush)
{
	flush_audbuf();
	ffmpegctx.shmcont.addr->abufused = 0;

/* just empty all buffers into the stream */
	if (flush){
		if (ffmpegctx.acontext)
			encode_audio(flush);

		encode_video(flush);
		return;
	}

/* calculate this first so we don't overstep audio/video interleaving */
	double vpts;
	if (ffmpegctx.vstream)
		vpts = ffmpegctx.vstream->pts.val * (float)ffmpegctx.vstream->time_base.num / (float)ffmpegctx.vstream->time_base.den;
	else
		vpts = 0.0;

/* interleave audio / video */
		while(ffmpegctx.astream && ffmpegctx.encabuf_ofs >= ffmpegctx.aframe_sz){
			double apts = ffmpegctx.astream->pts.val * (float)ffmpegctx.astream->time_base.num / (float)ffmpegctx.astream->time_base.den;

			if (apts < vpts || ffmpegctx.astream->pts.val == AV_NOPTS_VALUE){
				encode_audio(flush);
			}
			else
				break;
		}

	if (ffmpegctx.vstream)
		encode_video(flush);

/* acknowledge that a frame has been consumed, then return to polling events */
	arcan_sem_post(ffmpegctx.shmcont.vsem);
}

static void encoder_atexit()
{
	if (!ffmpegctx.fcontext)
		return;

	if (ffmpegctx.lastfd != BADFD){
		arcan_frameserver_stepframe(true);

		if (ffmpegctx.fcontext)
			av_write_trailer(ffmpegctx.fcontext);
	}
}

static bool setup_ffmpeg_encode(const char* resource)
{
	struct frameserver_shmpage* shared = ffmpegctx.shmcont.addr;
	assert(shared);

	static bool initialized = false;

	if (shared->storage.w % 2 != 0 || shared->storage.h % 2 != 0){
		LOG("arcan_frameserver(encode) -- source image format (%dx%d) must be evenly disible by 2.\n",
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
	unsigned vbr = 0, abr = 0, samplerate = 44100, channels = 2;
	bool noaudio = false;
	float fps    = 25;

	struct arg_arr* args = arg_unpack(resource);
	const char (* vck) = NULL, (* ack) = NULL, (* cont) = NULL;

	const char* val;
	if (arg_lookup(args, "vbitrate", 0, &val)) vbr = strtoul(val, NULL, 10) * 1024;
	if (arg_lookup(args, "abitrate", 0, &val)) abr = strtoul(val, NULL, 10) * 1024;
	if (arg_lookup(args, "vpreset",  0, &val)) vbr = ( (vbr = strtoul(val, NULL, 10)) > 10 ? 10 : vbr);
	if (arg_lookup(args, "apreset",  0, &val)) abr = ( (abr = strtoul(val, NULL, 10)) > 10 ? 10 : abr);
	if (arg_lookup(args, "samplerate", 0, &val)) samplerate = strtoul(val, NULL, 0);
	if (arg_lookup(args, "fps", 0, &val)) fps = strtof(val, NULL);
	if (arg_lookup(args, "noaudio", 0, &val)) noaudio = true;
	
	arg_lookup(args, "vcodec", 0, &vck);
	arg_lookup(args, "acodec", 0, &ack);
	arg_lookup(args, "container", 0, &cont);

/* sanity- check decoded values */
	if (fps < 4 || fps > 60){
			LOG("arcan_frameserver(encode:%s) -- bad framerate (fps) argument, defaulting to 25.0fps\n", resource);
			fps = 25;
	}

	LOG("arcan_frameserver(encode:args) -- Parsing complete, values:\nvcodec: (%s:%f fps @ %d b/s), acodec: (%s:%d rate %d b/s), container: (%s)\n",
			vck?vck:"default",  fps, vbr, ack?ack:"default", samplerate, abr, cont?cont:"default");

/* overrides some of the other options to provide RDP output etc. */
	if (cont && strcmp(cont, "stream") == 0){
		avformat_network_init();
		cont = "stream";
	}
	
/* locate codecs and containers */
	struct codec_ent muxer = encode_getcontainer(cont, ffmpegctx.lastfd);
	struct codec_ent video = encode_getvcodec(vck, muxer.storage.container.format->flags);
	struct codec_ent audio = encode_getacodec(ack, muxer.storage.container.format->flags);
	unsigned contextc      = 0; /* track of which ID the next stream has */

	if (!video.storage.container.context){
		LOG("arcan_frameserver(encode) -- No valid output container found, aborting.\n");
		return false;
	}
	
	if (!video.storage.video.codec && !audio.storage.audio.codec){
		LOG("arcan_frameserver(encode) -- No valid video or audio setup found, aborting.\n");
		return false;
	}

/* some feasible combination found, prepare memory page */
	frameserver_shmpage_calcofs(shared, &(ffmpegctx.vidp), &(ffmpegctx.audp) );

	if (video.storage.video.codec){
		unsigned width  = shared->storage.w;
		unsigned height = shared->storage.h;

		if ( video.setup.video(&video, width, height, fps, vbr) ){
			ffmpegctx.encvbuf_sz = width * height * 4;
			ffmpegctx.encvbuf    = av_malloc(ffmpegctx.encvbuf_sz);
			ffmpegctx.ccontext   = sws_getContext(width, height, PIX_FMT_RGBA, width, height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);

			ffmpegctx.vstream = av_new_stream(muxer.storage.container.context, contextc++);
			ffmpegctx.vcodec  = video.storage.video.codec;
			ffmpegctx.vcontext= video.storage.video.context;
			ffmpegctx.pframe  = video.storage.video.pframe;

			ffmpegctx.vstream->codec = ffmpegctx.vcontext;
			ffmpegctx.fps = fps;

			LOG("arcan_frameserver(encode) -- video setup. (%d, %d)\n", width, height);
		}
	}

	if (!noaudio && video.storage.audio.codec){
		if ( audio.setup.audio(&audio, channels, samplerate, abr) ){
			ffmpegctx.encabuf_sz     = SHMPAGE_AUDIOBUF_SIZE * 2;
			ffmpegctx.encabuf_ofs    = 0;
			ffmpegctx.encabuf        = av_malloc(ffmpegctx.encabuf_sz);

			ffmpegctx.astream        = av_new_stream(muxer.storage.container.context, contextc++);
			ffmpegctx.acontext       = audio.storage.audio.context;
			ffmpegctx.acodec         = audio.storage.audio.codec;
			ffmpegctx.astream->codec = ffmpegctx.acontext;
			LOG("arcan_frameserver(encode) -- audio setup.\n");

/* feeding audio encoder by this much each time,
 * frame_size = number of samples per frame, might need to supply the encoder with a fixed amount, each sample covers n channels.
 * aframe_sz is based on S16LE 2ch stereo as this is aligned to the INPUT data, for float conversion, we need to double afterwards
 */
			ffmpegctx.aframe_smplcnt = (ffmpegctx.acodec->capabilities & CODEC_CAP_VARIABLE_FRAME_SIZE) > 0 ?
				samplerate / fps : ffmpegctx.acontext->frame_size;
			ffmpegctx.aframe_sz = 4 * ffmpegctx.aframe_smplcnt;

			LOG("arcan_frameserver(encode) -- audio sample format(%d)\n", ffmpegctx.acontext->sample_fmt);
			if (ffmpegctx.acontext->sample_fmt == AV_SAMPLE_FMT_FLT || ffmpegctx.acontext->sample_fmt == AV_SAMPLE_FMT_FLTP){
				ffmpegctx.encfbuf = av_malloc( ffmpegctx.aframe_sz * 2);
				ffmpegctx.float_samples = true;
				ffmpegctx.float_planar  = ffmpegctx.acontext->sample_fmt == AV_SAMPLE_FMT_FLTP;
			}

		}
	}

/* lastly, now that all streams are added, write the header */
	ffmpegctx.fcontext = muxer.storage.container.context;
	muxer.setup.muxer(&muxer);

/* additional setup for rtp */
	if (cont && strcmp(cont, "stream") == 0){
		char* sdpbuffer = malloc(2048);
		av_sdp_create(&muxer.storage.container.context, 1, sdpbuffer, 2048);
		LOG("arcan_frameserver(encode) -- SDP: %s\n", sdpbuffer);
	}
	
/* signal that we are ready to receive video frames */
	arcan_sem_post(ffmpegctx.shmcont.vsem);
	return true;
}

#ifdef _WIN32
#include <io.h>
#endif

void arcan_frameserver_ffmpeg_encode(const char* resource, const char* keyfile)
{
/* setup shmpage etc. resolution etc. is already in place thanks to the parent */
	ffmpegctx.shmcont = frameserver_getshm(keyfile, true);
	struct frameserver_shmpage* shared = ffmpegctx.shmcont.addr;
	frameserver_shmpage_setevqs(ffmpegctx.shmcont.addr, ffmpegctx.shmcont.esem, &(ffmpegctx.inevq), &(ffmpegctx.outevq), false);
	ffmpegctx.lastfd = BADFD;
	atexit(encoder_atexit);

	while (true){
		arcan_event* ev = arcan_event_poll(&ffmpegctx.inevq);

		if (ev){
			switch (ev->kind){

/* nothing happens until the first FDtransfer, and consequtive ones should really only be "useful" in streaming
 * situations, and perhaps not even there, so consider that scenario untested */
				case TARGET_COMMAND_FDTRANSFER:
					if (ffmpegctx.lastfd != BADFD)
						arcan_frameserver_stepframe(true); /* flush */

/* regular file_handle abstraction with the readhandle actually returns a HANDLE on win32,
 * since that's currently not very workable with avformat (it seems, hard to judge with that "API")
 * we covert that to a regular POSIX file handle */
					ffmpegctx.lastframe = frameserver_timemillis();

#ifdef _WIN32
					ffmpegctx.lastfd = _open_osfhandle( (intptr_t) frameserver_readhandle(ev), _O_APPEND);
#else
					ffmpegctx.lastfd = frameserver_readhandle(ev);
#endif
					if (!setup_ffmpeg_encode(resource))
						return;
				break;

				case TARGET_COMMAND_STEPFRAME:
					if (ffmpegctx.lastfd != BADFD)
						arcan_frameserver_stepframe(false);
				break;

				case TARGET_COMMAND_STORE:
					return;
				break;
			}
		}

		frameserver_delay(1);
	}
}
