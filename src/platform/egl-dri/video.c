/*
 * copyright 2014-2018, björn ståhl
 * license: 3-clause bsd, see copying file in arcan source repository.
 * reference: http://arcan-fe.com
 */

/*
 * Notes on further dma-buf improvements / things we are missing right now:
 *
 * [X] Add support for retrieving and sending modifier information to clients
 *     The client will then be responsible for picking a format that match the
 *     set of modifiers - likely done by the platform side of mesa-egl impl.
 *
 * [ ] Add the corresponding work to the zwp_... dma_buf
 *
 * [ ] Implement multi-buffer repack reblit support function, add both here
 *     and in waybridge so that we can work around the problem with the lack
 *     of shader 'variants' to deal with all the different ugly sampler fmts.
 *
 * [ ] Rework platform functions to accept sets of multiple descriptors and
 *     aggregate them in the frameserver- stage. Restrict the number of planes
 *     in this way to 4-5 or something equally low. (a wayland client can
 *     really gnaw file descriptors, think multiplanar subsurfaces for border..
 *
 * [d] Rework frameserver data aggregation to support multi-planar input format
 *     and tracking as direct scanout
 *
 * [d] Modify Shader Manager to support format variants for all the different
 *     kinds of samplers we need to be able to handle (y_uv, y_xuxv, y_u_v)
 *
 * [ ] Add an extended version of the map_... function that allows a plane
 *     index as part of the mapping function for layered compositing,
 *     bonus points for mimicking the heuristics used by surface flinger for
 *     switching between GL composited and MDP composition
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
#include <dlfcn.h>
#include <inttypes.h>
#include <sys/mman.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <poll.h>

#include <fcntl.h>
#include <assert.h>

#include <libdrm/drm.h>
#include <libdrm/drm_mode.h>
#include <libdrm/drm_fourcc.h>

#include "../EGL/egl.h"
#include "../EGL/eglext.h"

#if !defined(EGL_DRM_MASTER_FD_EXT)
#define EGL_DRM_MASTER_FD_EXT 0x333C
#endif

#if !defined(EGL_CONSUMER_AUTO_ACQUIRE_EXT)
#define EGL_CONSUMER_AUTO_ACQUIRE_EXT 0x332B
#endif

#if !defined(EGL_DRM_FLIP_EVENT_DATA_NV)
#define EGL_DRM_FLIP_EVENT_DATA_NV 0x33E
#endif

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

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

#define debug_print(fmt, ...) \
            do { if (DEBUG) arcan_warning("%s:%d:%s(): " fmt "\n", \
						"egl-dri:", __LINE__, __func__,##__VA_ARGS__); } while (0)

/* very noisy, enable for specific kinds of debugging */
#define verbose_print
/* #define verbose_print debug_print */

/*
 * Dynamically load all EGL function use, and look them up with dlsym if we're
 * dynamically linked against the EGL library already (for the devices where an
 * explicit library isn't defined). Since we synch a copy of the KHR EGL
 * headers there shouldn't be a conflict with the locally defined ones.
 */
typedef void* GLeglImageOES;
typedef void (EGLAPIENTRY* PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)(GLenum target, GLeglImageOES image);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLCHOOSECONFIGPROC)(EGLDisplay dpy, const EGLint *attrib_list,	EGLConfig *configs, EGLint config_size,	EGLint *num_config);
typedef EGLContext  (EGLAPIENTRY* PFNEGLCREATECONTEXTPROC)(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *attrib_list);
typedef EGLSurface  (EGLAPIENTRY* PFNEGLCREATEWINDOWSURFACEPROC)(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list);
typedef EGLint      (EGLAPIENTRY* PFNEGLGETERRORPROC)(void);
typedef EGLDisplay  (EGLAPIENTRY* PFNEGLGETDISPLAYPROC)(EGLNativeDisplayType display_id);
typedef void* (EGLAPIENTRY* PFNEGLGETPROCADDRESSPROC)(const char *procname);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLINITIALIZEPROC)
	(EGLDisplay dpy, EGLint *major, EGLint *minor);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLMAKECURRENTPROC)
	(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLDESTROYCONTEXTPROC)
	(EGLDisplay dpy, EGLContext ctx);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLDESTROYSURFACEPROC)
	(EGLDisplay dpy, EGLSurface surface);
typedef const char* (EGLAPIENTRY* PGNEGLQUERYSTRINGPROC)
	(EGLDisplay dpy, EGLint name);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLSWAPBUFFERSPROC)
	(EGLDisplay dpy, EGLSurface surface);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLSWAPINTERVALPROC)
	(EGLDisplay dpy, EGLint interval);
typedef EGLBoolean  (EGLAPIENTRY* PFNEGLTERMINATEPROC)
	(EGLDisplay dpy);
typedef EGLBoolean (EGLAPIENTRY* PFNEGLBINDAPIPROC)(EGLenum);
typedef EGLBoolean (EGLAPIENTRY* PFNEGLGETCONFIGSPROC)
	(EGLDisplay, EGLConfig*, EGLint, EGLint*);
typedef const char* (EGLAPIENTRY* PFNEGLQUERYSTRINGPROC)(EGLDisplay, EGLenum);
typedef EGLBoolean (EGLAPIENTRY* PFNEGLSTREAMCONSUMERACQUIREATTRIBNVPROC)(EGLDisplay,
	EGLStreamKHR, const EGLAttrib*);

struct egl_env {
/* EGLImage */
	PFNEGLCREATEIMAGEKHRPROC create_image;
	PFNEGLDESTROYIMAGEKHRPROC destroy_image;
	PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target_texture2D;

/* DMA-Buf */
	PFNEGLQUERYDMABUFFORMATSEXTPROC query_dmabuf_formats;
	PFNEGLQUERYDMABUFMODIFIERSEXTPROC query_dmabuf_modifiers;

/* EGLStreams */
	PFNEGLQUERYDEVICESEXTPROC query_devices;
	PFNEGLQUERYDEVICESTRINGEXTPROC query_device_string;
	PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display;
	PFNEGLGETOUTPUTLAYERSEXTPROC get_output_layers;
	PFNEGLCREATESTREAMKHRPROC create_stream;
	PFNEGLDESTROYSTREAMKHRPROC destroy_stream;
	PFNEGLSTREAMCONSUMEROUTPUTEXTPROC stream_consumer_output;
	PFNEGLCREATESTREAMPRODUCERSURFACEKHRPROC create_stream_producer_surface;
	PFNEGLSTREAMCONSUMERACQUIREKHRPROC stream_consumer_acquire;
	PFNEGLSTREAMCONSUMERACQUIREATTRIBNVPROC stream_consumer_acquire_attrib;

/* Basic EGL */
	PFNEGLDESTROYSURFACEPROC destroy_surface;
	PFNEGLGETERRORPROC get_error;
	PFNEGLCREATEWINDOWSURFACEPROC create_window_surface;
	PFNEGLMAKECURRENTPROC make_current;
	PFNEGLGETDISPLAYPROC get_display;
	PFNEGLINITIALIZEPROC initialize;
	PFNEGLBINDAPIPROC bind_api;
	PFNEGLGETCONFIGSPROC get_configs;
	PFNEGLCHOOSECONFIGPROC choose_config;
	PFNEGLCREATECONTEXTPROC create_context;
	PFNEGLGETPROCADDRESSPROC get_proc_address;
	PFNEGLDESTROYCONTEXTPROC destroy_context;
	PFNEGLTERMINATEPROC terminate;
	PFNEGLQUERYSTRINGPROC query_string;
	PFNEGLSWAPBUFFERSPROC swap_buffers;
	PFNEGLSWAPINTERVALPROC swap_interval;
};

static void map_ext_functions(struct egl_env* denv,
	void*(lookup)(void* tag, const char* sym, bool req), void* tag);

static void* lookup(void* tag, const char* sym, bool req)
{
	dlerror();
	void* res = dlsym(tag ? tag : RTLD_DEFAULT, sym);
	if (dlerror() != NULL && req){
		arcan_fatal("agp lookup(%s) failed, missing req. symbol.\n", sym);
	}
	return res;
}

static void* lookup_call(void* tag, const char* sym, bool req)
{
	PFNEGLGETPROCADDRESSPROC getproc = tag;
	void* res = getproc(sym);
	if (!res && req)
		arcan_fatal("agp lookup(%s) failed, missing req. symbol.\n", sym);
	return res;
}

static char* egl_synchopts[] = {
	"default", "Display controls refresh",
	"fast", "Clients refresh during display synch",
	"conservative", "Load regulates refresh",
	NULL
};

static char* egl_envopts[] = {
	"[ for multiple devices, append _n to key (e.g. device_2=) ]", "",
	"device=/path/to/dev", "for multiple devices suffix with _n (n = 2,3..)",
	"device_buffer=method", "set buffer transfer method (gbm, streams)",
	"device_libs=lib1:lib2", "libs used for device",
	"device_connector=ind", "primary display connector index",
	"device_wait", "loop until an active connector is found",
	NULL
};

enum {
	DEFAULT = 0,
	FAST,
	CONSERVATIVE,
	ENDM
} synchopt;

enum dri_method {
	M_GBM_SWAP,
	M_GBM_HEADLESS,
	M_EGLSTREAMS
};

enum vsynch_method {
	VSYNCH_FLIP = 0,
	VSYNCH_CLOCK = 1
};

#define IS_GBM_DISPLAY(X)((X)->method == M_GBM_SWAP || (X)->method == M_GBM_HEADLESS)

/*
 * Each open output device, can be shared between displays
 */
struct dev_node {
	int active; /*tristate, 0 = not used, 1 = active, 2 = displayless, 3 = inactive */
	int fd;

/* things we need to track to be able to forward devices to a client */
	struct {
		int fd;
		uint8_t* metadata;
		size_t metadata_sz;
	} client_meta;
	int refc;

/* dev_node to use instead of this when performing reset */
	int gpu_index;
	bool have_altgpu;

	enum vsynch_method vsynch_method;

/* kms/drm triggers, master is if we've achieved the drmMaster lock or not.
 * card_id is some unique sequential identifier for this card
 * crtc is an allocation bitmap for output port<->display allocation
 * atomic is set if the driver kms side supports/needs atomic modesetting */
	bool master, force_master, wait_connector;
	int card_id;
	uint32_t crtc_alloc;
	bool atomic;

/* method determines which of [stream,egldev] | [gbm] we use, this follows into
 * the platform-video-synch, setup and shutdown */
	enum dri_method method;
	EGLDeviceEXT egldev;
	struct gbm_device* gbm;

/*
 * NOTE: possible that these should be moved and managed per struct dispout
 * rather than shared between all displays.
 */
	EGLConfig config;
	EGLContext context;
	EGLDisplay display;

/*
 * to deal with multiple GPUs and multiple vendor libraries, these contexts are
 * managed per display and explicitly referenced / switched when we need to.
 */
	char* egllib;
	char* agplib;
	struct egl_env eglenv;
	struct agp_fenv* agpenv;
};

