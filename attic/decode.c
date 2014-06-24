#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <fft/kiss_fftr.h>

#include <arcan_shmif.h>
#include "graphing/net_graph.h"

#include "frameserver.h"

#define AUD_VIS_HRES 2048
#define AUD_SYNC_THRESH 4096

#include <libavcodec/avcodec.h>
#include <libavutil/audioconvert.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavdevice/avdevice.h>

static void flush_eventq();

struct {
	struct arcan_shmif_cont shmcont;

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
	int64_t last_dts;

/* for music- only playback, we can populate the video
 * channels with samples + FFT */
	bool fft_audio;
	kiss_fftr_cfg fft_state;

	int height;
	int width;
	int bpp;

	uint16_t samplerate;
	uint16_t channels;

	uint8_t* video_buf;
	uint32_t c_video_buf;

/* debug visualization */
	struct graph_context* graphing;

/* precalc dstptrs into shm */
	uint8_t* vidp, (* audp);

} decctx = {0};

/*
 * Audio visualization,
 * just HANN -> FFT -> dB scale -> pack in 8-bit
 * could be used to push vocal input events to the
 * main engine with little extra work for singalong-
 * style controls
 */
static void generate_frame()
{
/* window size is twice the possible output,
 * since the FFT will be N/2 out */
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
	static double vptsc = 0;

	int16_t* basep = (int16_t*) decctx.audp;
	int counter = decctx.shmcont.addr->abufused;

	while (counter){
/* could've split the window up into
 * two functions and used the b and a channels
 * but little point atm. */
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
				*base++ = (1.0f + ((smplbuf[j * 2] +
					smplbuf[j * 2 + 1]) / 2.0)) / 2.0 * 255.0;
				*base++ = (fsmplbuf[j] / high) * 255.0;
				*base++ = 0x00;
				*base++ = 0xff;
			}

			decctx.shmcont.addr->vpts = vptsc;
			arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID);

			vptsc += 1000.0f / (
				(double)(ARCAN_SHMPAGE_SAMPLERATE) / (double)smpl_wndw);
		}
	}

	arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID);
}

/* decode as much into our shared audio buffer as possible,
 * when it's full OR we switch to video frames, synch the audio */
static bool decode_aframe()
{
	static AVFrame* aframe;

	if (!aframe)
		aframe = av_frame_alloc();

	int got_frame = 1;

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
			if (aframe->format != AV_SAMPLE_FMT_S16 ||
				aframe->channels != ARCAN_SHMPAGE_ACHANNELS ||
				aframe->sample_rate != ARCAN_SHMPAGE_SAMPLERATE){
				uint8_t* outb[] = {decctx.audp, NULL};
				unsigned nsamples = (unsigned)(ARCAN_SHMPAGE_AUDIOBUF_SZ -
					decctx.shmcont.addr->abufused) >> 2;

				outb[0] += decctx.shmcont.addr->abufused;

				if (!decctx.rcontext){
					decctx.rcontext = swr_alloc_set_opts(decctx.rcontext,
						AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_S16, ARCAN_SHMPAGE_SAMPLERATE,
						dlayout, aframe->format, aframe->sample_rate, 0, NULL);

					swr_init(decctx.rcontext);
					LOG("resampler initialized, (%d) => (%d)\n",
						aframe->sample_rate, ARCAN_SHMPAGE_SAMPLERATE);
				}

				int rc = swr_convert(decctx.rcontext, outb, nsamples, (const uint8_t**)
					aframe->extended_data, aframe->nb_samples);
				if (-1 == rc)
					LOG("swr_convert failed\n");

				if (rc == nsamples){
					LOG("resample buffer overflow\n");
					swr_init(decctx.rcontext);
				}

				decctx.shmcont.addr->abufused += rc << 2;
			} else{
				uint8_t* ofbuf = aframe->extended_data[0];
				uint32_t* abufused = &decctx.shmcont.addr->abufused;
				size_t ntc;

/* flush the entire buffer to parent before continuing */
				do {
					ntc = plane_size > ARCAN_SHMPAGE_AUDIOBUF_SZ - *abufused ?
					ARCAN_SHMPAGE_AUDIOBUF_SZ - *abufused : plane_size;

					memcpy(&decctx.audp[*abufused], ofbuf, ntc);
					*abufused += ntc;
					plane_size -= ntc;
					ofbuf += ntc;

				}
				while (plane_size > 0);
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
		vframe = av_frame_alloc();

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

		arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID);
	}
	else;

	return true;
}

