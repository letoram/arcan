#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <fft/kiss_fftr.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_decode.h"

#define AUD_VIS_HRES 2048 

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

	int vid; /* selected video-stream */
	int aid; /* Selected audio-stream */

/* for music- only playback, we can populate the video
 * channels with the samples + their FFT */
	bool fft_audio;
	kiss_fftr_cfg fft_state;
	uint32_t vfc;

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

static void interleave_pict(uint8_t* buf, uint32_t size, AVFrame* frame, 
	uint16_t width, uint16_t height, enum PixelFormat pfmt);

/* Convert the interleaved output audio buffer into n- videoframes,
 * packed planar with uint16_t samples in R,G (slightly wasteful but simple)
 * and their FFT version in the second row, as floats packed in RGBA),
 * generate PTS based on n samples processed 
 */
static void generate_frame()
{
	const int smpl_wndw = AUD_VIS_HRES * 2;
	static float smplbuf[AUD_VIS_HRES * 2];
	static kiss_fft_scalar fsmplbuf[AUD_VIS_HRES * 2];
	static kiss_fft_cpx foutsmplbuf[AUD_VIS_HRES * 2];

	static bool gotfft;
	static kiss_fftr_cfg kfft;

	if (!gotfft){
		kfft = kiss_fftr_alloc(smpl_wndw, false, NULL, NULL);
		gotfft = true;
	}

	static int smplc;
	static int vfc = 0;
	static double vptsc = 0;

	int16_t* basep = (uint16_t*) decctx.audp;
	int counter = decctx.shmcont.addr->abufused;

	while (counter){
/* could've split the window up into 
 * two functions and used the b and a channels */
		float lv = (*basep++) / 32767.0f;
		float rv = (*basep++) / 32767.0f;
		float smpl = (lv + rv) / 2.0f; 
		smplbuf[smplc] = smpl;

/* hann window float sample before FFT */ 
		float winv = 0.5f * ( 1.0f - cosf(2.0 * M_PI * smplc / (float) smpl_wndw));
		fsmplbuf[smplc] = smpl + 1.0 * winv;

		smplc++;
		counter -= 4; /* 4 bytes consumed */

		if (smplc == smpl_wndw){
			smplc = 0;

			uint8_t* base = decctx.vidp;
			kiss_fftr(kfft, fsmplbuf, foutsmplbuf);

/* store FFT output in dB scale */
			float low = 255.0f;
			float high = 0.0f;

			for (int j= 0; j < smpl_wndw / 2; j++)
			{
				float magnitude = sqrtf(foutsmplbuf[j].r * foutsmplbuf[j].r +
					foutsmplbuf[j].i * foutsmplbuf[j].i);
				fsmplbuf[j] = 10.0f * log10f(magnitude);
				if (fsmplbuf[j] < low)
					low = fsmplbuf[j];
				if (fsmplbuf[j] > high)
					high = fsmplbuf[j];	
			}

/* wasting a level just to get POT as the interface doesn't
 * support a 1D texture format */
			for (int j=0; j<smpl_wndw / 2; j++){
				*base++ = 0;
				*base++ = 0;
				*base++ = 0;
				*base++ = 0xff;
			}

/* pack in output image, smooth two audio samples */
			for (int j=0; j < smpl_wndw / 2; j++){
				*base++ = (1.0f + ((smplbuf[j * 2] + smplbuf[j * 2 + 1]) / 2.0)) / 2.0 * 255.0;
				*base++ = (fsmplbuf[j] / high) * 255.0;
				*base++ = 0x00;
				*base++ = 0xff;
			}

			decctx.shmcont.addr->vpts = vptsc;
			decctx.shmcont.addr->vready = true;
			frameserver_semcheck( decctx.shmcont.vsem, -1);
			vptsc += 1000.0f / ((double)(SHMPAGE_SAMPLERATE) / (double)smpl_wndw);
		}
	}
}