enum disp_state {
	DISP_UNUSED = 0,
	DISP_KNOWN = 1,
	DISP_MAPPED = 2,
	DISP_CLEANUP = 3,
	DISP_EXTSUSP = 4
};

/*
 * only the setup_cards_db() initialization path can handle more than one
 * device node, and it is incomplete still until we can maintain affinity
 * for all resources.
 */
#ifndef VIDEO_MAX_NODES
#define VIDEO_MAX_NODES 4
#endif
static struct dev_node nodes[VIDEO_MAX_NODES];

enum output_format {
	output_888 = 0,
	output_10b = 1
};

/*
 * aggregation struct that represent one triple of display, card, bindings
 */
struct dispout {
/* connect drm, gbm and EGLs idea of a device */
	struct dev_node* device;
	unsigned long long last_update;
	int output_format;

/* the output buffers, actual fields use will vary with underlying
 * method, i.e. different for normal gbm, headless gbm and eglstreams */
	struct {
		int in_flip, in_destroy;
		EGLSurface esurf;
		EGLStreamKHR stream;
		struct gbm_bo* cur_bo, (* next_bo);
		uint32_t cur_fb;
		struct gbm_surface* surface;
		struct drm_mode_map_dumb dumb;
		size_t dumb_pitch;
	} buffer;

	struct {
		bool reset_mode, primary;
		drmModeConnector* con;
		uint32_t con_id;
		drmModeModeInfoPtr mode;
		drmModeCrtcPtr old_crtc;
		int crtc;
		uint32_t crtc_ind;
		int plane_id;
		enum dpms_state dpms;
		char* edid_blob;
		size_t blob_sz;
		size_t blackframes;
		size_t gamma_size;
		uint16_t* orig_gamma;
	} display;

/* internal v-store and system mappings, rules for drawing final output */
	arcan_vobj_id vid;
	size_t dispw, disph, dispx, dispy;
	_Alignas(16) float projection[16];
	_Alignas(16) float txcos[8];
	enum blitting_hint hint;
	enum disp_state state;
	platform_display_id id;

/* backlight is "a bit" quirky, we register a custom led controller that
 * is shared for all displays and processed while we're busy synching.
 * Subleds on this controller match the displayid of the display */
	struct backlight* backlight;
	long backlight_brightness;
};

