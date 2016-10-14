/*
 * Encode reference frameserver archetype
 * Copyright 2012-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: FFMPEG (GPLv2,v3,LGPL)
 */

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
#include <libavutil/imgutils.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

#include <arcan_shmif.h>
#include "encode_presets.h"
#include "frameserver.h"

#ifdef HAVE_VNCSERVER
#include "vncserver.h"
#endif

#ifdef HAVE_OCR
void ocr_serv_run(struct arg_arr* args, struct arcan_shmif_cont cont);
#endif

/* don't build / link to older versions */
#if LIBAVCODEC_VERSION_MAJOR < 54
	extern char* dated_ffmpeg_refused_old_build[-1];
#endif

static struct {
/* IPC */
	struct arcan_shmif_cont shmcont;
	int lastfd;        /* sent from parent */

/* Multiplexing / Output */
	AVFormatContext* fcontext;
	AVPacket packet;
	AVFrame* pframe;

/* VIDEO */
/* color format conversion (ccontext) is also used for
 * just populating the image/ color planes properly */
	struct SwsContext* ccontext;
	AVCodecContext* vcontext;
	AVStream* vstream;
	AVCodec* vcodec;
	int bpp;
	uint8_t* encvbuf;

/* set to ~twice the size of a full frame, larger than that and
 * we have terrible "compression" on our hands */
	size_t encvbuf_sz;
	int vpts_ofs;
/* used to rougly displace A/V synchronisation in encoded frames */

/* Timing (shared) */
	long long starttime;       /* monotonic clock time-stamp */
	unsigned long framecount;  /* number of frames treated, multiply with fps */
	float fps;

/* AUDIO */
/* containers and metadata */
	AVCodecContext* acontext;
	AVCodec* acodec;
	AVStream* astream;
	int channel_layout;
	int apts_ofs; /* used to roughly displace A/V
									 synchronisation in encoded frames */
	int silence_samples; /* used to dynamically drop or insert
													silence bytes in buffer_flush */

/* needed for intermediate buffering and format conversion */
	bool float_samples;

	uint8_t* encabuf;
	off_t encabuf_ofs;
	size_t encabuf_sz;

/* needed for encode_audio frame settings */
	int aframe_smplcnt;
	size_t aframe_insz, aframe_sz;
	unsigned long aframe_ptscnt;

/* for re-using this compilation unit from other frameservers */
} recctx;

struct cl_track {
	unsigned conn_id;
};

/* flush the audio buffer present in the shared memory page as
 * quick as possible, resample if necessary, then use the intermediate
 * buffer to feed encoder */
static void flush_audbuf()
{
	size_t ntc = recctx.shmcont.addr->abufused[0];
	uint8_t* dataptr = (uint8_t*) recctx.shmcont.audp;

	if (!recctx.acontext){
		recctx.shmcont.addr->abufused[0] = 0;
		return;
	}

/* parent events can modify this buffer to compensate for streaming desynch,
 * extra work for sample size alignment as shm api calculates
 * bytes and allows truncating (terrible) */
	if (recctx.silence_samples > 0){ /* insert n 0- level samples */
		size_t nti = (recctx.silence_samples << 2) > recctx.encabuf_sz -
			recctx.encabuf_ofs ? recctx.encabuf_sz - recctx.encabuf_ofs :
			recctx.silence_samples << 2;
		nti = nti - (nti % 4);

		memset(recctx.encabuf + recctx.encabuf_ofs, 0, nti);
		recctx.encabuf_ofs += nti;
		recctx.silence_samples = nti >> 2;

	}
	else if (recctx.silence_samples < 0){ /* drop n samples */
		size_t ntd = (ntc >> 2) > recctx.silence_samples ?
			recctx.silence_samples << 2 : ntc;
		if (ntd == ntc){
			recctx.silence_samples -= recctx.silence_samples << 2;
			recctx.shmcont.addr->abufused[0] = 0;
			return;
		}

		dataptr += ntd;
		ntc -= ntd;
	}
	else
		;

	if (ntc + recctx.encabuf_ofs > recctx.encabuf_sz){
		ntc = recctx.encabuf_sz - recctx.encabuf_ofs;
		static bool warned;
		if (!warned){
			warned = true;
			printf("audio buffer overflow\n");
			LOG("(encode) audio buffer overflow, consider different"
				"	encoding options.\n");
		}
	}

	memcpy(&recctx.encabuf[recctx.encabuf_ofs], dataptr, ntc);
	recctx.encabuf_ofs += ntc;

/* worst case, we get overflown buffers and need to drop sound */
	recctx.shmcont.addr->abufused[0] = 00;
}

