/*
 * Decode Reference Frameserver Archetype
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Depends: LibVLC (LGPL)
 * Description: Default VLC based player. Still in quite a terrible shape with
 * few features mapped (subtitle control, subtitle as subsegment, playlists,
 * descriptor passing, stream switching, attenuation, accelerated handle, mouse
 * cursor handling for DVDs, passing, audio/video/subtitle track switching all
 * missing still, accelerated audio passthrough control, exposing chapters /
 * titles)
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <pthread.h>
#include <math.h>
#include <fcntl.h>

#include <vlc/vlc.h>
#include <kiss_fftr.h>
#include <arcan_shmif.h>
#include "frameserver.h"

static struct {
	libvlc_instance_t* vlc;
	libvlc_media_player_t* player;

	struct arcan_shmif_cont shmcont;

	bool fft_audio, got_video;
	kiss_fftr_cfg fft_state;

	bool loop;

	pthread_mutex_t rsync;
} decctx;

#define AUD_VIS_HRES 2048

static void process_inevq();

static unsigned video_setup(void** ctx, char* chroma, unsigned* width,
	unsigned* height, unsigned* pitches, unsigned* lines)
{
	unsigned rv = 1;
	decctx.got_video = true;

	chroma[0] = 'R';
	chroma[1] = 'G';
	chroma[2] = 'B';
	chroma[3] = 'A';

	*pitches = *width * 4;

	pthread_mutex_lock(&decctx.rsync);
	if (!arcan_shmif_resize(&decctx.shmcont, *width, *height)){
		LOG("arcan_frameserver(decode) shmpage setup failed, "
			"requested: (%d x %d)\n", *width, *height);

		rv = 0;
	}
	pthread_mutex_unlock(&decctx.rsync);

	return rv;
}

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
	static double vptsc = 0;

	int16_t* basep = decctx.shmcont.audp;
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

			uint32_t* base = decctx.shmcont.vidp;
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

/*
 * This should be re-worked to pack in base256 with an
 * unpack shader to get decent precision in the output vis,
 * and generalized to a support function that we can
 * associate with any data-channel and new context
 */

			for (int j=0; j<smpl_wndw / 2; j++){
				*base++ = RGBA(0, 0, 0, 0xff);
			}

			for (int j=0; j < smpl_wndw / 2; j++)
				*base++ = RGBA(
					((1.0f + ((smplbuf[j * 2] +
						smplbuf[j * 2 + 1]) / 2.0)) / 2.0 * 255.0),
					((fsmplbuf[j] / high) * 255.0),
					0x00,
					0xff
				);

			decctx.shmcont.addr->vpts = vptsc;
			arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID);

			vptsc += 1000.0f / (
				(double)(ARCAN_SHMIF_SAMPLERATE) / (double)smpl_wndw);
		}
	}

	arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID | SHMIF_SIGAUD);
}

static void audio_play(void *data,
	const void *samples, unsigned count, int64_t pts)
{
	size_t nb = count * ARCAN_SHMIF_ACHANNELS * ARCAN_SHMIF_SAMPLE_SIZE;

	if (!decctx.got_video && decctx.shmcont.addr->w != AUD_VIS_HRES)
	{
		pthread_mutex_lock(&decctx.rsync);
		arcan_shmif_resize(&decctx.shmcont, AUD_VIS_HRES, 2);
		decctx.fft_audio = true;
		arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(STREAMINFO),
			.ext.streaminf.langid = {'A', 'U', 'D'}
		};
		arcan_shmif_enqueue(&decctx.shmcont, &ev);
		pthread_mutex_unlock(&decctx.rsync);
	}

	pthread_mutex_lock(&decctx.rsync);

	size_t left = ARCAN_SHMIF_AUDIOBUF_SZ - decctx.shmcont.addr->abufused;
	if (left < nb)
		arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGAUD);

	left = ARCAN_SHMIF_AUDIOBUF_SZ - decctx.shmcont.addr->abufused;
	if (left > nb){
		memcpy( (uint8_t*)(decctx.shmcont.audp) +
			decctx.shmcont.addr->abufused, samples, nb);
		decctx.shmcont.addr->abufused += nb;
	}

	pthread_mutex_unlock(&decctx.rsync);

	if (decctx.fft_audio){
		generate_frame();
	}
}

static void audio_flush()
{
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(FLUSHAUD)
	};
	LOG("flush\n");
	decctx.shmcont.addr->abufused = 0;
	arcan_shmif_enqueue(&decctx.shmcont, &ev);
}

static void audio_drain()
{
	arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGAUD);
}

static void video_cleanup(void* ctx)
{
}

