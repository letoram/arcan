/*
 * copyright 2014-2016, björn ståhl
 * license: 3-clause bsd, see copying file in arcan source repository.
 * reference: http://arcan-fe.com
 */

/*
 * points to explore for this platform module:
 *
 * (currently a bit careful spending more time here pending the development
 * of vulkan, nvidia egl streams extension etc.)
 *
 * 0. _prepare _restore external support, currently there are a number of
 * related bugs and races that can be triggered with VT switching that tells
 * us the _agp layer and our rebuilding/reinit is incomplete.
 *
 * 1. <Zero Connector mode> This one is quite heavy, due to the way EGL and
 * friends are integrated the current case with all displays being removed
 * isn't well supported. The best approach would probably be to treat as an
 * external_launch sort of situation or rebuild the EGL context with a
 * headless one in order for other features (sharing etc.) to remain working
 * and then switch when something is plugged in.
 *
 * 2. Multiple graphics cards and hotplugging graphics cards. Bonus points
 * for surviving VT switch, moving all displays to a new plugged GPU, VT
 * switch back and everything remapped correctly. Don't have the hardware
 * to test this at all now.
 *
 * Possibly approach is to do something like this:
 *  a. create an agp- function that synchs raw / s_raw for all objects
 *     (readback into buffers etc).
 *
 *  b. reset hadle passing failure state for all frameservers,
 *     send a MIGRATE event with descriptor, indicating that those who use
 *     a certain render node need to switch / rebuild. This would work
 *     recursively for arcan_lwa.
 *
 *  c. [shared output]
 *      ACPI- twiddle to shut down one GPU, activate the other, redo
 *      grab_card and build GL, and just rerun the mapping.
 *
 *     [different output]
 *      activate the other card and build GL, emitt a display reset event
 *      and do a new connector scan.
 *
 *  d. agp call to push all data back up, and possible erase if needed.
 *
 *  The number of failure modes for this one is quite high, especially
 *  when OOM on one card but not the other. Still, pretty cool feature ;-)
 *
 * 4. Advanced synchronization options (swap-interval, synch directly to
 * front buffer, swap-with-tear, pre-render then wake / move cursor just
 * before etc.), discard when we miss deadline, drm_vblank_relative,
 * drm_vblank_secondary - also try synch strategy on a per display basis.
 *
 * 5. DRMs Atomic- modesetting support is currently not used
 *
 * 6. egl-nvidia bits about streams should be merged after [5]
 *
 * 7. "always" headless mode of operation build-time for processing
 *    jobs and other situations where wer don't need the full monty. Would
 *    best be done with [1]
 */

/*
 * Notes on hotplug / hotremoval: We are quite adamant in staying away from
 * pulling in a nasty dependency like udev into the platform build, but it
 * seems like the libdrm interface fails to provide a polling mechanism for
 * display changes, and that CRTC scanning is very costly (hundreds of
 * miliseconds)
 *
 * the current concession is that this is something that is up to the appl to
 * decide if it should be exposed or not. As an example, 'durden' has its
 * _cmd fifo mapped to rescan for that purpose. This can further be mapped
 * to evdev- style nodes which some drivers seem to map hotplug.
 *
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <glob.h>
#include <ctype.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <poll.h>

#include <fcntl.h>
#include <assert.h>

#include <libdrm/drm.h>
#include <libdrm/drm_mode.h>
#include <libdrm/drm_fourcc.h>

#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>

/*
 * Other refactoring project -- see if we can extract out what we need from
 * libdrm etc. without pulling in xlib, xcb and everything else that world
 * has to offer.
 */
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <gbm.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_videoint.h"
#include "arcan_led.h"
#include "arcan_shmif.h"
#include "../agp/glfun.h"
#include "arcan_event.h"
#include "libbacklight.h"

/*
 * extensions needed for buffer passing
 */
static PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR;
static PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES;

/*
 * real heuristics scheduled for 0.5.3, see .5 at top
 */
static char* egl_synchopts[] = {
	"default", "double buffered, Display controls refresh",
	NULL
};

static char* egl_envopts[] = {
	"ARCAN_VIDEO_DEVICE=/dev/dri/card0", "specifiy primary device",
	"ARCAN_VIDEO_CONNECTOR=conn_ind", "primary display connector (invalid lists)",
	"ARCAN_VIDEO_DRM_MASTER", "fail if drmMaster can't be obtained",
	"ARCAN_VIDEO_WAIT_CONNECTOR", "loop until an active connector is found",
	NULL
};

enum {
	DEFAULT,
	ENDM
} synchopt;

/*
 * Each open output device, can be shared between displays
 */
struct dev_node {
	int fd, rnode;
	bool master;
	int refc;
	int card_id;
	uint32_t crtc_alloc;
	struct gbm_device* gbm;

	EGLConfig config;
	EGLContext context;
	EGLDisplay display;
};

enum disp_state {
	DISP_UNUSED = 0,
	DISP_KNOWN = 1,
	DISP_MAPPED = 2,
	DISP_CLEANUP = 3,
	DISP_EXTSUSP = 4
};

/*
 * Multiple- device nodes (i.e. cards) is currently untested
 * and thus only partially implemented due to lack of hardware
 */
static const int MAX_NODES = 1;
static struct dev_node nodes[1];

/*
 * aggregation struct that represent one triple of display, card, bindings
 */
struct dispout {
/* connect drm, gbm and EGLs idea of a device */
	struct dev_node* device;

/* 1 buffer for 1 device for 1 display */
	struct {
		int in_flip, in_destroy;
		EGLSurface esurf;
		struct gbm_bo* cur_bo, (* next_bo);
		uint32_t cur_fb, next_fb;
		struct gbm_surface* surface;
	} buffer;

	struct {
		bool reset_mode, primary;
		drmModeConnector* con;
		uint32_t con_id;
		drmModeModeInfoPtr mode;
		drmModeCrtcPtr old_crtc;
		int crtc;
		enum dpms_state dpms;
		char* edid_blob;
		size_t blob_sz;
		size_t blackframes;
		size_t gamma_size;
		uint16_t* orig_gamma;
	} display;

/* v-store mapping, with texture blitting options and possibly mapping hint */
	arcan_vobj_id vid;
	size_t dispw, disph, dispx, dispy;;
	_Alignas(16) float projection[16];
	_Alignas(16) float txcos[8];

/* backlight is "a bit" quirky, we register a custom led controller that
 * is processed while we're synching- where the subleds correspond to the
 * displayid of the display */
	struct backlight* backlight;
	long backlight_brightness;

	enum blitting_hint hint;
	enum disp_state state;
	platform_display_id id;
};

static struct {
	struct dispout* last_display;
	size_t canvasw, canvash;
	int destroy_pending;
	int ledid, ledind;
	uint8_t ledval[3];
	int ledpair[2];
} egl_dri = {
	.ledind = 255
};

#ifndef MAX_DISPLAYS
#define MAX_DISPLAYS 16
#endif

static struct dispout displays[MAX_DISPLAYS];

static struct dispout* allocate_display(struct dev_node* node)
{
	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_UNUSED){
			displays[i].device = node;
			displays[i].id = i;
			displays[i].display.primary = false;

			node->refc++;
			displays[i].state = DISP_KNOWN;
			return &displays[i];
		}
	}

	return NULL;
}

static struct dispout* get_display(size_t index)
{
	if (index >= MAX_DISPLAYS)
		return NULL;
	else
		return &displays[index];
}

static int adpms_to_dpms(enum dpms_state state)
{
	switch (state){
	case ADPMS_ON: return DRM_MODE_DPMS_ON;
	case ADPMS_STANDBY: return DRM_MODE_DPMS_STANDBY;
	case ADPMS_SUSPEND: return DRM_MODE_DPMS_SUSPEND;
	case ADPMS_OFF: return DRM_MODE_DPMS_OFF;
	default:
		return -1;
	}
}

static void dpms_set(struct dispout* d, int level)
{
	drmModePropertyPtr prop;
	for (size_t i = 0; i < d->display.con->count_props; i++){
		prop = drmModeGetProperty(d->device->fd, d->display.con->props[i]);
		if (!prop)
			continue;

		if (strcmp(prop->name, "DPMS") == 0){
			drmModeConnectorSetProperty(d->device->fd,
				d->display.con->connector_id, prop->prop_id, level);
			i = d->display.con->count_props;
		}

		drmModeFreeProperty(prop);
	}
}

/*
 * free, dealloc, possibly re-index displays
 */
static void disable_display(struct dispout*, bool);

/*
 * assumes that the video pipeline is in a state to safely
 * blit, will take the mapped objects and schedule buffer transfer
 */
static void update_display(struct dispout*);

/* naive approach, unless env is set, just scan /dev/dri/card* and
 * grab the first one present that also results in a working gbm
 * device, only used during first init */
