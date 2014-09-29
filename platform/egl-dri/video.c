/*
 * Long todo for this platform module:
 * 1. HEADLESS mode with EGLImage/EGLSurface transfer
 *
 * 2. handle all odd monitor configurations and desires,
 *    which one to synchronize to, fullscreen, mirroring,
 *    layout, orientation (rotation), similar events
 *
 * 3. work with both GLESv3 and OpenGL2+
 *
 * 4. controlling pty - changes, how to behave?
 *
 * 5. external launch
 *
 * 6. implement synchronization options and synchronization switching
 *
 * 7. hotplug events
 *
 * 8. graphics debugging string for the inevitable "my XXX doesn't work"
 *
 * 9. reset on shutdown
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/poll.h>

#include <fcntl.h>
#include <assert.h>

#include <drm.h>

/*
 * Any way to evict the xf86 dependency, in the dream scenario
 * where we can get away without having the thing installed AT ALL?
 */
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <gbm.h>

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#ifndef EGL_SUFFIX
#define EGL_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(EGL_SUFFIX, fun)

static char* egl_synchopts[] = {
	"default", "double buffered, display controls refresh",
/*
 * default + heuristic -> drop frame if we're lagging behind
 * triple buffered -> poor idea, shouldn't be used
 * pre-vsync align, tear if we are out of options
 * simulate-n-Hz display
 */
	NULL
};

enum {
	DEFAULT,
	ENDM
}	synchopt;

static struct {
	struct gbm_bo* bo;
	struct gbm_device* dev;
	struct gbm_surface* surface;
} gbm;

static struct {
	int fd;
	uint32_t crtc_id;
	uint32_t connector_id;

	drmModeModeInfo* mode;
	drmModeRes* res;
} drm;

static struct {
	EGLConfig config;
	EGLContext context;
	EGLDisplay display;
	EGLSurface surface;

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

static const char device_name[] = "/dev/dri/card0";

#ifdef WITH_HEADLESS
bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	arcan_fatal("not yet supported");
}

#else

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

static void dump_connectors(FILE* dst, drmModeRes* res)
{
	fprintf(dst, "FIXME: iterate connectors and dump state for each\n");

}

static int setup_drm(void)
{
	drmModeRes* resources;
	int i, area;

	const char* device = getenv("ARCAN_VIDEO_DEVICE");
	if (!device)
		device = device_name;

	drm.fd = open(device, O_RDWR);

	if (drm.fd < 0) {
		arcan_warning("egl-gbmkms(), could not open drm device\n");
		return -1;
	}

	resources = drmModeGetResources(drm.fd);
	if (!resources) {
		arcan_warning("drmModeGetResources failed: %s\n", strerror(errno));
		return -1;
	}

/* find a connected connector: */
	for (i = 0; i < resources->count_connectors; i++){
		kms.connector = drmModeGetConnector(drm.fd, resources->connectors[i]);
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
		arcan_warning("egl-gbmkms(), no connected output.\n");
		return -1;
	}

/*
 * should let display configuration determine which one we
 * actually selects...
 */
	for (i = 0, area = 0; i < kms.connector->count_modes; i++) {
		drmModeModeInfo *current_mode = &kms.connector->modes[i];
		int current_area = current_mode->hdisplay * current_mode->vdisplay;
		if (current_area > area) {
			drm.mode = current_mode;
			area = current_area;
		}
	}

	if (!drm.mode) {
		arcan_warning("egl-gbmkms(), could not find a suitable display mode.\n");
		return -1;
	}

	for (i = 0; i < resources->count_encoders; i++) {
		kms.encoder = drmModeGetEncoder(drm.fd, resources->encoders[i]);
		if (kms.encoder->encoder_id == kms.connector->encoder_id)
			break;
		drmModeFreeEncoder(kms.encoder);
		kms.encoder = NULL;
	}

	if (!kms.encoder) {
		arcan_warning("egl-gbmkms() - could not find a working encoder.\n");
		return -1;
	}

	drm.crtc_id = kms.encoder->crtc_id;
	drm.connector_id = kms.connector->connector_id;

	return 0;
}