/*
 * This is somewhat ugly, a real ffmpeg expert could probably help out here --
 * we don't actually use the resampler for resampling purposes,
 * output encoder samplerate is forced to the same as SHMPAGE_SAMPLERATE,
 * but the resampler API is used to convert between all *** possible
 * expected output formats and filling out plane- alignments etc.
 */
static uint8_t* s16swrconv(int* size, int* nsamp)
{
	static struct SwrContext* resampler = NULL;
	static uint8_t** resamp_outbuf = NULL;

	if (!resampler){
		resampler = swr_alloc_set_opts(NULL, AV_CH_LAYOUT_STEREO,
			recctx.acontext->sample_fmt,
			recctx.acontext->sample_rate, AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_S16,
			ARCAN_SHMIF_SAMPLERATE, 0, NULL);

		resamp_outbuf = av_malloc(sizeof(uint8_t*) * ARCAN_SHMIF_ACHANNELS);
		av_samples_alloc(resamp_outbuf, NULL, ARCAN_SHMIF_ACHANNELS,
			recctx.aframe_smplcnt, recctx.acontext->sample_fmt, 0);

		if (swr_init(resampler) < 0 ){
			LOG("(encode) couldn't allocate resampler, giving up.\n");
			exit(1);
		}
	}

	const uint8_t* indata[] = {recctx.encabuf, NULL};
	int rc = swr_convert(resampler, resamp_outbuf, recctx.aframe_smplcnt,
		indata, recctx.aframe_smplcnt);

	if (rc < 0){
		LOG("(encode) couldn't resample, giving up.\n");
		exit(1);
	}

	*nsamp = rc;
	*size = av_samples_get_buffer_size(NULL, ARCAN_SHMIF_ACHANNELS, rc,
		recctx.acontext->sample_fmt, 0);
	memmove(recctx.encabuf, recctx.encabuf + recctx.aframe_insz,
		recctx.encabuf_ofs - recctx.aframe_insz);

	recctx.encabuf_ofs -= recctx.aframe_insz;

	return resamp_outbuf[0];
}

static bool encode_audio(bool flush)
{
	AVCodecContext* ctx = recctx.acontext;
	AVFrame* frame;
	bool forcetog = false;
	int got_packet = false;

/* NOTE:
 * for real sample-rate conversion, this test would need to
 * reflect the state of the resampler internal buffers */
	if (!flush && recctx.aframe_insz > recctx.encabuf_ofs)
		return false;

	AVPacket pkt = {0};
	av_init_packet(&pkt);

	frame = av_frame_alloc();
	frame->channel_layout = ctx->channel_layout;

	int buffer_sz;
	uint8_t* ptr;

forceencode:
	ptr = s16swrconv(&buffer_sz, &frame->nb_samples);

	if ( avcodec_fill_audio_frame(frame, ARCAN_SHMIF_ACHANNELS,
		ctx->sample_fmt, ptr, buffer_sz, 0) < 0 ){
		LOG("(encode) couldn't fill target audio frame.\n");
		exit(EXIT_FAILURE);
	}

	frame->pts = recctx.aframe_ptscnt;
	recctx.aframe_ptscnt += frame->nb_samples;

	int rv = avcodec_encode_audio2(ctx, &pkt, frame, &got_packet);

	if (0 != rv && !flush){
		LOG("(encode) : encode_audio, couldn't encode, giving up.\n");
		exit(EXIT_FAILURE);
	}

	if (got_packet){
		if (pkt.pts != AV_NOPTS_VALUE)
			pkt.pts = av_rescale_q(pkt.pts, ctx->time_base,
				recctx.astream->time_base);

		if (pkt.dts != AV_NOPTS_VALUE)
			pkt.dts = av_rescale_q(pkt.dts, ctx->time_base,
				recctx.astream->time_base);

/*
 * NOTE:
 * we might be mistreating duration both here and in video,
 * investigate!
 */
		if (pkt.duration > 0)
			pkt.duration = av_rescale_q(pkt.duration, ctx->time_base,
				recctx.astream->time_base);

		pkt.stream_index = recctx.astream->index;

		if (0 != av_interleaved_write_frame(recctx.fcontext, &pkt) && !flush){
			LOG("(encode) : encode_audio, write_frame failed, giving up.\n");
			exit(EXIT_FAILURE);
		}

		av_freep(&frame);
	}

	av_packet_unref(&pkt);

/*
 * for the flush case, we may have a little bit of buffers left, both in the
 * encoder and the resampler,
 * CODEC_CAP_DELAY = pframe can be NULL and encode audio is used to flush
 * CODEC_CAP_SMALL_LAST_FRAME or CODEC_CAP_VARIABLE_FRAME_SIZE =
 * we can the last few buffer bytes can be stored as well otherwise those
 * will be discarded
 */

	if (flush){
/*
 * setup a partial new frame with as many samples as we can fit,
 * change the expected "frame size" to match
 * and then re-use the encode / conversion code
 */
		if (!forcetog &&
			((ctx->flags & CODEC_CAP_SMALL_LAST_FRAME) > 0 ||
				(ctx->flags & CODEC_CAP_VARIABLE_FRAME_SIZE) > 0)){
			recctx.aframe_insz = recctx.encabuf_ofs;
			recctx.aframe_smplcnt = recctx.aframe_insz >> 2;
			frame = av_frame_alloc();
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
					av_interleaved_write_frame(recctx.fcontext, &flushpkt);
					av_packet_unref(&flushpkt);
				}
			} while (gotpkt);
		}

		return false;
	}

	return true;
}