static void grab_card(int n, char** card, int* fd)
{
	*card = NULL;
	*fd = -1;
	const char* override = getenv("ARCAN_VIDEO_DEVICE");
	if (override){
		if (isdigit(override[0]))
			*fd = strtoul(override, NULL, 10);
		else
			*card = strdup(override);
		return;
	}

#ifndef VDEV_GLOB
#define VDEV_GLOB "/dev/dri/card*"
#endif

	glob_t res;

	if (glob(VDEV_GLOB, 0, NULL, &res) == 0){
		char** beg = res.gl_pathv;
		while(n > 0 && *beg++){
			n--;
		}
		char* rstr = *beg ? strdup(*beg) : NULL;
		globfree(&res);
		*card = rstr;
	}
}

static char* last_err = "unknown";
static size_t err_sz = 0;
#define SET_SEGV_MSG(X) last_err = (X); err_sz = sizeof(X);

static void sigsegv_errmsg(int sign)
{
	size_t nw __attribute__((unused));
	nw = write(STDOUT_FILENO, last_err, err_sz);
	_exit(EXIT_FAILURE);
}

static const char* egl_errstr()
{
	EGLint errc = eglGetError();
	switch(errc){
	case EGL_SUCCESS:
		return "Success";
	case EGL_NOT_INITIALIZED:
		return "Not initialize for the specific display connection";
	case EGL_BAD_ACCESS:
		return "Cannot access the requested resource (wrong thread?)";
	case EGL_BAD_ALLOC:
		return "Couldn't allocate resources for the requested operation";
	case EGL_BAD_ATTRIBUTE:
		return "Unrecognized attribute or attribute value";
	case EGL_BAD_CONTEXT:
		return "Context argument does not name a valid context";
	case EGL_BAD_CONFIG:
		return "EGLConfig argument did not match a valid config";
	case EGL_BAD_CURRENT_SURFACE:
		return "Current surface refers to an invalid destination";
	case EGL_BAD_DISPLAY:
		return "The EGLDisplay argument does not match a valid display";
	case EGL_BAD_SURFACE:
		return "EGLSurface argument does not name a valid surface";
	case EGL_BAD_MATCH:
		return "Inconsistent arguments";
	case EGL_BAD_PARAMETER:
		return "Invalid parameter passed to function";
	case EGL_BAD_NATIVE_PIXMAP:
		return "NativePixmapType is invalid";
	case EGL_BAD_NATIVE_WINDOW:
		return "Native Window Type does not refer to a valid window";
	case EGL_CONTEXT_LOST:
		return "Power-management event has forced the context to drop";
	default:
		return "Uknown Error";
	}
}

static int setup_buffers(struct dispout* d)
{
	SET_SEGV_MSG("libgbm(), creating scanout buffer"
		" failed catastrophically.\n")

#ifdef HDEF_10BIT
	d->buffer.surface = gbm_surface_create(d->device->gbm,
		d->display.mode->hdisplay, d->display.mode->vdisplay,
		GBM_FORMAT_XRGB2101010, GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING
	);

	if (!d->buffer.surface && (arcan_warning("libgbm(), 10-bit output\
		requested but no suitable scanout, trying 8-bit\n"), 1))
#else
	d->buffer.surface = gbm_surface_create(d->device->gbm,
		d->display.mode->hdisplay, d->display.mode->vdisplay,
		GBM_FORMAT_XRGB8888, GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING
	);
#endif

	d->buffer.esurf = eglCreateWindowSurface(d->device->display,
		d->device->config, (uintptr_t)d->buffer.surface, NULL);

	if (d->buffer.esurf == EGL_NO_SURFACE) {
		arcan_warning("egl-dri() -- couldn't create a window surface.\n");
		return -1;
	}

	eglMakeCurrent(d->device->display, d->buffer.esurf,
		d->buffer.esurf, d->device->context);

	return 0;
}

int platform_video_cardhandle(int cardn)
{
	if (cardn < 0 || cardn > MAX_NODES)
		return -1;

	return nodes[cardn].rnode;
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	struct dispout* d = get_display(disp);

	if (!d || d->state != DISP_MAPPED || mode >= d->display.con->count_modes)
		return false;

	if (d->display.mode == &d->display.con->modes[mode])
		return true;

	d->display.reset_mode = true;
	d->display.mode = &d->display.con->modes[mode];
	build_orthographic_matrix(d->projection,
		0, d->display.mode->hdisplay, d->display.mode->vdisplay, 0, 0, 1);
	d->dispw = d->display.mode->hdisplay;
	d->disph = d->display.mode->vdisplay;

/*
 * reset scanout buffers to match new crtc mode
	if (d->buffer.cur_bo){
		gbm_surface_release_buffer(d->buffer.surface, d->buffer.cur_bo);
		d->buffer.cur_bo = NULL;
	}

	if (d->buffer.next_bo){
		gbm_surface_release_buffer(d->buffer.surface, d->buffer.next_bo);
		d->buffer.next_bo = NULL;
	}
*/
	d->state = DISP_CLEANUP;
	eglDestroySurface(d->device->display, d->buffer.esurf);

/*
 * drop current framebuffers
 	if (d->buffer.cur_fb){
		drmModeRmFB(d->device->fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
	}

	if(d->buffer.next_fb){
		drmModeRmFB(d->device->fd, d->buffer.next_fb);
		d->buffer.next_fb = 0;
	}
*/
	gbm_surface_destroy(d->buffer.surface);

/*
 * setup / allocate a new set of buffers that match the new mode
 */
	setup_buffers(d);
	d->state = DISP_MAPPED;

	return true;
}

bool platform_video_set_display_gamma(platform_display_id did,
	size_t n_ramps, uint16_t* r, uint16_t* g, uint16_t* b)
{
	struct dispout* d = get_display(did);
	if (!d)
		return false;

	drmModeCrtc* inf = drmModeGetCrtc(d->device->fd, d->display.crtc);

	if (!inf)
		return false;

	int rv = -1;
	if (inf->gamma_size > 0 && n_ramps == inf->gamma_size){
/* first time we get called, saved trhe original gamma for the display
 * so that we can restore it when the display gets deallocated */
		if (!d->display.orig_gamma){
			if (!platform_video_get_display_gamma(did,
				&d->display.gamma_size, &d->display.orig_gamma)){
				drmModeFreeCrtc(inf);
				return false;
			}
		}
		rv = drmModeCrtcSetGamma(d->device->fd, d->display.crtc, n_ramps, r, g, b);
	}

	drmModeFreeCrtc(inf);
	return rv == 0;
}

bool platform_video_get_display_gamma(platform_display_id did,
	size_t* n_ramps, uint16_t** outb)
{
	struct dispout* d = get_display(did);
	if (!d || !n_ramps)
		return false;

	drmModeCrtc* inf = drmModeGetCrtc(d->device->fd, d->display.crtc);
	if (!inf)
		return false;

	if (inf->gamma_size <= 0){
		drmModeFreeCrtc(inf);
		return false;
	}

	*n_ramps = inf->gamma_size;
	uint16_t* ramps = malloc(*n_ramps * 3 * sizeof(uint16_t));
	if (!ramps){
		drmModeFreeCrtc(inf);
		return false;
	}

	bool rv = true;
	memset(ramps, '\0', *n_ramps * 3 * sizeof(uint16_t));
	if (drmModeCrtcGetGamma(d->device->fd, d->display.crtc, *n_ramps,
		&ramps[0], &ramps[*n_ramps], &ramps[2 * *n_ramps])){
		free(ramps);
		rv = false;
	}
	*outb = ramps;
	drmModeFreeCrtc(inf);
	return rv;
}

bool platform_video_display_edid(platform_display_id did,
	char** out, size_t* sz)
{
	struct dispout* d = get_display(did);
	if (!d)
		return false;

	*out = NULL;
	*sz = 0;

	if (d->display.edid_blob){
		*sz = 0;
		*out = malloc(d->display.blob_sz);
		if (*out){
			*sz = d->display.blob_sz;
			memcpy(*out, d->display.edid_blob, d->display.blob_sz);
		}
		return true;
	}
	return false;
}

/*
 * this platform does not currently support dynamic modes
 * (this should well be possible for old CRTs though)..
 */
bool platform_video_specify_mode(
	platform_display_id disp, struct monitor_mode mode)
{
	return false;
}

static bool map_extensions()
{
	eglCreateImageKHR = (PFNEGLCREATEIMAGEKHRPROC)
		eglGetProcAddress("eglCreateImageKHR");

	eglDestroyImageKHR = (PFNEGLDESTROYIMAGEKHRPROC)
		eglGetProcAddress("eglDestroyImageKHR");

	glEGLImageTargetTexture2DOES = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
		eglGetProcAddress("glEGLImageTargetTexture2DOES");

	return true;
}

