/* libFFMPEG */
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

typedef struct arcan_ffmpeg_context {
	struct frameserver_shmpage* shared;
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;
	
	sem_handle async;
	sem_handle vsync;
	sem_handle esync;
	
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
	bool loop;

	int vid;
	int aid;

	int height;
	int width;
	int bpp;

	uint16_t samplerate;
	uint16_t channels;

	int16_t* audio_buf;
	uint32_t c_audio_buf;

	uint8_t* video_buf;
	uint32_t c_video_buf;

} arcan_ffmpeg_context;

/* preload and scan for streams.
 * arg(1)   : filename
 * ret(ok)  : pointer to allocated context
 * ret(fail): NULL */
arcan_ffmpeg_context* ffmpeg_preload(const char* fname);

/* free any resources related to the ffmpeg context */
void ffmpeg_cleanup(arcan_ffmpeg_context*);

/* assumes that ctx->shared has been set up to point
 * to shared memory, controlled by the respective sempares
 *
 * ret(true)  : all frames processed (or decoding error, common enough).
 * ret(false) : check_alive failed or semaphores have been freed
 *
 * notes :
 * assumes the symbol bool sem_check(sem_handle) exists
 * and returns true on a successfull wait or false if parent process is dead */
bool ffmpeg_decode(arcan_ffmpeg_context*);
