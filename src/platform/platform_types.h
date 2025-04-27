#ifndef HAVE_PLATFORM_TYPES
#define HAVE_PLATFORM_TYPES

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#ifndef BADFD
#define BADFD -1
#endif

#define PENDING_QUEUE_DEPTH 4

#include <stdint.h>
#include <pthread.h>
#include "os_platform_types.h"

typedef int8_t arcan_errc;
typedef int arcan_aobj_id;

/*
 * This part of the engine has received notably less attention, We've so- far
 * stuck with fixed format, fixed frequency etc.  Many of the more interesting
 * OpenAL bits (effects) are missing. The entire interface, buffer management
 * and platform abstraction is slated for rework in 0.6.
 */

enum aobj_kind {
	AOBJ_INVALID,
	AOBJ_STREAM,
	AOBJ_SAMPLE,
	AOBJ_FRAMESTREAM,
	AOBJ_CAPTUREFEED
};

/*
 * Request a [buffer] to be filled using buffer_data. Provides a negative
 * value to indicate that the audio object is being destructed. [tag] is a a
 * caller-provided that used when creating the feed.  Expects  ARCAN_OK as
 * result to indicate that the buffer should be queued for playback.
 * if [cont] is set, more buffers will be provided if [ARCAN_OK] is
 * returned. Expects [ARCAN_ERRC_NOTREADY] to indicate that there is no more
 * data to feed. Any other error leads to cleanup / destruction.
 */
typedef arcan_errc(*arcan_afunc_cb)(
	void* aobj, arcan_aobj_id id, ssize_t buffer, bool cont, void* tag);

/*
 * There is one global hook that can be used to get access to audio
 * data as it is beeing flushed to lower layers, and this is the form
 * of that callback.
 */
typedef void(*arcan_monafunc_cb)(arcan_aobj_id id, uint8_t* buf,
	size_t bytes, unsigned channels, unsigned frequency, void* tag);

/*
 * It is possible that the frameserver is a process parasite in another
 * process where we would like to interface audio control anyhow throuh
 * a gain proxy. This callback is used for those purposes.
 */
typedef arcan_errc(*arcan_again_cb)(float gain, void* tag);

/*
 * We only work with / support one internal pixel representation which should
 * be defined at build time to correspond to whatever the underlying hardware
 * supports optimally.
 */
#ifndef VIDEO_PIXEL_TYPE
#define VIDEO_PIXEL_TYPE uint32_t
#endif

typedef VIDEO_PIXEL_TYPE av_pixel;

/* GLES2/3 typically, doesn't support BGRA formats */
#ifndef OPENGL
#ifndef RGBA
#define RGBA(r, g, b, a)(\
((uint32_t) (a) << 24) |\
((uint32_t) (b) << 16) |\
((uint32_t) (g) <<  8) |\
((uint32_t) (r)))
#endif

#ifndef GL_PIXEL_FORMAT
#define GL_PIXEL_FORMAT 0x1908
#endif

#ifndef RGBA_DECOMP
static inline void RGBA_DECOMP(av_pixel val, uint8_t* r,
	uint8_t* g, uint8_t* b, uint8_t* a)
{
	*r = (val & 0x000000ff);
	*g = (val & 0x0000ff00) >>  8;
	*b = (val & 0x00ff0000) >> 16;
	*a = (val & 0xff000000) >> 24;
}
#endif

#ifndef GL_STORE_PIXEL_FORMAT
#define GL_STORE_PIXEL_FORMAT 0x1908
#endif

#ifndef GL_NOALPHA_PIXEL_FORMAT
#define GL_NOALPHA_PIXEL_FORMAT 0x1907
#endif

#else
#ifndef RGBA
#define RGBA(r, g, b, a)(\
((uint32_t) (a) << 24) |\
((uint32_t) (r) << 16) |\
((uint32_t) (g) <<  8) |\
((uint32_t) (b)))
#endif

/*
 * GL_BGRA8888
 */
#ifndef GL_PIXEL_FORMAT
#define GL_PIXEL_FORMAT 0x80E1
#endif

/*
 * GL_RGBA
 */
#ifndef GL_STORE_PIXEL_FORMAT
#define GL_STORE_PIXEL_FORMAT 0x1908
#endif

/*
 * GL_RGB
 */
#ifndef GL_NOALPHA_PIXEL_FORMAT
#define GL_NOALPHA_PIXEL_FORMAT 0x1907
#endif

#ifndef RGBA_DECOMP
static inline void RGBA_DECOMP(av_pixel val, uint8_t* r,
	uint8_t* g, uint8_t* b, uint8_t* a)
{
	*b = (val & 0x000000ff);
	*g = (val & 0x0000ff00) >>  8;
	*r = (val & 0x00ff0000) >> 16;
	*a = (val & 0xff000000) >> 24;
}
#endif

#endif

#define OUT_DEPTH_R 8
#define OUT_DEPTH_G 8
#define OUT_DEPTH_B 8
#define OUT_DEPTH_A 0

/*
 * For objects that are not opaque or invisible, a blending function can be
 * specified. These functions regulate how overlapping objects should be mixed.
 */
enum arcan_blendfunc {
	BLEND_NONE     = 0,
	BLEND_NORMAL   = 1,
	BLEND_ADD      = 2,
	BLEND_MULTIPLY = 3,
	BLEND_SUB      = 4,
	BLEND_PREMUL   = 5,

/* force is a control bit rather than a specific mode, if not set blending
 * will be disabled for objects marked as fully opaque */
	BLEND_FORCE    = 128
};

