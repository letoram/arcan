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

/* intermediate story when it can't be avoided */
	int16_t* audio_buf;
	uint32_t c_audio_buf;

	uint8_t* video_buf;
	uint32_t c_video_buf;
	
/* precalc dstptrs into shm */
	void* vidp, (* audp);

} arcan_ffmpeg_context;

void arcan_frameserver_ffmpeg_run(const char* resource, const char* keyfile);