static struct {
	struct dispout* last_display;
	size_t canvasw, canvash;
	long long destroy_pending;
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

/*
 * Same example as on khronos.org/registry/OpenGL/docs/rules.html
 */
static bool check_ext(const char* needle, const char* haystack)
{
	const char* cpos = haystack;
	size_t len = strlen(needle);
	const char* eoe = haystack + strlen(haystack);

	while (cpos < eoe){
		int n = strcspn(cpos, " ");
		if (len == n && strncmp(needle, cpos, n) == 0)
			return true;
		cpos += (n+1);
	}

	return false;
}

static void dpms_set(struct dispout* d, int level)
{
/*
 * FIXME: this needs to be deferred in the same way as disable / etc.
 */
	drmModePropertyPtr prop;
	debug_print("dpms_set(%d) to %d", d->device->fd, level);
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

static void release_card(size_t i)
{
	if (!nodes[i].active)
		return;

	if (nodes[i].context != EGL_NO_CONTEXT){
		nodes[i].eglenv.destroy_context(nodes[i].display, nodes[i].context);
		nodes[i].context = EGL_NO_CONTEXT;
	}

	if (IS_GBM_DISPLAY(&nodes[i])){
		if (nodes[i].gbm)
			gbm_device_destroy(nodes[i].gbm);
		nodes[i].gbm = NULL;
	}
	else {
	}

	if (nodes[i].master)
		drmDropMaster(nodes[i].fd);
	close(nodes[i].fd);
	nodes[i].fd = -1;

	if (nodes[i].display != EGL_NO_DISPLAY){
		nodes[i].eglenv.terminate(nodes[i].display);
		nodes[i].display = EGL_NO_DISPLAY;
	}

	nodes[i].active = false;
}

void setup_backlight_ledmap()
{
	if (pipe(egl_dri.ledpair) == -1)
		return;

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
	if (!egl_dri.last_display)
		return "No EGL display";

	EGLint errc = egl_dri.last_display->device->eglenv.get_error();
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

static int setup_buffers_stream(struct dispout* d)
{
	if (!d->device->eglenv.create_stream ||
		!d->device->eglenv.query_devices ||
		!d->device->eglenv.query_device_string ||
		!d->device->eglenv.get_platform_display ||
		!d->device->eglenv.get_output_layers ||
		!d->device->eglenv.create_stream ||
		!d->device->eglenv.stream_consumer_output ||
		!d->device->eglenv.create_stream_producer_surface){
		debug_print("EGLStreams, buffers failed, missing functions");
		return -1;
	}

	const char* extstr = d->device->eglenv.query_string(
		d->device->display, EGL_EXTENSIONS);
	const char* lastext;
	if (!check_ext(lastext = "EGL_EXT_output_base", extstr) ||
		!check_ext(lastext = "EGL_EXT_output_drm", extstr) ||
		!check_ext(lastext = "EGL_KHR_stream", extstr) ||
		!check_ext(lastext = "EGL_EXT_stream_consumer_egloutput", extstr) ||
		!check_ext(lastext = "EGL_KHR_stream_producer_eglsurface", extstr)){
		debug_print("EGLstreams, couldn't find extension (%s)", lastext);
			return -1;
	}

	EGLAttrib layer_attrs[] = {
		EGL_DRM_PLANE_EXT,
		d->display.plane_id,
		EGL_NONE
	};

	EGLint surface_attrs[] = {
		EGL_WIDTH, d->display.mode->hdisplay,
		EGL_HEIGHT, d->display.mode->vdisplay,
		EGL_NONE
	};

	EGLint stream_attrs[] = {
		EGL_STREAM_FIFO_LENGTH_KHR, 1,
//		EGL_CONSUMER_AUTO_ACQUIRE_EXT, EGL_FALSE,
 		EGL_NONE
 	};

	const char* extension_string =
		eglQueryString(d->device->display, EGL_EXTENSIONS);
/*
 * 1. Match output layer to KMS plane
 */
	EGLOutputLayerEXT layer;
	EGLint n_layers = 0;
	if (!d->device->eglenv.get_output_layers(
		d->device->display, layer_attrs, &layer, 1, &n_layers) || !n_layers){
		debug_print("EGLstreams, couldn't get output layer for display");
		return -1;
	}

/*
 * 2. Create stream
 */
	d->buffer.stream =
		d->device->eglenv.create_stream(d->device->display, stream_attrs);
	if (d->buffer.stream == EGL_NO_STREAM_KHR){
		debug_print("EGLstreams - couldn't create output stream");
		return -1;
	}

/*
 * 3. Map stream output
 */
	if (!d->device->eglenv.stream_consumer_output(
		d->device->display, d->buffer.stream, layer)){
		d->device->eglenv.destroy_stream(d->device->display, d->buffer.stream);
		d->buffer.stream = EGL_NO_STREAM_KHR;
		debug_print("EGLstreams - couldn't map output stream");
		return -1;
	}

/*
 * 4. Create stream-bound surface
 */
	d->buffer.esurf = d->device->eglenv.create_stream_producer_surface(
		d->device->display, d->device->config, d->buffer.stream, surface_attrs);
	if (!d->buffer.esurf){
		d->device->eglenv.destroy_stream(d->device->display, d->buffer.stream);
		d->buffer.stream = EGL_NO_STREAM_KHR;
		debug_print("EGLstreams - couldn't create output surface");
		return -1;
	}

	egl_dri.last_display = d;
	d->device->eglenv.make_current(d->device->display,
		d->buffer.esurf, d->buffer.esurf, d->device->context);

/*
 * 5. Set synchronization attributes on stream
 */
	if (d->device->eglenv.stream_consumer_acquire_attrib){
		EGLAttrib attr[] = {
			EGL_DRM_FLIP_EVENT_DATA_NV, (EGLAttrib) d,
			EGL_NONE,
		};
		d->device->eglenv.stream_consumer_acquire_attrib(
			d->device->display, d->buffer.stream, attr);
	}
	return 0;
}

static int setup_buffers_gbm(struct dispout* d)
{
	SET_SEGV_MSG("libgbm(), creating scanout buffer"
		" failed catastrophically.\n")

	if (!d->device->eglenv.create_image){
		map_ext_functions(&d->device->eglenv,
			lookup_call, d->device->eglenv.get_proc_address);
	}

	if (d->output_format == 1){
		d->buffer.surface = gbm_surface_create(d->device->gbm,
			d->display.mode->hdisplay, d->display.mode->vdisplay,
			GBM_FORMAT_XRGB2101010, GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING
		);

		if (!d->buffer.surface)
			debug_print("libgbm(), 10-bit output\
				requested but no suitable scanout, trying 8-bit\n");
	}

	if (!d->buffer.surface)
		d->buffer.surface = gbm_surface_create(d->device->gbm,
			d->display.mode->hdisplay, d->display.mode->vdisplay,
			GBM_FORMAT_XRGB8888, GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING
		);

	d->buffer.esurf = d->device->eglenv.create_window_surface(
		d->device->display, d->device->config, (uintptr_t)d->buffer.surface, NULL);

	if (d->buffer.esurf == EGL_NO_SURFACE){
		debug_print("couldn't create a window surface.");
		return -1;
	}

	egl_dri.last_display = d;
	d->device->eglenv.make_current(d->device->display,
		d->buffer.esurf, d->buffer.esurf, d->device->context);

	return 0;
}

static int setup_buffers(struct dispout* d)
{
	if (IS_GBM_DISPLAY(d->device))
		return setup_buffers_gbm(d);
	else
		return setup_buffers_stream(d);
}

size_t platform_video_displays(platform_display_id* dids, size_t* lim)
{
	size_t rv = 0;

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_UNUSED)
			continue;

		if (dids && lim && *lim < rv)
			dids[rv] = i;
		rv++;
	}

	if (lim)
		*lim = MAX_DISPLAYS;

	return rv;
}

int platform_video_cardhandle(int cardn,
		int* buffer_method, size_t* metadata_sz, uint8_t** metadata)
{
	if (cardn < 0 || cardn > COUNT_OF(nodes))
		return -1;

	if (metadata_sz && metadata &&
			nodes[cardn].eglenv.query_dmabuf_formats &&
			nodes[cardn].eglenv.query_dmabuf_modifiers){
		*metadata_sz = 0;
		*metadata = NULL;
	}
	else if (metadata_sz && metadata){
		debug_print("no format/modifiers query support, sending simple card\n");
		*metadata_sz = 0;
		*metadata = NULL;
	}

	if (buffer_method)
		*buffer_method = nodes[cardn].method;

	return nodes[cardn].client_meta.fd;
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	struct dispout* d = get_display(disp);

	if (!d || d->state != DISP_MAPPED || mode >= d->display.con->count_modes)
		return false;

	if (d->display.mode == &d->display.con->modes[mode])
		return true;

	debug_print("(%d) schedule mode switch to %zu * %zu", (int) disp,
		d->display.mode->hdisplay, d->display.mode->vdisplay);

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
/* the BOs should die with the surface */
	d->state = DISP_CLEANUP;
	d->device->eglenv.destroy_surface(d->device->display, d->buffer.esurf);
	d->buffer.esurf = EGL_NO_SURFACE;
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

/*
 * setup / allocate a new set of buffers that match the new mode
 */
	if (IS_GBM_DISPLAY(d->device)){
		gbm_surface_destroy(d->buffer.surface);
		d->buffer.surface = NULL;
		if (setup_buffers_gbm(d) != 0)
			return false;
	}
	else {
		d->device->eglenv.destroy_stream(d->device->display, d->buffer.stream);
		d->buffer.stream = EGL_NO_STREAM_KHR;
		if (setup_buffers_stream(d) != 0)
			return false;
	}

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

/*
 * Recall, one of the many ***s in graphics programming at this level is that
 * even though a symbol is exposed, doesn't mean that you should call it. The
 * wise men at Khronos decided that you should also verify them against a list
 * of strings, and of course write the parser yourself.
 */
static void map_ext_functions(struct egl_env* denv,
	void*(lookup)(void* tag, const char* sym, bool req), void* tag)
{
/* Mapping dma_buf */
/* XXX: */
	denv->create_image = (PFNEGLCREATEIMAGEKHRPROC)
		lookup(tag, "eglCreateImageKHR", false);
/* XXX: */
	denv->destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)
		lookup(tag, "eglDestroyImageKHR", false);
/* XXX: */
	denv->image_target_texture2D = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
		lookup(tag, "glEGLImageTargetTexture2DOES", false);

/* EGL_EXT_image_dma_buf_import_modifiers */
	denv->query_dmabuf_modifiers = (PFNEGLQUERYDMABUFMODIFIERSEXTPROC)
		lookup(tag, "eglQueryDmaBufModifiersEXT", false);
	denv->query_dmabuf_formats = (PFNEGLQUERYDMABUFFORMATSEXTPROC)
		lookup(tag, "eglQueryDmaBufFormatsEXT", false);

/* EGLStreams */
/* "EGL_EXT_device_query"
 * "EGL_EXT_device_enumeration"
 * "EGL_EXT_device_query" */

	denv->query_device_string = (PFNEGLQUERYDEVICESTRINGEXTPROC)
		lookup(tag, "eglQueryDeviceStringEXT", false);
	denv->query_devices = (PFNEGLQUERYDEVICESEXTPROC)
		lookup(tag, "eglQueryDevicesEXT", false);
	denv->get_platform_display = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
		lookup(tag, "eglGetPlatformDisplayEXT", false );
	denv->get_output_layers = (PFNEGLGETOUTPUTLAYERSEXTPROC)
		lookup(tag, "eglGetOutputLayersEXT", false);
	denv->create_stream = (PFNEGLCREATESTREAMKHRPROC)
		lookup(tag, "eglCreateStreamKHR", false);
	denv->destroy_stream = (PFNEGLDESTROYSTREAMKHRPROC)
		lookup(tag, "eglDestroyStreamKHR", false);
  denv->stream_consumer_output = (PFNEGLSTREAMCONSUMEROUTPUTEXTPROC)
		lookup(tag, "eglStreamConsumerOutputEXT", false);
	denv->create_stream_producer_surface = (PFNEGLCREATESTREAMPRODUCERSURFACEKHRPROC)
		lookup(tag, "eglCreateStreamProducerSurfaceKHR", false);
	denv->stream_consumer_acquire = (PFNEGLSTREAMCONSUMERACQUIREKHRPROC)
		lookup(tag, "eglStreamConsumerAcquireKHR", false);
	denv->stream_consumer_acquire_attrib = (PFNEGLSTREAMCONSUMERACQUIREATTRIBNVPROC)
		lookup(tag, "eglStreamConsumerAcquireAttribNV", false);
}

static void map_functions(struct egl_env* denv,
	void*(lookup)(void* tag, const char* sym, bool req), void* tag)
{
	denv->destroy_surface =
		(PFNEGLDESTROYSURFACEPROC) lookup(tag, "eglDestroySurface", true);
	denv->get_error =
		(PFNEGLGETERRORPROC) lookup(tag, "eglGetError", true);
	denv->create_window_surface =
		(PFNEGLCREATEWINDOWSURFACEPROC) lookup(tag, "eglCreateWindowSurface", true);
	denv->make_current =
		(PFNEGLMAKECURRENTPROC) lookup(tag, "eglMakeCurrent", true);
	denv->get_display =
		(PFNEGLGETDISPLAYPROC) lookup(tag, "eglGetDisplay", true);
	denv->initialize =
		(PFNEGLINITIALIZEPROC) lookup(tag, "eglInitialize", true);
	denv->bind_api =
		(PFNEGLBINDAPIPROC) lookup(tag, "eglBindAPI", true);
	denv->get_configs =
		(PFNEGLGETCONFIGSPROC) lookup(tag, "eglGetConfigs", true);
	denv->choose_config =
		(PFNEGLCHOOSECONFIGPROC) lookup(tag, "eglChooseConfig", true);
	denv->create_context =
		(PFNEGLCREATECONTEXTPROC) lookup(tag, "eglCreateContext", true);
	denv->destroy_context =
		(PFNEGLDESTROYCONTEXTPROC) lookup(tag, "eglDestroyContext", true);
	denv->terminate = (PFNEGLTERMINATEPROC) lookup(tag, "eglTerminate", true);
	denv->query_string =
		(PFNEGLQUERYSTRINGPROC) lookup(tag, "eglQueryString", true);
	denv->swap_buffers =
		(PFNEGLSWAPBUFFERSPROC) lookup(tag, "eglSwapBuffers", true);
	denv->swap_interval =
		(PFNEGLSWAPINTERVALPROC) lookup(tag, "eglSwapInterval", true);
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

/*
 * first: successful setup_node[egl or gbm], then setup_node
 */
static bool setup_node(struct dev_node* node)
{
	const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	EGLint apiv;
	const char* ident = agp_ident();
	EGLint attrtbl[24] = {
		EGL_RENDERABLE_TYPE, 0,
		EGL_RED_SIZE, OUT_DEPTH_R,
		EGL_GREEN_SIZE, OUT_DEPTH_G,
		EGL_BLUE_SIZE, OUT_DEPTH_B,
		EGL_ALPHA_SIZE, OUT_DEPTH_A,
		EGL_DEPTH_SIZE, 1,
		EGL_STENCIL_SIZE, 1,
	};
	int attrofs = 14;

	if (node->method == M_EGLSTREAMS){
		attrtbl[attrofs++] = EGL_SURFACE_TYPE;
		attrtbl[attrofs++] = EGL_STREAM_BIT_KHR;
	}
	else {
		attrtbl[attrofs++] = EGL_SURFACE_TYPE;
		attrtbl[attrofs++] = EGL_WINDOW_BIT;
	}
	attrtbl[attrofs++] = EGL_NONE;

/* right now, this platform won't support anything that isn't rendering using
 * xGL,VK/EGL which will be a problem for a software based AGP. When we get
 * one, we need a fourth scanout path (ffs) where the worldid rendertarget
 * writes into the scanout buffer immediately. It might be possibly for that
 * AGP to provide a 'faux' EGL implementation though */
	size_t i = 0;
	if (strcmp(ident, "OPENGL21") == 0){
		apiv = EGL_OPENGL_API;
		for (i = 0; attrtbl[i] != EGL_RENDERABLE_TYPE; i++);
		attrtbl[i+1] = EGL_OPENGL_BIT;
	}
	else if (strcmp(ident, "GLES3") == 0 ||
		strcmp(ident, "GLES2") == 0){
		for (i = 0; attrtbl[i] != EGL_RENDERABLE_TYPE; i++);
#ifndef EGL_OPENGL_ES2_BIT
			debug_print("EGL implementation do not support GLESv2, "
				"yet AGP platform requires it, use a different AGP platform.");
			return false;
#endif

#ifndef EGL_OPENGL_ES3_BIT
#define EGL_OPENGL_ES3_BIT EGL_OPENGL_ES2_BIT
#endif
		attrtbl[i+1] = EGL_OPENGL_ES3_BIT;
		apiv = EGL_OPENGL_ES_API;
	}
	else
		return false;

	SET_SEGV_MSG("EGL-dri(), getting the display failed\n");

	if (!node->eglenv.initialize(node->display, NULL, NULL)){
		debug_print("failed to initialize EGL");
		return false;
	}

/*
 * make sure the API we've selected match the AGP platform
 */
	if (!node->eglenv.bind_api(apiv)){
		debug_print("couldn't bind GL API");
		return false;
	}

/*
 * grab and activate config
 */
	EGLint nc;
	node->eglenv.get_configs(node->display, NULL, 0, &nc);
	if (nc < 1){
		debug_print("no configurations found (%s)", egl_errstr());
		return false;
	}

	EGLint selv;
	debug_print("%d configurations found", (int) nc);

	if (!node->eglenv.choose_config(
		node->display, attrtbl, &node->config, 1, &selv)){
		debug_print("couldn't chose a configuration (%s)", egl_errstr());
		return false;
	}

/*
 * create a context to match, and if the output mode is streams,
 * a matching EGLstream
 */
	node->context = node->eglenv.create_context(node->display,
		node->config, EGL_NO_CONTEXT, context_attribs);
	if (node->context == NULL) {
		debug_print("couldn't create a context");
		return false;
	}

	return true;
}

/*
 * We have a circular dependency problem here "kind of": we need to know what
 * driver to pick in order to setup EGL for the node, but there is also an Egl
 * function to setup the EGLDevice from which we can get the node. For most
 * cases the driver would just resolve to a GLvnd implementation anyhow, but we
 * don't know and don't want the restriction when it comes to switching between
 * test drivers etc.
 */
static int setup_node_egl(struct dev_node* node, const char* lib, int fd)
{
	if (!node->eglenv.query_string){
		debug_print("EGLStreams, couldn't get EGL extension string");
		return -1;
	}

	const char* extstr = node->eglenv.query_string(EGL_NO_DISPLAY,EGL_EXTENSIONS);
	const char* lastext;
	if (!check_ext(lastext = "EGL_EXT_platform_base", extstr)){
		debug_print("EGLStreams, missing extension (%s)", lastext);
		return -1;
	}

	if (!node->eglenv.query_devices){
		debug_print("EGLStreams, couldn't find extensions/functions");
		return -1;
	}

	EGLint numdev;
	if (!node->eglenv.query_devices(0, NULL, &numdev) || numdev < 1){
		debug_print("EGLStreams, query failed or no devices found");
		return -1;
	}

	EGLDeviceEXT devs[numdev];
	if (!node->eglenv.query_devices(numdev, devs, &numdev)){
		debug_print("EGLStreams, couldn't query device data");
		return -1;
	}

/*
 * sweep all devices that matches and expose the necessary extensions and pick
 * the first one (should possibly change that to a counter for multiple cards
 * again) or, if fd is provided, the one with stat data that match.
 */
	bool found = false;

	for (size_t i = 0; i < numdev && !found; i++){
		const char* ext = node->eglenv.query_device_string(devs[i], EGL_EXTENSIONS);
		if (!check_ext(lastext = "EGL_EXT_device_drm", ext))
			continue;

		const char* fn =
			node->eglenv.query_device_string(devs[i], EGL_DRM_DEVICE_FILE_EXT);

		if (!fn)
			continue;

		int lfd = platform_device_open(fn, O_RDWR);

/* no caller provided device, go with the one we found */
		if (-1 == fd){
			fd = lfd;
			found = true;
			node->egldev = devs[i];
		}
/* we we want to pair the incoming descriptor with the suggested one */
		else {
			struct stat s1, s2;
			if (-1 == fstat(lfd, &s2) || -1 == fstat(fd, &s1) ||
				s1.st_ino != s2.st_ino || s1.st_dev != s2.st_dev){
					close(lfd);
			}
			else{
				found = true;
				node->egldev = devs[i];
			}
		}
	}

/*
 * 1:1 for card-node:egldisplay might not be correct for the setup here
 * (with normal GBM, this doesn't really matter that much as we have
 * finer control over buffer scanout)
 */
	if (found){
		EGLint attribs[] = {EGL_DRM_MASTER_FD_EXT, fd, EGL_NONE};
		node->fd = fd;
		node->method = M_EGLSTREAMS;
		node->atomic =
			drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) == 0 &&
			drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1) == 0;
		node->display = node->eglenv.get_platform_display(
			EGL_PLATFORM_DEVICE_EXT, node->egldev, attribs);
		node->eglenv.swap_interval(node->display, 0);
		return 0;
	}

