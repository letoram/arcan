/*
 * copyright 2014-2015, björn ståhl
 * license: 3-clause bsd, see copying file in arcan source repository.
 * reference: http://arcan-fe.com
 */

/*
 * points to explore for this platform module:
 * (currently a bit careful spending more time here pending the
 * development of vulcan, nvidia egl streams extension etc.)
 *
 * 1. display hotplug events [ note update: we seem again to be forced to
 * consider the whole udev/.. mess, have the display scan be user- invoked for
 * now and look into the design of a better device-detection+ shared
 * synchronization platform rather than have a custom one in each sub-platform.
 * ]
 *
 *    shallow experiments in the lab showed somewhere around ~150ms complete
 *    stalls for a rescan so that is not really a viable option. one would
 *    thing that there would be some mechanism for the drm- master to do this
 *    already.
 *
 * 2. support for multiple graphics cards, i have no hardware and testing rig
 * for this, but the heavy lifting should be left up to the egl implementation
 * or so, maybe we need to track locality in vstore and do a whole prime-buffer
 * etc. transfer or mirror the vstore on both devices. hunt for node[0]
 * references as those have to be fixed.
 *
 *    in addition (and this is harder) we would need some kind of hinting to
 *    which render-node which application should map to and also support
 *    migrating between nodes. platform design currently has no way to achieve
 *    this.
 *
 * 3. support for external launch / building, restoring contexts
 *    note the test cases mentioned in _prepare
 *
 * 4. backlight? backlight support should really be added as yet another led
 * driver, that code is a bit old and dusty though so there is incentive to
 * redesign that anyhow (so both dedicated led controllers, backlights and
 * keyboards are covered in the same interface).
 *
 * 5. advanced synchronization options (swap-interval, synch directly to front
 * buffer, swap-with-tear, pre-render then wake / move cursor just before
 * etc.), discard when we miss deadline, drm_vblank_relative,
 * drm_vblank_secondary?
 *
 * 6. Survive "no output display" (possibly by reverting into a stall/wait
 * until the display is made available, or switch to a display-less context)
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

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/poll.h>

#include <fcntl.h>
#include <assert.h>

#include <libdrm/drm.h>
#include <libdrm/drm_mode.h>
#include <libdrm/drm_fourcc.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>

/*
 * Any way to evict the xf86 dependency, in the dream scenario
 * where we can get away without having the thing installed AT ALL?
 */
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <gbm.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#include "arcan_shmif.h"
#include "../agp/glfun.h"
#include "arcan_event.h"

#ifndef PLATFORM_SUFFIX
#define PLATFORM_SUFFIX platform
#endif

/*
 * extensions needed for buffer passing
 */
static PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES;

/*
 * real heuristics scheduled for 0.5.1, see .5 at top
 */
static char* egl_synchopts[] = {
	"default", "double buffered, display controls refresh",
	NULL
};

static char* egl_envopts[] = {
	"ARCAN_VIDEO_DEVICE=/dev/dri/card0", "specifiy primary device",
	"ARCAN_VIDEO_DRM_NOMASTER", "set to disable drmMaster management",
	"ARCAN_VIDEO_DRM_NOBUFFER", "set to disable IPC buffer passing",
	"ARCAN_VIDEO_WAIT_CONNECTOR", "loop until an active connector is found",
	NULL
};

enum {
	DEFAULT,
	ENDM
}	synchopt;

/*
 * Each open output device, can be shared between displays
 */
struct dev_node {
	int fd;
	int refc;
	struct gbm_device* gbm;

	EGLConfig config;
	EGLContext context;
	EGLDisplay display;
};

/*
 * Multiple- device nodes (i.e. cards) is currently untested
 * and thus only partially implemented due to lack of hardware
 */
static struct dev_node nodes[1];

/*
 * aggregation struct that represent one triple of display, card, bindings
 */
struct dispout {
/* connect drm, gbm and EGLs idea of a device */
	struct dev_node* device;

/* 1 buffer for 1 device for 1 display */
	struct {
		int in_flip;
		EGLSurface esurf;
		struct gbm_bo* bo;
		uint32_t fbid;
		struct gbm_surface* surface;
	} buffer;