static void drm_mode_tos(FILE* dst, unsigned val)
{
	if ( (val & DRM_MODE_TYPE_BUILTIN) > 0){
		fprintf(dst, "/builtin");
		val &= ~DRM_MODE_TYPE_BUILTIN;
	}

	if ( (val & DRM_MODE_TYPE_CLOCK_C) > 0){
		fprintf(dst, "/clock");
		val &= ~DRM_MODE_TYPE_CLOCK_C;
	}

	if ( (val & DRM_MODE_TYPE_CRTC_C) > 0){
		fprintf(dst, "/crtc");
		val &= ~DRM_MODE_TYPE_CRTC_C;
	}

	if ( (val & DRM_MODE_TYPE_PREFERRED) > 0){
		fprintf(dst, "/preferred");
		val &= ~DRM_MODE_TYPE_PREFERRED;
	}

	if ( (val & DRM_MODE_TYPE_DEFAULT) > 0){
		fprintf(dst, "/default");
		val &= ~DRM_MODE_TYPE_DEFAULT;
	}

	if ( (val & DRM_MODE_TYPE_USERDEF) > 0){
		fprintf(dst, "/userdef");
		val &= ~DRM_MODE_TYPE_USERDEF;
	}

	if ( (val & DRM_MODE_TYPE_DRIVER) > 0){
		fprintf(dst, "/driver");
		val &= ~DRM_MODE_TYPE_DRIVER;
	}

	if ( val > 0 )
		fprintf(dst, "/unknown(%d)", (int)val);
}

static void drm_mode_flag(FILE* dst, unsigned val)
{
	if ( (val & DRM_MODE_FLAG_PHSYNC) > 0 ){
		fprintf(dst, "/phsync");
		val &= ~DRM_MODE_FLAG_PHSYNC;
	}

	if ( (val & DRM_MODE_FLAG_NHSYNC) > 0 ){
		fprintf(dst, "/nhsync");
		val &= ~DRM_MODE_FLAG_NHSYNC;
	}

	if ( (val & DRM_MODE_FLAG_PVSYNC) > 0 ){
		fprintf(dst, "/pvsync");
		val &= ~DRM_MODE_FLAG_PVSYNC;
	}

	if ( (val & DRM_MODE_FLAG_NVSYNC) > 0 ){
		fprintf(dst, "/nvsync");
		val &= ~DRM_MODE_FLAG_NVSYNC;
	}

	if ( (val & DRM_MODE_FLAG_INTERLACE) > 0 ){
		fprintf(dst, "/interlace");
		val &= ~DRM_MODE_FLAG_INTERLACE;
	}

	if ( (val & DRM_MODE_FLAG_DBLSCAN) > 0 ){
		fprintf(dst, "/dblscan");
		val &= ~DRM_MODE_FLAG_DBLSCAN;
	}

	if ( (val & DRM_MODE_FLAG_CSYNC) > 0 ){
		fprintf(dst, "/csync");
		val &= ~DRM_MODE_FLAG_CSYNC;
	}

	if ( (val & DRM_MODE_FLAG_PCSYNC) > 0 ){
		fprintf(dst, "/pcsync");
		val &= ~DRM_MODE_FLAG_PCSYNC;
	}

	if ( (val & DRM_MODE_FLAG_NCSYNC) > 0 ){
		fprintf(dst, "/ncsync");
		val &= ~DRM_MODE_FLAG_NCSYNC;
	}

	if ( (val & DRM_MODE_FLAG_HSKEW) > 0 ){
		fprintf(dst, "/hskew");
		val &= ~DRM_MODE_FLAG_HSKEW;
	}

	if ( (val & DRM_MODE_FLAG_BCAST) > 0 ){
		fprintf(dst, "/bcast");
		val &= ~DRM_MODE_FLAG_BCAST;
	}

	if ( (val & DRM_MODE_FLAG_PIXMUX) > 0 ){
		fprintf(dst, "/pixmux");
		val &= ~DRM_MODE_FLAG_PIXMUX;
	}

	if ( (val & DRM_MODE_FLAG_DBLCLK) > 0 ){
		fprintf(dst, "/dblclk");
		val &= ~DRM_MODE_FLAG_DBLCLK;
	}

	if ( (val & DRM_MODE_FLAG_CLKDIV2) > 0 ){
		fprintf(dst, "/clkdiv2");
		val &= ~DRM_MODE_FLAG_CLKDIV2;
	}

	if ( (val & DRM_MODE_FLAG_3D_MASK) > 0 ){
		fprintf(dst, "/3dmask");
		val &= ~DRM_MODE_FLAG_3D_MASK;
	}

	if ( (val & DRM_MODE_FLAG_3D_NONE) > 0 ){
		fprintf(dst, "/3dnone");
		val &= ~DRM_MODE_FLAG_3D_NONE;
	}

	if ( (val & DRM_MODE_FLAG_3D_FRAME_PACKING) > 0 ){
		fprintf(dst, "/3dframep");
		val &= ~DRM_MODE_FLAG_3D_FRAME_PACKING;
	}

	if ( (val & DRM_MODE_FLAG_3D_FIELD_ALTERNATIVE) > 0 ){
		fprintf(dst, "/3dfield_alt");
		val &= ~DRM_MODE_FLAG_3D_FIELD_ALTERNATIVE;
	}

	if ( (val & DRM_MODE_FLAG_3D_LINE_ALTERNATIVE) > 0 ){
		fprintf(dst, "/3dline_alt");
		val &= ~DRM_MODE_FLAG_3D_LINE_ALTERNATIVE;
	}

	if ( (val & DRM_MODE_FLAG_3D_SIDE_BY_SIDE_FULL) > 0 ){
		fprintf(dst, "/3dsbs");
		val &= ~DRM_MODE_FLAG_3D_SIDE_BY_SIDE_FULL;
	}

	if ( (val & DRM_MODE_FLAG_3D_L_DEPTH) > 0 ){
		fprintf(dst, "/3dldepth");
		val &= ~DRM_MODE_FLAG_3D_L_DEPTH;
	}

	if ( (val & DRM_MODE_FLAG_3D_L_DEPTH_GFX_GFX_DEPTH) > 0 ){
		fprintf(dst, "/3dldepth_gfx2_depth");
		val &= ~DRM_MODE_FLAG_3D_L_DEPTH_GFX_GFX_DEPTH;
	}

	if ( (val & DRM_MODE_FLAG_3D_TOP_AND_BOTTOM) > 0 ){
		fprintf(dst, "/3dt&b");
		val &= ~DRM_MODE_FLAG_3D_TOP_AND_BOTTOM;
	}

	if ( (val & DRM_MODE_FLAG_3D_SIDE_BY_SIDE_HALF) > 0 ){
		fprintf(dst, "/3dsbs-h");
		val &= ~DRM_MODE_FLAG_3D_SIDE_BY_SIDE_HALF;
	}

	if (val > 0){
		fprintf(dst, "/unknown(%d)", (int) val);
	}
}

static void drm_mode_connector(FILE* fpek, int val)
{
	switch(val){
	case DRM_MODE_CONNECTOR_Unknown:
		fprintf(fpek, "unknown");
	break;

	case DRM_MODE_CONNECTOR_VGA:
		fprintf(fpek, "vga");
	break;

	case DRM_MODE_CONNECTOR_DVII:
		fprintf(fpek, "dvii");
	break;

	case DRM_MODE_CONNECTOR_DVID:
		fprintf(fpek, "dvid");
	break;

	case DRM_MODE_CONNECTOR_DVIA:
		fprintf(fpek, "dvia");
	break;

	case DRM_MODE_CONNECTOR_Composite:
		fprintf(fpek, "composite");
	break;

	case DRM_MODE_CONNECTOR_SVIDEO:
		fprintf(fpek, "s-video");
	break;

	case DRM_MODE_CONNECTOR_Component:
		fprintf(fpek, "component");
	break;

	case DRM_MODE_CONNECTOR_9PinDIN:
		fprintf(fpek, "9-pin din");
	break;

	case DRM_MODE_CONNECTOR_DisplayPort:
		fprintf(fpek, "displayPort");
	break;

	case DRM_MODE_CONNECTOR_HDMIA:
		fprintf(fpek, "hdmi-a");
	break;

	case DRM_MODE_CONNECTOR_HDMIB:
		fprintf(fpek, "hdmi-b");
	break;

	case DRM_MODE_CONNECTOR_TV:
		fprintf(fpek, "tv");
	break;

	case DRM_MODE_CONNECTOR_eDP:
		fprintf(fpek, "eDP");
	break;

	default:
		fprintf(fpek, "unknown");
	}
}

/* should be passed on to font rendering */
static const char* subpixel_type(int val)
{
	switch(val){
	case DRM_MODE_SUBPIXEL_UNKNOWN:
		return "unknown";

	case DRM_MODE_SUBPIXEL_HORIZONTAL_RGB:
		return "horiz- RGB";

	case DRM_MODE_SUBPIXEL_HORIZONTAL_BGR:
		return "horiz- BGR";

	case DRM_MODE_SUBPIXEL_VERTICAL_RGB:
		return "vert- RGB";

	case DRM_MODE_SUBPIXEL_VERTICAL_BGR:
		return "vert- BGR";

	default:
		return "unsupported";
	}
}