static void* video_lock(void* ctx, void** planes)
{
	pthread_mutex_lock(&decctx.rsync);
	*planes = decctx.shmcont.vidp;
	return NULL;
}

static void video_display(void* ctx, void* picture)
{
	if (decctx.shmcont.addr->abufused)
		arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGAUD | SHMIF_SIGVID);
	else
		arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID);
}

static void video_unlock(void* ctx, void* picture, void* const* planes)
{
	pthread_mutex_unlock(&decctx.rsync);
}

static void push_streamstatus()
{
	static int c;

	struct arcan_event status = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(STREAMSTATUS),
		.ext.streamstat.frameno = c++
	};

	int64_t dura =  libvlc_media_player_get_length(decctx.player) / 1000;

	int dh = dura / 3600;
	int dm = (dura % 3600) / 60;
	int ds = (dura % 60);

	size_t strlim = sizeof(status.ext.streamstat.timelim) /
		sizeof(status.ext.streamstat.timelim[0]);

	snprintf((char*)status.ext.streamstat.timelim, strlim-1,
		"%d:%02d:%02d", dh, dm, ds);

	int64_t duras = libvlc_media_player_get_time(decctx.player) / 1000;
	ds = duras % 60;
	dh = duras / 3600;
	dm = (duras % 3600) / 60;

	status.ext.streamstat.completion = ( (float) duras / (float) dura );

	snprintf((char*)status.ext.streamstat.timestr, strlim,
		"%d:%02d:%02d", dh, dm, ds);

	arcan_shmif_enqueue(&decctx.shmcont, &status);
}

static void player_event(const struct libvlc_event_t* event, void* ud)
{
	switch(event->type){
	case libvlc_MediaPlayerPlaying:
	break;

	case libvlc_MediaPlayerPositionChanged:
		push_streamstatus();
	break;

	case libvlc_MediaPlayerEncounteredError:
		case libvlc_MediaPlayerEndReached:
			LOG("end reached\n");
			decctx.shmcont.addr->dms = false;
	break;

	default:
		LOG("unhandled event (%s)\n", libvlc_event_type_name(event->type));
	}

	process_inevq();
}

static libvlc_media_t* find_capture_device(
	int id, int desw, int desh, float desfps)
{
	libvlc_media_t* media = NULL;

#ifdef WIN32

#elif __APPLE__
	char url[48];
	snprintf(url, sizeof(url) / sizeof(url[0]), "qtcapture://%d", id);
	media = libvlc_media_new_location(decctx.vlc, url);

#else
	char url[24];
	snprintf(url,24, "v4l2:///dev/video%d", id);
	media = libvlc_media_new_path(decctx.vlc, url);
#endif

/* add_media_options	:v4l2-width=640 :v4l2-height=480 */

	return media;
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" file    \t path      \t try to open file path for playback \n"
		" stream  \t url       \t attempt to open URL for streaming input \n"
		" capture \t devind    \t try to open a capture device\n"
		" fps     \t rate      \t force a specific framerate\n"
		" width   \t outw      \t scale output to a specific width\n"
		" height  \t outh      \t scale output to a specific height\n"
		"---------\t-----------\t----------------\n"
	);
}

static void seek_relative(int seconds)
{
	int64_t time_v = libvlc_media_player_get_time(decctx.player);
	time_v += seconds * 1000;
	time_v = time_v > 0 ? time_v : 0;
	libvlc_media_player_set_time(decctx.player, time_v);
}

static void process_inevq()
{
	arcan_event ev;

	while (arcan_shmif_poll(&decctx.shmcont, &ev) > 0){
		arcan_tgtevent* tgt = &ev.tgt;

		if (ev.category == EVENT_TARGET)
		switch(tgt->kind){
		case TARGET_COMMAND_GRAPHMODE:
/* switch audio /video visualization, RGBA-pack YUV420 hinting,
 * set_deinterlace */
		break;

		case TARGET_COMMAND_AUDDELAY:

		break;

		case TARGET_COMMAND_FRAMESKIP:
/* change buffering etc. behavior */
		break;

		case TARGET_COMMAND_SETIODEV:
/* switch stream
 * get_spu_count, get_spu_description,
 * get_title_description, get_chapter_description
 * get_track, set_track, ...
 * */
		break;

/*
 * case TARGET_COMMAND_FDTRANSFER:
		{
#if _WIN32
			libvlc_media_t* media = libvlc_media_new_fd(
				decctx.vlc, _open_osfhandle(
				(intptr_t)frameserver_readhandle(&ev), _O_APPEND));
#else
			libvlc_media_t* media = libvlc_media_new_fd(
				decctx.vlc, dup(ev.tgt.ioevs[0].iv));
#endif
			libvlc_media_player_set_media(decctx.player, media);
			libvlc_media_release(media);
		}
		break;
 */

		case TARGET_COMMAND_EXIT:
			decctx.shmcont.addr->dms = false;
		break;

		case TARGET_COMMAND_SEEKTIME:
			if (tgt->ioevs[1].iv != 0){
					seek_relative(tgt->ioevs[1].iv);
			}
			else
				libvlc_media_player_set_position(decctx.player, tgt->ioevs[0].fv);
		break;

		default:
			LOG("unhandled target event received (%d:%d)\n", tgt->kind, ev.category);
		}
	}

}