	return -1;
}

static void cleanup_node_gbm(struct dev_node* node)
{
	if (node->fd >= 0)
		close(node->fd);
	if (node->client_meta.fd >= 0)
		close(node->client_meta.fd);
	node->client_meta.fd = -1;
	node->fd = -1;
	if (node->gbm)
		gbm_device_destroy(node->gbm);
	node->gbm = NULL;
}

static int setup_node_gbm(struct dev_node* node, const char* path, int fd)
{
	SET_SEGV_MSG("libdrm(), open device failed (check permissions) "
		" or use ARCAN_VIDEO_DEVICE environment.\n");

	node->client_meta.fd = -1;
	node->client_meta.metadata = NULL;
	node->client_meta.metadata_sz = 0;

	if (!path && fd == -1)
		return -1;
	else if (fd != -1)
		node->fd = fd;
	else
		node->fd = platform_device_open(path, O_RDWR | O_CLOEXEC);

	if (-1 == node->fd){
		if (path)
			debug_print("gbm, open device failed on path(%s)", path);
		else
			debug_print("gbm, open device failed on fd(%d)", fd);
		return -1;
	}

	SET_SEGV_MSG("libgbm(), create device failed catastrophically.\n");
	fcntl(node->fd, F_SETFD, FD_CLOEXEC);
	node->gbm = gbm_create_device(node->fd);

	if (!node->gbm){
		debug_print("gbm, couldn't create gbm device on node");
		cleanup_node_gbm(node);
		return -1;
	}

	node->method = M_GBM_SWAP;

	if (node->eglenv.get_platform_display){
		debug_print("gbm, using eglGetPlatformDisplayEXT");
		node->display = node->eglenv.get_platform_display(
			EGL_PLATFORM_GBM_MESA, (void*)(node->gbm), NULL);
	}
	else{
		debug_print("gbm, building display using native handle only");
		node->display = node->eglenv.get_display((void*)(node->gbm));
	}

/* Set the render node environment variable here, this is primarily for legacy
 * clients that gets launched through arcan - the others should get the
 * descriptor from DEVICEHINT. It also won't work for multiple cards as the
 * last one would just overwrite */
	char pbuf[24] = "/dev/dri/renderD128";

	char* rdev = drmGetRenderDeviceNameFromFd(node->fd);
	if (rdev){
		debug_print("derived render-node: %s", rdev);
		setenv("ARCAN_RENDER_NODE", rdev, 1);
		free(rdev);
	}
/* make a poor guess */
	else {
		size_t ind = strtoul(&path[13], NULL, 10);
		snprintf(pbuf, 24, "/dev/dri/renderD%d", (int)(ind + 128));
		debug_print("guessing render-node to %s", pbuf);
		setenv("ARCAN_RENDER_NODE", pbuf, 1);
	}

	node->client_meta.fd = open(pbuf, O_RDWR | O_CLOEXEC);
	return 0;
}

/*
 * foreach prop on object(id:type):
 *  foreach modprob on prop:
 *   found if name matches modprob -> true:set_val
 */
static bool lookup_drm_propval(int fd,
	uint32_t oid, uint32_t otype, const char* name, uint64_t* val)
{
	drmModeObjectPropertiesPtr oprops =
		drmModeObjectGetProperties(fd, oid, otype);

	for (size_t i = 0; i < oprops->count_props; i++){
		drmModePropertyPtr mprops = drmModeGetProperty(fd, oprops->props[i]);
		if (!mprops)
			continue;

		if (strcmp(name, mprops->name) == 0){
			*val = oprops->prop_values[i];
			drmModeFreeObjectProperties(oprops);
			drmModeFreeProperty(mprops);
			return true;
		}

		drmModeFreeProperty(mprops);
	}

	drmModeFreeObjectProperties(oprops);
	return false;
}

/*
 * we also have the option of drmModeAddFB2(
 *  fd,w,h,fmt,handles,pitches,ofsets, bufid, flags)
 * and match/extract a handle from the agp- rendertarget directly (though
 * we would have to make the rtgt- double buffered via the _swap call).
 */
static uint32_t get_gbm_fd(struct dispout* d, struct gbm_bo* bo)
{
	uint32_t new_fb;
	uintptr_t old_fb = (uintptr_t) gbm_bo_get_user_data(bo);
	if (old_fb)
		return old_fb;

	uint32_t handle = gbm_bo_get_handle(bo).u32;
	uint32_t width  = gbm_bo_get_width(bo);
	uint32_t height = gbm_bo_get_height(bo);
	uint32_t stride = gbm_bo_get_stride(bo);

	if (drmModeAddFB(d->device->fd, width, height, 24,
		sizeof(av_pixel) * 8, stride, handle, &new_fb)){
			debug_print("(%d) couldn't add framebuffer (%s)",
				(int)d->id, strerror(errno));
		gbm_surface_release_buffer(d->buffer.surface, bo);
		return 0;
	}

	old_fb = new_fb;
	gbm_bo_set_user_data(bo, (void*)old_fb, NULL);
	return new_fb;
}

static bool set_dumb_fb(struct dispout* d)
{
	struct drm_mode_create_dumb create = {
		.width = d->display.mode->hdisplay,
		.height = d->display.mode->vdisplay,
		.bpp = 32
	};
	int fd = d->device->fd;
	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0){
		debug_print("(%d) create dumb-fb failed", (int) d->id);
		return false;
	}
	if (drmModeAddFB(fd,
		d->display.mode->hdisplay, d->display.mode->vdisplay, 24, 32,
		create.pitch, create.handle, &d->buffer.cur_fb)){
		debug_print("(%d) couldn't add dumb-fb", (int) d->id);
		return false;
	}

	d->buffer.dumb.handle = create.handle;
	d->buffer.dumb_pitch = create.pitch;
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &d->buffer.dumb) < 0){
		drmModeRmFB(fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
		debug_print("(%d) couldn't map dumb-fb", (int) d->id);
		return false;
	}

	void* mem = mmap(0,
		create.size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, d->buffer.dumb.offset);
	if (MAP_FAILED == mem){
		debug_print("(%d) couldn't mmap dumb-fb", (int) d->id);
		drmModeRmFB(fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
		return false;
	}
	memset(mem, 0xaa, create.size);
/* NOTE: should we munmap here? */
	return true;
}

static bool resolve_add(int fd, drmModeAtomicReqPtr dst, uint32_t obj_id,
	drmModeObjectPropertiesPtr pptr, const char* name, uint32_t val)
{
	for (size_t i = 0; i < pptr->count_props; i++){
		drmModePropertyPtr prop = drmModeGetProperty(fd, pptr->props[i]);
		if (!prop)
			continue;

		if (strcmp(prop->name, name) == 0){
			drmModeAtomicAddProperty(dst, obj_id, prop->prop_id, val);
			drmModeFreeProperty(prop);
			return true;
		}
		drmModeFreeProperty(prop);
	}

	return false;
}

static bool atomic_set_mode(struct dispout* d)
{
	uint32_t mode;
	bool rv = false;
	int fd = d->device->fd;

	if (0 != drmModeCreatePropertyBlob(fd,
		d->display.mode, sizeof(drmModeModeInfo), &mode)){
		debug_print("(%d) atomic-modeset, failed to create mode-prop");
		return false;
	}

	drmModeAtomicReqPtr aptr = drmModeAtomicAlloc();

#define AADD(ID, LBL, VAL) if (!resolve_add(fd,aptr,(ID),pptr,(LBL),(VAL))){\
	debug_print("(%d) atomic-modeset, failed to resolve prop %s", (int) d->id, (LBL));\
	goto cleanup;\
}

	drmModeObjectPropertiesPtr pptr =
		drmModeObjectGetProperties(fd, d->display.crtc, DRM_MODE_OBJECT_CRTC);
	if (!pptr){
		debug_print("(%d) etomic-modeset, failed to get crtc prop", (int) d->id);
		goto cleanup;
	}
	AADD(d->display.crtc, "MODE_ID", mode);
	AADD(d->display.crtc, "ACTIVE", 1);
	drmModeFreeObjectProperties(pptr);

	pptr = drmModeObjectGetProperties(fd,
		d->display.con->connector_id, DRM_MODE_OBJECT_CONNECTOR);
	if (!pptr){
		debug_print("(%d) atomic-modeset, failed to get connector prop", (int)d->id);
		goto cleanup;
	}
	AADD(d->display.con->connector_id, "CRTC_ID", d->display.crtc);
	drmModeFreeObjectProperties(pptr);

	pptr =
		drmModeObjectGetProperties(fd, d->display.plane_id, DRM_MODE_OBJECT_PLANE);
	if (!pptr){
		debug_print("(%d) atomic-modeset, failed to get plane props", (int)d->id);
		goto cleanup;
	}

	unsigned width = d->display.mode->hdisplay << 16;
	unsigned height = d->display.mode->vdisplay << 16;

	AADD(d->display.plane_id, "SRC_X", 0);
	AADD(d->display.plane_id, "SRC_Y", 0);
	AADD(d->display.plane_id, "SRC_W", width);
	AADD(d->display.plane_id, "SRC_H", height);
	AADD(d->display.plane_id, "CRTC_X", 0);
	AADD(d->display.plane_id, "CRTC_Y", 0);
	AADD(d->display.plane_id, "CRTC_W", width);
	AADD(d->display.plane_id, "CRTC_H", height);
	AADD(d->display.plane_id, "FB_ID", d->buffer.cur_fb);
	AADD(d->display.plane_id, "CRTC_ID", d->display.crtc);
#undef AADD

/* resolve sym:id for the properties on the objects we need:
 */

	if (0 != drmModeAtomicCommit(fd,aptr, DRM_MODE_ATOMIC_ALLOW_MODESET, NULL)){
		goto cleanup;
	}
	else
		rv = true;

cleanup:
	drmModeAtomicFree(aptr);
	drmModeDestroyPropertyBlob(fd, mode);

	return rv;
}