	struct {
		bool ready;
		drmModeConnector* con;
		uint32_t con_id;
		drmModeModeInfoPtr mode;
		drmModeCrtcPtr old_crtc;
		int crtc;
		enum dpms_state dpms;
	} display;

/* v-store mapping, with texture blitting options and possibly mapping hint */
	arcan_vobj_id vid;
	size_t dispw, disph;
	_Alignas(16) float projection[16];
	_Alignas(16) float txcos[8];

	bool alive, in_cleanup;
};

static struct {
	struct dispout* last_display;
	size_t canvasw, canvash;
} egl_dri;

/*
 * primary functions for doing video- platform to egl/dri mapping,
 * returns NULL if no display could be mapped to the device
 */
#ifndef MAX_DISPLAYS
#define MAX_DISPLAYS 8
#endif
static struct dispout displays[MAX_DISPLAYS];
size_t const disp_sz = sizeof(displays) / sizeof(displays[0]);
static struct dispout* allocate_display(struct dev_node* node)
{
	for (size_t i = 0; i < sizeof(displays)/sizeof(displays[0]); i++)
		if (displays[i].alive == false){
			displays[i].device = node;
			node->refc++;
			displays[i].alive = true;
			return &displays[i];
		}

	return NULL;
}

/*
 * get device indexed, this is used as an iterator
 */
static struct dispout* get_display(size_t index)
{
	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].alive){
			if (index == 0)
				return &displays[i];
			else
				index--;
		}
	}

	return NULL;
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
static void disable_display(struct dispout*);

/*
 * assumes that the video pipeline is in a state to safely
 * blit, will take the mapped objects and schedule buffer transfer
 */
static void update_display(struct dispout*);

/* naive approach, unless env is set, just scan /dev/dri/card* and
 * grab the first one present. only used during first init */
static const char* grab_card()
{
	const char* override = getenv("ARCAN_VIDEO_DEVICE");
	if (override)
		return override;

	static char* lastcard;

#ifndef VDEV_GLOB
#define VDEV_GLOB "/dev/dri/card*"
#endif

	if (lastcard)
		lastcard = (free(lastcard), NULL);

	glob_t res;
	if (glob(VDEV_GLOB, 0, NULL, &res) == 0){
		if (*(res.gl_pathv)){
			lastcard = strdup(*(res.gl_pathv));
			globfree(&res);
			return lastcard;
		}
		globfree(&res);
	}

	return override;
}

static char* last_err = "unknown";
static size_t err_sz = 0;
#define SET_SEGV_MSG(X) last_err = (X); err_sz = sizeof(X);

void sigsegv_errmsg(int sign)
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

	d->buffer.surface = gbm_surface_create(d->device->gbm,
		d->display.mode->hdisplay, d->display.mode->vdisplay,
		GBM_FORMAT_XRGB8888,
		GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING
	);

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

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	struct dispout* d = get_display(disp);

	if (!d || mode >= d->display.con->count_modes)
		return false;

	d->display.mode = &d->display.con->modes[mode];
	build_orthographic_matrix(d->projection,
		0, d->display.mode->hdisplay, d->display.mode->vdisplay, 0, 0, 1);

/*
 * reset scanout buffers to match new crtc mode
 */
	if (d->buffer.bo){
		gbm_surface_release_buffer(d->buffer.surface, d->buffer.bo);
		d->buffer.bo = NULL;
	}
	d->in_cleanup = true;
	eglDestroySurface(d->device->display, d->buffer.esurf);
	if(d->buffer.fbid)
		drmModeRmFB(d->device->fd, d->buffer.fbid);

	gbm_surface_destroy(d->buffer.surface);
	setup_buffers(d);
	d->in_cleanup = false;
/*
 * the next update will setup new BOs and activate CRTC
 */

	return true;
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

static void drm_mode_scale(FILE* fpek, int val)
{
	switch (val){
	case DRM_MODE_SCALE_FULLSCREEN:
		fprintf(fpek, "fullscreen");
	break;

	case DRM_MODE_SCALE_ASPECT:
		fprintf(fpek, "fit aspect");
	break;

	default:
		fprintf(fpek, "unknown");
	}
}