static int encode_video(bool flush)
{
	uint8_t* srcpl[4] = {(uint8_t*)recctx.shmcont.vidp, NULL, NULL, NULL};
	int srcstr[4] = {recctx.shmcont.addr->w * recctx.bpp};

/* the main problem here is that the source material may encompass many
 * framerates, in fact, even be variable (!) the samplerate we're running
 * with that is of interest. Thus compare the current time against the next
 * expected time-slots, if we're running behind, just repeat the last
 * frame N times as to not get out of synch with possible audio. */
	double mspf = 1000.0 / recctx.fps;
	long long next_frame = mspf * (double)(recctx.framecount + 1);
	long long frametime  = arcan_timemillis() - recctx.starttime;

	if (frametime < next_frame - mspf * 0.5)
		return 0;

	frametime -= next_frame;
	int fc = frametime > 0 ? floor(frametime / mspf) : 0;

	sws_scale(recctx.ccontext, (const uint8_t* const*) srcpl, srcstr, 0,
		recctx.shmcont.addr->h, recctx.pframe->data, recctx.pframe->linesize);

	AVCodecContext* ctx = recctx.vcontext;
	AVPacket pkt = {0};
	int got_outp = false;

	av_init_packet(&pkt);
	recctx.pframe->pts = recctx.framecount++;

	int rs = avcodec_encode_video2(recctx.vcontext, &pkt, flush ?
		NULL : recctx.pframe, &got_outp);

	if (rs < 0 && !flush) {
		LOG("(encode) encode_video failed, terminating.\n");
		exit(EXIT_FAILURE);
	}

	if (got_outp){
		if (pkt.pts != AV_NOPTS_VALUE)
			pkt.pts = av_rescale_q_rnd(pkt.pts, ctx->time_base,
				recctx.vstream->time_base, AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);

		if (pkt.dts != AV_NOPTS_VALUE)
			pkt.dts = av_rescale_q_rnd(pkt.dts, ctx->time_base,
				recctx.vstream->time_base, AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);

/*
 * deprecated, seems from code inspection that the flag is set in the packet
 * in the encoder instead
		if (recctx.pframe->flags ctx->coded_frame->key_frame)
			pkt.flags |= AV_PKT_FLAG_KEY;
 */

		if (pkt.dts > pkt.pts){
			static bool dts_warn;

			if (!dts_warn){
				LOG("(encode) DTS > PTS inconsistency\n");
				dts_warn = true;
			}

			pkt.dts = pkt.pts;
		}

		pkt.duration = av_rescale_q(pkt.duration,
			ctx->time_base, recctx.vstream->time_base);
		pkt.stream_index = recctx.vstream->index;

		if (av_interleaved_write_frame(recctx.fcontext, &pkt) != 0 && !flush){
			LOG("(encode) writing encoded video failed, terminating.\n");
			exit(EXIT_FAILURE);
		}
	}

	av_packet_unref(&pkt);
	return fc;
}