static const char* connection_type(int conn)
{
	switch(conn){
	case DRM_MODE_CONNECTED:
		return "connected";

	case DRM_MODE_DISCONNECTED:
		return "not connected";

	case DRM_MODE_UNKNOWNCONNECTION:
		return "unknown";

	default:
		return "undefined";
	}
}

static void dump_connectors(FILE* dst, struct dev_node* node, bool shorth)
{
	drmModeRes* res = drmModeGetResources(node->fd);
	if (!res){
		fprintf(dst, "DRM dump, couldn't acquire resource list\n");
		return;
	}

	fprintf(dst, "DRM Dump: \n\tConnectors: %d\n", res->count_connectors);
	for (size_t i = 0; i < res->count_connectors; i++){
		drmModeConnector* conn = drmModeGetConnector(
			node->fd, res->connectors[i]);
		if (!conn)
			continue;

		fprintf(dst, "\t(%d), id:(%d), encoder:(%d), type: ",
			(int) i, conn->connector_id, conn->encoder_id);
		drm_mode_connector(dst, conn->connector_type);
		fprintf(dst, " phy(%d * %d), mode: %s, hinting: %s\n",
			(int)conn->mmWidth, (int)conn->mmHeight,
			connection_type(conn->connection),
			subpixel_type(conn->subpixel));

		if (!shorth)
			for (size_t j = 0; j < conn->count_modes; j++){
				fprintf(dst, "\t\t Mode (%d:%s): clock@%d, refresh@%d\n\t\tflags : ",
					(int)j, conn->modes[j].name,
					conn->modes[j].clock, conn->modes[j].vrefresh
			)	;
				drm_mode_flag(dst, conn->modes[j].flags);
				fprintf(dst, " type : ");
				drm_mode_tos(dst, conn->modes[j].type);
			}

		fprintf(dst, "\n\n");
		drmModeFreeConnector(conn);
	}

	drmModeFreeResources(res);
}

static int setup_node(struct dev_node* node, const char* path, int fd)
{
	SET_SEGV_MSG("libdrm(), open device failed (check permissions) "
		" or use ARCAN_VIDEO_DEVICE environment.\n");

	memset(node, '\0', sizeof(struct dev_node));
	node->rnode = -1;
	if (!path && fd == -1)
		return -1;
	else if (!path)
		node->fd = fd;
	else
		node->fd = open(path, O_RDWR);

	if (-1 == node->fd){
		if (path)
			arcan_warning("egl-dri(), open device failed on path(%s)\n", path);
		else
			arcan_warning("egl-dri(), open device failed on fd(%d)\n", fd);
		return -1;
	}

	SET_SEGV_MSG("libgbm(), create device failed catastrophically.\n");
	fcntl(node->fd, F_SETFD, FD_CLOEXEC);
	node->gbm = gbm_create_device(node->fd);

	if (!node->gbm){
		arcan_warning("egl-dri(), couldn't create gbm device on node.\n");
		close(node->fd);
		if (node->rnode >= 0)
			close(node->rnode);
		node->rnode = -1;
		node->fd = -1;
		return -1;
	}

/*
 * this is a hack until we find a better way to derive a handle to a matching
 * render node from the gbm connection, and then use TARGET_COMMAND_DEVICE_NODE
 */
	const char cpath[] = "/dev/dri/card";
	char pbuf[24] = "/dev/dri/renderD128";

	if (!getenv("ARCAN_RENDER_NODE") && path && strncmp(path, cpath, 13) == 0){
		size_t ind = strtoul(&path[13], NULL, 10);
		snprintf(pbuf, 24, "/dev/dri/renderD%d", (int)(ind + 128));
	}
	setenv("ARCAN_RENDER_NODE", pbuf, 1);
	node->rnode = open(pbuf, O_RDWR | O_CLOEXEC);

	static const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	const char* ident = agp_ident();

	EGLint apiv;

	static EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, 0,
		EGL_RED_SIZE, OUT_DEPTH_R,
		EGL_GREEN_SIZE, OUT_DEPTH_G,
		EGL_BLUE_SIZE, OUT_DEPTH_B,
		EGL_ALPHA_SIZE, OUT_DEPTH_A,
		EGL_DEPTH_SIZE, 1,
		EGL_STENCIL_SIZE, 1,
		EGL_NONE
	};

	size_t i = 0;
	if (strcmp(ident, "OPENGL21") == 0){
		apiv = EGL_OPENGL_API;
		for (i = 0; attribs[i] != EGL_RENDERABLE_TYPE; i++);
		attribs[i+1] = EGL_OPENGL_BIT;
	}
	else if (strcmp(ident, "GLES3") == 0 ||
		strcmp(ident, "GLES2") == 0){
		for (i = 0; attribs[i] != EGL_RENDERABLE_TYPE; i++);
#ifndef EGL_OPENGL_ES2_BIT
			arcan_warning("EGL implementation do not support GLESv2, "
				"yet AGP platform requires it, use a different AGP platform.\n");
			return -2;
#endif

#ifndef EGL_OPENGL_ES3_BIT
#define EGL_OPENGL_ES3_BIT EGL_OPENGL_ES2_BIT
#endif
		attribs[i+1] = EGL_OPENGL_ES3_BIT;
		apiv = EGL_OPENGL_ES_API;
	}
	else
		return -2;

	SET_SEGV_MSG("EGL-dri(), getting the display failed\n");
/*
 * first part of GL setup, we create the display,
 * config and device as they seem to be on a per-GPU basis
 */

	node->display = eglGetDisplay((void*)(node->gbm));
	if (!eglInitialize(node->display, NULL, NULL)){
		arcan_warning("egl-dri() -- failed to initialize EGL.\n");
		goto reset_node;
	}

/*
 * make sure the API we've selected match the AGP platform
 */
	if (!eglBindAPI(apiv)){
		arcan_warning("egl-dri() -- couldn't bind GL API.\n");
		goto reset_node;
	}

/*
 * grab and activate config
 */
	EGLint nc;
	eglGetConfigs(node->display, NULL, 0, &nc);
	if (nc < 1){
		arcan_warning(
			"egl-dri() -- no configurations found (%s).\n", egl_errstr());
		goto reset_node;
	}

	EGLConfig* configs = malloc(sizeof(EGLConfig) * nc);
	memset(configs, '\0', sizeof(EGLConfig) * nc);

	EGLint selv;
	arcan_warning(
		"egl-dri() -- %d configurations found.\n", (int) nc);

	if (!eglChooseConfig(node->display, attribs, &node->config, 1, &selv)){
		arcan_warning(
			"egl-dri() -- couldn't chose a configuration (%s).\n", egl_errstr());
		free(configs);
		goto reset_node;
	}

/*
 * finally create a context to match, the last part of egl
 * setup, comes when more of the stack is up and running
 */
	node->context = eglCreateContext(node->display, node->config,
		EGL_NO_CONTEXT, context_attribs);
	if (node->context == NULL) {
		arcan_warning("egl-dri() -- couldn't create a context.\n");
		goto reset_node;
	}

	return 0;

reset_node:
	close(node->fd);
	if (node->rnode >= 0)
		close(node->rnode);
	node->rnode = -1;
	node->fd = -1;
	gbm_device_destroy(node->gbm);
	node->gbm = NULL;

	return -1;
}