static void drm_mode_encoder(FILE* fpek, int val)
{
	switch(val){
	case DRM_MODE_ENCODER_NONE:
		fputs("none", fpek);
	break;
	case DRM_MODE_ENCODER_DAC:
		fputs("dac", fpek);
	break;
	case DRM_MODE_ENCODER_TMDS:
		fputs("tmds", fpek);
	break;
	case DRM_MODE_ENCODER_LVDS:
		fputs("lvds", fpek);
	break;
	case DRM_MODE_ENCODER_TVDAC:
		fputs("tvdac", fpek);
	break;
	default:
		fputs("unknown", fpek);
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

static void dump_connectors(FILE* dst, struct dev_node* node)
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

		for (size_t j = 0; j < conn->count_modes; j++){
			fprintf(dst, "\t\t Mode (%d:%s): clock@%d, refresh@%d\n\t\tflags : ",
				(int)j, conn->modes[j].name,
				conn->modes[j].clock, conn->modes[j].vrefresh
			);
			drm_mode_flag(dst, conn->modes[j].flags);
			fprintf(dst, " type : ");
			drm_mode_tos(dst, conn->modes[j].type);
		}

		fprintf(dst, "\n\n");
		drmModeFreeConnector(conn);
	}

	drmModeFreeResources(res);
}

static int setup_node(struct dev_node* node, const char* path)
{
	SET_SEGV_MSG("libdrm(), open device failed (check permissions) "
		" or use ARCAN_VIDEO_DEVICE environment.\n");
	if (!path)
		return -1;

	memset(node, '\0', sizeof(struct dev_node));
	node->fd = open(path, O_RDWR);

	if (-1 == node->fd){
		arcan_warning("egl-dri(), open device failed on %s\n", path);
		return -1;
	}

	SET_SEGV_MSG("libgbm(), create device failed catastrophically.\n");
	node->gbm = gbm_create_device(node->fd);

	if (!node->gbm){
		arcan_warning("egl-dri(), couldn't create gbm device on node.\n");
		close(node->fd);
		node->fd = 0;
		return -1;
	}

	static const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	const char* ident = agp_ident();

	EGLint apiv;

	static EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, 0,
		EGL_RED_SIZE, 1,
		EGL_GREEN_SIZE, 1,
		EGL_BLUE_SIZE, 1,
		EGL_ALPHA_SIZE, 0,
		EGL_DEPTH_SIZE, 1,
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
			return -1;
#endif

#ifndef EGL_OPENGL_ES3_BIT
#define EGL_OPENGL_ES3_BIT EGL_OPENGL_ES2_BIT
#endif
		attribs[i+1] = EGL_OPENGL_ES3_BIT;
		apiv = EGL_OPENGL_ES_API;
	}
	else
		return -1;

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
		return -1;
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
	node->fd = 0;
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
 * find encoder and use that to grab CRTC
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

			d->display.crtc = res->crtcs[j];
			d->display.old_crtc = drmModeGetCrtc(d->device->fd, enc->crtc_id);
			i = res->count_encoders;
			crtc_found = true;
			break;
		}
	}

	if (!crtc_found){
		arcan_warning("egl-dri() - could not find a working encoder/crtc.\n");
		drmModeFreeConnector(d->display.con);
		d->display.con = NULL;
		drmModeFreeResources(res);
		return -1;
	}

/* Primary display setup, notify about other ones (?) */
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
 * Security notice: stride and format comes from an untrusted
 * data source, it has not been verified if MESA- implementation
 * of eglCreateImageKHR etc. treats this as trusted in respect
 * to the buffer or not, otherwise this is a possibly source
 * for crashes etc. and I see no good way for verifying the
 * buffer manually. The whole procedure is rather baffling, why can't
 * I as DRM master use the preexisting notification interfaces to be
 * signalled of buffers and metadata, and enumerate which ones
 * have been allocated and by whom, but instead rely on yet another
 * layer of IPC primitives.
 */

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
		arcan_warning("could not import EGL buffer\n");
		return false;
	}

