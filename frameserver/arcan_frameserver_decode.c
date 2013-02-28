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
#include "./graphing/net_graph.h"

#define AUD_VIS_HRES 512
#define AUD_VIS_VRES 256

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_encode.h"

/* LibFFMPEG
 * A possible option for future versions not constrained to a single arcan_frameserver,
 * is to make this into a small:ish patch for ffplay.c instead rather than maintaining a separate
 * player as is the case now */
#include <libavcodec/avcodec.h>
#include <libavutil/audioconvert.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavdevice/avdevice.h>

static void flush_eventq();

struct {
	struct frameserver_shmcont shmcont;
	
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;
	
	struct SwsContext* ccontext;
	struct SwrContext* rcontext;

	AVFormatContext* fcontext;
	AVCodecContext* acontext;
	AVCodecContext* vcontext;
	AVCodec* vcodec;
	AVCodec* acodec;
	AVStream* astream;
	AVStream* vstream;
	AVPacket packet;
	AVFrame* pframe, (* aframe);

	struct graph_context* graphing;
	int graphmode;
	
	int vid; /* selected video-stream */
	int aid; /* Selected audio-stream */

	int height;
	int width;
	int bpp;

	uint16_t samplerate;
	uint16_t channels;

	uint8_t* video_buf;
	uint32_t c_video_buf;
	
/* precalc dstptrs into shm */
	uint8_t* vidp, (* audp);

} decctx = {0};

const int audio_vis_width  = AUD_VIS_HRES;
const int audio_vis_height = AUD_VIS_VRES;

static void interleave_pict(uint8_t* buf, uint32_t size, AVFrame* frame, uint16_t width, uint16_t height, enum PixelFormat pfmt);

static inline void synch_audio()
{
	decctx.shmcont.addr->aready = true;
	frameserver_semcheck( decctx.shmcont.asem, -1);
	decctx.shmcont.addr->abufused = 0;
}

/* decode as much into our shared audio buffer as possible,
 * when it's full OR we switch to video frames, synch the audio */
static bool decode_aframe()
{
	static char* afr_sconv = NULL;
	static size_t afr_sconv_sz = 0;
	
	AVPacket cpkg = {
		.size = decctx.packet.size,
		.data = decctx.packet.data
	};

	int got_frame = 1;

	while (cpkg.size > 0) {
		uint32_t ofs = 0;
		avcodec_get_frame_defaults(decctx.aframe);
		int nts = avcodec_decode_audio4(decctx.acontext, decctx.aframe, &got_frame, &cpkg);

		if (nts == -1)
			return false;

		cpkg.size -= nts;
		cpkg.data += nts;

		if (got_frame){
			int plane_size;
			ssize_t ds = av_samples_get_buffer_size(&plane_size,
				decctx.acontext->channels, decctx.aframe->nb_samples, decctx.acontext->sample_fmt, 1);

/* skip packets with broken sample formats (shouldn't happen) */
			if (ds < 0)
				continue;
	
			int64_t dlayout = (decctx.aframe->channel_layout && decctx.aframe->channels == av_get_channel_layout_nb_channels(decctx.aframe->channel_layout)) ?
				decctx.aframe->channel_layout : av_get_default_channel_layout(decctx.aframe->channels);

/* should we resample? */
				if (decctx.aframe->format != AV_SAMPLE_FMT_S16 || decctx.aframe->channels != SHMPAGE_ACHANNELCOUNT || decctx.aframe->sample_rate != SHMPAGE_SAMPLERATE){
					uint8_t* outb[] = {decctx.audp, NULL};
					unsigned nsamples = (unsigned)(SHMPAGE_AUDIOBUF_SIZE - decctx.shmcont.addr->abufused) >> 2;
					outb[0] += decctx.shmcont.addr->abufused;

					if (!decctx.rcontext){
						decctx.rcontext = swr_alloc_set_opts(decctx.rcontext, AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_S16, SHMPAGE_SAMPLERATE,
							dlayout, decctx.aframe->format, decctx.aframe->sample_rate, 0, NULL);
						swr_init(decctx.rcontext);
						LOG("(decode) resampler initialized, (%d) => (%d)\n", decctx.aframe->sample_rate, SHMPAGE_SAMPLERATE);
					}
	
					int rc = swr_convert(decctx.rcontext, outb, nsamples, (const uint8_t**) decctx.aframe->extended_data, decctx.aframe->nb_samples);
					if (-1 == rc)
						LOG("(decode) swr_convert failed\n");

					if (rc == nsamples){
						LOG("(decode) resample buffer overflow\n");
						swr_init(decctx.rcontext);
					}

					decctx.shmcont.addr->abufused += rc << 2;
				} else{
					uint8_t* ofbuf = decctx.aframe->extended_data[0];
					uint32_t* abufused = &decctx.shmcont.addr->abufused;
					size_t ntc;

/* flush the entire buffer to parent before continuing */
					do {
						ntc = plane_size > SHMPAGE_AUDIOBUF_SIZE - *abufused ?
						SHMPAGE_AUDIOBUF_SIZE - *abufused : plane_size;

						memcpy(&decctx.audp[*abufused], ofbuf, ntc);
						*abufused += ntc;
						plane_size -= ntc;
						ofbuf += ntc;

						if (*abufused == SHMPAGE_AUDIOBUF_SIZE)
							synch_audio();

					} while (plane_size > 0);
				}
			;
		}
	}

	return true;
}