void arcan_frameserver_stepframe()
{
	static bool first_audio = false;
	double apts, vpts;

	flush_audbuf();

/* some recording sources start video before audio, to not start with
 * bad interleaving, wait for some audio frames before start pushing video */
	if (!first_audio && recctx.acontext){
		if (recctx.encabuf_ofs > 0){
			first_audio = true;
			recctx.starttime = arcan_timemillis();
		}

		goto end;
	}

/* interleave audio / video */
	if (recctx.astream && recctx.vstream){
		while(1){
			apts = av_stream_get_end_pts(recctx.astream);
			vpts = av_stream_get_end_pts(recctx.vstream);

			if (apts < vpts){
				if (!encode_audio(false))
					break;
			}
			else {
				if (encode_video(false) == 0)
					break;
			}
		}
	}
/* audio or video only */
	else if (recctx.astream)
		while (encode_audio(false));
	else
		while (encode_video(false) > 0);

end:
	recctx.shmcont.addr->vready = false;
}

static void encoder_atexit()
{
	if (!recctx.fcontext)
		return;

	if (recctx.lastfd != -1){
		if (recctx.acontext)
			encode_audio(true);

		if (recctx.vcontext)
			encode_video(true);
	}

	av_write_trailer(recctx.fcontext);

	if (recctx.astream){
		LOG("(encode) closing audio stream\n");
		avcodec_close(recctx.astream->codec);
	}

	if (recctx.vstream){
		LOG("(encode) closing video stream\n");
		avcodec_close(recctx.vstream->codec);
	}

/*
 * good form says that we should do this, have received
 * some crashes here though.
 	 if (!(recctx.fcontext->oformat->flags & AVFMT_NOFILE)){
		avio_close(recctx.fcontext->pb);
	}
 */

	avformat_free_context(recctx.fcontext);

	LOG("(encode) atexit cleanup finished\n");
	fflush(stderr);
}

static void log_callback(void* ptr, int level, const char* fmt, va_list vl)
{
	vfprintf(stderr, fmt, vl);
}

/*
 * expects ccontext to be populated elsewhere
 */
