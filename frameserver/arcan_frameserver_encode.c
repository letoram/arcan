#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <assert.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_encode.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

/* although there's a libswresampler already "handy", speex is used 
 * (a) for the simple relief in not having to deal with more ffmpeg "APIs"
 * and (b) for future VoIP features */
#include <speex/speex_resampler.h>

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
	file_handle lastfd;        /* sent from parent */

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
	bool float_samples;
	uint8_t* encabuf;
	float* encfbuf;
	off_t encabuf_ofs;
	size_t encabuf_sz;
	
/* needed for encode_audio frame settings */
	int aframe_smplcnt;
	size_t aframe_sz;
	unsigned long aframe_cnt;

} ffmpegctx = {0};

static struct resampler* grab_resampler(arcan_aobj_id id, unsigned frequency, unsigned channels)
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
	res = *ip = malloc( sizeof(struct resampler) );
	res->next = NULL;

	int errc;
	res->resampler = speex_resampler_init(channels, frequency, ffmpegctx.acontext->sample_rate, 3, &errc);
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
	
	unsigned hdr[5] = {/* src */ 0, /* size_t */ 0, /* frequency */ 0, /* channels */ 0, 0/* 0xfeedface */};
	
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

			for (int i = 0; i < frame->nb_samples * 2; i++)
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

/* ahead by too much? give up */
	if (delta < -thresh)
		return;
	
/* running behind, need to repeat a frame */
	if ( delta > thresh )
		fc += 1 + floor( delta / mspf);
		
	if (fc > 1)
		LOG("behind, double frame: %d\n", fc);
	
	int rv = sws_scale(ffmpegctx.ccontext, (const uint8_t* const*) srcpl, srcstr, 0, 
		ffmpegctx.vcontext->height, ffmpegctx.pframe->data, ffmpegctx.pframe->linesize);

/* might repeat the number of frames in order to compensate for poor frame sampling alignment */
	while (fc--){
		AVCodecContext* ctx = ffmpegctx.vcontext;
		AVPacket pkt = {0};
		int got_outp = false;
		av_init_packet(&pkt);
		
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
		
		ffmpegctx.pframe->pts = ffmpegctx.framecount++;
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
		
	if (ffmpegctx.vstream){
//		LOG("vframe\n");
		encode_video(flush);
	}

/* acknowledge that a frame has been consumed, then return to polling events */
	arcan_sem_post(ffmpegctx.shmcont.vsem);
}

static void encoder_atexit()
{
	if (ffmpegctx.lastfd != BADFD){
		arcan_frameserver_stepframe(true);

		if (ffmpegctx.fcontext)
			av_write_trailer(ffmpegctx.fcontext);
	}
}

static void setup_videocodec(const char* req)
{
	if (req){
		ffmpegctx.vcodec = avcodec_find_encoder_by_name(req);
		if (!ffmpegctx.vcodec)
		LOG("arcan_frameserver(encode) -- requested codec (%s) not found, trying vp8 video.\n", req);
	}

	if (!ffmpegctx.vcodec)
		ffmpegctx.vcodec = avcodec_find_encoder(CODEC_ID_VP8);
	
	if (!ffmpegctx.vcodec){
		LOG("arcan_frameserver(encode) -- no vp8 support found, trying H264 video.\n");
		ffmpegctx.vcodec = avcodec_find_encoder(CODEC_ID_H264);
	}
	
	if (!ffmpegctx.vcodec){
		LOG("arcan_frameserver(encode) -- no h264 support found, trying FLV1 (lossless) video.\n");
		ffmpegctx.vcodec = avcodec_find_encoder(CODEC_ID_FLV1);
	}
	
/* fallback to the lossless RLEish "almost always built in" codec */
	if (!ffmpegctx.vcodec){
		LOG("arcan_frameserver(encode) -- no FLV1 support found, trying mpeg1video.\n");
		ffmpegctx.vcodec = avcodec_find_encoder(CODEC_ID_MPEG1VIDEO); 
	}

	if (!ffmpegctx.vcodec){
		LOG("arcan_frameserver(encode) -- no suitable video codec found, no video- stream will be stored.\n");
	}
}

/* should be replaced with a table of preferred codecs, and then if the sample_formats don't match,
 * disable in the table and retry */