/* note, if shared + vbufofs is aligned to ffmpeg standards, we could sws_scale directly to it */
static bool decode_vframe()
{
	int complete_frame = 0;

	avcodec_decode_video2(decctx.vcontext, decctx.pframe, &complete_frame, &(decctx.packet));
	if (complete_frame) {
		uint8_t* dstpl[4] = {NULL, NULL, NULL, NULL};
		int dststr[4] = {0, 0, 0, 0};
		dststr[0] =decctx.width * decctx.bpp;
		dstpl[0] = decctx.video_buf;
		if (!decctx.ccontext) {
			decctx.ccontext = sws_getContext(decctx.vcontext->width, decctx.vcontext->height, decctx.vcontext->pix_fmt,
				decctx.vcontext->width, decctx.vcontext->height, PIX_FMT_BGR32, SWS_FAST_BILINEAR, NULL, NULL, NULL);
		}

		sws_scale(decctx.ccontext, (const uint8_t* const*) decctx.pframe->data, decctx.pframe->linesize, 0, decctx.vcontext->height, dstpl, dststr);

/* SHM-CHG-PT */
		decctx.shmcont.addr->vpts = (decctx.packet.dts != AV_NOPTS_VALUE ? decctx.packet.dts : 0) * av_q2d(decctx.vstream->time_base) * 1000.0;
		memcpy(decctx.vidp, decctx.video_buf, decctx.c_video_buf);

/* parent will check vready, then set to false and post */
		decctx.shmcont.addr->vready = true;
		frameserver_semcheck( decctx.shmcont.vsem, -1);
	}

	return true;
}

bool ffmpeg_decode()
{
	bool fstatus = true;
	/* Main Decoding sequence */
	while (fstatus &&
		av_read_frame(decctx.fcontext, &decctx.packet) >= 0) {

/* got a videoframe */
		if (decctx.packet.stream_index == decctx.vid){
			fstatus = decode_vframe();
		}

/* or audioframe, not that currently both audio and video synch separately */
		else if (decctx.packet.stream_index == decctx.aid){
			fstatus = decode_aframe();
			if (decctx.shmcont.addr->abufused)
				synch_audio();
		}

		av_free_packet(&decctx.packet);
		flush_eventq();
	}

	return fstatus;
}

static void ffmpeg_cleanup()
{
	free(decctx.video_buf);
	decctx.video_buf = NULL;
	
	av_free(decctx.pframe);
	decctx.pframe = NULL;
	
	av_free(decctx.aframe);
	decctx.aframe = NULL;
}