/* other option ?
 * EGLImage -> gbm_bo -> glTexture2D with EGL_NATIVE_PIXMAP_KHR */
	agp_activate_vstore(dst);
	glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, img);
	agp_deactivate_vstore(dst);

	return true;
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	bool free_conn = false;

	drmModeConnector* conn;
	drmModeRes* res;

	if (id >= disp_sz){
		id -= disp_sz;
		res = drmModeGetResources(nodes[0].fd);
		if (!res)
			return NULL;

		conn = drmModeGetConnector(nodes[0].fd, id);
		free_conn = true;
	}
	else {
		struct dispout* d = get_display(id);
		if (!d)
			return NULL;
		conn = d->display.con;
	}

	static struct monitor_mode* mcache;
	static size_t mcache_sz;

	*count = 0;

	*count = conn->count_modes;

	if (*count > mcache_sz){
		mcache_sz = *count;
		arcan_mem_free(mcache);
		mcache = arcan_alloc_mem(sizeof(struct monitor_mode) * mcache_sz,
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);
	}

	for (size_t i = 0; i < conn->count_modes; i++){
		mcache[i].refresh = conn->modes[i].vrefresh;
		mcache[i].width = conn->modes[i].hdisplay;
		mcache[i].height = conn->modes[i].vdisplay;
		mcache[i].subpixel = subpixel_type(conn->subpixel);
		mcache[i].phy_width = 0;
		mcache[i].phy_height = 0;
		mcache[i].dynamic = false;
		mcache[i].id = i;
/*
 * phy_width, dpi > dpmm
 * phy_height, dpi > dpmm
 * decode flags into mode as well
 */
		mcache[i].depth = sizeof(av_pixel) * 8;
	}

	if (free_conn){
		drmModeFreeConnector(conn);
		drmModeFreeResources(res);
	}

	return mcache;
}

static struct dispout* match_connector(int fd, drmModeConnector* con, int* id)
{
	int j = 0;

	for (struct dispout* d; (d = get_display(j++));){
		if (d->device->fd == fd &&
			d->display.con->connector_id == con->connector_id){
				*id = j-1;
				return d;
			}
	}

	return NULL;
}

/*
 * The cost for this function is rather unsavory,
 * nouveau testing has shown somewhere around ~110+ ms stalls
 * for one re-scan
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
		struct dispout* d = match_connector(nodes[0].fd, con, &id);

		if (con->connection == DRM_MODE_CONNECTED){
			if (d)
				continue;

			arcan_event ev = {
				.category = EVENT_VIDEO,
				.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
				.vid.source = sizeof(displays) / sizeof(displays[0]) +
					con->connector_id
			};
			arcan_event_enqueue(arcan_event_defaultctx(), &ev);
		}
		else {
			if (d){
				disable_display(d);
				arcan_event ev = {
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_REMOVED,
					.vid.source = id
				};
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			}
		}

		drmModeFreeConnector(con);
	}

	drmModeFreeResources(res);
}

static void disable_display(struct dispout* d)
{
	if (!d->alive){
		arcan_warning("egl-dri(), attempting to destroy inactive display\n");
		return;
	}
	d->device->refc -= 1;

	if (d->buffer.in_flip){
		arcan_warning("Attempting to destroy display during flip\n");
		return;
	}

	d->in_cleanup = true;
	eglDestroySurface(d->device->display, d->buffer.esurf);
	d->buffer.esurf = NULL;

	if (d->buffer.fbid)
		drmModeRmFB(d->device->fd, d->buffer.fbid);
	d->buffer.fbid = 0;

	gbm_surface_destroy(d->buffer.surface);
	d->buffer.surface = NULL;

	if (0 > drmModeSetCrtc(d->device->fd,
		d->display.old_crtc->crtc_id,
		d->display.old_crtc->buffer_id,
		d->display.old_crtc->x,
		d->display.old_crtc->y,
		&d->display.con_id, 1,
		&d->display.old_crtc->mode
	)){
		arcan_warning("Error setting old CRTC on %d\n",
		d->display.con_id);
	}

	drmModeFreeConnector(d->display.con);
	d->display.con = NULL;

	drmModeFreeCrtc(d->display.old_crtc);
	d->display.old_crtc = NULL;

/*
 * drop vstore mapping as well?
 */
	d->device = NULL;
	d->alive = false;
	d->in_cleanup = false;
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
	}

	res.phy_width = egl_dri.canvasw;
	res.phy_height = egl_dri.canvash;

	return res;
}

