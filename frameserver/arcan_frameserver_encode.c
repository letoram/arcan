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
#include "arcan_frameserver_encode.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

struct {
	struct frameserver_shmcont shmcont;
	
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;
	
	struct SwsContext* ccontext;
	AVFormatContext* fcontext;
	AVCodecContext* acontext;
	AVCodecContext* vcontext;
	AVCodec* vcodec;
	AVCodec* acodec;
	AVStream* astream;
	AVStream* vstream;
	AVPacket packet;
	AVFrame* pframe;

	bool extcc;

	int vid; /* selected video-stream */
	int aid; /* Selected audio-stream */

/* intermediate storage when it can't be avoided */
	int16_t* encabuf;
	size_t encabuf_sz;

	uint8_t* encvbuf;
	size_t encvbuf_sz;
	
/* precalc dstptrs into shm */
	uint8_t* vidp, (* audp);

/* sent from parent */
	file_handle lastfd;

} ffmpegctx = {0};

/* there's exactly one video frame to encode, and stuff as much audio into it as possible */
void arcan_frameserver_stepframe(unsigned long frameno, bool flush)
{
	ssize_t rs = -1;
/* TODO:
 * if astream open and abuf, flush abuf into audio codec, feed both into muxer */
	uint8_t* srcpl[4] = {ffmpegctx.vidp, NULL, NULL, NULL};
	int srcstr[4] = {0, 0, 0, 0};
	srcstr[0] = ffmpegctx.vcontext->width * 4;

	int rv = sws_scale(ffmpegctx.ccontext, (const uint8_t* const*) srcpl, srcstr, 0, ffmpegctx.vcontext->height, ffmpegctx.pframe->data, ffmpegctx.pframe->linesize); 

	if (flush){
		rs = avcodec_encode_video(ffmpegctx.vcontext, ffmpegctx.encvbuf, ffmpegctx.encvbuf_sz, ffmpegctx.pframe);
		frameserver_dumprawfile_handle(ffmpegctx.encvbuf, rs != -1 ? rs : 0, ffmpegctx.lastfd, true);
	} else {
		rs = avcodec_encode_video(ffmpegctx.vcontext, ffmpegctx.encvbuf, ffmpegctx.encvbuf_sz, ffmpegctx.pframe);
		if (-1 != rs)
			frameserver_dumprawfile_handle(ffmpegctx.encvbuf, rs, ffmpegctx.lastfd, false);
	}

	arcan_sem_post(ffmpegctx.shmcont.vsem);
}

static bool setup_ffmpeg_encode(const char* resource)
{
	struct frameserver_shmpage* shared = ffmpegctx.shmcont.addr;
	
	static bool initialized = false;
	if (initialized)
		return true;

/* codec stdvals */
	unsigned vbr = 400000;
	struct AVRational timebase = {1, 25};
	unsigned gop = 10;
/* decode encoding options from the resourcestr */

/* tend to be among the color formats codec people mess up the least */
	enum PixelFormat c_pix_fmt = PIX_FMT_YUV420P;

	
	frameserver_shmpage_calcofs(shared, &(ffmpegctx.vidp), &(ffmpegctx.audp) );
	avcodec_register_all();

/* unless the caller has explicitly requested something else */
	ffmpegctx.vcodec = avcodec_find_encoder(CODEC_ID_H264);
	
	if (!ffmpegctx.vcodec){
		LOG("arcan_frameserver(encode) -- no h264 support found, trying mpeg1video video.\n");
		ffmpegctx.vcodec = avcodec_find_encoder(CODEC_ID_MPEG1VIDEO);
	}
	
/* fallback to the lossless RLEish "almost always built in" codec */
	if (!ffmpegctx.vcodec){
		LOG("arcan_frameserver(encode) -- no FLV1 support found, trying mpeg1video.\n");
		ffmpegctx.vcodec = avcodec_find_encoder(CODEC_ID_RAWVIDEO); 
	}

	if (!ffmpegctx.vcodec){
		LOG("arcan_frameserver(encode) -- no suitable codec found, aborting.\n");
		return false;
	}
	
	
	
	AVCodecContext* ctx = avcodec_alloc_context();
	
	ctx->bit_rate = vbr;
	ctx->pix_fmt = c_pix_fmt;
	ctx->gop_size = gop;
	ctx->time_base = timebase;
	ctx->width = shared->w;
	ctx->height = shared->h;
	
	ffmpegctx.vcontext = ctx;
	
	if (avcodec_open2(ffmpegctx.vcontext, ffmpegctx.vcodec, NULL) < 0){
		LOG("arcan_frameserver_ffmpeg_encode() -- video codec open failed.\n");
		return false;
	}

/* default to YUV420P, so then we need this framelayout */
	size_t base_sz = shared->w * shared->h;
	ffmpegctx.pframe = avcodec_alloc_frame();
	ffmpegctx.pframe->data[0] = malloc( (base_sz * 3) / 2);
	ffmpegctx.pframe->data[1] = ffmpegctx.pframe->data[0] + base_sz;
	ffmpegctx.pframe->data[2] = ffmpegctx.pframe->data[1] + base_sz / 4;
	ffmpegctx.pframe->linesize[0] = shared->w;
	ffmpegctx.pframe->linesize[1] = shared->w / 2;
	ffmpegctx.pframe->linesize[2] = shared->w / 2;

/* larger than this and we have a really crap codec ;-) */
	ffmpegctx.encvbuf_sz = 4 * 1024 * 1024;
	ffmpegctx.encvbuf    = malloc(ffmpegctx.encvbuf_sz);
	
	ffmpegctx.ccontext = sws_getContext(ffmpegctx.vcontext->width, ffmpegctx.vcontext->height, PIX_FMT_RGBA, ffmpegctx.vcontext->width,
		ffmpegctx.vcontext->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);

/* signal that we are ready to receive */
	arcan_sem_post(ffmpegctx.shmcont.vsem);

	initialized = true;
	return true;
}

void arcan_frameserver_ffmpeg_encode(const char* resource, const char* keyfile)
{
/* setup shmpage etc. resolution etc. is already in place thanks to the parent */
	ffmpegctx.shmcont = frameserver_getshm(keyfile, true);
	struct frameserver_shmpage* shared = ffmpegctx.shmcont.addr;
	frameserver_shmpage_setevqs(ffmpegctx.shmcont.addr, ffmpegctx.shmcont.esem, &(ffmpegctx.inevq), &(ffmpegctx.outevq), false); 
	ffmpegctx.lastfd = BADFD;

/* main event loop */
	while (true){
		arcan_event* ev = arcan_event_poll(&ffmpegctx.inevq);

		if (ev){
			LOG("kind: %d\n", ev->kind);
			
			switch (ev->kind){
				case TARGET_COMMAND_FDTRANSFER:
					LOG("fdtransfer!\n");
					if (ffmpegctx.lastfd != BADFD)
						arcan_frameserver_stepframe(0, true); /* flush */
						
					ffmpegctx.lastfd = frameserver_readhandle(ev);
					LOG("got fd: %d\n", ffmpegctx.lastfd);
					if (!setup_ffmpeg_encode(resource))
						goto cleanup;
					
				break;
				case TARGET_COMMAND_STEPFRAME: 
					if (ffmpegctx.lastfd != BADFD)
						arcan_frameserver_stepframe(ev->data.target.ioevs[0], false);
				break;
				case TARGET_COMMAND_STORE: 
					goto cleanup; 
				break;
			}
		}

		frameserver_delay(1);
	}

cleanup:
	return;
}