static int setup_kms(struct dispout* d, int conn_id, size_t w, size_t h)
{
	SET_SEGV_MSG("egl-dri(), enumerating connectors on device failed.\n");
	drmModeRes* res;

retry:
 	res = drmModeGetResources(d->device->fd);
	if (!res){
		arcan_warning("egl-dri(), drmModeGetResources failed on %d\n",
			(int)d->device->fd);

		return -1;
	}

/* for the default case we don't have a connector, but for
 * newly detected displays we store / reserve */
	if (!d->display.con)
	for (int i = 0; i < res->count_connectors; i++){
		d->display.con = drmModeGetConnector(d->device->fd, res->connectors[i]);

		if (d->display.con->connection == DRM_MODE_CONNECTED &&
			(conn_id == -1 || conn_id == d->display.con->connector_id))
			break;

		drmModeFreeConnector(d->display.con);
		d->display.con = NULL;
	}

/*
 * No connect in place, set a retry- timer or give up
 */
	if (!d->display.con){
		drmModeFreeResources(res);

/* only wait for the first display */
		if (d == &displays[0] && getenv("ARCAN_VIDEO_WAIT_CONNECTOR")){
			arcan_warning("egl-dri(), no connected display found"
				" retrying in 5s.\n");
			sleep(5);
			goto retry;
		}

		arcan_warning("egl-dri(), no connected displays.\n");
		return -1;
	}
	d->display.con_id = d->display.con->connector_id;
	SET_SEGV_MSG("egl-dri(), enumerating connector/modes failed.\n");

/*
 * If dimensions are specified, find the closest match
 */
	if (w != 0 && h != 0)
	for (ssize_t i = 0, area = w*h; i < d->display.con->count_modes; i++){
		drmModeModeInfo* cm = &d->display.con->modes[i];
		ssize_t dist = (cm->hdisplay - w) * (cm->vdisplay - h);
		if (dist > 0 && dist < area){
			d->display.mode = cm;
			d->dispw = cm->hdisplay;
			d->disph = cm->vdisplay;
			area = dist;
		}
	}
/*
 * If no dimensions are specified, grab the first one.
 * (according to drm documentation, that should be the most 'fitting')
 */
	else if (d->display.con->count_modes >= 1){
		drmModeModeInfo* cm = &d->display.con->modes[0];
		d->display.mode = cm;
		d->dispw = cm->hdisplay;
		d->disph = cm->vdisplay;
	}

	if (!d->display.mode) {
		arcan_warning("egl-dri(), could not find a suitable display mode.\n");
		drmModeFreeConnector(d->display.con);
		d->display.con = NULL;
		drmModeFreeResources(res);
		return -1;
	}

	build_orthographic_matrix(d->projection,
		0, d->display.mode->hdisplay, d->display.mode->vdisplay, 0, 0, 1);

/*
 * grab any EDID data now as we've had issues trying to query it on some
 * displays later while buffers etc. are queued(?)
 */
	drmModePropertyPtr prop;
	bool done;
	for (size_t i = 0; i < d->display.con->count_props && !done; i++){
		prop = drmModeGetProperty(d->device->fd, d->display.con->props[i]);
		if (!prop)
			continue;

		if ((prop->flags & DRM_MODE_PROP_BLOB) &&
			0 == strcmp(prop->name, "EDID")){
			drmModePropertyBlobPtr blob =
				drmModeGetPropertyBlob(d->device->fd, d->display.con->prop_values[i]);

			if (blob && blob->length > 0){
				d->display.edid_blob = malloc(blob->length);
				if (d->display.edid_blob){
					d->display.blob_sz = blob->length;
					memcpy(d->display.edid_blob, blob->data, blob->length);
					done = true;
				}
			}
			drmModeFreePropertyBlob(blob);
		}
		drmModeFreeProperty(prop);
	}

/*
 * find encoder and use that to grab CRTC, question is if we need to track
 * encoder use as well or the crtc_alloc is sufficient.
 */
	SET_SEGV_MSG("libdrm(), setting matching encoder failed.\n");
	bool crtc_found = false;

	for (int i = 0; i < res->count_encoders; i++){
		drmModeEncoder* enc = drmModeGetEncoder(d->device->fd, res->encoders[i]);
		if (!enc)
			continue;

		for (int j = 0; j < res->count_crtcs; j++){
			if (!(enc->possible_crtcs & (1 << j)))
				continue;

			if (!(d->device->crtc_alloc & (1 << res->crtcs[j]))){
				d->display.crtc = res->crtcs[j];
				d->device->crtc_alloc |= 1 << res->crtcs[j];
				crtc_found = true;
				i = res->count_encoders;
				break;
			}

		}
	}

	if (!crtc_found){
		arcan_warning("egl-dri() - could not find a working encoder/crtc.\n");
		drmModeFreeConnector(d->display.con);
		d->display.con = NULL;
		drmModeFreeResources(res);
		return -1;
	}

	dpms_set(d, DRM_MODE_DPMS_ON);
	d->display.dpms = ADPMS_ON;

	drmModeFreeResources(res);
	return 0;
}

bool platform_video_map_handle(
	struct storage_info_t* dst, int64_t handle)
{
	EGLint attrs[] = {
		EGL_DMA_BUF_PLANE0_FD_EXT,
		handle,
		EGL_DMA_BUF_PLANE0_PITCH_EXT,
		dst->vinf.text.stride,
		EGL_DMA_BUF_PLANE0_OFFSET_EXT,
		0,
		EGL_WIDTH,
		dst->w,
		EGL_HEIGHT,
		dst->h,
		EGL_LINUX_DRM_FOURCC_EXT,
		dst->vinf.text.format,
		EGL_NONE
	};

	if (!eglCreateImageKHR || !glEGLImageTargetTexture2DOES)
		return false;

/*
 * Security notice: stride and format comes from an untrusted data source, it
 * has not been verified if MESA- implementation of eglCreateImageKHR etc.
 * treats this as trusted in respect to the buffer or not, otherwise this is a
 * possibly source for crashes etc. and I see no good way for verifying the
 * buffer manually.
 */

	if (0 != dst->vinf.text.tag){
		eglDestroyImageKHR(nodes[0].display, (EGLImageKHR) dst->vinf.text.tag);
		dst->vinf.text.tag = 0;
	}

	if (-1 == handle)
		return false;

/*
 * in addition, we actually need to know which render-node this
 * little bugger comes from, this approach is flawed for multi-gpu
 */
	EGLImageKHR img = eglCreateImageKHR(nodes[0].display,
		EGL_NO_CONTEXT,
		EGL_LINUX_DMA_BUF_EXT,
		(EGLClientBuffer)NULL, attrs
	);

	if (img == EGL_NO_IMAGE_KHR){
		arcan_warning("could not import EGL buffer (%zu * %zu), "
			"stride: %d, format: %d from %d\n", dst->w, dst->h,
		 dst->vinf.text.stride, dst->vinf.text.format,handle
		);
		return false;
	}

/* other option ?
 * EGLImage -> gbm_bo -> glTexture2D with EGL_NATIVE_PIXMAP_KHR */
	agp_activate_vstore(dst);
	glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, img);
	dst->vinf.text.tag = (uintptr_t) img;
	agp_deactivate_vstore(dst);

	return true;
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	bool free_conn = false;

	struct dispout* d = get_display(id);
	if (!d || d->state == DISP_UNUSED)
		return NULL;

	drmModeConnector* conn = d->display.con;
	drmModeRes* res = drmModeGetResources(d->device->fd);

	static struct monitor_mode* mcache;
	static size_t mcache_sz;

	*count = conn->count_modes;

	if (*count > mcache_sz){
		mcache_sz = *count;
		arcan_mem_free(mcache);
		mcache = arcan_alloc_mem(sizeof(struct monitor_mode) * mcache_sz,
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	}

	for (size_t i = 0; i < conn->count_modes; i++){
		mcache[i].refresh = conn->modes[i].vrefresh;
		mcache[i].width = conn->modes[i].hdisplay;
		mcache[i].height = conn->modes[i].vdisplay;
		mcache[i].subpixel = subpixel_type(conn->subpixel);
		mcache[i].phy_width = conn->mmWidth;
		mcache[i].phy_height = conn->mmHeight;
		mcache[i].dynamic = false;
		mcache[i].id = i;
		mcache[i].primary = d->display.mode == &conn->modes[i];
		mcache[i].depth = sizeof(av_pixel) * 8;
	}

	return mcache;
}

static struct dispout* match_connector(int fd, drmModeConnector* con)
{
	int j = 0;

	for (size_t i=0; i < MAX_DISPLAYS; i++){
		struct dispout* d = &displays[i];
		if (d->state == DISP_UNUSED)
			continue;

		if (d->device->fd == fd &&
			d->display.con->connector_id == con->connector_id)
				return d;
	}

	return NULL;
}

/*
 * The cost for this function is rather unsavory, nouveau testing has shown
 * somewhere around ~110+ ms stalls for one re-scan
 */
void platform_video_query_displays()
{
	drmModeRes* res = drmModeGetResources(nodes[0].fd);
	if (!res){
		arcan_warning("egl-dri() - couldn't get resources for rescan\n");
		return;
	}

/*
 * each device node, each connector, check against each display
 */

/*
 * ugly scan complexity, but low values of n.
 */
	for (size_t i = 0; i < res->count_connectors; i++){
		drmModeConnector* con = drmModeGetConnector(nodes[0].fd,
			res->connectors[i]);

		int id;
		struct dispout* d = match_connector(nodes[0].fd, con);

		if (con->connection == DRM_MODE_CONNECTED){
			if (d){
				drmModeFreeConnector(con);
				continue;
			}

/* allocate display and mark as known but not mapped, give up
 * if we're out of display slots */
			d = allocate_display(&nodes[0]);
			if (!d)
				break;
			d->display.con = con;
			d->display.con_id = d->display.con->connector_id;
			d->backlight = backlight_init(NULL,
				d->device->card_id, d->display.con->connector_type,
				d->display.con->connector_type_id
			);
			if (d->backlight)
				d->backlight_brightness = backlight_get_brightness(d->backlight);
/* register as a new LED controller, if FDs become a bit
 * of an issue, we could try share one big controller for all
 * displays */
			arcan_event ev = {
				.category = EVENT_VIDEO,
				.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
				.vid.displayid = d->id,
				.vid.ledctrl = egl_dri.ledid,
				.vid.ledid = d->id
			};
			arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			continue; /* don't want to free con */
		}
		else {
/* only event-notify known displays */
			if (d){
				platform_display_id id = d->id;
				disable_display(d, true);
				arcan_event ev = {
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_REMOVED,
					.vid.displayid = id,
					.vid.ledctrl = egl_dri.ledid,
					.vid.ledid = d->id
				};
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			}
		}

		drmModeFreeConnector(con);
	}

	drmModeFreeResources(res);
}