void push_streamstatus()
{
	static int updatei;
	static unsigned int c;

/* don't update every frame, that's excessive */
	if (updatei > 0){
		updatei--;
		return;
	}

	updatei = 20;

	struct arcan_event status = {
			.category = EVENT_EXTERNAL,
			.kind = EVENT_EXTERNAL_NOTICE_STREAMSTATUS,
			.data.external.streamstat.frameno = c++
	};

/* split duration and store */
	int64_t dura = decctx.fcontext->duration / AV_TIME_BASE;
	int dh = dura / 3600;
	int dm = (dura % 3600) / 60;
	int ds = (dura % 60);

	size_t strlim = sizeof(status.data.external.streamstat.timelim) /
		sizeof(status.data.external.streamstat.timelim[0]);

	snprintf((char*)status.data.external.streamstat.timelim, strlim-1,
		"%d:%02d:%02d", dh, dm, ds);

/* use last pts to indicate current position, base is in milliseconds */
	int64_t duras = decctx.last_dts / 1000.0;
	ds = duras % 60;
	dh = duras / 3600;
	dm = (duras % 3600) / 60;

	status.data.external.streamstat.completion =
		( (float) duras / (float) dura );

	snprintf((char*)status.data.external.streamstat.timestr, strlim,
		"%d:%02d:%02d", dh, dm, ds);

	arcan_event_enqueue(&decctx.outevq, &status);
}

bool ffmpeg_decode()
{
	bool fstatus = true;
	av_init_packet(&decctx.packet);
	decctx.packet.data = (uint8_t*) &decctx.packet;

	/* Main Decoding sequence */
	while (fstatus &&
		av_read_frame(decctx.fcontext, &decctx.packet) >= 0) {

		if (decctx.packet.dts != AV_NOPTS_VALUE){
			if (decctx.packet.stream_index == decctx.vid)
				decctx.last_dts = decctx.packet.dts *
					av_q2d(decctx.vstream->time_base) * 1000.0;
			else if (decctx.packet.stream_index == decctx.aid)
				decctx.last_dts = decctx.packet.dts *
					av_q2d(decctx.astream->time_base) * 1000.0;
		}

/*
 * got a videoframe, this will synch both audio
 * and video unless we've been instructed to pack audio-fft
 * in video
 */
		if (decctx.packet.stream_index == decctx.vid)
			fstatus = decode_vframe();

		else if (decctx.packet.stream_index == decctx.aid){
			fstatus = decode_aframe();
			if (decctx.fft_audio)
				generate_frame();
			}

		av_free_packet(&decctx.packet);
		push_streamstatus();
		flush_eventq();
	}

	return fstatus;
}