/*
 * foreach plane in plane-resources(dev):
 *  if plane.crtc == display.crtc:
 *   find type
 *   if type is primary, set and true
 */
static bool find_plane(struct dispout* d)
{
	drmModePlaneResPtr plane_res = drmModeGetPlaneResources(d->device->fd);
	d->display.plane_id = 0;
	if (!plane_res){
		debug_print("(%d) atomic-modeset, couldn't find plane on device",(int)d->id);
		return false;
	}
	for (size_t i = 0; i < plane_res->count_planes; i++){
		drmModePlanePtr plane =
			drmModeGetPlane(d->device->fd, plane_res->planes[i]);
		if (!plane){
			debug_print("(%d) atomic-modeset, couldn't get plane plane (%zu)",(int)d->id,i);
			return false;
		}
		uint32_t crtcs = plane->possible_crtcs;
		drmModeFreePlane(plane);
		if (0 == (crtcs & (1 << d->display.crtc_ind)))
			continue;

		uint64_t val;
		if (!lookup_drm_propval(d->device->fd,
			plane_res->planes[i], DRM_MODE_OBJECT_PLANE, "type", &val))
			continue;

/* NOTE: There are additional constraints for PRIMARY planes that don't
 * apply to OVERLAY planes - we can't do scaling, plane size must cover
 * all of CRTC etc. If we use this wrong, check dmesg for something like
 * 'DRM: plane must cover entire CRTC' */
		if (val == DRM_PLANE_TYPE_PRIMARY){
			d->display.plane_id = plane_res->planes[i];
			break;
		}
	}
	drmModeFreePlaneResources(plane_res);
	return d->display.plane_id != 0;
}

static int setup_kms(struct dispout* d, int conn_id, size_t w, size_t h)
{
	SET_SEGV_MSG("egl-dri(), enumerating connectors on device failed.\n");
	drmModeRes* res;

retry:
 	res = drmModeGetResources(d->device->fd);
	if (!res){
		debug_print("(%d) setup_kms, couldn't get resources (fd:%d)",
			(int)d->id, (int)d->device->fd);
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
 * No connector in place, set a retry- timer or give up. The other
 * option would be to switch over to display/headless mode
 */
	if (!d->display.con){
		drmModeFreeResources(res);

/* only wait for the first display */
		if (d == &displays[0] && d->device->wait_connector){
			debug_print("(%d) setup-kms, no display - retry in 5s", (int)d->id);
			sleep(5);
			goto retry;
		}

		debug_print("(%d) setup-kms, no connected displays", (int)d->id);
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
		debug_print("(%d) setup-kms, could not find a suitable display mode");
		drmModeFreeConnector(d->display.con);
		d->display.con = NULL;
		drmModeFreeResources(res);
		return -1;
	}

	debug_print("(%d) setup-kms, picked %zu*%zu", (int)d->id,
		(size_t)d->display.mode->hdisplay, (size_t)d->display.mode->vdisplay);

	build_orthographic_matrix(d->projection,
		0, d->display.mode->hdisplay, d->display.mode->vdisplay, 0, 0, 1);

/*
 * Grab any EDID data now as we've had issues trying to query it on some
 * displays later while buffers etc. are queued(?). Some reports have hinted
 * that it's more dependent on race conditions on the kernel-driver side when
 * there are multiple EDID queries in flight which can happen as part of
 * on_hotplug(func) style event storms in independent software.
 */
	drmModePropertyPtr prop;
	bool done = false;
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

			debug_print("(%d) possible crtc: %d", (int)d->id, j);
			if (!(d->device->crtc_alloc & (1 << j))){
				d->display.crtc = res->crtcs[j];
				d->display.crtc_ind = j;
				d->device->crtc_alloc |= 1 << j;
				crtc_found = true;
				i = res->count_encoders;
				break;
			}

		}
	}

	if (!crtc_found){
		debug_print("(%d) setup-kms, no working encoder/crtc", (int)d->id);
		drmModeFreeConnector(d->display.con);
		d->display.con = NULL;
		drmModeFreeResources(res);
		return -1;
	}

/* find a matching output-plane for atomic/streams */
	if (d->device->atomic){
		if (!find_plane(d)){
			debug_print("(%d) setup_kms, atomic-find_plane fail", (int)d->id);
			goto drop_disp;
		}
		if (!set_dumb_fb(d)){
			debug_print("(%d) setup_kms, atomic dumb-fb fail", (int)d->id);
			goto drop_disp;
		}
		if (!atomic_set_mode(d)){
			debug_print("(%d) setup_kms, atomic modeset fail", (int)d->id);
			drmModeRmFB(d->device->fd, d->buffer.cur_fb);
			d->buffer.cur_fb = 0;
			goto drop_disp;
		}
	}

	dpms_set(d, DRM_MODE_DPMS_ON);
	d->display.dpms = ADPMS_ON;

	drmModeFreeResources(res);
	return 0;

drop_disp:
	drmModeFreeConnector(d->display.con);
	d->display.con = NULL;
	d->device->crtc_alloc &= ~(1 << d->display.crtc_ind);
	drmModeFreeResources(res);
	return -1;
}

/* NOTE: this does not handle multiple planes correctly,
 * interface needs to carry both that, strides/offsets and designated-gpu +
 * modifiers */
static bool map_handle_gbm(struct agp_vstore* dst, int64_t handle)
{
	if (!nodes[0].eglenv.create_image || !nodes[0].eglenv.image_target_texture2D)
		return false;

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

/*
 * Security notice: stride and format comes from an untrusted data source, it
 * has not been verified if MESA- implementation of eglCreateImageKHR etc.
 * treats this as trusted in respect to the buffer or not, otherwise this is a
 * possibly source for crashes etc. and I see no good way for verifying the
 * buffer manually.
 */
	if (0 != dst->vinf.text.tag){
		nodes[0].eglenv.destroy_image(
			nodes[0].display, (EGLImageKHR) dst->vinf.text.tag);
		dst->vinf.text.tag = 0;

/*
 * Usage note, this goes against what the spec says - but from what it seems
 * like in mesa, we leak one handle per connection without this, and if we
 * close every time, the driver live-locks.
 */
		if (handle != dst->vinf.text.handle){
			close(dst->vinf.text.handle);
		}
		dst->vinf.text.handle = -1;
	}

	if (-1 == handle)
		return false;

/*
 * in addition, we actually need to know which render-node this
 * little bugger comes from, this approach is flawed for multi-gpu
 */
	EGLImageKHR img = nodes[0].eglenv.create_image(
		nodes[0].display,
		EGL_NO_CONTEXT,
		EGL_LINUX_DMA_BUF_EXT,
		(EGLClientBuffer)NULL, attrs
	);

	if (img == EGL_NO_IMAGE_KHR){
		debug_print("could not import EGL buffer (%zu * %zu), "
			"stride: %d, format: %d from %d", dst->w, dst->h,
		 dst->vinf.text.stride, dst->vinf.text.format,handle
		);
		close(handle);
		return false;
	}

/* other option ?
 * EGLImage -> gbm_bo -> glTexture2D with EGL_NATIVE_PIXMAP_KHR */
	agp_activate_vstore(dst);
	nodes[0].eglenv.image_target_texture2D(GL_TEXTURE_2D, img);
	dst->vinf.text.tag = (uintptr_t) img;
	dst->vinf.text.handle = handle;
	agp_deactivate_vstore(dst);
	return true;
}

/*
 * There's a really ugly GLES- inheritance GOTCHA here that makes streams
 * a ******** pain to work with. 99.9% of all existing code works against
 * GL_TEXTURE_2D as the target for 2D buffers. Of course, there's a 'special'
 * GL_TEXTURE_EXTERNAL_OES target that also requires a different sampler in
 * the shader code. This leaves us with 3-ish options.
 * This is actually true for GBM- buffers as well, but so far MESA doesn't
 * really give a duck.
 *
 * 1. Mimic 'CopyTextureCHROMIUM' - explicit render-to-texture pass.
 * 2. The 'Cogl' approach - Make shader management exponentially worse by
 *    tracking the dst- and when binding to a backend, compile/generate variants
 *    where the sampler references are replaced with the 'right' target by
 *    basically doing string- replacement on the program source.
 * 3. Move the complexity to the script level, breaking the opaqueness of
 *    VIDs by forcing separate rules and gotcha's when the VID comes from an
 *    external source. Possibly on the shader level by allowing additional
 *    rule-slots.
 * +. Find some long-lost OpenGL function that relies on semi-defined behavior
 *    to get rid of the _OES sampler type. There's probably something in
 *    EGLImage.
 * +. Nasty hybrid: have a special external version of the 'default' and
 *    when/if that one fails, fall back to 1/2.
 *
 * Granted, we need something similar for dma-buf when the source is one of
 * the many YUUVUUVUV formats.
 *
 * OpenGL: an arcane language with 400 different words for memcpy, where you
 * won't be sure of what src is, or dst, how much will actually be copied or
 * what happens to data in transit.
 */
bool map_handle_stream(struct agp_vstore* dst, int64_t handle)
{
/*
 * 1. eglCreateStreamFromFileDescriptorKHR(dpy, handle)
 * 2. glBindTexture (GL_TEXTURE_EXTERNAL_OES)
 * 3. eglStreamConsumerGLTextureExternalKHR(dpy, stream)
 *
 * to 'poll' the stream, we can go with eglStreamConsumerQueryStream and
 * check that for EGL_STREAM_STATE_NEW_FRAME_AVAILABLE_KHR. We need semantics
 * the the BUFFER_ calls in shmif and the corresponding place in engine/
 * arcan_event.c to use a reserved identifier for matching against the
 * handle.
 *
 * then we have eglStreamConsumerAcquireKHR(dpy, stream)
 */

	return false;
}

/* This interface is insufficient for dealing multi-planar formats and
 * individual plane updates. Something to worry about when we have a test
 * set that actually works for that usecase.. */
bool platform_video_map_handle(
	struct agp_vstore* dst, int64_t handle)
{
/*
 * MULTIGPU:FAIL
 * we need to follow the affinity for the specific [dst], and run the procedure
 * for each set bit in the field, if it is even possible to do with PRIME etc.
 * otherwise we need a mechanism to activate the DEVICEHINT event for the
 * provider to indicate that we need a portable handle.
 */
	if (IS_GBM_DISPLAY(&nodes[0]))
		return map_handle_gbm(dst, handle);
	else
		return map_handle_stream(dst, handle);
	return true;
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	bool free_conn = false;