static void disable_display(struct dispout* d, bool dealloc)
{
	if (!d || d->state == DISP_UNUSED)
		return;

	if (d->buffer.in_flip){
		d->buffer.in_destroy = true;
		egl_dri.destroy_pending++;
		return;
	}

	d->device->refc--;
	if (d->buffer.in_destroy)
		egl_dri.destroy_pending--;
	d->buffer.in_destroy = false;

	if (d->display.edid_blob){
		free(d->display.edid_blob);
		d->display.edid_blob = NULL;
		d->display.blob_sz = 0;
	}

	if (d->state == DISP_KNOWN){
		d->device = NULL;
		d->state = DISP_UNUSED;
		return;
	}

	d->state = DISP_CLEANUP;
	eglMakeCurrent(d->device->display, EGL_NO_SURFACE,
		EGL_NO_SURFACE, d->device->context);

	eglDestroySurface(d->device->display, d->buffer.esurf);
	d->buffer.esurf = NULL;

	if (d->buffer.cur_fb){
		drmModeRmFB(d->device->fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
	}

	if (d->buffer.next_fb){
		drmModeRmFB(d->device->fd, d->buffer.next_fb);
		d->buffer.next_fb = 0;
	}

	gbm_surface_destroy(d->buffer.surface);
	d->buffer.surface = NULL;

	d->device->crtc_alloc &= ~(1 << d->display.crtc);

	if (d->display.old_crtc && 0 > drmModeSetCrtc(
		d->device->fd,
		d->display.old_crtc->crtc_id,
		d->display.old_crtc->buffer_id,
		d->display.old_crtc->x,
		d->display.old_crtc->y,
		&d->display.con_id, 1,
		&d->display.old_crtc->mode
	)){

#ifdef _DEBUG
		arcan_warning("Error setting old CRTC on %d\n", d->display.con_id);
#endif
	}

	if (dealloc){
		if (d->display.orig_gamma){
			drmModeCrtcSetGamma(d->device->fd, d->display.crtc,
				d->display.gamma_size, d->display.orig_gamma,
				&d->display.orig_gamma[1*d->display.gamma_size],
				&d->display.orig_gamma[2*d->display.gamma_size]
			);
			free(d->display.orig_gamma);
			d->display.orig_gamma = NULL;
		}

		drmModeFreeConnector(d->display.con);
		d->display.con = NULL;

		drmModeFreeCrtc(d->display.old_crtc);
		d->display.old_crtc = NULL;

		d->device = NULL;
		d->state = DISP_UNUSED;

		if (d->backlight){
			backlight_set_brightness(d->backlight, d->backlight_brightness);
			backlight_destroy(d->backlight);
			d->backlight = NULL;
		}
	}
	else
		d->state = DISP_EXTSUSP;
}

struct monitor_mode platform_video_dimensions()
{
	struct monitor_mode res = {
		.width = egl_dri.canvasw,
		.height = egl_dri.canvash
	};

/*
 * this is done to work around how gl- agp handles scissoring as there's no
 * version of platform_video_dimension that worked for the display out
 */
	if (egl_dri.last_display){
		res.width = egl_dri.last_display->display.mode->hdisplay;
		res.height = egl_dri.last_display->display.mode->vdisplay;
		if (egl_dri.last_display->display.con){
			res.phy_width = egl_dri.last_display->display.con->mmWidth;
			res.phy_height = egl_dri.last_display->display.con->mmHeight;
		}
	}
/*
 * fake dimensions to provide an OK default PPCM (say 72)
 */
	if (!res.phy_width)
		res.phy_width = (float)egl_dri.canvasw / (float)28.34645 * 10.0;

	if (!res.phy_height)
		res.phy_height = (float)egl_dri.canvash / (float)28.34645 * 10.0;

	return res;
}

void* platform_video_gfxsym(const char* sym)
{
	return eglGetProcAddress(sym);
}

static void do_led(struct dispout* disp, uint8_t val)
{
	if (disp && disp->backlight){
		float lvl = (float) val / 255.0;
		float max_brightness = backlight_get_max_brightness(disp->backlight);
		backlight_set_brightness(disp->backlight, lvl * max_brightness);
	}
}

/* read-end of ledpair pipe is in nonblocking, so just run through
 * it and update the corresponding backlights */
static void flush_leds()
{
	if (egl_dri.ledid < 0)
		return;

	uint8_t buf[2];
	while (2 == read(egl_dri.ledpair[0], buf, 2)){
		switch (tolower(buf[0])){
		case 'A': egl_dri.ledind = 255; break;
		case 'a': egl_dri.ledind = buf[1]; break;
		case 'r': egl_dri.ledval[0] = buf[1]; break;
		case 'g': egl_dri.ledval[1] = buf[1]; break;
		case 'b': egl_dri.ledval[2] = buf[1]; break;
		case 'i': egl_dri.ledval[0] = egl_dri.ledval[1]=egl_dri.ledval[2]=buf[1];
		case 'c':
/*
 * don't expose an RGB capable backlight (are there such displays out there?
 * the other option would be to weight the gamma channel of the ramps but if
 * someone wants that behavior it is probably better to change all the ramps
 */
			if (egl_dri.ledind != 255)
				do_led(get_display(egl_dri.ledind), egl_dri.ledval[0]);
			else
				for (size_t i = 0; i < MAX_DISPLAYS; i++)
					do_led(get_display(i), buf[1]);
		break;
		}
	}
}

bool platform_video_init(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	bool rv = false;
	struct sigaction old_sh;
	struct sigaction err_sh = {
		.sa_handler = sigsegv_errmsg
	};

/*
 * temporarily override segmentation fault handler here because it has happened
 * in libdrm for a number of "user-managable" settings (i.e. drm locked to X,
 * wrong permissions etc.)
 */
	sigaction(SIGSEGV, &err_sh, &old_sh);

	int n = 0, fd;
	char* device;
	while(1){
retry_card:
		grab_card(n++, &device, &fd);
		if (!device && -1 == fd)
			goto cleanup;

		int rc = setup_node(&nodes[0], device, fd);
		if (rc != 0){
			arcan_warning("egl-dri() - setup on %s failed\n", device);
			if (getenv("ARCAN_VIDEO_DEVICE"))
				goto cleanup;
		}
		nodes[0].card_id = n-1;
		free(device);

		if (0 == rc)
			break;

		if (-2 == rc)
			goto cleanup;
	}

	if (-1 == drmSetMaster(nodes[0].fd)){
		if (getenv("ARCAN_VIDEO_DRM_MASTER")){
		arcan_fatal("platform/egl-dri(), couldn't get drmMaster (%s) - make sure"
			" nothing else holds the master lock or try without "
			"ARCAN_VIDEO_DRM_MASTER env.\n", strerror(errno));
		}
		else
		arcan_warning("platform/egl-dri(), couldn't get drmMaster (%s), trying "
			" to continue anyways.\n", strerror(errno));
	}
	map_extensions();

/*
 * if w, h are set it acts as a hint to the resolution that we will request.
 * Default drawing hint is stretch to display anyhow.
 */
	struct dispout* d = allocate_display(&nodes[0]);
	d->display.primary = true;
	egl_dri.last_display = d;

/*
 * force connector is a workaround for dealing with explicitly getting a single
 * monitor being primary synch, as we have no good mechanism for communicating /
 * managing that (dynamic synchronization strategy refactor will change that)
 */
	int connid = -1;
	const char* arg = getenv("ARCAN_VIDEO_CONNECTOR");
	if (arg){
		char* end;
		int vl = strtoul(arg, &end, 10);
		if (end != arg && *end == '\0')
			connid = vl;
		else{
			arcan_warning("ARCAN_VIDEO_CONNECTOR specified but couldn't "
				"parse ID from (%s)\n", arg);
			goto cleanup;
		}
	}

	if (setup_kms(d, connid, w, h) != 0){
		disable_display(d, true);
		arcan_warning( arg ?
			"ARCAN_VIDEO_CONNECTOR specified but couldn't configure display.\n" :
			"setup_kms(), card found but no working/connected display.\n");

		if (!getenv("ARCAN_VIDEO_DEVICE"))
			goto retry_card;

		dump_connectors(stdout, &nodes[0], true);
		goto cleanup;
	}

	if (setup_buffers(d) != 0){
		disable_display(d, true);
		goto cleanup;
	}

	d->backlight = backlight_init(NULL,
		d->device->card_id, d->display.con->connector_type,
		d->display.con->connector_type_id
	);
	if (d->backlight)
		d->backlight_brightness = backlight_get_brightness(d->backlight);

/*
 * requested canvas does not always match display
 */
	egl_dri.canvasw = d->display.mode->hdisplay;
	egl_dri.canvash = d->display.mode->vdisplay;
	build_orthographic_matrix(d->projection, 0,
		egl_dri.canvasw, egl_dri.canvash, 0, 0, 1);
	memcpy(d->txcos, arcan_video_display.mirror_txcos, sizeof(float) * 8);
	d->vid = ARCAN_VIDEO_WORLDID;
	d->state = DISP_MAPPED;
	rv = true;

	if (pipe(egl_dri.ledpair) != -1){
		egl_dri.ledid = arcan_led_register(egl_dri.ledpair[1], -1,
			"backlight", (struct led_capabilities){
			.nleds = MAX_DISPLAYS,
			.variable_brightness = true,
			.rgb = false
		});

/* prepare the pipe-pair to be non-block and close-on-exit */
		if (-1 == egl_dri.ledid){
			close(egl_dri.ledpair[0]);
			close(egl_dri.ledpair[1]);
			egl_dri.ledpair[0] = egl_dri.ledpair[1] = -1;
		}
		else{
			for (size_t i = 0; i < 2; i++){
				int flags = fcntl(egl_dri.ledpair[i], F_GETFL);
				if (-1 != flags)
					fcntl(egl_dri.ledpair[i], F_SETFL, flags | O_NONBLOCK);

				flags = fcntl(egl_dri.ledpair[i], F_GETFD);
				if (-1 != flags)
					fcntl(egl_dri.ledpair[i], F_SETFD, flags | O_CLOEXEC);
			}
		}
	}

/*
 * send a first 'added' event for display tracking as the primary / connected
 * display will not show up in the rescan
 */
	arcan_event ev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
		.vid.ledctrl = egl_dri.ledid
	};
	arcan_event_enqueue(arcan_event_defaultctx(), &ev);
	platform_video_query_displays();

cleanup:
	sigaction(SIGSEGV, &old_sh, NULL);
	return rv;
}