static bool ffmpeg_preload(const char* fname, AVInputFormat* iformat,
	AVDictionary** opts, bool skipaud, bool skipvid)
{
	int errc = avformat_open_input(&decctx.fcontext, fname, iformat, NULL);
	if (0 != errc || !decctx.fcontext){
		LOG("avformat_open_input() couldn't open fcontext"
			"	for resource (%s)\n", fname);
		return false;
	}

	errc = avformat_find_stream_info(decctx.fcontext, NULL);

	if (! (errc >= 0) ){
		LOG("avformat_find_stream_info() didn't return"
			"	any useful data.\n");
		return NULL;
	}

/* locate streams and codecs */
	int vid,aid;

	vid = aid = decctx.vid = decctx.aid = -1;
	LOG("%d streams found in container.\n",decctx.fcontext->nb_streams);

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
	LOG("win32:probe_vidcap, find input format yielded %"
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

	LOG("scanning for capture device (requested: %dx%d @ %f fps)\n",
		desw, desh, fps);
	const char* fname = probe_vidcap(ind, &format);
	if (!fname || !format)
		return NULL;

	return ffmpeg_preload(fname, format, &opts, false, false);
}

static inline void targetev(arcan_event* ev)
{
	arcan_tgtevent* tgt = &ev->data.target;

	switch (ev->kind){
		case TARGET_COMMAND_GRAPHMODE:
/* add debugging / optimization geometry, the option of
 * using YUV420 or other formats packed in the RGBA buffer
 * to reduce decoding / scaling and offload to shader etc. */
		break;

		case TARGET_COMMAND_FRAMESKIP:
/* only forward every n frames */
		break;

		case TARGET_COMMAND_SETIODEV:
/* switch stream */
		break;

		case TARGET_COMMAND_SEEKTIME:
/* ioev[0] -> absolute, float
 * ioev[1] -> relative */
			if (fabs(tgt->ioevs[0].fv) > 0.0000000001){
				if (decctx.fcontext->duration != AV_NOPTS_VALUE){
					int64_t newv = (float)decctx.fcontext->duration * tgt->ioevs[0].fv;
					avformat_seek_file(decctx.fcontext, -1, INT64_MIN, newv, INT64_MAX,0);
				}
			}
			else if (tgt->ioevs[1].iv != 0){
				avformat_seek_file(decctx.fcontext, -1, INT64_MIN,
					(decctx.last_dts / 1000.0 + tgt->ioevs[1].iv)*AV_TIME_BASE,
				 	INT64_MAX, 0);
			}
			else;

			push_streamstatus();
		break;

		case TARGET_COMMAND_EXIT:
			exit(1);
		break;

		default:
			LOG("unhandled target event (%d), ignored.\n", ev->kind);
	}
}

/* use labels etc. for trying to populate the context table */
/* we also process requests to save state, shutdown, reset,
 * plug/unplug input, here */
static inline void flush_eventq()
{
	 arcan_event ev;

	while ( 1 == arcan_event_poll(&decctx.inevq, &ev) ){
		switch (ev.category){
		case EVENT_IO: break;
		case EVENT_TARGET: targetev(&ev); break;
		}
	}

}

void arcan_frameserver_decode_run(const char* resource, const char* keyfile)
{
	bool statusfl = false;
	struct arg_arr* args = arg_unpack(resource);
	decctx.shmcont = arcan_shmif_acquire(keyfile, SHMIF_INPUT, true, false);

	arcan_shmif_setevqs(decctx.shmcont.addr, decctx.shmcont.esem,
		&(decctx.inevq), &(decctx.outevq), false);

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
				desw = (desw > 0 && desw < ARCAN_SHMPAGE_MAXW) ? desw : 0;
			}

			if (arg_lookup(args, "height", 0, &val)){
				desh = strtoul(val, NULL, 10);
				desh = (desh > 0 && desh < ARCAN_SHMPAGE_MAXH) ? desh : 0;
			}

			statusfl = ffmpeg_vidcap(devind, desw, desh, fps);
		}
		else if (arg_lookup(args, "file", 0, &val)){
			statusfl = ffmpeg_preload(val, NULL, NULL, noaudio, novideo);
		}
		else{
/* as to not entirely break the API, we revert to default-treat
 * resource as a filename */
			LOG("failed, couldn't decode resource request (%s)\n", resource);
			return;
		}

		if (!statusfl)
			break;

/* take something by default so that we can still graph etc. */
		if (!decctx.vcontext){
			decctx.width  = AUD_VIS_HRES;
			decctx.height = 2;
			decctx.bpp    = 4;
			decctx.fft_audio = true;
		}

		if (!arcan_shmif_resize(&decctx.shmcont, decctx.width, decctx.height)){
			LOG("arcan_frameserver(decode) shmpage setup failed, "
				"requested: (%d x %d @ %d)	aud(%d,%d)\n",
				decctx.width, decctx.height, decctx.bpp,
				decctx.channels, decctx.samplerate);
			return;
		}
		arcan_shmif_calcofs(decctx.shmcont.addr, &(decctx.vidp), &(decctx.audp) );

	} while (ffmpeg_decode() && decctx.shmcont.addr->loop);
}