void* platform_video_gfxsym(const char* sym)
{
	return eglGetProcAddress(sym);
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

	const char* device = grab_card();

	if (setup_node(&nodes[0], device) != 0)
		goto cleanup;

	if (!getenv("ARCAN_VIDEO_DRM_NOMASTER"))
		drmSetMaster(nodes[0].fd);

	map_extensions();

/*
 * if w, h are set it acts as a hint to the resolution that we will request.
 * Default drawing hint is stretch to display anyhow.
 */
	struct dispout* d = allocate_display(&nodes[0]);

	if (setup_kms(d, -1, w, h) != 0){
		disable_display(d);
		goto cleanup;
	}

	if (setup_buffers(d) != 0){
		disable_display(d);
		goto cleanup;
	}

/*
 * requested canvas does not always match display
 */
	egl_dri.canvasw = d->display.mode->hdisplay;
	egl_dri.canvash = d->display.mode->vdisplay;

	d->vid = ARCAN_VIDEO_WORLDID;
	dump_connectors(stdout, &nodes[0]);
	rv = true;

cleanup:
	sigaction(SIGSEGV, &old_sh, NULL);

	return rv;
}

static void page_flip_handler(int fd, unsigned int frame,
	unsigned int sec, unsigned int usec, void* data)
{
	struct dispout* d = data;
	assert(d->buffer.in_flip == 1);
	d->buffer.in_flip = 0;
	gbm_surface_release_buffer(d->buffer.surface, d->buffer.bo);
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

/* at this stage, the contents of all RTs have been synched,
 * with nd == 0, nothing has changed from what was draw last time */
	struct dispout* d;
	int i = 0;

/* blit to each display */
	agp_shader_activate(agp_default_shader(BASIC_2D));
	agp_blendstate(BLEND_NONE);

	while ( (d = get_display(i++)) )
		update_display(d);

	drmEventContext evctx = {
			.version = DRM_EVENT_CONTEXT_VERSION,
			.page_flip_handler = page_flip_handler,
	};

	int pending;
	do{
/* for multiple cards, extend this pollset */
		struct pollfd fds = {
			.fd = nodes[0].fd,
			.events = POLLIN | POLLERR | POLLHUP
		};

		if (-1 == poll(&fds, 1, -1) || (fds.revents & (POLLHUP | POLLERR)))
			arcan_fatal("platform/egl-dri() - poll on device failed.\n");

		drmHandleEvent(nodes[0].fd, &evctx);

		pending = 0;
		int i = 0;
		while((d = get_display(i++))){
			pending |= d->buffer.in_flip;
		}
	}
	while (pending != 0);

	if (post)
		post();
}

