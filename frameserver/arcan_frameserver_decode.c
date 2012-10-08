#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_decode.h"

static void interleave_pict(uint8_t* buf, uint32_t size, AVFrame* frame, uint16_t width, uint16_t height, enum PixelFormat pfmt);

static void synch_audio(arcan_ffmpeg_context* ctx)
{
	ctx->shmcont.addr->aready = true;
	frameserver_semcheck( ctx->shmcont.asem, -1);
	ctx->shmcont.addr->abufused = 0;
}

/* decode as much into our shared audio buffer as possible,
 * when it's full OR we switch to video frames, synch the audio */
static bool decode_aframe(arcan_ffmpeg_context* ctx)
{
	AVPacket cpkg = {
		.size = ctx->packet.size,
		.data = ctx->packet.data
	};
  
	int got_frame = 1;
	
	
	while (cpkg.size > 0) {
		uint32_t ofs = 0;
		avcodec_get_frame_defaults(ctx->aframe);
		int nts = avcodec_decode_audio4(ctx->acontext, ctx->aframe, &got_frame, &cpkg);
	
		if (nts == -1)
			return false;
		
		cpkg.size -= nts;
		cpkg.data += nts;

		if (got_frame){
			int plane_size;
			bool planar = av_sample_fmt_is_planar(ctx->acontext->sample_fmt); 
			ssize_t ds = av_samples_get_buffer_size(&plane_size, ctx->acontext->channels, ctx->aframe->nb_samples, ctx->acontext->sample_fmt, 1);
			
			if (planar && ctx->acontext->channels > 1){
				LOG("arcan_frameserver(decode) -- unsupported planar audio format detected.\n");
			}
			else{
/* lock / synch before we send more data */
				if (ctx->shmcont.addr->abufused + plane_size > SHMPAGE_AUDIOBUF_SIZE)
					synch_audio(ctx);
				
				memcpy(ctx->audp + ctx->shmcont.addr->abufused, ctx->aframe->extended_data[0], plane_size);
				ctx->shmcont.addr->abufused += plane_size;
			}
			
		}
	}
	
	return true;
}

/* note, if shared + vbufofs is aligned to ffmpeg standards, we could sws_scale directly to it */
static bool decode_vframe(arcan_ffmpeg_context* ctx)
{
	int complete_frame = 0;

	avcodec_decode_video2(ctx->vcontext, ctx->pframe, &complete_frame, &(ctx->packet));
	if (complete_frame) {
		if (ctx->extcc)
			interleave_pict(ctx->video_buf, ctx->c_video_buf, ctx->pframe, ctx->vcontext->width, ctx->vcontext->height, ctx->vcontext->pix_fmt);
		else {
			uint8_t* dstpl[4] = {NULL, NULL, NULL, NULL};
			int dststr[4] = {0, 0, 0, 0};
			dststr[0] =ctx->width * ctx->bpp;
			dstpl[0] = ctx->video_buf;
			if (!ctx->ccontext) {
				ctx->ccontext = sws_getContext(ctx->vcontext->width, ctx->vcontext->height, ctx->vcontext->pix_fmt,
				                               ctx->vcontext->width, ctx->vcontext->height, PIX_FMT_BGR32, SWS_FAST_BILINEAR, NULL, NULL, NULL);
			}
			sws_scale(ctx->ccontext, (const uint8_t* const*) ctx->pframe->data, ctx->pframe->linesize, 0, ctx->vcontext->height, dstpl, dststr);
		}

/* SHM-CHG-PT */
		ctx->shmcont.addr->vpts = (ctx->packet.dts != AV_NOPTS_VALUE ? ctx->packet.dts : 0) * av_q2d(ctx->vstream->time_base) * 1000.0;
		memcpy(ctx->vidp, ctx->video_buf, ctx->c_video_buf);

/* parent will check vready, then set to false and post */
		ctx->shmcont.addr->vready = true;
		frameserver_semcheck( ctx->shmcont.vsem, -1);
	}

	return true;
}

bool ffmpeg_decode(arcan_ffmpeg_context* ctx)
{
	bool fstatus = true;
	/* Main Decoding sequence */
	while (fstatus &&
		av_read_frame(ctx->fcontext, &ctx->packet) >= 0) {

/* got a videoframe */
		if (ctx->packet.stream_index == ctx->vid){
			fstatus = decode_vframe(ctx);
		}

		else if (ctx->packet.stream_index == ctx->aid){
			fstatus = decode_aframe(ctx);
			if (ctx->shmcont.addr->abufused)
				synch_audio(ctx);
		}

		av_free_packet(&ctx->packet);
	}

	return fstatus;
}

void ffmpeg_cleanup(arcan_ffmpeg_context* ctx)
{
	if (ctx){
		free(ctx->video_buf);
		av_free(ctx->pframe);
		av_free(ctx->aframe);
	}
}