static bool ffmpeg_preload(const char* fname, AVInputFormat* iformat, AVDictionary** opts)
{
	memset(&decctx, 0, sizeof(decctx)); 

	int errc = avformat_open_input(&decctx.fcontext, fname, iformat, NULL);
	if (0 != errc || !decctx.fcontext)
		return false;

	errc = avformat_find_stream_info(decctx.fcontext, NULL);

	if (! (errc >= 0) )
		return NULL;

/* locate streams and codecs */
	int vid,aid;

	vid = aid = decctx.vid = decctx.aid = -1;

/* scan through all video streams, grab the first one,
 * find a decoder for it, extract resolution etc. */
	for (int i = 0; i < decctx.fcontext->nb_streams && (vid == -1 || aid == -1); i++)
		if (decctx.fcontext->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO && vid == -1) {
			decctx.vid = vid = i;
			decctx.vcontext  = decctx.fcontext->streams[vid]->codec;
			decctx.vcodec    = avcodec_find_decoder(decctx.vcontext->codec_id);
			decctx.vstream   = decctx.fcontext->streams[vid];
			avcodec_open2(decctx.vcontext, decctx.vcodec, opts);

			if (decctx.vcontext) {
				decctx.width  = decctx.vcontext->width;
				decctx.bpp    = 4;
				decctx.height = decctx.vcontext->height;
/* dts + dimensions */
				decctx.c_video_buf = (decctx.vcontext->width * decctx.vcontext->height * decctx.bpp);
				decctx.video_buf   = (uint8_t*) av_malloc(decctx.c_video_buf);
			}
		}
		else if (decctx.fcontext->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO && aid == -1) {
			decctx.aid      = aid = i;
			decctx.astream  = decctx.fcontext->streams[aid];
			decctx.acontext = decctx.fcontext->streams[aid]->codec;
			decctx.acodec   = avcodec_find_decoder(decctx.acontext->codec_id);
			avcodec_open2(decctx.acontext, decctx.acodec, opts);

/* weak assumption that we always have 2 channels, but the frameserver interface is this simplistic atm. */
			decctx.channels   = 2;
			decctx.samplerate = decctx.acontext->sample_rate;
		}

	decctx.pframe = avcodec_alloc_frame();
	decctx.aframe = avcodec_alloc_frame();

	return true;
}

#ifndef _WIN32
#include <sys/types.h>
#include <sys/stat.h>
static const char* probe_vidcap(signed prefind, AVInputFormat** dst)
{
	char arg[16];
	struct stat fs;

	for (int i = prefind; i >= 0; i--){
		snprintf(arg, sizeof(arg)-1, "/dev/video%d", i);
		if (stat(arg, &fs) == 0){
			*dst = av_find_input_format("video4linux2");
			return strdup(arg);
		}
	}

	*dst = NULL;
	return NULL;
}
#else
/* for windows, the suggested approach nowadays isn't vfwcap but dshow,
 * the problem is that we both need to be able to probe and look for a video device
 * and this enumeration then requires bidirectional communication with the parent */
static const char* probe_vidcap(signed prefind, AVInputFormat** dst)
{
	char arg[16];
	
	snprintf(arg, sizeof(arg)-1, "%d", prefind);
	*dst = av_find_input_format("vfwcap");
	
	return strdup(arg);
}
#endif