/*
 * for recovery, first emit a display added for the default 0 display, then
 * interate all already known displays and do the same. Lastly, do a rescan for
 * good measure
 */
void platform_video_recovery()
{
	arcan_event ev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_DISPLAY_ADDED
	};
	arcan_evctx* evctx = arcan_event_defaultctx();
	arcan_event_enqueue(evctx, &ev);

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_MAPPED){
			platform_video_map_display(
				ARCAN_VIDEO_WORLDID, displays[i].id, HINT_NONE);
			ev.vid.displayid = displays[i].id;
			arcan_event_enqueue(evctx, &ev);
		}
	}

	platform_video_query_displays();
}

static void page_flip_handler(int fd, unsigned int frame,
	unsigned int sec, unsigned int usec, void* data)
{
	struct dispout* d = data;
	d->buffer.in_flip = 0;

	if (d->buffer.cur_fb)
		drmModeRmFB(fd, d->buffer.cur_fb);
	d->buffer.cur_fb = d->buffer.next_fb;
	d->buffer.next_fb = 0;

	if (d->buffer.cur_bo)
		gbm_surface_release_buffer(d->buffer.surface, d->buffer.cur_bo);
	d->buffer.cur_bo = d->buffer.next_bo;
	d->buffer.next_bo = NULL;
}

void flush_display_events(int timeout)
{
	int pending = 1;
	struct dispout* d;

/* Until we have a decent 'conductor' for managing synchronization for
 * all the different audio/video/input producers and consumers, keep
 * on processing audio input while we wait for displays to finish synch.
 *
 * Until we have support for Atomic modesetting, we don't have reliable
 * Vsync notification (**censored**), so we have to give up sooner or later.
 */
	unsigned long long start = arcan_timemillis();
	size_t naud = arcan_audio_refresh();
	int period = (timeout > 0 ? (naud > 0 ? 2 : timeout) : timeout);

	drmEventContext evctx = {
			.version = DRM_EVENT_CONTEXT_VERSION,
			.page_flip_handler = page_flip_handler
	};
	do{
/* for multiple cards, extend this pollset */
		struct pollfd fds = {
			.fd = nodes[0].fd,
			.events = POLLIN | POLLERR | POLLHUP
		};

		int rv = poll(&fds, 1, period);
		if (-1 == rv){
			if (errno == EINTR || errno == EAGAIN)
				continue;
			arcan_fatal("platform/egl-dri() - poll on device failed.\n");
		}
		else if (0 == rv){
			unsigned long long now = arcan_timemillis();
			if (naud && timeout && now > start && now - start < timeout){
				naud = arcan_audio_refresh();
				continue;
			}
			return;
		}

		if (fds.revents & (POLLHUP | POLLERR))
			arcan_warning("platform/egl-dri() - display broken/recovery missing.\n");
		else
			drmHandleEvent(nodes[0].fd, &evctx);

/* with this approach we only force- synch on primary displays,
 * as we don't want to be throttled by lower- clocked secondary displays */
		int i = 0;
		pending = 0;
		while((d = get_display(i++)))
			if (d->display.primary)
				pending |= d->buffer.in_flip;
	}
	while (pending);
}

/*
 * A lot more work / research is needed on this one to be able to handle all
 * weird edge-cases depending on the mapped displays and priorities (powersave?
 * tearfree? lowest possible latency in regards to other external clocks etc.)
 * - especially when mixing in future synch models that don't require VBlank
 */
void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	size_t nd;
	struct dispout* d;

/*
 * there are some conditions to when it is safe to destroy a display or not,
 * and with multiple queued buffers, we need to wait for the queue to flush
 */
	int i = 0;
	while (egl_dri.destroy_pending > 0){
		while( (d = get_display(i++)) )
			disable_display(d, true);
		flush_display_events(8);
		i = 0;
	}

/* at this stage, the contents of all RTs have been synched, with nd == 0,
 * nothing has changed from what was draw last time - but since we normally run
 * double buffered it is easier to synch the same contents in both buffers */
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

	static int last_nd;
	bool update = nd || last_nd;
	if (update){
		while ( (d = get_display(i++)) ){
			if (d->state == DISP_MAPPED && d->buffer.in_flip == 0)
				update_display(d);
			}
	}
	last_nd = nd;

/*
 * still use an artifical delay / timeout here, see previous notes about the
 * need for a real 'conductor' with synchronization- strategy support
 */
	flush_leds();
	flush_display_events(update ? 16 : 8);

	if (post)
		post();
}

void platform_video_shutdown()
{
	struct dispout* d;
	int rc = 10;

	do{
		for(size_t i = 0; i < MAX_DISPLAYS; i++){
			disable_display(&displays[i], true);
		}
		flush_display_events(17);
	} while (egl_dri.destroy_pending && rc-- > 0);

	for (size_t i = 0; i < sizeof(nodes)/sizeof(nodes[0]); i++){
		if (0 >= nodes[i].fd)
			continue;

		eglDestroyContext(nodes[i].display, nodes[i].context);
		gbm_device_destroy(nodes[i].gbm);

		if (nodes[0].master)
			drmDropMaster(nodes[0].fd);
		close(nodes[i].fd);

		nodes[i].fd = -1;
		eglTerminate(nodes[i].display);
	}

}

void platform_video_setsynch(const char* arg)
{
	int ind = 0;

	while(egl_synchopts[ind]){
		if (strcmp(egl_synchopts[ind], arg) == 0){
			synchopt = (ind > 0 ? ind / 2 : ind);
			arcan_warning("synchronisation strategy set to (%s)\n",
				egl_synchopts[ind]);
			break;
		}

		ind += 2;
	}
}

const char* platform_video_capstr()
{
	static char* buf;
	static size_t buf_sz;

	if (buf){
		free(buf);
		buf = NULL;
	}

	FILE* stream = open_memstream(&buf, &buf_sz);
	if (!stream)
		return "platform/egl-dri capstr(), couldn't create memstream\n";

	const char* vendor = (const char*) glGetString(GL_VENDOR);
	const char* render = (const char*) glGetString(GL_RENDERER);
	const char* version = (const char*) glGetString(GL_VERSION);
	const char* shading = (const char*)glGetString(GL_SHADING_LANGUAGE_VERSION);
	const char* exts = (const char*) glGetString(GL_EXTENSIONS);

	const char* eglexts = "";

	if (get_display(0)){
		eglexts = (const char*)eglQueryString(
		get_display(0)->device->display, EGL_EXTENSIONS);

		dump_connectors(stream, get_display(0)->device, true);
	}
	fprintf(stream, "Video Platform (EGL-DRI)\n"
			"Vendor: %s\nRenderer: %s\nGL Version: %s\n"
			"GLSL Version: %s\n\n Extensions Supported: \n%s\n\n"
			"EGL Extensions supported: \n%s\n\n",
			vendor, render, version, shading, exts, eglexts);

	fclose(stream);

	return buf;
}

const char** platform_video_synchopts()
{
	return (const char**) egl_synchopts;
}

