/*
 * Copyright 2014-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description:
 * This platform layer is an attempt to decouple the _video.c and _3dbase.c
 * parts of the engine from working with OpenGL directly.
 */

#ifndef HAVE_ARCAN_VIDEOPLATFORM
#define HAVE_ARCAN_VIDEOPLATFORM

#include "platform_types.h"
#include "agp_platform.h"

/*
 * run once before any other setup in order to provide for platforms that need
 * to do one-time things like opening privileged resources and then dropping
 * them. Unlike video_init, this will only be called once and before
 * environmental variables etc. are applied, so other platform features might
 * be missing.
 */
void platform_video_preinit();

/*
 * Allocate resources, devices and set up a safe initial default.
 * [w, h, bpp, fs, frames, caption] arguments are used for legacy reasons,
 * and new platform implementations should accept 0- values and rather
 * probe best values and use other mapping / notification functions for
 * resizing and similar operations.
 */
bool platform_video_init(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption);

/*
 * Sent as a trigger to notify that higher scripting levels have recovered
 * from an error and possible video- layer related events are possibly missing
 * and may need to be re-emitted.
 */
void platform_video_recovery();

/*
 * Register token as an authenticated primitive for the device connected to
 * cardn
 */
bool platform_video_auth(int cardn, unsigned token);

/*
 * Release / free as much resource as possible while still being able to
 * resume operations later. This is used for suspend/resume style behavior
 * when switching virtual terminals or when going into powersave- states.
 * After this point, the event subsystem will also be deinitialized.
 */
void platform_video_prepare_external();

/*
 * Return the number of frame updates needed for the active swapchain to
 * reach the mapped output, or 0 if this happens without the rendering layer.
 */
size_t platform_video_decay();

/*
 * Undo the effects of the prepare_external call.
 */
void platform_video_restore_external();

/*
 * get a (NULL terminated) array of environment options that can be set during
 * the command line, this is primarily used to populate command-line help.
 */
const char** platform_video_envopts();

/*
 * The AGP layer may need to dynamically map symbols against whatever graphics
 * library is in play but the video layer is typically the one capable of
 * determining how such functions should be found.
 */
void* platform_video_gfxsym(const char* sym);

/*
 * take the received handle and associate it with the specified backing store.
 * [DEPRECATED]
 */
bool platform_video_map_handle(struct agp_vstore*, int64_t inh);

/*
 * take a set of agp_buffer_planes and bind to the specified vstore.
 */
bool platform_video_map_buffer(
	struct agp_vstore*, struct agp_buffer_plane* planes, size_t n);

/*
 * Export the vstore (if possible) in agp_buffer_plane compatible format.
 * This should come either from a vstore that itself has been mapped from
 * agp planes, or be a swapped out vstore from a rendertarget.
 *
 * Returns the number of planes actually used, keep n >= 4 (YUYU)
 */
size_t platform_video_export_vstore(
	struct agp_vstore*, struct agp_buffer_plane* planes, size_t n);

/*
 * Reset and rebuild the graphics context(s) associated with a specific card
 * (or -1, default for all). If multiple cards are assigned to one cardid, the
 * swap_primary switches out the contents of one card for another index.
 *
 * This is only valid to call while the platform is in an external state,
 * i.e. _prepare_external _reset _restore_external
 */
void platform_video_reset(int cardid, int swap_primary);

/*
 * retrieve descriptor and possible access metadata necessary for allowing
 * external client access into the card specified by the cardid.
 *
 * out:metadata_sz
 * out:metadata, dynamically allocated, caller takes ownership
 * out:buffer_method, see shmif event handler
 */
int platform_video_cardhandle(int cardn,
		int* buffer_method, size_t* metadata_sz, uint8_t** metadata);

/*
 * triggers the actual rendering and is responsible for applying whatever
 * synchronization strategy that is currently active, and to run the related
 * benchmark costs trigger functions (bench_register_cost,bench_register_frame)
 */
typedef void (*video_synchevent)(void);
void platform_video_synch(uint64_t tick, float fract,
	video_synchevent pre, video_synchevent post);

/*
 * string that can be used to identify the underlying video platform, i.e.
 * driver version, GL string etc. Primarily intended for debug- data
 * collection.
 */
const char* platform_video_capstr();

typedef uint32_t platform_display_id;
typedef uint32_t platform_mode_id;

struct monitor_mode {
	platform_mode_id id;

/* coordinate system UL origo */
	size_t x, y;

/* scanout resolution */
	size_t width;
	size_t height;

/* in millimeters */
	size_t phy_width;
	size_t phy_height;

/* estimated output color depth */
	uint8_t depth;

/* estimated display vertical refresh, can be 0 to indicate a dynamic or
 * unknown rate -- primarily a hint to the synchronization strategy */
	uint8_t refresh;

/* Description regarding subpixel orientation, e.g. hRGB or vGRB etc. */
	const char* subpixel;

/* There should only be one primary mode per display */
	bool primary;

/* If the display supports user- specified mode configurations via the
 * _specify_mode option, this will be true */
	bool dynamic;
};