/*
 * Internal shader type tracking
 */
enum shdrutype {
	shdrbool   = 0,
	shdrint    = 1,
	shdrfloat  = 2,
	shdrvec2   = 3,
	shdrvec3   = 4,
	shdrvec4   = 5,
	shdrmat4x4 = 6
};

/* Built-in shader properties, these are order dependant, check shdrmgmt.c */
enum agp_shader_envts{
/* packed matrices */
	MODELVIEW_MATR  = 0,
	PROJECTION_MATR = 1,
	TEXTURE_MATR    = 2,
	OBJ_OPACITY     = 3,

/* transformation completion */
	TRANS_BLEND     = 4,
	TRANS_MOVE      = 5,
	TRANS_ROTATE    = 6,
	TRANS_SCALE     = 7,

/* object storage / rendering properties */
	SIZE_INPUT  = 8,
	SIZE_OUTPUT = 9,
	SIZE_STORAGE= 10,
	RTGT_ID = 11,

	FRACT_TIMESTAMP_F = 12,
	TIMESTAMP_D       = 13,
};

/*
 * union specifier
 */
enum txstate {
	TXSTATE_OFF   = 0,
	TXSTATE_TEX2D = 1,
	TXSTATE_DEPTH = 2,
	TXSTATE_TEX3D = 3,
	TXSTATE_CUBE  = 4,
	TXSTATE_TPACK = 5, /* vstore buffer contents is an atlas */
};

enum storage_source {
	STORAGE_IMAGE_URI,
	STORAGE_TEXT,
	STORAGE_TEXTARRAY,
	STORAGE_TPACK /* this means the source buffer has the raw tpack 'screen' */
};

struct agp_region {
	size_t x1, y1, x2, y2;
};

struct drm_hdr_meta {
	int eotf;
	float rx, ry, gx, gy, bx, by; /* 0.0 <= n <= 1.3107 */
	float wpx, wpy;
	float master_min, master_max;
	float cll;
	float fll;
};

struct agp_vstore;
struct agp_vstore {
	size_t refcount;
	uint32_t update_ts;

	union {
		struct {
/* ID number connecting to AGP, this MAY be bound diretly to the glid
 * of a specific context, or act as a reference into multiple contexts */
			unsigned glid;
			unsigned* glid_proxy;

/* used for PBO transfers */
			unsigned rid, wid;

/* intermediate storage for reconstructing lost context */
			uint32_t s_raw;
			av_pixel*  raw;
			uint64_t s_fmt;
			uint64_t d_fmt;
			unsigned s_type;

/* may need to propagate vpts state */
			uint64_t vpts;

/* for rerasterization */
			float hppcm, vppcm;

/* re- construction string may be used as factory in conservative memory
 * management model to recreate contents of raw */
			enum storage_source kind;
			union {
				char* source;
				char** source_arr;
				struct {
					size_t buf_sz; /* the resolved / unpacked TPACK screen */
					uint8_t* buf;
					void* group; /* struct arcan_renderfun_fontgroup */
					void* tui; /* optional tui context that can be unpacked to buf */
				} tpack;
			};


/* used if we have an external buffered backing store
 * (implies s_raw / raw / source are useless) */
			int format;
			size_t stride;
			int64_t handle;
			uintptr_t tag;
		} text;

		struct {
			float r;
			float g;
			float b;
		} col;
	} vinf;

/* if set, a local copy will be synched in here */
	struct agp_vstore* dst_copy;

	size_t w, h;
	uint8_t bpp, txmapped,
		txu, txv, scale, imageproc, filtermode;

	struct {
		int model;
		struct drm_hdr_meta drm;
	} hdr;
};

/* Built in Shader Vertex Attributes */
enum shader_vertex_attributes {
	ATTRIBUTE_VERTEX,
	ATTRIBUTE_NORMAL,
	ATTRIBUTE_COLOR,
	ATTRIBUTE_TEXCORD0,
	ATTRIBUTE_TEXCORD1,
	ATTRIBUTE_TANGENT,
	ATTRIBUTE_BITANGENT,
	ATTRIBUTE_JOINTS0,
	ATTRIBUTE_WEIGHTS1
};

/*
 * end of internal representation specific data.
 */
typedef long long arcan_vobj_id;

enum ARCAN_ANALOGFILTER_KIND {
	ARCAN_ANALOGFILTER_NONE = 0,
	ARCAN_ANALOGFILTER_PASS = 1,
	ARCAN_ANALOGFILTER_AVG  = 2,
	ARCAN_ANALOGFILTER_FORGET = 3,
 	ARCAN_ANALOGFILTER_ALAST = 4
};

/*
 * Some platforms can statically/dynamically determine what kinds of events
 * they are capable of emitting. This is helpful when determining what input
 * mode to expect (window manager that requires translated inputs and waits
 * because none are available
 */
enum PLATFORM_EVENT_CAPABILITIES {
	ACAP_TRANSLATED = 1,
	ACAP_MOUSE = 2,
	ACAP_GAMING = 4,
	ACAP_TOUCH = 8,
	ACAP_POSITION = 16,
	ACAP_ORIENTATION = 32,
	ACAP_EYES = 64
};

struct arcan_evctx;

#endif