static inline void synch_audio()
{
	if (decctx.fft_audio)
		generate_frame();

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
	static AVFrame* aframe;

	if (!aframe)
		aframe = avcodec_alloc_frame();
	
	int got_frame = 1;

	uint32_t ofs = 0;
	int nts = avcodec_decode_audio4(decctx.acontext, aframe, 
		&got_frame, &decctx.packet);

	if (nts == -1)
		return false;

	if (got_frame){
		int plane_size;
		ssize_t ds = av_samples_get_buffer_size(&plane_size,
			decctx.acontext->channels, aframe->nb_samples, 
			decctx.acontext->sample_fmt, 1);

/* skip packets with broken sample formats (shouldn't happen) */
		if (ds < 0)
			return true;
	
		int64_t dlayout = (aframe->channel_layout && aframe->channels == 
			av_get_channel_layout_nb_channels(aframe->channel_layout)) ?
			aframe->channel_layout : av_get_default_channel_layout(aframe->channels);

/* should we resample? */
			if (aframe->format != AV_SAMPLE_FMT_S16 || aframe->channels !=
				SHMPAGE_ACHANNELCOUNT || aframe->sample_rate != SHMPAGE_SAMPLERATE){
				uint8_t* outb[] = {decctx.audp, NULL};
				unsigned nsamples = (unsigned)(SHMPAGE_AUDIOBUF_SIZE - 
					decctx.shmcont.addr->abufused) >> 2;
	
				outb[0] += decctx.shmcont.addr->abufused;

				if (!decctx.rcontext){
					decctx.rcontext = swr_alloc_set_opts(decctx.rcontext, 
						AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_S16, SHMPAGE_SAMPLERATE, 
						dlayout, aframe->format, aframe->sample_rate, 0, NULL);
	
					swr_init(decctx.rcontext);
					LOG("(decode) resampler initialized, (%d) => (%d)\n", 
						aframe->sample_rate, SHMPAGE_SAMPLERATE);
				}
	
				int rc = swr_convert(decctx.rcontext, outb, nsamples, (const uint8_t**) 
					aframe->extended_data, aframe->nb_samples);
				if (-1 == rc)
					LOG("(decode) swr_convert failed\n");

				if (rc == nsamples){
					LOG("(decode) resample buffer overflow\n");
					swr_init(decctx.rcontext);
				}

				decctx.shmcont.addr->abufused += rc << 2;
			} else{
				uint8_t* ofbuf = aframe->extended_data[0];
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

	return true;
}

/* note, if shared + vbufofs is aligned to ffmpeg standards, 
 * we could sws_scale directly to it */
static bool decode_vframe()
{
	int complete_frame = 0;
	static AVFrame* vframe;

	if (vframe == NULL)
		vframe = avcodec_alloc_frame();

	avcodec_decode_video2(decctx.vcontext, vframe, 
		&complete_frame, &decctx.packet);

	if (complete_frame) {
		uint8_t* dstpl[4] = {NULL, NULL, NULL, NULL};
		int dststr[4] = {0, 0, 0, 0};
		dststr[0] = decctx.width * decctx.bpp;
		dstpl[0] = decctx.video_buf;
		if (!decctx.ccontext) {
			decctx.ccontext = sws_getContext(decctx.vcontext->width, 
				decctx.vcontext->height, decctx.vcontext->pix_fmt,
				decctx.vcontext->width, decctx.vcontext->height, PIX_FMT_BGR32, 
					SWS_FAST_BILINEAR, NULL, NULL, NULL);
		}

		sws_scale(decctx.ccontext, (const uint8_t* const*) vframe->data, 
			vframe->linesize, 0, decctx.vcontext->height, dstpl, dststr);

/* SHM-CHG-PT */
		decctx.shmcont.addr->vpts = (decctx.packet.dts != AV_NOPTS_VALUE ? 
			decctx.packet.dts : 0) * av_q2d(decctx.vstream->time_base) * 1000.0;
		memcpy(decctx.vidp, decctx.video_buf, decctx.c_video_buf);

		decctx.shmcont.addr->vready = true;
		frameserver_semcheck( decctx.shmcont.vsem, -1);
	}
	else;

	return true;
}

bool ffmpeg_decode()
{
	bool fstatus = true;
	av_init_packet(&decctx.packet);
	decctx.packet.data = 0;
	decctx.packet.size = 0;

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

static bool ffmpeg_preload(const char* fname, AVInputFormat* iformat, 
	AVDictionary** opts, bool skipaud, bool skipvid)
{
	memset(&decctx, 0, sizeof(decctx)); 

	int errc = avformat_open_input(&decctx.fcontext, fname, iformat, NULL);
	if (0 != errc || !decctx.fcontext){
		LOG("(decode) avformat_open_input() couldn't open fcontext"
			"	for resource (%s)\n", fname);
		return false;
	}

	errc = avformat_find_stream_info(decctx.fcontext, NULL);

	if (! (errc >= 0) ){
		LOG("(decode) avformat_find_stream_info() didn't return"
			"	any useful data.\n");
		return NULL;
	}

/* locate streams and codecs */
	int vid,aid;

	vid = aid = decctx.vid = decctx.aid = -1;
	LOG("(decode) %d streams found in container.\n",decctx.fcontext->nb_streams);

/* scan through all video streams, grab the first one,
 * find a decoder for it, extract resolution etc. */
	for (int i = 0; i < decctx.fcontext->nb_streams && 
		(vid == -1 || aid == -1); i++)
		if (decctx.fcontext->streams[i]->codec->codec_type == 
			AVMEDIA_TYPE_VIDEO && vid == -1 && !skipvid) {
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
				decctx.c_video_buf = (decctx.vcontext->width * 
					decctx.vcontext->height * decctx.bpp);
				decctx.video_buf   = (uint8_t*) av_malloc(decctx.c_video_buf);
			}
		}
		else if (decctx.fcontext->streams[i]->codec->codec_type == 
			AVMEDIA_TYPE_AUDIO && aid == -1 && !skipaud) {
			decctx.aid      = aid = i;
			decctx.astream  = decctx.fcontext->streams[aid];
			decctx.acontext = decctx.fcontext->streams[aid]->codec;
			decctx.acodec   = avcodec_find_decoder(decctx.acontext->codec_id);
			avcodec_open2(decctx.acontext, decctx.acodec, opts);

/* weak assumption that we always have 2 channels, but the frameserver 
 * interface is this simplistic atm. */
			decctx.channels   = 2;
			decctx.samplerate = decctx.acontext->sample_rate;
		}

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
 * the problem is that we both need to be able to probe and look for a 
 * video device and this enumeration then requires bidirectional communication
 * with the parent, in a way frameserver_decode was not prepared for, so 
 * pending a larger refactoring, just hack it by index and vfw */
static const char* probe_vidcap(signed prefind, AVInputFormat** dst)
{
	char arg[16];
	if (prefind > 0) 
		prefind--;
	
	snprintf(arg, sizeof(arg)-1, "%d", prefind);
	*dst = av_find_input_format("vfwcap");
	LOG("(decode) win32:probe_vidcap, find input format yielded %" 
		PRIxPTR "\n", *dst);
	
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
/* supported options: standard, channel, video_size, pixel_format, 
 * list_formats, framerate */

	LOG("(decode) scanning for capture device (requested: %dx%d @ %f fps)\n",
		desw, desh, fps);
	const char* fname = probe_vidcap(ind, &format);
	if (!fname || !format)
		return NULL;

	return ffmpeg_preload(fname, format, &opts, false, false);
}

static void interleave_pict(uint8_t* buf, uint32_t size, AVFrame* frame, 
	uint16_t width, uint16_t height, enum PixelFormat pfmt)
{
	bool planar = (pfmt == PIX_FMT_YUV420P || pfmt == PIX_FMT_YUV422P || 
		pfmt == PIX_FMT_YUV444P || pfmt == PIX_FMT_YUV411P);

	if (planar) { /* need to expand into an interleaved format */
		/* av_malloc (buf) guarantees alignment */
		uint32_t* dst = (uint32_t*) buf;

/* atm. just assuming plane1 = Y, plane2 = U, plane 3 = V and that correct 
 * linewidth / height is present */
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
		break;

/* missing; seek, mapping graphmode to possible audiovis for 
 * FFT etc. */

		default:
			arcan_warning("frameserver(decode), unknown target event "
				"(%d), ignored.\n", ev->kind);
	}
}

/* use labels etc. for trying to populate the context table */
/* we also process requests to save state, shutdown, reset, 
 * plug/unplug input, here */
static inline void flush_eventq(){
	 arcan_event* ev;
	 arcan_errc evstat;

	while ( (ev = arcan_event_poll(&decctx.inevq, &evstat)) 
		&& evstat == ARCAN_OK){
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
		bool noaudio = false;
		bool novideo = false;

		if (arg_lookup(args, "noaudio", 0, &val)){
			noaudio = true;
		} else if (arg_lookup(args, "novideo", 0, &val))
			novideo = true;

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
		else if (arg_lookup(args, "file", 0, &val)){
			statusfl = ffmpeg_preload(val, NULL, NULL, noaudio, novideo);
		}
		else
/* as to not entirely break the API, we revert to default-treat 
 * resource as a filename */
			statusfl = ffmpeg_preload(resource, NULL, NULL, noaudio, novideo);

		if (!statusfl)
			break;

/* take something by default so that we can still graph etc. */
		if (!decctx.vcontext){
			decctx.width  = AUD_VIS_HRES;
			decctx.height = 2; 
			decctx.bpp    = 4;
			decctx.fft_audio = true;
		}
		
/* initialize both semaphores to 0 => render frame (wait for 
 * parent to signal) => regain lock */
		decctx.shmcont = shms;
		frameserver_semcheck(decctx.shmcont.asem, -1);
		frameserver_semcheck(decctx.shmcont.vsem, -1);
		frameserver_shmpage_setevqs(decctx.shmcont.addr, decctx.shmcont.esem, 
			&(decctx.inevq), &(decctx.outevq), false);

		if (!frameserver_shmpage_resize(&shms, decctx.width, decctx.height)){
			LOG("arcan_frameserver(decode) shmpage setup failed, "
				"requested: (%d x %d @ %d)	aud(%d,%d)\n", 
				decctx.width, decctx.height, decctx.bpp, 
				decctx.channels, decctx.samplerate);
			return;
		} 
	
		frameserver_shmpage_calcofs(shms.addr, &(decctx.vidp), &(decctx.audp) );
	} while (ffmpeg_decode() && decctx.shmcont.addr->loop);
}
