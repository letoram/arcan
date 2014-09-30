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
#endif