	struct dispout* d = get_display(id);
	if (!d || d->state == DISP_UNUSED)
		return NULL;

	debug_print("(%d) issuing mode scan", (int) d->id);
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
static void query_card(struct dev_node* node)
{
	drmModeRes* res = drmModeGetResources(node->fd);
	if (!res){
		debug_print("couldn't get resources for rescan on %i", node->fd);
		return;
	}

	for (size_t i = 0; i < res->count_connectors; i++){
		drmModeConnector* con = drmModeGetConnector(node->fd, res->connectors[i]);
		struct dispout* d = match_connector(node->fd, con);

/* no display on connector */
		if (con->connection != DRM_MODE_CONNECTED){
/* if there was one known, remove it and notify */
			debug_print("(%zu) lost, disabled", (int)i);
			if (d){
				debug_print("(%d) display lost, disabling", (int)d->id);
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
			drmModeFreeConnector(con);
			continue;
		}

/* do we already know about the connector? then do nothing */
		if (d){
			debug_print("(%d) already known", (int)d->id);
			drmModeFreeConnector(con);
			continue;
		}

/* allocate display and mark as known but not mapped, give up
 * if we're out of display slots */
		debug_print("unknown display detected");
		d = allocate_display(&nodes[0]);
		if (!d){
			debug_print("failed  to allocate new display");
			drmModeFreeConnector(con);
			continue;
		}

/* save the ID for later so that we can match in match_connector */
		d->display.con = con;
		d->display.con_id = con->connector_id;
		d->backlight = backlight_init(
			d->device->card_id, d->display.con->connector_type,
			d->display.con->connector_type_id
		);
		debug_print(
			"(%d) assigned connector id (%d)",(int)d->id,(int)con->connector_id);
		if (d->backlight){
			debug_print("(%d) display backlight assigned", (int)d->id);
			d->backlight_brightness = backlight_get_brightness(d->backlight);
		}
		arcan_event ev = {
			.category = EVENT_VIDEO,
			.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
			.vid.displayid = d->id,
			.vid.ledctrl = egl_dri.ledid,
			.vid.ledid = d->id,
			.vid.cardid = d->device->card_id
		};
		arcan_event_enqueue(arcan_event_defaultctx(), &ev);
		continue; /* don't want to free con */
	}
	drmModeFreeResources(res);
}

void platform_video_query_displays()
{
	debug_print("issuing display requery");

/*
 * each device node, each connector, check against each display
 * ugly scan complexity, but low values of n.
 */
	for (size_t j = 0; j < COUNT_OF(nodes); j++){
		debug_print("query_card: %zu", j);
		query_card(&nodes[j]);
	}
}

static void disable_display(struct dispout* d, bool dealloc)
{
	if (!d || d->state == DISP_UNUSED){
		debug_print("disable_display called on unused display (%d)", (int)d->id);
		return;
	}

	debug_print("(%d) trying to disable", (int)d->id);
	if (d->buffer.in_flip){
		debug_print("(%d) flip pending, deferring destruction", (int)d->id);
		d->buffer.in_destroy = true;
		egl_dri.destroy_pending |= 1 << d->id;
		return;
	}
/*
	if (egl_dri.last_display == d){
		egl_dri.last_display = NULL;
		d->device->eglenv.make_current(d->device->display,
			EGL_NO_SURFACE, EGL_NO_SURFACE, d->device->context);
	}
 */

	d->device->refc--;
	if (d->buffer.in_destroy){
		egl_dri.destroy_pending &= ~(1 << d->id);
	}
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

	debug_print("(%d) destroying EGL surface", (int)d->id);
	d->device->eglenv.destroy_surface(d->device->display, d->buffer.esurf);
	d->buffer.esurf = NULL;

	if (d->buffer.cur_fb){
		drmModeRmFB(d->device->fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
	}

	if (IS_GBM_DISPLAY(d->device)){
		if (d->buffer.surface){
			debug_print("destroy gbm dislay");

			if (d->buffer.cur_bo)
				gbm_surface_release_buffer(d->buffer.surface, d->buffer.cur_bo);
			gbm_surface_destroy(d->buffer.surface);
		}
		if (d->buffer.cur_bo)
			d->buffer.cur_bo = NULL;

		d->buffer.surface = NULL;
	}
	else
		debug_print("EGL- display");

/* restore the color LUTs, not 100% certain that this is the best approach here
 * since an external- launch then needs to figure out / manipulate them on its
 * own, losing color calibration and so on in the process */
	if (d->display.orig_gamma){
		drmModeCrtcSetGamma(d->device->fd, d->display.crtc,
			d->display.gamma_size, d->display.orig_gamma,
			&d->display.orig_gamma[1*d->display.gamma_size],
			&d->display.orig_gamma[2*d->display.gamma_size]
		);
	}

/* in extended suspend, we have no idea which displays we are returning to so
 * the only real option is to fully deallocate even in EXTSUSP */
	debug_print("(%d) release crtc id (%d)", (int)d->id,(int)d->display.crtc_ind);
	d->device->crtc_alloc &= ~(1 << d->display.crtc_ind);
	if (d->display.old_crtc){
		debug_print("(%d) old mode found, trying to reset", (int)d->id);
		if (d->device->atomic){
			d->display.mode = &d->display.old_crtc->mode;
			if (atomic_set_mode(d)){
				debug_print("(%d) atomic-modeset failed on (%d)",
					(int)d->id, (int)d->display.con_id);
			}
		}
		else if (0 > drmModeSetCrtc(
			d->device->fd,
			d->display.old_crtc->crtc_id,
			d->display.old_crtc->buffer_id,
			d->display.old_crtc->x,
			d->display.old_crtc->y,
			&d->display.con_id, 1,
			&d->display.old_crtc->mode
		)){
			debug_print("Error setting old CRTC on %d", d->display.con_id);
		}
	}

/* in the no-dealloc state we still want to remember which CRTCs etc were
 * set as those might have been changed as part of a modeset request */
	if (!dealloc){
		debug_print("(%d) switched state to EXTSUSP", (int)d->id);
		d->state = DISP_EXTSUSP;
		return;
	}

/* gamma has already been restored above, but we need to free the resources */
	debug_print("(%d) full deallocation requested", (int)d->id);
	if (d->display.orig_gamma){
		free(d->display.orig_gamma);
		d->display.orig_gamma = NULL;
	}

	drmModeFreeConnector(d->display.con);
	d->display.con = NULL;
	d->display.con_id = 0;

	drmModeFreeCrtc(d->display.old_crtc);
	d->display.old_crtc = NULL;
	d->display.mode = NULL;

/*	d->device = NULL; */
	d->state = DISP_UNUSED;

	if (d->backlight){
		backlight_set_brightness(d->backlight, d->backlight_brightness);
		backlight_destroy(d->backlight);
		d->backlight = NULL;
	}
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
	if (egl_dri.last_display && egl_dri.last_display->display.mode){
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
	return nodes[0].eglenv.get_proc_address(sym);
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

static bool try_node(int fd, const char* pathref,
	int dst_ind, bool gbm, bool force_master, int connid, int w, int h)
{
/* set default lookup function if none has been provided */
	if (!nodes[dst_ind].eglenv.get_proc_address){
		nodes[dst_ind].eglenv.get_proc_address =
			(PFNEGLGETPROCADDRESSPROC)eglGetProcAddress;
	}
	struct dev_node* node = &nodes[dst_ind];
	node->active = true;
	map_functions(&node->eglenv, lookup, NULL);
	map_ext_functions(&node->eglenv, lookup_call, node->eglenv.get_proc_address);

	if (gbm){
		if (0 != setup_node_gbm(node, pathref, fd)){
			node->eglenv.get_proc_address = NULL;
			debug_print("couldn't open (%d:%s) in GBM mode",
				fd, pathref ? pathref : "(no path)");
				release_card(dst_ind);
			return false;
		}
	}
	else {
		if (0 != setup_node_egl(node, pathref, fd)){
			debug_print("couldn't open (%d:%s) in EGLStreams mode",
				fd, pathref ? pathref : "(no path)");
			release_card(dst_ind);
			return false;
		}
	}

	if (!setup_node(node)){
		debug_print("setup/configure [%d](%d:%s)",
			dst_ind, fd, pathref ? pathref : "(no path)");
		release_card(dst_ind);
		return false;
	}

	drmDropMaster(node->fd);
	if (0 != drmSetMaster(node->fd)){
		debug_print("set drmMaster on [%d](%d:%s) failed, reason: %s",
			dst_ind, fd, pathref ? pathref : "(no path)", strerror(errno));
		if (force_master){
			release_card(dst_ind);
			return false;
		}
	}

	nodes->force_master = force_master;
	struct dispout* d = allocate_display(node);
	d->display.primary = dst_ind == 0;
	egl_dri.last_display = d;

	if (setup_kms(d, connid, w, h) != 0){
		disable_display(d, true);
		debug_print("card found, but no working/connected display");
		release_card(dst_ind);
		return false;
	}

	if (setup_buffers(d) != 0){
		disable_display(d, true);
		release_card(dst_ind);
		return false;
	}

	d->backlight = backlight_init(d->device->card_id,
		d->display.con->connector_type, d->display.con->connector_type_id);

	if (d->backlight)
		d->backlight_brightness = backlight_get_brightness(d->backlight);
	return true;
}

/*
		dump_connectors(stdout, &nodes[0], true);
 */

/*
 * config/profile matching derived approach, for use when something more
 * specific and sophisticated is desired
 */
static bool try_card(size_t devind, int w, int h, size_t* dstind)
{
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	char* devstr, (* cfgstr), (* altstr);
	int connind = -1;
	bool gbm = true;

/* basic device, device_1, device_2 etc. search path */
	if (!get_config("video_device", devind, &devstr, tag))
		return false;

/* reference to another card_id, only one is active at any one moment
 * and card_1 should reference card_2 and vice versa. */
	if (get_config("video_device_alternate", devind, &cfgstr, tag)){
/* sweep from devind down to 0 and see if there is a card with the
 * specified path, if so, open but don't activate this one */
	}

	if (get_config("video_device_buffer", devind, &cfgstr, tag)){
		if (strcmp(cfgstr, "streams") == 0)
			gbm = false;
		free(cfgstr);
	}

/* reload any possible library references */
	if (nodes[devind].agplib){
		free(nodes[devind].agplib);
		nodes[devind].agplib = NULL;
	}
	if (nodes[devind].egllib){
		free(nodes[devind].egllib);
		nodes[devind].egllib = NULL;
	}
	get_config("video_device_egllib", devind, &nodes[devind].egllib, tag);
	get_config("video_device_agplib", devind, &nodes[devind].agplib, tag);

/* hard- connector index set */
	if (get_config("video_device_connector", devind, &cfgstr, tag)){
		connind = strtol(cfgstr, NULL, 10) % INT_MAX;
		free(cfgstr);
	}

	bool force_master = get_config("video_device_master", devind, NULL, tag);
	nodes[devind].wait_connector =
		get_config("video_device_wait", devind, NULL, tag);

	int fd = platform_device_open(devstr, O_RDWR | O_CLOEXEC);
	if (try_node(fd, devstr, *dstind, gbm, force_master, connind, w, h)){
		debug_print("card at %d added", *dstind);
		nodes[*dstind].card_id = *dstind;
		nodes[*dstind].fd = fd;
		*dstind++;
		return true;
	}
	else{
		free(nodes[devind].egllib);
		free(nodes[devind].agplib);
		nodes[devind].egllib = nodes[devind].agplib = NULL;
		close(fd);
		free(devstr);
		return false;
	}
}

static bool setup_cards_db(int w, int h)
{
	size_t dstind = 0;
	for (size_t devind = 0; devind < COUNT_OF(nodes); devind++){
		if (!try_card(devind, w, h, &dstind))
			return dstind > 0;
		dstind++;
	}

	return dstind > 0;
}

/*
 * Externally/inheritance based card management, some parent process is
 * responsible for the device node. This has the drawback of not knowing the
 * settings to use, so some transfer mechanism would be needed for that as
 * well. This is primarily for inane garbage like logind.
 */
static bool setup_cards_inherit(int w, int h)
{
	const char* override = getenv("ARCAN_VIDEO_DEVFD");
	if (!override)
		return false;

	int fd = -1;
	if (isdigit(override[0]))
		fd = strtoul(override, NULL, 10);

	return try_node(fd, NULL, 0, true, false, -1, w, h);
}

/*
 * naive approach - for when there's no explicit configuration set.
 * This just globs a preset/os-specific path and takes the first
 * device that appears and can be opened.
 */
static bool setup_cards_basic(int w, int h)
{
/*
 * on OpenBSD etc. we have a different path, /dev/drm0
 */
#ifndef VDEV_GLOB
#ifdef __OpenBSD__
#define DEVICE_PATH "/dev/drm%zu"
#else
#define DEVICE_PATH "/dev/dri/card%zu"
#endif
#endif

/* sweep as there might be more GPUs but without any connected
 * display, indicating that it's not a valid target for autodetect. */
	for (size_t i = 0; i < 4; i++){
		char buf[sizeof(DEVICE_PATH)];
		snprintf(buf, sizeof(buf), DEVICE_PATH, i);
		int fd = platform_device_open(buf, O_RDWR | O_CLOEXEC);
		debug_print("trying [basic/auto] setup on %s", buf);
		if (-1 != fd){
/* possible quick hack, just check modules if we have nouveau or nvidia loaded
 * and use that to select buffer mode - there's probably better ways but meh. */
			if (try_node(fd, buf, 0, true, false, -1, w, h) ||
				try_node(fd, buf, 0, false, false, -1, w, h))
					return true;
			else{
				debug_print("node setup failed");
				close(fd);
			}
		}
	}

	/* in the no-dealloc state we still want to remember which CRTCs etc were
	 * set as those might have been changed as part of a modeset request */
	return false;
}

void platform_video_preinit()
{
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

	if (setup_cards_db(w, h) ||
		setup_cards_inherit(w, h) || setup_cards_basic(w, h)){
		struct dispout* d = egl_dri.last_display;
		egl_dri.canvasw = d->display.mode->hdisplay;
		egl_dri.canvash = d->display.mode->vdisplay;
		build_orthographic_matrix(d->projection, 0,
			egl_dri.canvasw, egl_dri.canvash, 0, 0, 1);
		memcpy(d->txcos, arcan_video_display.mirror_txcos, sizeof(float) * 8);
		d->vid = ARCAN_VIDEO_WORLDID;
		d->state = DISP_MAPPED;
		debug_print("(%d) mapped/default display at %zu*%zu",
			(int)d->id, (size_t)egl_dri.canvasw, (size_t)egl_dri.canvash);

		setup_backlight_ledmap();
/*
 * send a first 'added' event for display tracking as the
 * primary / connected display will not show up in the rescan
 */
		arcan_event ev = {
			.category = EVENT_VIDEO,
			.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
			.vid.ledctrl = egl_dri.ledid,
			.vid.cardid = d->device->card_id
		};
		arcan_event_enqueue(arcan_event_defaultctx(), &ev);
		platform_video_query_displays();
		rv = true;
	}

	sigaction(SIGSEGV, &old_sh, NULL);
	return rv;
}

static bool in_external;
void platform_video_reset(int id, int swap)
{
	if (!in_external)
		return;

/* only swap has any real behavior here and only if there are fallback- card
 * nodes set for a specific GPU */
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
	debug_print("video_recovery, injecting 'added' for mapped displays");
	arcan_evctx* evctx = arcan_event_defaultctx();
	arcan_event_enqueue(evctx, &ev);

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_MAPPED){
			platform_video_map_display(
				ARCAN_VIDEO_WORLDID, displays[i].id, HINT_NONE);
			ev.vid.displayid = displays[i].id;
			ev.vid.cardid = displays[i].device->card_id;
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

	verbose_print("(%d) flip(frame: %u, @ %u.%u)", (int) d->id, frame, sec, usec);

	if (IS_GBM_DISPLAY(d->device)){
/* swap out front / back BO */
		if (d->buffer.cur_bo)
			gbm_surface_release_buffer(d->buffer.surface, d->buffer.cur_bo);

		verbose_print("(%d) gbm-bo, release %"PRIxPTR" with %"PRIxPTR,
			(int)d->id, (uintptr_t) d->buffer.cur_bo, (uintptr_t) d->buffer.next_bo);
		d->buffer.cur_bo = d->buffer.next_bo;
		d->buffer.next_bo = NULL;
	}
}

/*
 * Real synchronization work is in this function. Go through all mapped
 * displays and wait for any pending events to finish, or the specified
 * timeout(ms) to elapse.
 */
extern void amain_clock_pulse(int nticks);
extern void amain_process_event(arcan_event* ev, int drain);
static void flush_display_events(int timeout)
{
	int pending = 1;
	struct dispout* d;
	verbose_print("flush display events, timeout: %d", timeout);

/*
 * Until we have a decent 'conductor' for managing synchronization for
 * all the different audio/video/input producers and consumers, keep
 * on processing audio input while we wait for displays to finish synch.
 */
	unsigned long long start = arcan_timemillis();

/*
 * First sweep the audio sources to figure out if we have any streaming
 * ones that we should take into account so that they don't run out during
 * vsync.
 */
	size_t naud = synchopt == CONSERVATIVE ? 0 : arcan_audio_refresh();

/*
 * the polling timeout depends on our synch- strategy, if we have any
 * dynamic content providers to take into account - we should take the
 * vysnc- time to sweep that list.
 */
	int period;
	if (timeout > 0){
		period = 4; /* arbitrary, should MOVE TO DATABASE */
	}
	else
		period = timeout;

	drmEventContext evctx = {
			.version = DRM_EVENT_CONTEXT_VERSION,
			.page_flip_handler = page_flip_handler
	};

/*
 * NOTE: recent versions of DRM has added support to let us know which
 * CRTC actually provided a synch signal. When this is more wide-spread,
 * we should really switch to that kind of a system.
 */
	do{
/* MULTICARD> for multiple cards, extend this pollset */
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
/* IF we timeout, just continue with a new render pass as we might be dealing
 * with a faulty driver or an EGLStreams device that doesn't support drm-vsynch
 * integration */
		else if (0 == rv){
			unsigned long long now = arcan_timemillis();
			if (timeout && now > start && now - start < timeout){
				if (naud)
					naud = arcan_audio_refresh();

/* clamp the period so we don't exceed the timeout */
				now = arcan_timemillis();
				if (now - start < period)
					period = now - start;
				continue;
			}
			return;
		}

/* If we get HUP on a card we have open, it is basically as bad as a fatal
 * state, unless - we support hotplugging multi-GPUs, then that decision needs
 * to be re-evaluated as it is essentially a drop_card + drop all displays */
			if (fds.revents & (POLLHUP | POLLERR))
			debug_print("(card-fd %d) broken/recovery missing", (int) nodes[0].fd);
		else
			drmHandleEvent(nodes[0].fd, &evctx);

/* There is a special property here, 'PRIMARY'. The displays with this property
 * set are being used for synch, with the rest - we just accept the possibility
 * of tearing or ignore that display for another frame (extremes like 59.xx Hz
 * display main and a 30Hz secondary output) */
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

/*
 * Destruction of hotplugged displays are deferred to this stage as it is hard
 * to know when it is actually safe to do in other places in the pipeline.
 * Wait until the queued transfers to a display have been finished before it is
 * put down.
 */
	int i = 0;
	struct dispout* d;
	while (egl_dri.destroy_pending){
		flush_display_events(30);
		int ind = ffsll(egl_dri.destroy_pending) - 1;
		debug_print("synch, %d - destroy %d", ind);
		disable_display(&displays[ind], true);
		egl_dri.destroy_pending &= ~(1 << ind);
	}

/* At this stage, the contents of all RTs have been synched, with nd == 0,
 * nothing has changed from what was draw last time - but since we normally run
 * double buffered it is easier to synch the same contents in both buffers, so
 * that when dirty updates are being tracked, we won't be corrupted. */
	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

	static int last_nd;
	bool update = nd || last_nd;
	if (update){
		while ( (d = get_display(i++)) ){
			if (d->state == DISP_MAPPED && d->buffer.in_flip == 0){
				update_display(d);
			}
/*
 * mostly added noise
 * else {
				verbose_print("(%d) can't synch, flip pending", (int)d->id);
			}
 */
		}
	}
	last_nd = nd;

/*
 * The LEDs that are mapped as backlights via the internal pipe-led protocol
 * needs to be flushed separately, here is a decent time to get that out of
 * the way.
 */
	flush_leds();

/*
 * still use an artifical delay / timeout here, see previous notes about the
 * need for a real 'conductor' with synchronization- strategy support. As not
 * all displays report VSYNCH, some may need a simulated clock. We use poll
 * for that.
 */
	static unsigned long long last_synch;
	int lim = 16 - (arcan_timemillis() - last_synch);
	if (lim < 0)
		lim = 16;
	flush_display_events(lim);

	last_synch = arcan_timemillis();

/* Changed but not enough information to actually specify which card we need
 * to rescan in order for the changes to be detected. This needs cooperation
 * with the scripts anyhow as they need to rate-limit / invoke rescan. This
 * only takes care of an invalid or severed connection, moving device disc.
 * to a supervisory process would also require something in event.c */
	int pv = platform_device_poll(NULL);
	if (2 == pv){
		arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
			.category = EVENT_VIDEO,
			.vid.kind = EVENT_VIDEO_DISPLAY_CHANGED,
		});
	}
	else if (-1 == pv){
		arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
			.category = EVENT_SYSTEM,
			.sys.kind = EVENT_SYSTEM_EXIT,
			.sys.errcode = EXIT_FAILURE
		});
	}
	if (post)
		post();
}

bool platform_video_auth(int cardn, unsigned token)
{
	int fd = platform_video_cardhandle(cardn, NULL, NULL, NULL);
	if (fd != -1){
		bool auth_ok = drmAuthMagic(fd, token);
		debug_print("requested auth of (%u) on card (%d)", token, cardn);
		return auth_ok;
	}
	else
		return false;
}

void platform_video_shutdown()
{
	int rc = 10;

	do{
		for(size_t i = 0; i < MAX_DISPLAYS; i++){
			unsigned long start = arcan_timemillis();
			disable_display(&displays[i], true);
			debug_print("shutdown (%d) took %lu ms", arcan_timemillis() - start);
		}
		flush_display_events(17);
	} while (egl_dri.destroy_pending && rc-- > 0);

	for (size_t i = 0; i < sizeof(nodes)/sizeof(nodes[0]); i++)
		release_card(i);
}

void platform_video_setsynch(const char* arg)
{
	int ind = 0;

	while(egl_synchopts[ind]){
		if (strcmp(egl_synchopts[ind], arg) == 0){
			synchopt = (ind > 0 ? ind / 2 : ind);
			debug_print("synchronisation strategy set to (%s)", egl_synchopts[ind]);
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
	struct dispout* disp = get_display(0);

	if (disp){
		eglexts = (const char*)disp->device->eglenv.query_string(
		disp->device->display, EGL_EXTENSIONS);
		dump_connectors(stream, disp->device, true);
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

	if (state != out->display.dpms){
		debug_print("dmps (%d) change to (%d)", (int)disp, state);
		dpms_set(out, adpms_to_dpms(state));
	}

	out->display.dpms = state;
	return state;
}

bool platform_video_map_display(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
	struct dispout* d = get_display(disp);
	if (!d || d->state == DISP_UNUSED){
		debug_print(
			"map_display(%d->%d) attempted on unused disp", (int)id, (int)disp);
		return false;
	}

/* we have a known but previously unmapped display, set it up */
	if (d->state == DISP_KNOWN){
		debug_print("map_display(%d->%d), known but unmapped", (int)id, (int)disp);
		if (setup_kms(d,
			d->display.con->connector_id,
			d->display.mode ? d->display.mode->hdisplay : 0,
			d->display.mode ? d->display.mode->vdisplay : 0) ||
			setup_buffers(d) != 0){
			debug_print("map_display(%d->%d) alloc/map failed", (int)id, (int)disp);
			return false;
		}
		d->state = DISP_MAPPED;
	}

	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj){
		debug_print("setting display(%d) to unmapped", (int) disp);
		d->display.dpms = ADPMS_OFF;
		d->vid = id;
		return true;
	}

	if (vobj->vstore->txmapped != TXSTATE_TEX2D){
		debug_print("map_display(%d->%d) rejected, source not a valid texture",
			(int) id, (int) disp);
		return false;
	}

/* normal object may have origo in UL, WORLDID FBO in LL */
	float txcos[8];
		memcpy(txcos, vobj->txcos ? vobj->txcos :
			(vobj->vstore == arcan_vint_world() ?
				arcan_video_display.mirror_txcos :
				arcan_video_display.default_txcos), sizeof(float) * 8
		);
	debug_print("map_display(%d->%d) ok @%zu*%zu+%zu,%zu, txcos: %d, hint: %d",
		(int) id, (int) disp, (size_t) d->dispw, (size_t) d->disph,
		(size_t) d->dispx, (size_t) d->dispy, (int) hint);

	d->display.primary = hint & HINT_FL_PRIMARY;
	memcpy(d->txcos, txcos, sizeof(float) * 8);
	arcan_vint_applyhint(vobj, hint,
		txcos, d->txcos, &d->dispx, &d->dispy, &d->dispw, &d->disph,
		&d->display.blackframes
	);

	if (d->display.dpms == ADPMS_OFF){
		dpms_set(d, DRM_MODE_DPMS_ON);
		d->display.dpms = ADPMS_ON;
	}

	d->hint = hint;
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

/*
 * This is an ugly sinner, due to the whole 'anything can be mapped as
 * anything' with a lot of potential candidates being in non scanout- capable
 * memory, we pay > a lot < for first drawing into a RT, drawing this RT unto
 * the EGLDisplay and then swapping the EGLDisplay. A full copy (and allocated
 * buffer) could be avoided if we a. accept no shaders on WORLDID, b. only do
 * this for RTs or WORLDID, c. transformations are simple position or
 * 90-deg.rotations
 */
	agp_shader_activate(shid);
	agp_shader_envv(PROJECTION_MATR, d->projection, sizeof(float)*16);
	agp_draw_vobj(0, 0, d->dispw, d->disph, d->txcos, NULL);
	verbose_print("(%d) draw, shader: %d, %zu*%zu",
		(int)d->id, (int)shid, (size_t)d->dispw, (size_t)d->disph);

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

/* we want to know how multiple- displays drift against eachother */
	d->last_update = arcan_timemillis();

/*
 * make sure we target the right GL context
 * MULTIGPU> will also need to set the agp- current rendertarget
 */
	if (egl_dri.last_display != d){
		d->device->eglenv.make_current(d->device->display,
			d->buffer.esurf, d->buffer.esurf, d->device->context);
		egl_dri.last_display = d;
	}

/* activated- rendertarget covers scissor regions etc. so we want to reset */
	agp_blendstate(BLEND_NONE);
	agp_activate_rendertarget(NULL);

/*
 * for when we map fullscreen, have multi-buffering and garbage from previous
 * mapping left in the crop area
 */
	if (d->display.blackframes){
		verbose_print(
			"(%d) update, blackframes: %d", (int)d->id, (int)d->display.blackframes);
		agp_rendertarget_clear();
		d->display.blackframes--;
	}

/*
 * currently we only do binary damage / update tracking in that there are EGL
 * versions for saying 'this region is damaged, update that' to cut down on
 * fillrate/bw. This should likely be added to the agp_ layer as a simple dirty
 * list that the draw_vobj calls append to.
 */
	draw_display(d);
	d->device->eglenv.swap_buffers(d->device->display, d->buffer.esurf);
	verbose_print("(%d) swap", (int)d->id);

	uint32_t next_fb = 0;
	if (!IS_GBM_DISPLAY(d->device)){
		EGLAttrib attr[] = {
			EGL_DRM_FLIP_EVENT_DATA_NV, (EGLAttrib) d,
			EGL_NONE,
		};
		if (d->device->vsynch_method == VSYNCH_FLIP){
			if (!d->device->eglenv.stream_consumer_acquire_attrib(
				d->device->display, d->buffer.stream, attr)){
				d->device->vsynch_method = VSYNCH_CLOCK;
				debug_print("egl-dri(streams) - no acq-attr, revert to clock\n");
			}
		}
/* dumb buffer, will never change */
		next_fb = d->buffer.cur_fb;
	}
	else {
/* next/cur switching comes in the page-flip handler */
		d->buffer.next_bo = gbm_surface_lock_front_buffer(d->buffer.surface);
		if (!d->buffer.next_bo){
			verbose_print("(%d) update, failed to lock front buffer", (int)d->id);
			return;
		}
		next_fb = get_gbm_fd(d, d->buffer.next_bo);
	}

	bool new_crtc = false;
/* mode-switching is defered to the first frame that is ready as things
 * might've happened in the engine between _init and draw */
	if (d->display.reset_mode || !d->display.old_crtc){
/* save a copy of the old_crtc so we know what to restore on shutdown */
		if (!d->display.old_crtc)
			d->display.old_crtc = drmModeGetCrtc(d->device->fd, d->display.crtc);
		d->display.reset_mode = false;
		new_crtc = true;
	}

	if (new_crtc){
		debug_print("(%d) deferred modeset, switch now", (int) d->id);
		if (d->device->atomic){
			atomic_set_mode(d);
		}
		else {
			int rv = drmModeSetCrtc(d->device->fd, d->display.crtc,
				next_fb, 0, 0, &d->display.con_id, 1, d->display.mode);
			if (rv < 0){
				debug_print("(%d) error (%d) setting Crtc for %d:%d(con:%d)",
					(int)d->id, errno, d->device->fd, d->display.crtc, d->display.con_id);
			}
		}
	}

/* let DRM drive synch and wait for vsynch events on the file descriptor */
	if (d->device->vsynch_method == VSYNCH_FLIP){
		verbose_print("(%d) request flip (fd: %d, crtc: %"PRIxPTR", fb: %d)",
			(int)d->id, (uintptr_t) d->display.crtc, (int) next_fb);

		if (!drmModePageFlip(d->device->fd, d->display.crtc,
			next_fb, DRM_MODE_PAGE_FLIP_EVENT, d)){
			d->buffer.in_flip = 1;
			verbose_print("(%d) in flip", (int)d->id);
		}
		else {
			debug_print("(%d) error scheduling vsynch-flip (%"PRIxPTR":%"PRIxPTR")",
				(int)d->id, (uintptr_t) d->buffer.cur_fb, (uintptr_t)next_fb);
		}
	}
}

void platform_video_prepare_external()
{
	if (in_external)
		return;

	int rc = 10;
	debug_print("preparing external");
	do{
		for(size_t i = 0; i < MAX_DISPLAYS; i++)
			disable_display(&displays[i], false);
		if (egl_dri.destroy_pending)
			flush_display_events(16);
	} while(egl_dri.destroy_pending && rc-- > 0);

	if (nodes[0].master)
		drmDropMaster(nodes[0].fd);
	debug_print("external prepared");

	in_external = true;
}

void platform_video_restore_external()
{
/* uncertain if it is possible to poll on the device node to determine
 * when / if the drmMaster lock is released or not */
	debug_print("restoring external");
	if (!in_external)
		return;

	if (0 != drmSetMaster(nodes[0].fd) && nodes[0].force_master){
		debug_print("platform/egl-dri(), couldn't regain drmMaster access, "
			"retrying in 1 second\n");
	}

/* rebuild the mapped and known displays, extsusp is a marker that indicate
 * that the state of the engine is that the display is still alive, and should
 * be brought back to that state before we push 'removed' events */
	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_EXTSUSP){
/* refc? */
			if (setup_kms(&displays[i],
				displays[i].display.con->connector_id, 0, 0) != 0){
				debug_print(
					"(%d) restore external failed on kms setup", (int)displays[i].id);
				disable_display(&displays[i], true);
			}
			else if (setup_buffers(&displays[i]) != 0){
				debug_print(
					"(%d) restore external failed on buffer alloc", (int)displays[i].id);
				disable_display(&displays[i], true);
			}
			debug_print("(%d) restore ok, flag reset", (int)displays[i].id);
			displays[i].state = DISP_MAPPED;
			displays[i].display.reset_mode = true;
		}
	}

	in_external = false;
/* defer the video_rescan to arcan_video.c as the event queue may not be ready */
}
