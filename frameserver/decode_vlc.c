#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <pthread.h>
#include <math.h>
#include <fft/kiss_fftr.h>

#include <vlc/vlc.h>
#include <arcan_shmif.h>

struct {
	libvlc_instance_t* vlc;
	libvlc_media_player_t* player;
	
	struct arcan_shmif_cont shmcont;
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;

	bool fft_audio;
	kiss_fftr_cfg fft_state;

	pthread_mutex_t tsync;
	uint8_t* vidp, (* audp);

} decctx = {0};

#define LOG(...) (fprintf(stderr, __VA_ARGS__))
#define AUD_VIS_HRES 2048 

static unsigned video_setup(void** ctx, char* chroma, unsigned* width, 
	unsigned* height, unsigned* pitches, unsigned* lines)
{
	chroma[0] = 'R';
	chroma[1] = 'G';
	chroma[2] = 'B';
	chroma[3] = 'A';

	printf("format, %d, %d, %d, %d, %c%c%c%c\n", 
		*width, *height, *pitches, *lines, chroma[0], chroma[1], chroma[2], chroma[3]);
	*pitches = *width * 4;

	if (!arcan_shmif_resize(&decctx.shmcont, *width, *height)){
		LOG("arcan_frameserver(decode) shmpage setup failed, "
			"requested: (%d x %d)\n", *width, *height);
		return 0;
	} 
	
	arcan_shmif_calcofs(decctx.shmcont.addr, &(decctx.vidp), &(decctx.audp) );

	return 1;
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

	arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID | SHMIF_SIGAUD);
}

static void audio_play(void *data, 
	const void *samples, unsigned count, int64_t pts)
{
	size_t nb = count * ARCAN_SHMPAGE_ACHANNELS * sizeof(uint16_t);

	if (decctx.vidp == NULL)
	{
		arcan_shmif_resize(&decctx.shmcont, AUD_VIS_HRES, 2);
		arcan_shmif_calcofs(decctx.shmcont.addr, &(decctx.vidp), &(decctx.audp) );
		decctx.fft_audio = true;
	}

	pthread_mutex_lock(&decctx.tsync);
		memcpy(decctx.audp + decctx.shmcont.addr->abufused, samples, nb);
		decctx.shmcont.addr->abufused += nb;
	pthread_mutex_unlock(&decctx.tsync);

	if (decctx.fft_audio){
		generate_frame();
	}
}

static void audio_flush()
{
	pthread_mutex_lock(&decctx.tsync);
		arcan_event ev = {
			.kind = EVENT_EXTERNAL_NOTICE_FLUSHAUD,
			.category = EVENT_EXTERNAL
		};

		arcan_event_enqueue(&decctx.outevq, &ev); 
	pthread_mutex_unlock(&decctx.tsync);
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
	*planes = decctx.vidp;
	return NULL;
}

static void video_display(void* ctx, void* picture)
{
	pthread_mutex_lock(&decctx.tsync);
	if (decctx.shmcont.addr->abufused > 0)
		arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGAUD | SHMIF_SIGVID);
	else 
		arcan_shmif_signal(&decctx.shmcont, SHMIF_SIGVID);
	pthread_mutex_unlock(&decctx.tsync);
}

static void video_unlock(void* ctx, void* picture, void* const* planes)
{
		
}

static void push_streamstatus()
{
	static int c;

	struct arcan_event status = {
		.category = EVENT_EXTERNAL,
		.kind = EVENT_EXTERNAL_NOTICE_STREAMSTATUS,
		.data.external.streamstat.frameno = c++
	};

	int64_t dura =  libvlc_media_player_get_length(decctx.player) / 1000;

	int dh = dura / 3600;
	int dm = (dura % 3600) / 60;
	int ds = (dura % 60);

	size_t strlim = sizeof(status.data.external.streamstat.timelim) / 
		sizeof(status.data.external.streamstat.timelim[0]);

	snprintf((char*)status.data.external.streamstat.timelim, strlim-1,
		"%d:%02d:%02d", dh, dm, ds);

	int64_t duras = libvlc_media_player_get_time(decctx.player) / 1000;
	ds = duras % 60;
	dh = duras / 3600;
	dm = (duras % 3600) / 60;

	status.data.external.streamstat.completion = 
		( (float) duras / (float) dura ); 

	snprintf((char*)status.data.external.streamstat.timestr, strlim,
		"%d:%02d:%02d", dh, dm, ds);

	pthread_mutex_lock(&decctx.tsync);
		arcan_event_enqueue(&decctx.outevq, &status);
	pthread_mutex_unlock(&decctx.tsync);
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
			decctx.shmcont.addr->dms = false;
	break;

	default:
		printf("unhandled event\n");
	}
}

static void seek_relative(int seconds)
{
	int64_t time_v = libvlc_media_player_get_time(decctx.player);
	time_v += seconds * 1000;
	time_v = time_v > 0 ? time_v : 0;
	libvlc_media_player_set_time(decctx.player, time_v);
}

