#ifndef HAVE_PLATFORM_TYPES
#define HAVE_PLATFORM_TYPES

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#ifndef BADFD
#define BADFD -1
#endif

#include <pthread.h>
#include <semaphore.h>

typedef int pipe_handle;
typedef int file_handle;
typedef pid_t process_handle;
typedef sem_t* sem_handle;
typedef int8_t arcan_errc;
typedef int arcan_aobj_id;

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
					size_t rows, cols;
					size_t buf_sz; /* the resolved / unpacked TPACK screen */
					uint8_t* buf;
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

struct arcan_strarr;
struct arcan_evctx;

typedef struct {
	union {
		char* ptr;
		uint8_t* u8;
	};
	char zbyte; /* 'guarantees' ptr/u8 has a 0-byte end */
	size_t sz;
	bool mmap;
} map_region;

typedef struct {
	int fd;
	off_t start;
	off_t len;
	char* source;
} data_source;

enum resource_type {
	ARES_FILE = 1,
	ARES_FOLDER = 2,
	ARES_SOCKET = 3,
	ARES_CREATE = 256,
	ARES_RDONLY = 512
};

/*
 * Editing this table will require modifications in individual
 * platform/path.c, platform/namespace.c and platform/appl.c.
 *
 * The enum should fullfill the criteria:
 * (index = sqrt(enumv)),
 * exclusive(mask) = mask & (mask - 1) == 0
 */
enum arcan_namespaces {
/* .lua parse/load/execute,
 * generic resource load
 * special resource save (screenshots, ...)
 * rawresource open/write */
	RESOURCE_APPL = 1,

/*
 * shared resources between all appls.
 */
	RESOURCE_APPL_SHARED = 2,

/*
 * like RESOURCE_APPL, but contents can potentially be
 * reset on exit / reload.
 */
	RESOURCE_APPL_TEMP = 4,

/*
 * eligible recipients for target snapshot/restore
 */
	RESOURCE_APPL_STATE = 8,

/*
 * These three categories correspond to the previous
 * ones, and act as a reference point to load new
 * applications from when an explicit switch is
 * required. Depending on developer preferences,
 * these can potentially map to the same folder and
 * should be defined/set/overridden in platform/paths.c
 */
	RESOURCE_SYS_APPLBASE = 16,
	RESOURCE_SYS_APPLSTORE = 32,
	RESOURCE_SYS_APPLSTATE = 64,

/*
 * formatstring \f domain, separated in part due
 * to the wickedness of font- file formats
 */
	RESOURCE_SYS_FONT = 128,

/*
 * frameserver binaries read/execute (write-protected),
 * possibly signature/verify on load/run as well,
 * along with preemptive alloc+lock/wait on low system
 * loads.
 */
	RESOURCE_SYS_BINS = 256,

/*
 * LD_PRELOAD only (write-protected), recommended use
 * is to also have a database matching program configuration
 * and associated set of libraries.
 */
	RESOURCE_SYS_LIBS = 512,

/*
 * frameserver log output, state dumps, write-only since
 * read-backs from script would possibly be usable for
 * obtaining previous semi-sensitive data.
 */
	RESOURCE_SYS_DEBUG = 1024,

/*
 * shared scripts that can be system_loaded, should be RO and
 * updated / controlled with distribution versioning or through
 * explicit developer overrides
 */
	RESOURCE_SYS_SCRIPTS = 2048,

/*
 * the label will be interpreted as having a possible namespace prefix,
 * e.g. [myns]somewhere/something.
 */
	RESOURCE_NS_USER = 4096,
/*
 * must be set to the vale of the last system element (NS_USER ignored)
 */
	RESOURCE_SYS_ENDM = 2048
};

struct arcan_userns {
	bool read;
	bool write;
	bool ipc;
	int dirfd;
	char label[64];
	char name[32];
	char path[256];
};

struct platform_timing {
	bool tickless;
	unsigned cost_us;
};

#endif