const char** platform_video_envopts()
{
	return (const char**) egl_envopts;
}

enum dpms_state platform_video_dpms(
	platform_display_id disp, enum dpms_state state)
{
	struct dispout* out = get_display(disp);
	if (!out || out->state <= DISP_KNOWN)
		return ADPMS_IGNORE;

	if (state == ADPMS_IGNORE)
		return out->display.dpms;

	if (state != out->display.dpms)
		dpms_set(out, adpms_to_dpms(state));

	out->display.dpms = state;
	return state;
}

bool platform_video_map_display(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
	struct dispout* d = get_display(disp);
	if (!d || d->state == DISP_UNUSED)
		return false;

/* we have a known but previously unmapped display, set it up */
	if (d->state == DISP_KNOWN){
		if (setup_kms(d,
			d->display.con->connector_id,
			d->display.mode ? d->display.mode->hdisplay : 0,
			d->display.mode ? d->display.mode->vdisplay : 0) ||
			setup_buffers(d) != 0){
			arcan_warning("egl-dri(map_display) - couldn't setup kms/"
				"buffers on %d:%d\n", (int)d->id, (int)d->display.con->connector_id);
			return false;
		}
		d->state = DISP_MAPPED;
	}

	arcan_vobject* vobj = arcan_video_getobject(id);
	if (vobj && vobj->vstore->txmapped != TXSTATE_TEX2D){
			arcan_warning("platform_video_map_display(), attempted to map a "
				"video object with an invalid backing store");
			return false;
	}

	float txcos[8];
		memcpy(txcos, vobj && vobj->txcos ? vobj->txcos :
			(vobj->vstore == arcan_vint_world() ?
				arcan_video_display.mirror_txcos :
				arcan_video_display.default_txcos), sizeof(float) * 8
		);

	d->display.primary = hint & HINT_FL_PRIMARY;
	memcpy(d->txcos, txcos, sizeof(float) * 8);
	arcan_vint_applyhint(vobj, hint,
		txcos, d->txcos, &d->dispx, &d->dispy, &d->dispw, &d->disph,
		&d->display.blackframes
	);

	d->hint = hint;

/*
 * BADID displays won't be rendered but remain allocated, question is should we
 * power-save the display or return the original Crtc until we need it again?
 * Both have valid points..
 */
	d->vid = id;
	return true;
}

static void fb_cleanup(struct gbm_bo* bo, void* data)
{
	struct dispout* d = data;

	if (d->state == DISP_CLEANUP)
		return;

	disable_display(d, true);
}

static void draw_display(struct dispout* d)
{
	arcan_vobject* vobj = arcan_video_getobject(d->vid);
	agp_shader_id shid = agp_default_shader(BASIC_2D);

	if (!vobj) {
		agp_rendertarget_clear();
		return;
	}
	else{
		if (vobj->program > 0)
			shid = vobj->program;

		agp_activate_vstore(d->vid == ARCAN_VIDEO_WORLDID ?
			arcan_vint_world() : vobj->vstore);
	}

	agp_shader_activate(shid);
	agp_shader_envv(PROJECTION_MATR, d->projection, sizeof(float)*16);
	agp_draw_vobj(0, 0, d->dispw, d->disph, d->txcos, NULL);
/*
 * another rough corner case, if we have a store that is not world ID but
 * shared with different texture coordinates (to extend display), we need to
 * draw the cursor .. but if the texture coordinates indicate that we only draw
 * a subset, we need to check if the cursor is actually inside that area...
 * Seems more and more that accelerated cursors add to more state explosion
 * than they are worth ..
 */
	if (vobj->vstore == arcan_vint_world()){
		arcan_vint_drawcursor(false);
	}

	agp_deactivate_vstore();
}

static void update_display(struct dispout* d)
{
	if (d->display.dpms != ADPMS_ON)
		return;

/* render-target may set scissors etc. based on the display
 * when using the NULL rendertarget */
	egl_dri.last_display = d;

	agp_blendstate(BLEND_NONE);
	agp_activate_rendertarget(NULL);
/*
 * current_fbid* drawing hints, mapping etc. should be taken into account here,
 * there's quite possible drm flags to set scale here
 */
	eglMakeCurrent(d->device->display, d->buffer.esurf,
		d->buffer.esurf, d->device->context);

/*
 * for when we map fullscreen, have multi-buffering and garbage from previous
 * mapping left in the crop area
 */
	if (d->display.blackframes){
		agp_rendertarget_clear();
		d->display.blackframes--;
	}

/*
 * currently we only do binary damage / update tracking in that there are EGL
 * versions for saying 'this region is damaged, update that' to cut down on
 * fillrate/bw, but the video.c synch code does not expose such information
 * (though trivial to add), just have reset/add_region list to the normal
 * draw calls - and forward this list here.
 */
	draw_display(d);
	eglSwapBuffers(d->device->display, d->buffer.esurf);

/* next/cur switching comes in the page-flip handler */
	struct gbm_bo* bo = gbm_surface_lock_front_buffer(d->buffer.surface);
	if (!bo)
		return;

	uint32_t handle = gbm_bo_get_handle(bo).u32;
	uint32_t width  = gbm_bo_get_width(bo);
	uint32_t height = gbm_bo_get_height(bo);
	uint32_t stride = gbm_bo_get_stride(bo);
	gbm_bo_set_user_data(bo, d, fb_cleanup);

	bool new_crtc = false;

/* mode-switching is defered to the first frame that is ready as things
 * might've happened in the engine between _init and draw */
	if (d->display.reset_mode || !d->display.old_crtc){
		if (!d->display.old_crtc)
			d->display.old_crtc = drmModeGetCrtc(d->device->fd, d->display.crtc);
		d->display.reset_mode = false;
		new_crtc = true;
	}

	d->buffer.next_bo = bo;
	if (drmModeAddFB(d->device->fd, width, height, 24, sizeof(av_pixel) * 8,
		stride, handle, &d->buffer.next_fb)){
		arcan_warning("rgl-dri(), couldn't add framebuffer (%s)\n",
			strerror(errno));
		return;
	}

	if (new_crtc){
		int rv = drmModeSetCrtc(d->device->fd, d->display.crtc,
			d->buffer.next_fb, 0, 0, &d->display.con_id, 1, d->display.mode);
		if (rv < 0){
			arcan_warning("error (%d) setting Crtc for %d:%d(con:%d)\n",
				errno, d->device->fd, d->display.crtc, d->display.con_id);
		}
	}

	if (!drmModePageFlip(d->device->fd, d->display.crtc,
		d->buffer.next_fb, DRM_MODE_PAGE_FLIP_EVENT, d))
		d->buffer.in_flip = 1;
}

/* These two functions are important yet incomplete (and something for the
 * sadists) -- For these to be working and complete we need to:
 *
 *  1. handle detection of all device changes that might've occured while
 *     we were gone and propagate the related events. This includes GPUs
 *     appearing / disappearing and monitors being plugged/replaced/unplugged
 *     The testing backlog etc. is what makes this difficult.
 *
 *  2. add correct flushing as part of agp memory management, meaning reading
 *     back and store all GPU-local assets.
 *
 * Unfortunately this is a necessary feature for proper hibernate/suspend/
 * virtual terminal/seat switching. Then we need to do the same for audio,
 * event and led devices.
 */
void platform_video_prepare_external()
{
	int rc = 10;
	do{
		for(size_t i = 0; i < MAX_DISPLAYS; i++)
			disable_display(&displays[i], false);
		if (egl_dri.destroy_pending)
			flush_display_events(16);
	} while(egl_dri.destroy_pending && rc-- > 0);

	if (nodes[0].master)
		drmDropMaster(nodes[0].fd);
}

void platform_video_restore_external()
{
/* uncertain if it is possible to poll on the device node to determine
 * when / if the drmMaster lock is released or not */
	if (-1 == drmSetMaster(nodes[0].fd)){
		if (getenv("ARCAN_VIDEO_DRM_MASTER")){
			while(-1 == drmSetMaster(nodes[0].fd)){
				arcan_warning("platform/egl-dri(), couldn't regain drmMaster access, "
					"retrying in 1 second\n");
				arcan_timesleep(1000);
			}
			nodes[0].master = true;
		}
		else
			nodes[0].master = false;
	}
	else
		nodes[0].master = true;

/* rebuild the mapped and known displays, extsusp is a marker that indicate
 * that the state of the engine is that the display is still alive, and should
 * be brought back to that state before we push 'removed' events */
	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_EXTSUSP){
/* refc? */
			if (setup_kms(&displays[i], displays[i].display.con->connector_id, 0, 0) != 0){
				disable_display(&displays[i], true);
			}
			else if (setup_buffers(&displays[i]) != 0){
				disable_display(&displays[i], true);
			}
			displays[i].state = DISP_MAPPED;
			displays[i].display.reset_mode = true;
		}
	}

/* defer the video_rescan to arcan_video.c as the event queue may not be ready */
}