static int setup_gbm(void)
{
	gbm.dev = gbm_create_device(drm.fd);

	gbm.surface = gbm_surface_create(gbm.dev,
		drm.mode->hdisplay, drm.mode->vdisplay,
		GBM_FORMAT_XRGB8888,
		GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING
	);

	if (!gbm.surface) {
		arcan_warning("egl-gbmkms(), failed to create gbm surface\n");
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

	static const EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 1,
		EGL_GREEN_SIZE, 1,
		EGL_BLUE_SIZE, 1,
		EGL_ALPHA_SIZE, 0,
		EGL_DEPTH_SIZE, 1,
		EGL_NONE
	};

	egl.display = eglGetDisplay(gbm.dev);
	if (!eglInitialize(egl.display, NULL, NULL)){
		arcan_warning("egl-gbmkms() -- failed to initialize EGL.\n");
		return -1;
	}

	if (!eglBindAPI(EGL_OPENGL_ES_API)){
		arcan_warning("egl-gbmkms() -- couldn't bind OpenGL API.\n");
		return -1;
	}

	GLint nc;
	eglGetConfigs(egl.display, NULL, 0, &nc);
	if (nc < 1){
		arcan_warning(
			"egl-gbmkms() -- no configurations found (%s).\n", egl_errstr());
	}

	EGLConfig* configs = malloc(sizeof(EGLConfig) * nc);
	memset(configs, '\0', sizeof(EGLConfig) * nc);

	GLint selv;
	arcan_warning(
		"egl-gbmkms() -- %d configurations found.\n", (int) nc);

	if (!eglChooseConfig(egl.display, attribs, &egl.config, 1, &selv)){
		arcan_warning(
			"egl-gbmkms() -- couldn't chose a configuration (%s).\n", egl_errstr());
		return -1;
	}

	egl.context = eglCreateContext(egl.display, egl.config,
			EGL_NO_CONTEXT, context_attribs);
	if (egl.context == NULL) {
		arcan_warning("egl-gbmkms() -- couldn't create a context.\n");
		return -1;
	}

	egl.surface = eglCreateWindowSurface(egl.display,
		egl.config, gbm.surface, NULL);

	if (egl.surface == EGL_NO_SURFACE) {
		arcan_warning("egl-gbmkms() -- couldn't create a window surface.\n");
		return -1;
	}

	eglMakeCurrent(egl.display, egl.surface, egl.surface, egl.context);

	arcan_video_display.width = drm.mode->hdisplay;
	arcan_video_display.height = drm.mode->vdisplay;
	arcan_video_display.bpp = 4;
	arcan_video_display.pbo_support = true;

	glViewport(0, 0, arcan_video_display.width, arcan_video_display.height);

	return 0;
}

static void fb_cleanup(struct gbm_bo *bo, void *data)
{
	struct drm_fb *fb = data;
	/* struct gbm_device *gbm = */ gbm_bo_get_device(bo);

	if (fb->fb_id)
		drmModeRmFB(drm.fd, fb->fb_id);

	free(fb);
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
		arcan_warning("egl-gbmkms() : couldn't add framebuffer\n", strerror(errno));
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

bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	if (0 != setup_drm() || 0 != setup_gbm() || 0 != setup_gl())
		return false;

/* clear the color buffer */
	glClearColor(0.0, 0.0, 0.0, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);

	return true;
}
#endif

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
		glClearColor(0, 0, 0, 1.0);
		glClear(GL_COLOR_BUFFER_BIT);
		eglSwapBuffers(egl.display, egl.surface);

		gbm.bo = gbm_surface_lock_front_buffer(gbm.surface);
		fb = next_framebuffer(gbm.bo);

		drmModeSetCrtc(drm.fd, drm.crtc_id, fb->fb_id, 0, 0,
			&drm.connector_id, 1, drm.mode);
	}

	arcan_bench_register_cost( arcan_video_refresh(fract) );
	eglSwapBuffers(egl.display, egl.surface);

	struct gbm_bo* new_buf = gbm_surface_lock_front_buffer(gbm.surface);
	fb = next_framebuffer(new_buf);

	int waiting_for_flip = 1;
	int ret = drmModePageFlip(drm.fd, drm.crtc_id, fb->fb_id,
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
				"platform/egl-gbmkms() - poll on device failed, investigate.\n");
		}

		drmHandleEvent(drm.fd, &evctx);
	}

	gbm_surface_release_buffer(gbm.surface, gbm.bo);
	gbm.bo = new_buf;

	if (post)
		post();
}

const char* platform_video_capstr()
{
	static char* capstr;
	static size_t capstr_sz;

	static char* compstr;

	if (!capstr){
		const char* vendor = (const char*) glGetString(GL_VENDOR);
		const char* render = (const char*) glGetString(GL_RENDERER);
		const char* version = (const char*) glGetString(GL_VERSION);
		const char* shading = (const char*)glGetString(GL_SHADING_LANGUAGE_VERSION);
		const char* exts = (const char*) glGetString(GL_EXTENSIONS);

		size_t interim_sz = 64 * 1024;
		char* interim = malloc(interim_sz);
		size_t nw = snprintf(interim, interim_sz, "Video Platform (EGL-DRI)\n"
			"Vendor: %s\nRenderer: %s\nGL Version: %s\n"
			"GLSL Version: %s\n\n Extensions Supported: \n%s\n\n",
			vendor, render, version, shading, exts
		) + 1;

		if (nw < (interim_sz >> 1)){
			capstr = malloc(nw);
			memcpy(capstr, interim, nw);
			free(interim);
		}
		else
			capstr = interim;

		capstr_sz = nw;
	}

	if (compstr)
		free(compstr);

	char* buf;
	size_t buf_sz;
	FILE* stream = open_memstream(&buf, &buf_sz);
	dump_connectors(stream, drm.res);
	fclose(stream);

	compstr = malloc(capstr_sz + buf_sz + 1);
	memcpy(compstr, buf, buf_sz);
	memcpy(compstr+buf_sz, capstr, capstr_sz);
	compstr[capstr_sz + buf_sz] = '\0';
	free(buf);

	return compstr;
}

const char** PLATFORM_SYMBOL(_video_synchopts) ()
{
	return (const char**) egl_synchopts;
}

void PLATFORM_SYMBOL(_video_prepare_external) () {}
void PLATFORM_SYMBOL(_video_restore_external) () {}
void PLATFORM_SYMBOL(_video_shutdown) ()
{
	fb_cleanup(gbm.bo, gbm_bo_get_user_data(gbm.bo));
}