static bool setup_ffmpeg_encode(struct arg_arr* args, int desw, int desh)
{
	struct arcan_shmif_page* shared = recctx.shmcont.addr;
	assert(shared);

#ifdef _DEBUG
	av_log_set_level( AV_LOG_DEBUG );
#else
	av_log_set_level( AV_LOG_WARNING );
#endif
	av_log_set_callback(log_callback);

	static bool initialized = false;

	if (desw % 2 != 0 || desh % 2 != 0){
		LOG("(encode) source image format (%"PRIu16" * %"PRIu16") must be evenly"
		"	divisible by 2.\n", shared->w, shared->h);

		return false;
	}

	if (!initialized){
		avcodec_register_all();
		av_register_all();
		initialized = true;
	}

/* codec stdvals, these may be overridden by the codec- options,
 * mostly used as hints to the setup- functions from the presets.* files */
	unsigned vbr = 5, abr = 5, samplerate = ARCAN_SHMIF_SAMPLERATE,
		channels = 2, presilence = 0, bpp = 4;

	bool noaudio = false, stream_outp = false;
	float fps    = 25;

	const char (* vck) = NULL, (* ack) = NULL, (* cont) = NULL,
		(* streamdst) = NULL;

	const char* val;
	if (arg_lookup(args, "vbitrate", 0, &val))
		vbr = strtoul(val, NULL, 10) * 1024;
	if (arg_lookup(args, "abitrate", 0, &val))
		abr = strtoul(val, NULL, 10) * 1024;
	if (arg_lookup(args, "vpreset",  0, &val)) vbr =
		( (vbr = strtoul(val, NULL, 10)) > 10 ? 10 : vbr);
	if (arg_lookup(args, "apreset",  0, &val)) abr =
		( (abr = strtoul(val, NULL, 10)) > 10 ? 10 : abr);
	if (arg_lookup(args, "fps", 0, &val)) fps = strtof(val, NULL);
	if (arg_lookup(args, "noaudio", 0, &val)) noaudio = true;
	if (arg_lookup(args, "presilence", 0, &val)) presilence =
		( (presilence = strtoul(val, NULL, 10)) > 0 ? presilence : 0);
	if (arg_lookup(args, "vptsofs", 0, &val))
		recctx.vpts_ofs = ( strtoul(val, NULL, 10) );
	if (arg_lookup(args, "aptsofs", 0, &val))
		recctx.apts_ofs = ( strtoul(val, NULL, 10) );

	arg_lookup(args, "vcodec", 0, &vck);
	arg_lookup(args, "acodec", 0, &ack);
	arg_lookup(args, "container", 0, &cont);

/* sanity- check decoded values */
	if (fps < 4 || fps > 60){
			LOG("(encode:) bad framerate (fps) argument, "
				"defaulting to 25.0fps\n");
			fps = 25;
	}

	LOG("(encode) Avcodec version: %d.%d\n",
		LIBAVCODEC_VERSION_MAJOR, LIBAVCODEC_VERSION_MINOR);
	LOG("(encode:args) Parsing complete, values:\nvcodec: (%s:%f "
		"fps @ %d %s), acodec: (%s:%d rate %d %s), container: (%s)\n",
		vck?vck:"default",  fps, vbr, vbr <= 10 ? "qual.lvl" : "b/s",
		ack?ack:"default", samplerate, abr, abr <= 10 ? "qual.lvl" : "b/s",
		cont?cont:"default");

/* overrides some of the other options to provide RDP output etc. */
	if (cont && strcmp(cont, "stream") == 0){
		avformat_network_init();
		stream_outp = true;
		cont = "stream";

		LOG("(encode) enabled streaming output\n");
		if (!arg_lookup(args, "streamdst", 0, &streamdst) ||
			strncmp("rtmp://", streamdst, 7) != 0){
			LOG("(encode:args) Streaming requested, but no "
				"valid streamdst set, giving up.\n");
			return false;
		}
	}

	struct codec_ent muxer = encode_getcontainer(cont,
		recctx.lastfd, streamdst);
	struct codec_ent video = encode_getvcodec(vck,
		muxer.storage.container.format->flags);
	struct codec_ent audio = encode_getacodec(ack,
		muxer.storage.container.format->flags);

	if (!video.storage.container.context){
		LOG("(encode) No valid output container found, aborting.\n");
		return false;
	}

	if (!video.storage.video.codec && !audio.storage.audio.codec){
		LOG("(encode) No valid video or audio setup found, aborting.\n");
		return false;
	}

	if (video.storage.video.codec){
		if ( video.setup.video(&video, desw, desh, fps, vbr, stream_outp) ){
			recctx.encvbuf_sz = desw * desh * bpp;
			recctx.bpp = bpp;
			recctx.encvbuf = av_malloc(recctx.encvbuf_sz);
			recctx.vstream=avformat_new_stream(muxer.storage.container.context,NULL);
			recctx.vcodec = video.storage.video.codec;
			recctx.vcontext= video.storage.video.context;
			recctx.pframe = video.storage.video.pframe;

			recctx.vstream->codec = recctx.vcontext;
			recctx.fps = fps;
			LOG("(encode) Video output stream: %d x %d %f fps\n", desw, desh, fps);
		}
	}

	if (!noaudio && video.storage.audio.codec){
		if ( audio.setup.audio(&audio, channels, samplerate, abr) ){
			recctx.encabuf_sz = recctx.shmcont.addr->abufsize * 2;
			recctx.encabuf_ofs = 0;
			recctx.encabuf = av_malloc(recctx.encabuf_sz);

			recctx.astream=avformat_new_stream(muxer.storage.container.context,NULL);
			recctx.acontext = audio.storage.audio.context;
			recctx.acodec = audio.storage.audio.codec;
			recctx.astream->codec = recctx.acontext;

/* feeding audio encoder by this much each time,
 * frame_size = number of samples per frame, might need to supply the
 * encoder with a fixed amount, each sample covers n channels.
 * aframe_sz is based on S16LE 2ch stereo as this is aligned to the INPUT data,
 * for float conversion, we need to double afterwards
 */

			if ( (recctx.acodec->capabilities & CODEC_CAP_VARIABLE_FRAME_SIZE) > 0){
				recctx.aframe_smplcnt = recctx.acontext->frame_size ?
					recctx.acontext->frame_size : round( samplerate / fps );
			}
			else {
				recctx.aframe_smplcnt = recctx.acontext->frame_size;
			}

			recctx.aframe_insz = recctx.aframe_smplcnt *
				ARCAN_SHMIF_ACHANNELS * sizeof(uint16_t);
			recctx.aframe_sz = recctx.aframe_smplcnt * ARCAN_SHMIF_ACHANNELS *
				av_get_bytes_per_sample(recctx.acontext->sample_fmt);
			LOG("(encode) audio: bytes per sample: %d, samples per frame: %d\n",
				av_get_bytes_per_sample( recctx.acontext->sample_fmt ),
			 	recctx.aframe_smplcnt);
		}
	}

/* lastly, now that all streams are added, write the header */
	recctx.fcontext = muxer.storage.container.context;
	if (!muxer.setup.muxer(&muxer)){
		LOG("(encode) muxer setupa failed, giving up.\n");
		return false;
	}

	if (presilence > 0 && recctx.acontext)
	{
		 presilence *= (float)ARCAN_SHMIF_SAMPLERATE / 1000.0;
		 if (presilence > recctx.encabuf_sz >> 2)
			 presilence = recctx.encabuf_sz >> 2;
			recctx.silence_samples = presilence;
	}

	return true;
}

