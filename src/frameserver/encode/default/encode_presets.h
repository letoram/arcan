/* the use for these functions is just to call with,
 * a possibly user supplied preferred codec identification string,
 * begin with container, as we need the flags to open correctly.
 * then video and audio, passing the flags of the container.
 * then call each codec_ents setup function with respective options */
#ifndef _HAVE_ENCPRESETS
#define _HAVE_ENCPRESETS

enum codec_kind {
	CODEC_VIDEO,
	CODEC_AUDIO,
	CODEC_FORMAT
};

struct codec_ent
{
	enum codec_kind kind;

	const char* const name;
	const char* const shortname;
	int id;

	union {
		struct {
		const AVCodec* codec;
		AVCodecContext* context;
		AVFrame* pframe;
		int channel_layout;
		} video, audio;

		struct {
			AVOutputFormat*  format;
			AVFormatContext* context;
		} container;

	} storage;

/* pass the codec member of this structure as first arg,
 * unsigned number of channels (only == 2 supported currently)
 * unsigned samplerate (> 0, <= 48000)
 * unsigned abr|quality (0..n, n < 10 : quality preset, otherwise bitrate) */
	union {
		bool (*video)(struct codec_ent*, unsigned, unsigned, float, unsigned, bool);
		bool (*audio)(struct codec_ent*, unsigned, unsigned, unsigned);
		bool (*muxer)(struct codec_ent*);
	} setup;
};

/*
 * try to find and allocate a valid video codec combination,
 * requested : (NULL) use default, otherwise look for this as name.
 */
struct codec_ent encode_getvcodec(const char* const requested, int flags);
struct codec_ent encode_getacodec(const char* const requested, int flags);
struct codec_ent encode_getcontainer(const char* const requested,
	int fd, const char* remote);
#endif