static void setup_audiocodec(const char* req)
{
	ffmpegctx.acodec = avcodec_find_encoder_by_name(req);
	
	if (req){
		ffmpegctx.acodec = avcodec_find_encoder_by_name(req);
		if (!ffmpegctx.acodec)
			LOG("arcan_frameserver(encode) -- requested audio codec (%s) not found, trying OGG Vorbis.\n", req);
	}

/* CODEC_ID_VORBIS would resolve to the internal crappy vorbis implementation in ffmpeg, don't want that */
	if (!ffmpegctx.acodec)
		ffmpegctx.acodec = avcodec_find_encoder_by_name("libvorbis"); 
	
	if (!ffmpegctx.acodec){
		LOG("arcan_frameserver(encode) -- no Vorbis support found, trying FLAC.\n");
		ffmpegctx.acodec = avcodec_find_encoder(CODEC_ID_FLAC);
	}

	if (!ffmpegctx.acodec){
		LOG("arcan_frameserver(encode) -- no vorbis support found, trying raw (PCM/S16LE).\n");
		ffmpegctx.acodec = avcodec_find_encoder(CODEC_ID_PCM_S16LE);
	}
	
	if (!ffmpegctx.acodec)
		LOG("arcan_frameserver(encode) -- no suitable audio codec found, no audio- stream will be stored.\n");
	else {
		bool float_found = false, sint16_found = false;
		
		int i = 0;
		while(ffmpegctx.acodec->sample_fmts[i] != AV_SAMPLE_FMT_NONE){
			if (ffmpegctx.acodec->sample_fmts[i] == AV_SAMPLE_FMT_S16)
				sint16_found = true;
			else if (ffmpegctx.acodec->sample_fmts[i] == AV_SAMPLE_FMT_FLT)
				float_found = true;
			
			i++;
		}
		
		if (float_found == false && sint16_found == false){
			LOG("arcan-frameserver(encode) -- no compatible sample format found in audio codec, no audio- stream will be stored.\n");
		} 
		else if (float_found && sint16_found == false) 
			ffmpegctx.float_samples = true;
	}	
}

static void setup_container(const char* req)
{
	AVOutputFormat* fmt = NULL;
	
	if (req){
		fmt = av_guess_format(req, NULL, NULL);
		if (!fmt)
			LOG("arcan_frameserver(encode) -- requested container (%s) not found, trying Matroska (MKV).\n", req);
	}
	
	if (!fmt)
		fmt = av_guess_format("matroska", NULL, NULL);

	if (!fmt){
		fmt = av_guess_format("mp4", NULL, NULL);
		LOG("arcan_frameserver(encode) -- Matroska container not found, trying MP4.\n");
	}
	
	if (!fmt){
		LOG("arcan_frameserver(encode) -- MP4 container not found, trying AVI.\n");
		fmt = av_guess_format("avi", NULL, NULL);
	}
	
	if (!fmt)
		LOG("arcan_frameserver(encode) -- no suitable container format found, giving up.\n");
	else {
		char fdbuf[16];
		
		ffmpegctx.fcontext = avformat_alloc_context();
		ffmpegctx.fcontext->oformat = fmt;
		
		sprintf(fdbuf, "pipe:%d", ffmpegctx.lastfd);
		int rv = avio_open2(&ffmpegctx.fcontext->pb, fdbuf, AVIO_FLAG_WRITE, NULL, NULL);
		if (rv == 0){
			LOG("arcan_frameserver(encode) -- muxer output prepared.\n");
		}
		else {
			LOG("arcan_frameserver(encode) -- muxer output failed (%d).\n", rv);
			ffmpegctx.fcontext = NULL; /* give up */
		}
	}
}