/*
 * Retrieve default rendertarget dimensions, virtual canvas is set in
 * width/height, output buffer is set in phy_width/phy_height
 */
struct monitor_mode platform_video_dimensions();

/*
 * Queue a rescan of output displays, this can be asynchronous and any results
 * are pushed as events.
 */
void platform_video_query_displays();

/*
 * query list of available modes for a single display
 */
struct monitor_mode* platform_video_query_modes(
	platform_display_id, size_t* count);

/*
 * query a specific display_id for a descriptive blob (EDID for some platforms)
 * that could be used to further identify the display. Actual parsing/
 * identification is left as an exercise for the caller.
 */
bool platform_video_display_edid(platform_display_id did,
	char** out, size_t* sz);

/*
 * switch mode on the display to a previously queried one from
 * platform_video_query_modes along with override options to enable low and
 * high- definition outputs as well as target variable refresh-rates.
 */
struct platform_mode_opts {
	int depth;
	float vrr;
};

bool platform_video_set_mode(
	platform_display_id, platform_mode_id mode_id, struct platform_mode_opts opts);

/*
 * update the gamma ramps for the specified display.
 *
 * returns [true] if the [did] and [r,g,b] channels are valid, the
 * underlying display accepts gamma ramps and [n_ramps] size corresponds
 * to the size of the ramps a _get call would yield.
 *
 * practical use-case is thus to first call platform_video_get_display_gamma,
 * modify the returned ramps, call platform_video_set_display_gamma and
 * then free the buffer from _get_.
 */
bool platform_video_set_display_gamma(platform_display_id did,
	size_t n_ramps, uint16_t* r, uint16_t* g, uint16_t* b);

/*
 * Return the dynamic count of available displays, and [if set], their
 * respective values in [dids] limited by [lim].
 * [lim] will be updated with the upper limit of displays (if applicable).
 */
size_t platform_video_displays(platform_display_id* dids, size_t* lim);

/*
 * get the current gamma ramps for the specified display.
 *
 * return [true] if the [did] is valid, the underlying display
 * supports gamma ramps and enough memory exist to allocate output storage.
 *
 * [outb] will be set to a dynamically allocated buffer of 3*n_ramps,
 * with the ramps for each channel in a planar format (r, then g, then b).
 *
 * [Caller takes responsibility for deallocation]
 */
bool platform_video_get_display_gamma(platform_display_id did,
	size_t* n_ramps, uint16_t** outb);

/*
 * set or query the display power management state.
 * ADPMS_IGNORE => return current state,
 * other options change the current state of monitors connected to a display
 * and returns the estimated current state (should match requested state).
 * For LCDs, OFF / SUSPEND / STANDBY are essentially the same state.
 */
enum dpms_state {
	ADPMS_IGNORE = 0,
	ADPMS_OFF = 1,
	ADPMS_SUSPEND = 2,
	ADPMS_STANDBY = 3,
	ADPMS_ON = 4
};

enum dpms_state
	platform_video_dpms(platform_display_id disp, enum dpms_state state);

/*
 * Update and activate the specific (dynamic) mode with desired mode dimensions
 * and possibly refresh, this fails if the display do not support dynamic
 * mapping.
 */
bool platform_video_specify_mode(
	platform_display_id, struct monitor_mode mode);

/*
 * map a video object to the output display, if id is set to ARCAN_VIDEO_BADID,
 * that display output is disabled by whatever means possible (black+dealloc,
 * sleep display etc.) if id is set to ARCAN_VIDEO_WORLDID, the primary
 * rendertarget will be used.
 *
 * The object referenced by ID is not allowed to have a ffunc associated with
 * it, this in order for the platform to be notified when it is removed.
 */
enum blitting_hint {
	HINT_NONE = 0,
	HINT_FL_PRIMARY = 1,
	HINT_FIT = 2,
	HINT_CROP = 4,
	HINT_YFLIP = 8,
	HINT_ROTATE_CW_90 = 16,
	HINT_ROTATE_CCW_90 = 32,
	HINT_ROTATE_180 = 64,
	HINT_CURSOR = 128, /* not permitted for layer == 0 */
	HINT_DIRECT = 256, /* attempt direct scanout (ignore force_compose setting) */
	HINT_ENDM = 156
};

/* This replaces the platform_video_map_display call and can be used for
 * runtime configuration of hardware accelerated composition and special
 * display features. Will return the upper limit of possible layers left based
 * on the current configuration, or -1 if the combination cannot be solved for. */
struct display_layer_cfg {
	ssize_t x;
	ssize_t y;
	enum blitting_hint hint;
	float opacity;
};

ssize_t platform_video_map_display_layer(arcan_vobj_id id,
	platform_display_id disp, size_t layer_index, struct display_layer_cfg cfg);

/* For all displays that map the supplied vstore at any layer, mark the related
 * region as having been changed - this is mainly intended for dynamic vstores
 * where damage tracking is possible. Mappings that act as render-targets are
 * excluded by default. */
void platform_video_invalidate_map(
	struct agp_vstore*, struct agp_region region);

/* deprecated - simply maps to display_layer=0 */
bool platform_video_map_display(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint);

void platform_video_shutdown();

#endif