static bool ffmpeg_vidcap(unsigned ind, int desw, int desh, float fps)
{
	AVDictionary* opts = NULL;
	AVInputFormat* format;
	char cbuf[32];

	avdevice_register_all();
	if (fps > 0.0){
		snprintf(cbuf, sizeof(cbuf), "%f", fps);
		av_dict_set(&opts, "framerate", cbuf, 0);
	}

	if (desw > 0 && desh > 0){
		snprintf(cbuf, sizeof(cbuf), "%dx%d", desw, desh);
		av_dict_set(&opts, "video_size", cbuf, 0);
	}
/* supported options: standard, channel, video_size, pixel_format, list_formats, framerate */

	LOG("(decode) scanning for capture device (requested: %dx%d @ %f fps)\n", desw, desh, fps);
	const char* fname = probe_vidcap(ind, &format);
	if (!fname || !format)
		return NULL;

	return ffmpeg_preload(fname, format, &opts);
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

static inline void targetev(arcan_event* ev)
{
	arcan_tgtevent* tgt = &ev->data.target;

	switch (ev->kind){
		case TARGET_COMMAND_GRAPHMODE:
			decctx.graphmode = tgt->ioevs[0].iv;
		break;

		default:
			arcan_warning("frameserver(decode), unknown target event (%d), ignored.\n", ev->kind);
	}
}

/* use labels etc. for trying to populate the context table */
/* we also process requests to save state, shutdown, reset, plug/unplug input, here */
static inline void flush_eventq(){
	 arcan_event* ev;
	 arcan_errc evstat;

	while ( (ev = arcan_event_poll(&decctx.inevq, &evstat)) && evstat == ARCAN_OK){
		switch (ev->category){
			case EVENT_IO: break;
			case EVENT_TARGET: targetev(ev); break;
		}
	}

}

void arcan_frameserver_ffmpeg_run(const char* resource, const char* keyfile)
{
	bool statusfl = false;
	struct arg_arr* args = arg_unpack(resource);
	struct frameserver_shmcont shms = frameserver_getshm(keyfile, true);
	
	av_register_all();

	do {
		const char* val;

/* special about stream devices is that we can specify external resources (e.g.
 * http://, rtmp:// etc. along with buffer dimensions */
		if (arg_lookup(args, "stream", 0, &val)){

		}
/* special about capture devices is that we can decide to only probe,
 * perform frameserver- side scaling (or provide hinting to device) */
		else if (arg_lookup(args, "capture", 0, &val)){
			unsigned devind = 0;
			int desw = 0, desh = 0;
			float fps = -1;

			if (arg_lookup(args, "device", 0, &val)){
				devind = strtoul(val, NULL, 10);
			}

			if (arg_lookup(args, "fps", 0, &val)){
				fps = strtof(val, NULL);
			}
			
			if (arg_lookup(args, "width", 0, &val)){
				desw = strtoul(val, NULL, 10);
				desw = (desw > 0 && desw < MAX_SHMWIDTH) ? desw : 0;
			}

			if (arg_lookup(args, "height", 0, &val)){
				desh = strtoul(val, NULL, 10);
				desh = (desh > 0 && desh < MAX_SHMHEIGHT) ? desh : 0;
			}
				
			statusfl = ffmpeg_vidcap(devind, desw, desh, fps);
		}
		else
/* as to not entirely break the API, we revert to default-treat resource as a filename */
			statusfl = ffmpeg_preload(resource, NULL, NULL);

		if (!statusfl)
			break;

/* take something by default so that we can still graph etc. */
		if (!decctx.vcontext){
			decctx.width  = audio_vis_height;
			decctx.height = audio_vis_width;
			decctx.bpp    = 4;
		}
		
/* initialize both semaphores to 0 => render frame (wait for parent to signal) => regain lock */
		decctx.shmcont = shms;
		frameserver_semcheck(decctx.shmcont.asem, -1);
		frameserver_semcheck(decctx.shmcont.vsem, -1);
		frameserver_shmpage_setevqs(decctx.shmcont.addr, decctx.shmcont.esem, &(decctx.inevq), &(decctx.outevq), false);
		if (!frameserver_shmpage_resize(&shms, decctx.width, decctx.height)){
			LOG("arcan_frameserver(decode) shmpage setup failed, requested: (%d x %d @ %d) aud(%d,%d)\n", decctx.width,
				decctx.height, decctx.bpp, decctx.channels, decctx.samplerate);
			return;
		}
		
		decctx.graphing = graphing_new(GRAPH_MANUAL, decctx.width, decctx.height, (uint32_t*) decctx.vidp);
		frameserver_shmpage_calcofs(shms.addr, &(decctx.vidp), &(decctx.audp) );

	} while (ffmpeg_decode() && decctx.shmcont.addr->loop);
}
