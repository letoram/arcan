#ifndef HAVE_ARCAN_VIDEOPLATFORM
#define HAVE_ARCAN_VIDEOPLATFORM
/*
 * Initialize the video platform to a display that matches the
 * specified dimensions. this interface is slated for redesign to
 * cover more adaptive configurations (probing displays, etc.)
 *
 * width / height to 0 will force whatever the platform layer decides
 * the main display would like.
 *
 * (frames / fs are hints to where we are running as a window
 * in another display server, and whether we should request to
 * fake fullscreen or not.)
 */

#ifndef VIDEO_PIXEL_TYPE
#define VIDEO_PIXEL_TYPE uint32_t
#endif

typedef VIDEO_PIXEL_TYPE av_pixel;

#ifndef RGBA
#define RGBA(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16) |\
((uint32_t) (g) << 8) | ((uint32_t) (r)) )
#endif

#ifndef GL_PIXEL_FORMAT
#define GL_PIXEL_FORMAT GL_RGBA
#endif

#ifndef GL_PIXEL_BPP
#define GL_PIXEL_BPP 4
#define GL_PIXEL_BPP_BIT 32
#endif

#define RGBA_FULLALPHA_REPACK(inv)(	RGBA( ((inv) & 0x000000ff), \
(((inv) & 0x0000ff00) >> 8), (((inv) & 0x00ff0000) >> 16), 0xff) )

#ifndef RGBA_DECOMP
static inline void RGBA_DECOMP(av_pixel val, uint8_t* r,
	uint8_t* g, uint8_t* b, uint8_t* a)
{
	*r = val & 0x000000ff;
	*g = (val & 0x0000ff00) >> 8;
	*b = (val & 0x00ff0000) >> 16;
	*a = (val & 0xff000000) >> 24;
}
#endif

typedef long long arcan_vobj_id;

bool platform_video_init(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption);

/*
 * get a (NULL terminated) array of synchronization options that are
 * valid arguments to _setsynch(). It should follow the pattern
 * {"synchopt1", "description1",
 *  "synchopt2", "description2",
 *  NULL};
 */
const char** platform_video_synchopts();

/*
 * switch active synchronization strategy (if possible), strat must be
 * a valid result from platform_video_synchopts and can change dynamically.
 */
void platform_video_setsynch(const char* strat);

/*
 * triggers the actual rendering and is responsible for applying whatever
 * synchronization strategy that is currently active, and to run the related
 * benchmark costs trigger functions (bench_register_cost,bench_register_frame)
 */
typedef void (*video_synchevent)(void);
void platform_video_synch(uint64_t tick, float fract,
	video_synchevent pre, video_synchevent post);

/*
 * string that can be used to identify the underlying video platform,
 * i.e. driver version, GL string etc. Primarily intended for debug- data
 * collection.
 */
const char* platform_video_capstr();

typedef uint32_t platform_display_id;
typedef uint32_t platform_mode_id;

struct monitor_modes {
	platform_mode_id id;
	uint16_t width;
	uint16_t height;
	uint8_t refresh;
	uint8_t depth;
};

/*
 * get list of available display IDs, these can then be queried for
 * currently available modes (which is subject to change based on
 * what connectors a user inserts / removes.
 */
platform_display_id* platform_video_query_displays(size_t* count);
struct monitor_modes* platform_video_query_modes(platform_display_id,
	size_t* count);

bool platform_video_set_mode(platform_display_id, platform_mode_id mode_id);

/*
 * map a video object to the output display,
 * if id is set to ARCAN_VIDEO_BADID, that display output is disabled
 * by whatever means possible (black+dealloc, sleep display etc.)
 * if id is set to ARCAN_VIDEO_WORLDID, the primary rendertarget will
 * be used.
 *
 * The object referenced by ID is not allowed to have a ffunc associated
 * with it, this in order for the platform to be notified when it is removed.
 */
bool platform_video_map_display(arcan_vobj_id id, platform_display_id disp);

void platform_video_shutdown();

/*
 * The following function abstracts the graphics operations that
 * arcan_video.c relies on, implementations can be found in platform/agp.
 *
 * This is currently a refactor-in-progress to fix some long standing
 * issues with GL<->GLES incompatibilty and inefficies that come from
 * the previous GL2.1 requirement. When the GL_HEADERS hack has been
 * removed, that refactor can be considered completed.
 */

/*
 * Some underlying implementations need to allocate handles / contexts
 * etc. as an extension to what platform_video_init has already done.
 */
void argp_init();
struct storage_info_t;

/*
 * Set as currently active sampling buffer for other drawing commands
 */
void argp_activate_vstore(struct storage_info_t* backing);

/*
 * Explicitly deactivate vstore, after this state of the specified backing
 * store can be consideired undefined.
 */
void argp_deactivate_vstore(struct storage_info_t* backing);

/*
 * Deallocate all resources associated with a backing store.
 * This function is internally reference counted as there can be a
 * 1:* between a vobject and a backing store.
 */
void argp_drop_vstore(struct storage_info_t* backing);

/*
 * Map multiple backing store devices sequentially across
 * available texture units.
 */
void argp_activate_vstore_multi(struct storage_info_t** backing, size_t n);

/*
 * Synchronize a populated backing store with the underlying
 * graphics layer
 */
void argp_update_vstore(struct storage_info_t*, bool copy, bool mipmap);

/*
 * Allocate id and upload / store raw buffer into vstore
 */
void argp_buffer_tostore(struct storage_info_t* dst,
	av_pixel* buf, size_t buf_sz, size_t w, size_t h,
	size_t origw, size_t origh, unsigned short zv
);

#endif