static arcan_ffmpeg_context* ffmpeg_preload(const char* fname, AVInputFormat* iformat)
{
	arcan_ffmpeg_context* dst = (arcan_ffmpeg_context*) calloc(sizeof(arcan_ffmpeg_context), 1);

	int errc = avformat_open_input(&dst->fcontext, fname, iformat, NULL);
	if (0 != errc || !dst->fcontext)
		return NULL;
	
	errc = avformat_find_stream_info(dst->fcontext, NULL);
	
	if (! (errc >= 0) )
		return NULL;
	
/* locate streams and codecs */
	int vid,aid;

	vid = aid = dst->vid = dst->aid = -1;

/* scan through all video streams, grab the first one,
 * find a decoder for it, extract resolution etc. */
	for (int i = 0; i < dst->fcontext->nb_streams && (vid == -1 || aid == -1); i++)
		if (dst->fcontext->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO && vid == -1) {
			dst->vid = vid = i;
			dst->vcontext  = dst->fcontext->streams[vid]->codec;
			dst->vcodec    = avcodec_find_decoder(dst->vcontext->codec_id);
			dst->vstream   = dst->fcontext->streams[vid];
			avcodec_open2(dst->vcontext, dst->vcodec, NULL);
			
			if (dst->vcontext) {
				dst->width  = dst->vcontext->width;
				dst->bpp    = 4;
				dst->height = dst->vcontext->height;
/* dts + dimensions */
				dst->c_video_buf = (dst->vcontext->width * dst->vcontext->height * dst->bpp);
				dst->video_buf   = (uint8_t*) av_malloc(dst->c_video_buf);
			}
		}
		else if (dst->fcontext->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO && aid == -1) {
			dst->aid      = aid = i;
			dst->astream  = dst->fcontext->streams[aid];
			dst->acontext = dst->fcontext->streams[aid]->codec;
			dst->acodec   = avcodec_find_decoder(dst->acontext->codec_id);
			avcodec_open(dst->acontext, dst->acodec);

/* weak assumption that we always have 2 channels, but the frameserver interface is this simplistic atm. */
			dst->channels   = 2;
			dst->samplerate = dst->acontext->sample_rate;
		}

	dst->pframe = avcodec_alloc_frame();
	dst->aframe = avcodec_alloc_frame();

	return dst;
}

#ifndef _WIN32
#include <sys/types.h>
#include <sys/stat.h>
static const char* probe_webcam(unsigned prefind)
{
	char arg[16];
	struct stat fs;
	
	for (int i = prefind; i >= 0; i--){
		snprintf(arg, sizeof(arg)-1, "/dev/video%d", i);
		if (stat(arg, &fs) == 0) 
			return strdup(arg);
	}
	return NULL;
}
#else
	
#endif
	
static arcan_ffmpeg_context* ffmpeg_webcam(unsigned ind, float fps, unsigned width, unsigned height)
{
	const char* fname = probe_webcam(ind);
	if (!fname)
		return NULL;
	
	avdevice_register_all();
	AVInputFormat* format = av_find_input_format("video4linux2");
	return format ? ffmpeg_preload(fname, format) : NULL;
}

static void interleave_pict(uint8_t* buf, uint32_t size, AVFrame* frame, uint16_t width, uint16_t height, enum PixelFormat pfmt)
{
	bool planar = (pfmt == PIX_FMT_YUV420P || pfmt == PIX_FMT_YUV422P || pfmt == PIX_FMT_YUV444P || pfmt == PIX_FMT_YUV411P);

	if (planar) { /* need to expand into an interleaved format */
		/* av_malloc (buf) guarantees alignment */
		uint32_t* dst = (uint32_t*) buf;

/* atm. just assuming plane1 = Y, plane2 = U, plane 3 = V and that correct linewidth / height is present */
		for (int row = 0; row < height; row++)
			for (int col = 0; col < width; col++) {
				uint8_t y = frame->data[0][row * frame->linesize[0] + col];
				uint8_t u = frame->data[1][(row/2) * frame->linesize[1] + (col / 2)];
				uint8_t v = frame->data[2][(row/2) * frame->linesize[2] + (col / 2)];

				*dst = 0xff | y << 24 | u << 16 | v << 8;
				dst++;
			}
	}
}

void arcan_frameserver_ffmpeg_run(const char* resource, const char* keyfile)
{
	arcan_ffmpeg_context* vidctx;
	struct frameserver_shmcont shms = frameserver_getshm(keyfile, true);
	av_register_all();

	do {
/* webcam:ind where ind is a hint to the probing function */
		if (strncmp(resource, "webcam", 6) == 0){
			unsigned devind = 0;
			char* ofs = index(resource, ':');
			if (ofs && (*++ofs)){
				unsigned ind = strtoul(ofs, NULL, 10);
				if (ind < 255)
					devind = ind;
			}
			
			vidctx = ffmpeg_webcam(devind, 30.0, 640, 480);
		} else {
			vidctx = ffmpeg_preload(resource, NULL);
		}
		
		if (!vidctx)
			break;

/* initialize both semaphores to 0 => render frame (wait for parent to signal) => regain lock */
		vidctx->shmcont = shms;
		frameserver_semcheck(vidctx->shmcont.asem, -1);
		frameserver_semcheck(vidctx->shmcont.vsem, -1);
	
		if (!frameserver_shmpage_resize(&shms, vidctx->width, vidctx->height, vidctx->bpp, vidctx->channels, vidctx->samplerate))
		arcan_fatal("arcan_frameserver_ffmpeg_run() -- setup of vid(%d x %d @ %d) aud(%d,%d) failed \n",
			vidctx->width,
			vidctx->height,
			vidctx->bpp,
			vidctx->channels,
			vidctx->samplerate
		);

		frameserver_shmpage_calcofs(shms.addr, &(vidctx->vidp), &(vidctx->audp) );
	
	} while (ffmpeg_decode(vidctx) && vidctx->shmcont.addr->loop);
}