static void dump_help()
{
	fprintf(stdout, "afsrv_encode, feature status: vnc "
#ifdef HAVE_VNCSERVER
"(enabled)"
#else
"(disabled)"
#endif
	"\n");
	fprintf(stdout, "Encode - frameserver is not currently supported "
		" in non-authorative mode, this frameserver will be spawned on "
		" demand by the main arcan process.\n");
}

int afsrv_encode(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	if (!args || !cont){
		dump_help();
		return EXIT_FAILURE;
	}

	recctx.shmcont = *cont;

	const char* argval;
	if (arg_lookup(args, "protocol", 0, &argval)){

#ifdef HAVE_VNCSERVER
		if (strcmp(argval, "vnc") == 0){
			vnc_serv_run(args, recctx.shmcont);
			return EXIT_SUCCESS;
		}
#endif

#ifdef HAVE_OCR
		if (strcmp(argval, "ocr") == 0){
			ocr_serv_run(args, recctx.shmcont);
			return EXIT_SUCCESS;
		}
#endif

		LOG("unsupported encoding protocol (%s) specified, giving up.\n", argval);
		return EXIT_FAILURE;
	}

	bool firstframe = false;

	recctx.lastfd = -1;

	while (true){
/* fail here means there's something wrong with
 * frameserver - main app connection */
		arcan_event ev;
		if (!arcan_shmif_wait(&recctx.shmcont, &ev))
			break;

		if (ev.category == EVENT_TARGET){
			switch (ev.tgt.kind){
/* nothing happens until the first FDtransfer, and consequtive ones should
 * really only be "useful" in streaming situations, and perhaps not even there,
 * so consider that scenario untested */
			case TARGET_COMMAND_STORE:
				recctx.lastfd = dup(ev.tgt.ioevs[0].iv);
				LOG("received file-descriptor, setting up encoder.\n");
				atexit(encoder_atexit);
				if (!setup_ffmpeg_encode(args, recctx.shmcont.addr->w,
					recctx.shmcont.addr->h))
					return EXIT_FAILURE;
				else{
					recctx.ccontext   = sws_getContext(
						recctx.shmcont.addr->w, recctx.shmcont.addr->h, AV_PIX_FMT_RGBA,
						recctx.shmcont.addr->w, recctx.shmcont.addr->h, AV_PIX_FMT_YUV420P,
						SWS_FAST_BILINEAR, NULL, NULL, NULL
					);
				}
			break;

/* the atexit handler flushes stream buffers and finalizes output headers */
			case TARGET_COMMAND_EXIT:
				LOG("(encode) parent requested termination, quitting.\n");
				return EXIT_SUCCESS;
			break;

			case TARGET_COMMAND_AUDDELAY:
				LOG("(encode) adjust audio buffering, %d milliseconds.\n",
					ev.tgt.ioevs[0].iv);
				recctx.silence_samples += (double)
					(ARCAN_SHMIF_SAMPLERATE / 1000.0) * ev.tgt.ioevs[0].iv;
			break;

			case TARGET_COMMAND_STEPFRAME:
				if (!firstframe){
					firstframe = true;
					recctx.starttime = arcan_timemillis();
				}

				while(!recctx.shmcont.addr->vready){
				}
				arcan_frameserver_stepframe();
			break;

			default:
				return EXIT_SUCCESS;
			}
		}
	}

	return EXIT_SUCCESS;
}