void platform_video_shutdown()
{
	struct dispout* d;

	while((d = get_display(0)))
		disable_display(d);

	for (size_t i = 0; i < sizeof(nodes)/sizeof(nodes[0]); i++){
		if (0 >= nodes[i].fd)
			continue;

		eglDestroyContext(nodes[i].display, nodes[i].context);
		gbm_device_destroy(nodes[i].gbm);
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

		dump_connectors(stream, get_display(0)->device);
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

static bool map_connector(int fd, int conid, arcan_vobj_id src)
{
	for (size_t i = 0; i < disp_sz; i++)
		if (displays[i].device &&
			fd == displays[i].device->fd &&
			conid == displays[i].display.con->connector_id){
			arcan_warning("egl-dri(map_connector) - connector already in use\n");
			return false;
		}

	struct dispout* out = allocate_display(&nodes[0]);

	if (setup_kms(out, conid, 0, 0) != 0){
		arcan_warning("egl-dri(map_connector) - couldn't setup connector\n");
		disable_display(out);
		return false;
	}

	if (setup_buffers(out) != 0){
		arcan_warning("egl-dri(map_connector) - couldn't setup rendering"
			" buffers for new connector\n");
		disable_display(out);
		return false;
	}

	return true;
}

enum dpms_state platform_video_dpms(
	platform_display_id disp, enum dpms_state state)
{
	struct dispout* out = get_display(disp);
	if (!out)
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
/* if disp > max number of active displays,
 * it is actually a device:connector reference */

	if (disp >= disp_sz)
		return map_connector(nodes[0].fd, disp-disp_sz, id);

	struct dispout* out = get_display(disp);

	if (!out)
		return false;

	arcan_vobject* vobj = arcan_video_getobject(id);
	if (vobj && vobj->vstore->txmapped != TXSTATE_TEX2D){
		arcan_warning("platform_video_map_display(), attempted to map a "
			"video object with an invalid backing store");
		return false;
	}

/*
 * note that we can't use unmap display here, some drivers behave..
 * aggressively towards creating/releasing a single Crtc repeatedly with others
 * active.
 */

/*
 * BADID displays won't be rendered but remain allocated, question is should we
 * power-save the display or return the original Crtc until we need it again?
 * Both have valid points..
 */
	out->vid = id;
	return true;
}

static void fb_cleanup(struct gbm_bo* bo, void* data)
{
	struct dispout* d = data;

	if (d->in_cleanup)
		return;

	disable_display(d);
}

static void step_fb(struct dispout* d, struct gbm_bo* bo)
{
	uint32_t handle = gbm_bo_get_handle(bo).u32;
	uint32_t width  = gbm_bo_get_width(bo);
	uint32_t height = gbm_bo_get_height(bo);
	uint32_t stride = gbm_bo_get_stride(bo);

	if (drmModeAddFB(d->device->fd, width, height, 24, sizeof(av_pixel) * 8,
		stride, handle, &d->buffer.fbid)){
		arcan_warning("rgl-dri(), couldn't add framebuffer (%s)\n",
			strerror(errno));
		return;
	}

	gbm_bo_set_user_data(bo, d, fb_cleanup);
	d->buffer.bo = bo;
}

static void draw_display(struct dispout* d)
{
	float* txcos = arcan_video_display.default_txcos;
	arcan_vobject* vobj = arcan_video_getobject(d->vid);

	if (d->vid == ARCAN_VIDEO_WORLDID){
		agp_activate_vstore(arcan_vint_world());
		txcos = arcan_video_display.mirror_txcos;
	}
	else if (!vobj) {
		agp_rendertarget_clear();
		return;
	}
	else {
		agp_activate_vstore(vobj->vstore);
		txcos = vobj->txcos ? vobj->txcos : arcan_video_display.default_txcos;
	}

	agp_shader_envv(PROJECTION_MATR, d->projection, sizeof(float)*16);
	agp_draw_vobj(0, 0, d->display.mode->hdisplay,
		d->display.mode->vdisplay, txcos, NULL);

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
/* render-target may set scissors etc. based on the display
 * when using the NULL rendertarget */
	egl_dri.last_display = d;
	agp_activate_rendertarget(NULL);

/*
 * drawing hints, mapping etc. should be taken into account here,
 * there's quite possible drm flags to set scale here
 */
	eglMakeCurrent(d->device->display, d->buffer.esurf,
		d->buffer.esurf, d->device->context);

	draw_display(d);
	eglSwapBuffers(d->device->display, d->buffer.esurf);

	struct gbm_bo* bo = gbm_surface_lock_front_buffer(d->buffer.surface);

/* allocate buffer object now that we have data on
 * the front buffer properties, we'll flip later */
	if (!d->buffer.bo){
		step_fb(d, bo);
		int rv = drmModeSetCrtc(d->device->fd, d->display.crtc,
			d->buffer.fbid, 0, 0, &d->display.con_id, 1, d->display.mode);

/*
 * drmModeConnectorSetProperty(d->device->fd,
 * 	d->display.enc->crtc_id, DRM_MODE_SCALE_FULLSCREEN, 1);
 */

/* this should be moved to only be updated when the mapping
 * has changed, kept here for experimentation purposes */
		if (rv < 0){
			arcan_warning("error (%d) setting Crtc for %d:%d(con:%d, buf:%d)\n",
				errno, d->device->fd, d->display.crtc, d->display.con_id,
				d->buffer.fbid
			);
		}
	}

	if (drmModePageFlip(d->device->fd, d->display.crtc,
		d->buffer.fbid, DRM_MODE_PAGE_FLIP_EVENT, d)){
		arcan_fatal("couldn't queue page flip (%s).\n", strerror(errno));
	}

	d->buffer.in_flip = 1;
}

void platform_video_prepare_external()
{
/* sweep all displays and save a list of their relevant configuration states
 * (connector ID, etc.) then drop them --
 *
 * if we're in DRM master mode, temporarily release it
 */
}

void platform_video_restore_external()
{
/* this one is for the sadists -- AGP is responsible for saving all the GL
 * related buffers (which might be difficult with EGLStreams or MESA handles),
 * reading back into RAM buffers etc.
 *
 * the real issue is handling all the possible things that can have changed
 * between prepare and restore - cards disappearing (!), connectors being
 * switched around etc. and storming these events upwards
 */
}
