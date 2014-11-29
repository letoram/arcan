/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Todo for this platform module:
 *
 * 1. Multiple- monitor configurations
 *    -> mode switches (with resizing the underlying framebuffers)
 *    -> dynamic vobj -> output mapping
 *
 * 2. Display Hotplug Events
 *
 * 3. Support for External Launch / Building, Restoring Contexts
 *
 * 4. Advanced Synchronization options (swap-interval, synch directly
 *    to front buffer, swap-with-tear, pre-render then wake / move
 *    cursor just before etc.)
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

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/poll.h>

#include <fcntl.h>
#include <assert.h>

#include <drm.h>

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

#include "../agp/glfun.h"

#ifndef PLATFORM_SUFFIX
#define PLATFORM_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(PLATFORM_SUFFIX, fun)

static char* egl_synchopts[] = {
	"default", "double buffered, display controls refresh",
/*
 * default + heuristic -> drop frame if we're lagging behind
 * triple buffered -> poor idea, shouldn't be used
 * pre-vsync align, tear if we are out of options
 * most interesting, racing the beam (single-buffer)
 * simulate-n-Hz display
 */
	NULL
};

static char* egl_envopts[] = {
	"ARCAN_VIDEO_DEVICE=/dev/dri/card0", "specifiy primary device",
	"ARCAN_VIDEO_DRM_NOMASTER", "set to disable drmMaster management",
	NULL
};

enum {
	DEFAULT,
	ENDM
}	synchopt;

/*
 static struct {
	bool master;
} dri_opts = {
	.master = true,
};
 */

static struct {
	struct gbm_bo* bo;
	struct gbm_device* dev;
	struct gbm_surface* surface;
} gbm;

#ifndef CONNECTOR_LIMIT
#define CONNECTOR_LIMIT 8
#endif

static struct {
	int fd;
	uint32_t crtc_id[CONNECTOR_LIMIT];
	uint32_t connector_id[CONNECTOR_LIMIT];

/* track in order to restore on shutdown */
	drmModeCrtcPtr old_crtc[CONNECTOR_LIMIT];

	drmModeModeInfo* mode;
	drmModeRes* res;
} drm;

/*struct display {
	struct arcan_shmif_cont conn;
	bool mapped;
	struct storage_info_t* vstore;
} disp[MAX_DISPLAYS];
*/

static struct {
	EGLConfig config;
	EGLContext context;
	EGLDisplay display;
	EGLSurface surface;

	size_t mdispw, mdisph;
	size_t canvasw, canvash;

	bool swap_damage;
	bool swap_age;
} egl;

struct drm_fb {
	struct gbm_bo* bo;
	uint32_t fb_id;
};

struct {
   drmModeConnector* connector;
   drmModeEncoder* encoder;
   drmModeModeInfo mode;
   uint32_t fb_id;
} kms;

/*
 * There's probably some sysfs- specific approach
 * but rather keep that outside and use the environment
 * variable to specify.
 */
static const char device_name[] = "/dev/dri/card0";
static char* last_err = "unknown";
static size_t err_sz = 0;
#define SET_SEGV_MSG(X) last_err = (X); err_sz = sizeof(X);