void arcan_frameserver_decode_run(const char* resource, const char* keyfile)
{
	libvlc_media_t* media = NULL;

/* connect to display server */
	struct arg_arr* args = arg_unpack(resource);
	decctx.shmcont = arcan_shmif_acquire(keyfile, SHMIF_INPUT, true, false);

/* decode external arguments, map the necessary ones to VLC */
	const char* val;
	bool noaudio = false;
	bool novideo = false;

	if (arg_lookup(args, "noaudio", 0, &val)){
		noaudio = true;
	} 
	else if (arg_lookup(args, "novideo", 0, &val))
		novideo = true;

	char const* vlc_argv[] = {
		"-I", "dummy", 
		"--ignore-config", 
		"--no-xlib"
	};
	char const vlc_argc = sizeof(vlc_argv) / sizeof(vlc_argv[0]);

	decctx.vlc = libvlc_new(vlc_argc, vlc_argv);

/* special about stream devices is that we can specify external resources (e.g.
 * http://, rtmp:// etc. along with buffer dimensions */
	if (arg_lookup(args, "stream", 0, &val)){
		media = libvlc_media_new_location(decctx.vlc, val);
		libvlc_set_user_agent(decctx.vlc, 
			"Arcan Frameserver Decode",
			"GoogleBot/1.0");
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
			
		if (arg_lookup(args, "width", 0, &val))
			desw = strtoul(val, NULL, 10);
			desw = (desw > 0 && desw < ARCAN_SHMPAGE_MAXW) ? desw : 0;

		if (arg_lookup(args, "height", 0, &val))
			desh = strtoul(val, NULL, 10);
			desh = (desh > 0 && desh < ARCAN_SHMPAGE_MAXH) ? desh : 0;
	}
	else if (arg_lookup(args, "file", 0, &val))
		media = libvlc_media_new_path(decctx.vlc, val);

	if (!media){
			printf("no media\n");
		 return;	
	}

	pthread_mutex_init(&decctx.tsync, NULL);

/* register media with vlc, hook up local input mapping */
  decctx.player = libvlc_media_player_new_from_media(media);
  libvlc_media_release(media);

	struct libvlc_event_manager_t* em = libvlc_media_player_event_manager(decctx.player);

	libvlc_event_attach(em, libvlc_MediaPlayerPositionChanged, player_event, NULL); 
	libvlc_event_attach(em, libvlc_MediaPlayerEndReached, player_event, NULL); 

	libvlc_video_set_format_callbacks(decctx.player, video_setup, video_cleanup);
	libvlc_video_set_callbacks(decctx.player, video_lock, video_unlock, video_display, NULL);
	libvlc_audio_set_format(decctx.player, "S16N", 44100, 2); 
	libvlc_audio_set_callbacks(decctx.player, 
		audio_play, /*pause*/ NULL, /*resume*/ NULL, audio_flush, audio_drain, NULL);

/* audio callbacks; ctx, play, pause, resume, flush, void*ctx */
/* register event manager and forward to output events */

	arcan_shmif_setevqs(decctx.shmcont.addr, decctx.shmcont.esem, 
		&(decctx.inevq), &(decctx.outevq), false);
	libvlc_media_player_play(decctx.player);

	arcan_event ev;
	
	while(decctx.shmcont.addr->dms && arcan_event_wait(&decctx.inevq, &ev)){
		arcan_tgtevent* tgt = &ev.data.target;
	
		if (ev.category == EVENT_TARGET)
		switch(ev.kind){
		case TARGET_COMMAND_GRAPHMODE:
/* switch audio /video visualization, RGBA-pack YUV420 hinting,
 * set_deinterlace */
		break;

		case TARGET_COMMAND_FRAMESKIP:
/* change buffering etc. behavior */
		break;
		
		case TARGET_COMMAND_SETIODEV:
/* switch stream
 * get_spu_count, get_spu_description, get_title_description, get_chapter_description
 * get_track, set_track, ...
 * */
		break;

		case TARGET_COMMAND_EXIT:
			goto cleanup;
		break;

		case TARGET_COMMAND_SEEKTIME:
			if (tgt->ioevs[1].iv != 0){
					seek_relative(tgt->ioevs[1].iv);
			}
			else 
				libvlc_media_player_set_position(decctx.player, tgt->ioevs[0].fv);
		break;

		default:
			printf("unhandled event: %d, %d\n", ev.kind, ev.category);
		}
			
/*
 * seek : libvlc_media_player_set_position (och get_position)
 * libvlc_media_player_set_pause
 *
 */
	}

cleanup:
/* cleanup */
 	libvlc_media_player_stop(decctx.player);
 	libvlc_media_player_release(decctx.player);
	libvlc_release(decctx.vlc);
}