int afsrv_decode(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	libvlc_media_t* media = NULL;

	if (!cont || !args){
		dump_help();
		return EXIT_FAILURE;
	}

	decctx.shmcont = *cont;
	setenv("VLC_PLUGIN_PATH", "/usr/local/lib/vlc/plugin", 0);

/* decode external arguments, map the necessary ones to VLC */
	const char* val;
	char const* vargs[] = {
		"--no-xlib",
/*		"--verbose", "3", */
		"--vout", "vmem",
		"--intf", "dummy",
		"--aout", "amem"
	};
	decctx.vlc = libvlc_new(sizeof(vargs)/sizeof(vargs[0]), vargs);
  if (decctx.vlc == NULL){
  	LOG("Couldn't initialize VLC session, giving up.\n");
    return EXIT_FAILURE;
  }

/* special about stream devices is that we can specify external resources (e.g.
 * http://, rtmp:// etc. along with buffer dimensions */
	if (arg_lookup(args, "stream", 0, &val)){
		media = libvlc_media_new_location(decctx.vlc, val);
		libvlc_set_user_agent(decctx.vlc,
			"MrSmith",
			"GoogleBot/1.0"); /* ;-) */
	}
/* for capture devices, we should be able to launch in a probe / detect
 * mode that propagates available ones upwards, otherwise we have the
 * semantics like; v4l2:// dshow:// qtcapture:// etc. */
	else if (arg_lookup(args, "capture", 0, &val)){
		unsigned devind = 0;
		int desw = 0, desh = 0;
		float fps = -1;

		if (arg_lookup(args, "device", 0, &val))
			devind = strtoul(val, NULL, 10);

		if (arg_lookup(args, "fps", 0, &val))
			fps = strtof(val, NULL);

		if (arg_lookup(args, "loop", 0, &val))
			decctx.loop = true;

		if (arg_lookup(args, "width", 0, &val))
			desw = strtoul(val, NULL, 10);
			desw = (desw > 0 && desw < ARCAN_SHMPAGE_MAXW) ? desw : 0;

		if (arg_lookup(args, "height", 0, &val))
			desh = strtoul(val, NULL, 10);
			desh = (desh > 0 && desh < ARCAN_SHMPAGE_MAXH) ? desh : 0;

		media = find_capture_device(devind, desw, desh, fps);
	}
	else if (arg_lookup(args, "file", 0, &val))
		media = libvlc_media_new_path(decctx.vlc, val);

	if (!media){
		LOG("couldn't open any media source, giving up.\n");
		 return EXIT_FAILURE;
	}

	pthread_mutex_init(&decctx.rsync, NULL);

/* register media with vlc, hook up local input mapping */
  decctx.player = libvlc_media_player_new_from_media(media);
/*  libvlc_media_release(media); */

	struct libvlc_event_manager_t* em =
		libvlc_media_player_event_manager(decctx.player);

	libvlc_event_attach(em, libvlc_MediaPlayerPositionChanged, player_event,NULL);
	libvlc_event_attach(em, libvlc_MediaPlayerEndReached, player_event, NULL);

	libvlc_video_set_format_callbacks(decctx.player, video_setup, video_cleanup);
	libvlc_video_set_callbacks(decctx.player,
		video_lock, video_unlock, video_display, NULL);

	libvlc_audio_set_format(decctx.player, "S16N",
		ARCAN_SHMIF_SAMPLERATE, ARCAN_SHMIF_ACHANNELS);

	libvlc_audio_set_callbacks(decctx.player,
		audio_play, /*pause*/ NULL, /*resume*/ NULL, audio_flush, audio_drain,NULL);

	libvlc_media_player_play(decctx.player);

/* video playback finish will pull this or seek back to beginning on loop */
	while(decctx.shmcont.addr->dms)
#if _WIN32
		Sleep(1000);
#else
		sleep(1);
#endif

 	libvlc_media_player_stop(decctx.player);
 	libvlc_media_player_release(decctx.player);
	libvlc_release(decctx.vlc);
	return EXIT_SUCCESS;
}