void sigsegv_errmsg(int sign)
{
	write(STDOUT_FILENO, last_err, err_sz);
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

bool PLATFORM_SYMBOL(_video_set_mode)(
	platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

bool PLATFORM_SYMBOL(_video_map_display)(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
/* add ffunc to the correct display */

	return false; /* no multidisplay /redirectable output support */
}

bool PLATFORM_SYMBOL(_video_specify_mode)(platform_display_id id,
	platform_mode_id mode_id, struct monitor_mode mode)
{
	return false;
}

struct monitor_mode* PLATFORM_SYMBOL(_video_query_modes)(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

	mode.width  = egl.mdispw;
	mode.height = egl.mdisph;
	mode.depth  = GL_PIXEL_BPP * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}

platform_display_id* PLATFORM_SYMBOL(_video_query_displays)(size_t* count)
{
	static platform_display_id id = 0;
	*count = 1;
	return &id;
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

static void dump_connectors(FILE* dst, drmModeRes* res)
{
	fprintf(dst, "DRM Dump: \n\tConnectors: %d\n", res->count_connectors);
	for (size_t i = 0; i < res->count_connectors; i++){
		drmModeConnector* conn = drmModeGetConnector(drm.fd, res->connectors[i]);
		if (!conn)
			continue;

		fprintf(dst, "\t(%d), id:(%d), encoder:(%d), type: ",
			(int) i, conn->connector_id, conn->encoder_id);
		drm_mode_connector(dst, conn->connector_type);
		fprintf(dst, " phy(%d * %d), hinting: %s\n",
			(int)conn->mmWidth, (int)conn->mmHeight, subpixel_type(conn->subpixel));

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
}

static int setup_drm(void)
{
	int i, area;

	SET_SEGV_MSG("libdrm(), open device failed (check permissions) "
		" or use ARCAN_VIDEO_DEVICE environment.\n");
	const char* device = getenv("ARCAN_VIDEO_DEVICE");
	if (!device)
		device = device_name;

	drm.fd = open(device, O_RDWR);

	if (drm.fd < 0) {
		arcan_warning("egl-dri(), could not open drm device.\n");
		return -1;
	}

	drmSetMaster(drm.fd);

	SET_SEGV_MSG("libdrm(), getting resources on device failed.\n");
	drm.res = drmModeGetResources(drm.fd);
	if (!drm.res) {
		arcan_warning("egl-dri(), drmModeGetResources "
			"failed: %s\n", strerror(errno));
		return -1;
	}

/* grab the first available connector, this can be
 * changed / altered dynamically by the calling script later */
	SET_SEGV_MSG("libdrm(), enumerating connectors on device failed.\n");
	for (i = 0; i < drm.res->count_connectors; i++){
		kms.connector = drmModeGetConnector(drm.fd, drm.res->connectors[i]);
		if (kms.connector->connection == DRM_MODE_CONNECTED)
			break;

		drmModeFreeConnector(kms.connector);
		kms.connector = NULL;
	}

/*
 * If a connector could not be found during initialization,
 * give up and let the outside world setup the connection.
 *
 * Still need to handle hotplug / geometry changes though
 */
	if (!kms.connector){
		arcan_warning("egl-dri(), no connected output.\n");
		return -1;
	}

	SET_SEGV_MSG("libdrm(), enumerating connector/modes failed.\n");
	for (i = 0, area = 0; i < kms.connector->count_modes; i++) {
		drmModeModeInfo *current_mode = &kms.connector->modes[i];
		int current_area = current_mode->hdisplay * current_mode->vdisplay;
		if (current_area > area) {
			drm.mode = current_mode;
			area = current_area;
		}
	}

	if (!drm.mode) {
		arcan_warning("egl-dri(), could not find a suitable display mode.\n");
		return -1;
	}

	SET_SEGV_MSG("libdrm(), setting matching encoder failed.\n");
	for (i = 0; i < drm.res->count_encoders; i++) {
		kms.encoder = drmModeGetEncoder(drm.fd, drm.res->encoders[i]);
		if (kms.encoder->encoder_id == kms.connector->encoder_id)
			break;
		drmModeFreeEncoder(kms.encoder);
		kms.encoder = NULL;
	}

	if (!kms.encoder) {
		arcan_warning("egl-dri() - could not find a working encoder.\n");
		return -1;
	}

	drm.old_crtc[0] = drmModeGetCrtc(drm.fd, kms.encoder->crtc_id);
	drm.crtc_id[0] = kms.encoder->crtc_id;
	drm.connector_id[0] = kms.connector->connector_id;

	return 0;
}

static int setup_gbm(void)
{
	SET_SEGV_MSG("libgbm(), create device failed catastrophically.\n");
	gbm.dev = gbm_create_device(drm.fd);

	SET_SEGV_MSG("libgbm(), creating scanout buffer failed catastrophically.\n");
	gbm.surface = gbm_surface_create(gbm.dev,
		drm.mode->hdisplay, drm.mode->vdisplay,
		GBM_FORMAT_XRGB8888,
		GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING
	);

	if (!gbm.surface) {
		arcan_warning("egl-dri(), failed to create gbm surface\n");
		return -1;
	}

	return 0;
}

static int setup_gl(void)
{
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
		apiv = EGL_OPENGL_API;
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
	egl.display = eglGetDisplay((void*)gbm.dev);
	if (!eglInitialize(egl.display, NULL, NULL)){
		arcan_warning("egl-dri() -- failed to initialize EGL.\n");
		return -1;
	}

	if (!eglBindAPI(apiv)){
		arcan_warning("egl-dri() -- couldn't bind GL API.\n");
		return -1;
	}

	EGLint nc;
	eglGetConfigs(egl.display, NULL, 0, &nc);
	if (nc < 1){
		arcan_warning(
			"egl-dri() -- no configurations found (%s).\n", egl_errstr());
	}

	EGLConfig* configs = malloc(sizeof(EGLConfig) * nc);
	memset(configs, '\0', sizeof(EGLConfig) * nc);

	EGLint selv;
	arcan_warning(
		"egl-dri() -- %d configurations found.\n", (int) nc);

	if (!eglChooseConfig(egl.display, attribs, &egl.config, 1, &selv)){
		arcan_warning(
			"egl-dri() -- couldn't chose a configuration (%s).\n", egl_errstr());
		return -1;
	}

	egl.context = eglCreateContext(egl.display, egl.config,
			EGL_NO_CONTEXT, context_attribs);
	if (egl.context == NULL) {
		arcan_warning("egl-dri() -- couldn't create a context.\n");
		return -1;
	}

	egl.surface = eglCreateWindowSurface(egl.display,
		egl.config, (uintptr_t)gbm.surface, NULL);

	if (egl.surface == EGL_NO_SURFACE) {
		arcan_warning("egl-dri() -- couldn't create a window surface.\n");
		return -1;
	}

	eglMakeCurrent(egl.display, egl.surface, egl.surface, egl.context);

	egl.mdispw = drm.mode->hdisplay;
	egl.mdisph = drm.mode->vdisplay;
	egl.canvasw = egl.mdispw;
	egl.canvash = egl.mdisph;

	return 0;
}

static void fb_cleanup(struct gbm_bo *bo, void *data)
{
	struct drm_fb *fb = data;
	if (fb->fb_id)
		drmModeRmFB(drm.fd, fb->fb_id);
	free(fb);

	struct gbm_device* gbmd = gbm_bo_get_device(bo);
	eglDestroyContext(egl.display, egl.context);
	eglDestroySurface(egl.display, egl.surface);
	eglTerminate(egl.display);

	if (gbm.surface)
		gbm_surface_destroy(gbm.surface);

	if (gbmd)
		gbm_device_destroy(gbmd);

	if (kms.encoder)
		drmModeFreeEncoder(kms.encoder);

	if (kms.connector)
		drmModeFreeConnector(kms.connector);

	for (size_t i = 0; i < CONNECTOR_LIMIT; i++)
		if (!drm.old_crtc[i])
			continue;
		else{
			drmModeSetCrtc(drm.fd, drm.old_crtc[i]->crtc_id,
				drm.old_crtc[i]->buffer_id, drm.old_crtc[i]->x,
				drm.old_crtc[i]->y, &drm.connector_id[i], 1,
				&drm.old_crtc[i]->mode);
			drmModeFreeCrtc(drm.old_crtc[i]);
		}

	close(drm.fd);
	memset(&drm, '\0', sizeof(drm));
/* do we need to do drmModeFreeResources? */
}

static struct drm_fb* next_framebuffer(struct gbm_bo* bo)
{
	struct drm_fb* fb = gbm_bo_get_user_data(bo);
	uint32_t width, height, stride, handle;
	int ret;

	if (fb)
		return fb;

	fb = calloc(1, sizeof *fb);
	fb->bo = bo;

	handle = gbm_bo_get_handle(bo).u32;
	width = gbm_bo_get_width(bo);
	height = gbm_bo_get_height(bo);
	stride = gbm_bo_get_stride(bo);

	ret = drmModeAddFB(drm.fd, width, height, 24, 32, stride, handle, &fb->fb_id);
	if (ret) {
		arcan_warning("egl-dri() : couldn't add framebuffer\n", strerror(errno));
		free(fb);
		return NULL;
	}

	gbm_bo_set_user_data(bo, fb, fb_cleanup);

	return fb;
}

static void page_flip_handler(int fd, unsigned int frame,
		  unsigned int sec, unsigned int usec, void *data)
{
	int *waiting_for_flip = data;
	*waiting_for_flip = 0;
}

struct monitor_mode PLATFORM_SYMBOL(_video_dimensions)()
{
	struct monitor_mode res = {
		.width = egl.canvasw,
		.height = egl.canvash,
		.phy_width = egl.mdispw,
		.phy_height = egl.mdisph
	};
	return res;
}

void* PLATFORM_SYMBOL(_video_gfxsym)(const char* sym)
{
	return eglGetProcAddress(sym);
}

/*
 * world- agp storage contains the data we need,
 * time to map / redraw / synch
 */
static void update_scanouts(size_t n_changed)
{
	agp_activate_rendertarget(NULL);

/*
 * DRI oddity, if nothing has actually changed (n_changed == 0)
 * and a drawRt call is not invoked, I'll get a crash in eglSwapBuffers(?!)
 */
	arcan_vint_drawrt(arcan_vint_world(), 0, 0, egl.mdispw, egl.mdisph);

	arcan_vint_drawcursor(false);
}

bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	bool rv = false;
	struct sigaction old_sh;
	struct sigaction err_sh = {
		.sa_handler = sigsegv_errmsg
	};

/*
 * temporarily override segmentation fault handler here
 * because it has happened in libdrm for a number of
 * "user-managable" settings (i.e. drm locked to X, wrong
 * permissions etc.)
 */
	sigaction(SIGSEGV, &err_sh, &old_sh);

	if (setup_drm() == 0 && setup_gbm() == 0 && setup_gl() == 0){
		agp_init();
		rv = true;
	}

	sigaction(SIGSEGV, &old_sh, NULL);

	return rv;
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	drmEventContext evctx = {
			.version = DRM_EVENT_CONTEXT_VERSION,
			.page_flip_handler = page_flip_handler,
	};

	struct drm_fb* fb;

/* first frame setup */
	if (!gbm.bo){
		agp_rendertarget_clear();
		eglSwapBuffers(egl.display, egl.surface);

		gbm.bo = gbm_surface_lock_front_buffer(gbm.surface);
		fb = next_framebuffer(gbm.bo);

		drmModeSetCrtc(drm.fd, drm.crtc_id[0], fb->fb_id, 0, 0,
			&drm.connector_id[0], 1, drm.mode);
	}

	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

	update_scanouts(nd);
	eglSwapBuffers(egl.display, egl.surface);

	struct gbm_bo* new_buf = gbm_surface_lock_front_buffer(gbm.surface);
	fb = next_framebuffer(new_buf);

	int waiting_for_flip = 1;
	int ret = drmModePageFlip(drm.fd, drm.crtc_id[0], fb->fb_id,
		DRM_MODE_PAGE_FLIP_EVENT, &waiting_for_flip);

	if (ret)
		arcan_fatal("couldn't queue page flip (%s).\n", strerror(errno));

	while (waiting_for_flip){
		struct pollfd fds = {
			.fd = drm.fd,
			.events = POLLIN | POLLERR | POLLHUP
		};

		if (-1 == poll(&fds, 1, -1) || (fds.revents & (POLLHUP | POLLERR))){
			arcan_fatal(
				"platform/egl-dri() - poll on device failed, investigate.\n");
		}

		drmHandleEvent(drm.fd, &evctx);
	}

	gbm_surface_release_buffer(gbm.surface, gbm.bo);
	gbm.bo = new_buf;

	if (post)
		post();
}

void PLATFORM_SYMBOL(_video_shutdown) ()
{
	fb_cleanup(gbm.bo, gbm_bo_get_user_data(gbm.bo));
}

void PLATFORM_SYMBOL(_video_setsynch)(const char* arg)
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

const char* PLATFORM_SYMBOL(_video_capstr)()
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
	const char* eglexts = (const char*)eglQueryString(egl.display,EGL_EXTENSIONS);

	fprintf(stream, "Video Platform (EGL-DRI)\n"
			"Vendor: %s\nRenderer: %s\nGL Version: %s\n"
			"GLSL Version: %s\n\n Extensions Supported: \n%s\n\n"
			"EGL Extensions supported: \n%s\n\n",
			vendor, render, version, shading, exts, eglexts);

	dump_connectors(stream, drm.res);

	fclose(stream);

	return buf;
}

const char** PLATFORM_SYMBOL(_video_synchopts) ()
{
	return (const char**) egl_synchopts;
}

const char** PLATFORM_SYMBOL(_video_envopts)()
{
	return (const char**) egl_envopts;
}

void PLATFORM_SYMBOL(_video_prepare_external) () {}
void PLATFORM_SYMBOL(_video_restore_external) () {}

