/* libFFMPEG */
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

typedef struct arcan_ffmpeg_context {
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
	uint8_t* vidp, (* audp);

} arcan_ffmpeg_context;

void arcan_frameserver_ffmpeg_run(const char* resource, const char* keyfile);