static bool setup_ffmpeg_encode(const char* resource)
{
	struct frameserver_shmpage* shared = ffmpegctx.shmcont.addr;

	static bool initialized = false;
	if (!initialized){
		avcodec_register_all();
		av_register_all();
		initialized = true;
	}
	
/* codec stdvals */
	unsigned vbr = 720 * 1024;
	unsigned abr = 192 * 1024;
	unsigned afreq = 44100;
	float fps    = 25;
	unsigned gop = 10;
/* decode encoding options from the resourcestr * -l */
	char* base = strdup(resource);
	char* blockb = base;
	char* vck = NULL, (* ac) = NULL, (* cont) = NULL;

/* parse user args and override defaults */
	while (*blockb){
		blockb = (blockb = index(base, ':')) ? (*blockb = '\0', blockb) : base + strlen(base);

		char* splitp = index(base, '=');
		if (!splitp){
			LOG("arcan_frameserver(encode) -- couldn't parse resource (%s)\n", resource);
			break;
		}
		
		else {
			*splitp++ = '\0';
/* video bit-rate */
			LOG("check: %s, %s\n", base, splitp);
			if (strcmp(base, "vbitrate") == 0)
				vbr = strtoul(splitp, NULL, 10) * 1024;
			else if (strcmp(base, "vcodec") == 0)
/* videocodec */
				vck = splitp;
			else if (strcmp(base, "abitrate") == 0)
/* audio bit-rate */
				abr = strtoul(splitp, NULL, 10) * 1024;
			else if (strcmp(base, "acodec") == 0)
/* audiocodec */
				ac = splitp;
/* mux format */
			else if (strcmp(base, "container") == 0)
				cont = splitp;
			else if (strcmp(base, "samplerate") == 0)
/* audio samples per second */
				afreq = strtoul(splitp, NULL, 0);
			else if (strcmp(base, "fps") == 0)
/* videoframes per second */
				fps = strtof(splitp, NULL);	
			else
				LOG("arcan_frameserver(encode) -- parsing resource string, unknown base : %s\n", base);
		}
		
		blockb++; /* should now point to new base or NULL */
		base = blockb;
	}

/* sanity- check decoded values */
	if (fps < 4 || fps > 60){
			LOG("arcan_frameserver(encode:%s) -- bad framerate (fps) argument, defaulting to 25.0fps\n", resource);
			fps = 25;
	}
	
	LOG("arcan_frameserver(encode:args) -- Parsing complete, values:\nvcodec: (%s:%f fps @ %d b/s), acodec: (%s:%d rate %d b/s), container: (%s)\n",
			vck?vck:"default",  fps, vbr, ac?ac:"default", afreq, abr, cont?cont:"default");

	setup_videocodec(vck);
	setup_audiocodec(ac);
	setup_container(cont);

	if (ffmpegctx.fcontext == NULL || (!ffmpegctx.vcodec && !ffmpegctx.acodec)){
		return false;
	}

	int contextc = 0;

/* some feasible combination found, prepare memory page */
	frameserver_shmpage_calcofs(shared, &(ffmpegctx.vidp), &(ffmpegctx.audp) );
	
	if (ffmpegctx.vcodec){
/* tend to be among the color formats codec people mess up the least */
		enum PixelFormat c_pix_fmt = PIX_FMT_YUV420P;

		AVCodecContext* ctx = avcodec_alloc_context3(ffmpegctx.vcodec);
	
		ctx->bit_rate = vbr;
		ctx->pix_fmt = c_pix_fmt;
		ctx->gop_size = gop;
		ctx->time_base = av_d2q(1.0 / fps, 1000000);
		ffmpegctx.fps = fps;
		ctx->width = shared->storage.w;
		ctx->height = shared->storage.h;
	
		ffmpegctx.vcontext = ctx;
	
		if (avcodec_open2(ffmpegctx.vcontext, ffmpegctx.vcodec, NULL) < 0){
			LOG("arcan_frameserver_ffmpeg_encode() -- video codec open failed.\n");
			avcodec_close(ctx);
			ffmpegctx.vcodec = NULL;
		} else {
/* default to YUV420P, so then we need this framelayout */
			if (ffmpegctx.fcontext->oformat->flags & AVFMT_GLOBALHEADER)
				ctx->flags |= CODEC_FLAG_GLOBAL_HEADER;

			size_t base_sz = shared->storage.w * shared->storage.h;
			ffmpegctx.pframe = avcodec_alloc_frame();
			ffmpegctx.pframe->data[0] = malloc( (base_sz * 3) / 2);
			ffmpegctx.pframe->data[1] = ffmpegctx.pframe->data[0] + base_sz;
			ffmpegctx.pframe->data[2] = ffmpegctx.pframe->data[1] + base_sz / 4;
			ffmpegctx.pframe->linesize[0] = shared->storage.w;
			ffmpegctx.pframe->linesize[1] = shared->storage.w / 2;
			ffmpegctx.pframe->linesize[2] = shared->storage.w / 2;

/* larger than this and we have a really crap codec ;-) */
			ffmpegctx.encvbuf_sz = base_sz * 4;
			ffmpegctx.encvbuf    = malloc(ffmpegctx.encvbuf_sz);
	
			ffmpegctx.ccontext = sws_getContext(ffmpegctx.vcontext->width, ffmpegctx.vcontext->height, PIX_FMT_RGBA, ffmpegctx.vcontext->width,
				ffmpegctx.vcontext->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
			
/* attach to output container */
			ffmpegctx.vstream = av_new_stream(ffmpegctx.fcontext, contextc++);
			ffmpegctx.vstream->codec = ffmpegctx.vcontext;
		}
	}

	if (ffmpegctx.acodec){
		AVCodecContext* ctx = avcodec_alloc_context3(ffmpegctx.acodec);
		ffmpegctx.acontext = ctx;
		ctx->bit_rate    = 64000;
	
		ctx->channels    = 2;
		ctx->channel_layout = av_get_default_channel_layout(2);

		ctx->sample_rate = afreq;
		ctx->sample_fmt  = ffmpegctx.float_samples ? AV_SAMPLE_FMT_FLT : AV_SAMPLE_FMT_S16;
		ctx->time_base   = av_d2q(1.0 / (double)afreq, 1000000);
		
		if (ffmpegctx.fcontext->oformat->flags & AVFMT_GLOBALHEADER)
				ctx->flags |= CODEC_FLAG_GLOBAL_HEADER;

		if (avcodec_open2(ffmpegctx.acontext, ffmpegctx.acodec, NULL) < 0){
			LOG("arcan_frameserver_ffmpeg_encode() -- audio codec open failed.\n");
			avcodec_close(ctx);
			ffmpegctx.acodec = NULL;
		} 
		else{
		
/* always used for resampling etc */
			ffmpegctx.encabuf_sz  = SHMPAGE_AUDIOBUF_SIZE * 2;
			ffmpegctx.encabuf_ofs = 0; 
			ffmpegctx.encabuf     = malloc(ffmpegctx.encabuf_sz);
			
/* feeding audio encoder by this much each time,
 * frame_size = number of samples per frame, might need to supply the encoder with a fixed amount, each sample covers n channels. */
			ffmpegctx.aframe_smplcnt = (ctx->codec->capabilities & CODEC_CAP_VARIABLE_FRAME_SIZE) > 0 ? ffmpegctx.acontext->sample_rate / ffmpegctx.fps : ctx->frame_size;
			ffmpegctx.aframe_sz = 4 * ffmpegctx.aframe_smplcnt; 
/* aframe_sz is based on S16LE 2ch stereo as this is aligned to the INPUT data, for float conversion, we need to double afterwards */
			
/* another intermediate buffer for float- based samples */
			if (ctx->sample_fmt == AV_SAMPLE_FMT_FLT)
				ffmpegctx.encfbuf = malloc( ffmpegctx.aframe_sz * 2);
			
			ffmpegctx.astream = av_new_stream(ffmpegctx.fcontext, contextc++);
			ffmpegctx.astream->codec = ffmpegctx.acontext;
		}
	}
	
/* setup container, we now have valid codecs, streams attached to the codecs and a container with the streams */
	if (ffmpegctx.fcontext){
		avformat_write_header(ffmpegctx.fcontext, NULL);
	}
	else {
			LOG("arcan_frameserver_ffmpeg_encode() -- no suitable output container, giving up.\n");
			return false;
	}
	
/* signal that we are ready to receive video frames */
	arcan_sem_post(ffmpegctx.shmcont.vsem);
	return true;
}

void arcan_frameserver_ffmpeg_encode(const char* resource, const char* keyfile)
{
/* setup shmpage etc. resolution etc. is already in place thanks to the parent */
	ffmpegctx.shmcont = frameserver_getshm(keyfile, true);
	struct frameserver_shmpage* shared = ffmpegctx.shmcont.addr;
	frameserver_shmpage_setevqs(ffmpegctx.shmcont.addr, ffmpegctx.shmcont.esem, &(ffmpegctx.inevq), &(ffmpegctx.outevq), false); 
	ffmpegctx.lastfd = BADFD;
	atexit(encoder_atexit);

	LOG("record session (%s) => (%s) setup\n", resource, keyfile);
	
/* main event loop */
	while (true){
		arcan_event* ev = arcan_event_poll(&ffmpegctx.inevq);

		if (ev){
			switch (ev->kind){
				case TARGET_COMMAND_FDTRANSFER:
					if (ffmpegctx.lastfd != BADFD)
						arcan_frameserver_stepframe(true); /* flush */
					
					ffmpegctx.lastframe = frameserver_timemillis();
					ffmpegctx.lastfd = frameserver_readhandle(ev);
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
