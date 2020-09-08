/*
 * copyright 2014-2020, björn ståhl
 * license: 3-clause bsd, see copying file in arcan source repository.
 * reference: http://arcan-fe.com
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
 * mask out these types as they won't be useful,
 */
#define VIDEO_PLATFORM_IMPL
#include "../../engine/arcan_conductor.h"

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

/*
 * same debugging / tracing setup as in egl-dri.c
 */
#define debug_print(fmt, ...) \
            do { if (DEBUG) arcan_warning("%lld:%s:%d:%s(): " fmt "\n",\
						arcan_timemillis(), "egl-dri:", __LINE__, __func__,##__VA_ARGS__); } while (0)

#ifndef verbose_print
#define verbose_print
#endif

#include "egl.h"

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

static char* egl_envopts[] = {
	"[ for multiple devices, append _n to key (e.g. device_2=) ]", "",
	"display_device=/path/to/dev", "for multiple devices suffix with _n (n = 2,3..)",
	"draw_device=/path/to/dev", "set to display device unless provided",
	"device_buffer=method", "set buffer transfer method (gbm, streams)",
	"device_libs=lib1:lib2", "libs used for device",
	"device_connector=ind", "primary display connector index",
	"device_wait", "loop until an active connector is found",
	"device_nodpms", "set to disable power management controls",
	"device_direct", "enable direct rendertarget scanout (experimental)",
	"device_no_rtproxy", "set to disable rendertarget proxying",
	"display_context=1", "set outer shared headless context, per display contexts",
	NULL
};

enum buffer_method {
	BUF_GBM,
/* There is another option to running a 'display-less' EGL context and
 * that is to build the display around a pbuffer, but there seem to be
 * little utility to having that over this form of 'headless' */
	BUF_HEADLESS,
	BUF_STREAM
};

enum vsynch_method {
	VSYNCH_FLIP = 0,
	VSYNCH_CLOCK = 1
};

enum display_update_state {
	UPDATE_FLIP,
	UPDATE_DIRECT,
	UPDATE_SKIP
};

/*
 * Each open output device, can be shared between displays
 */
struct dev_node {
	int active; /*tristate, 0 = not used, 1 = active, 2 = displayless, 3 = inactive */
	int draw_fd;
	int disp_fd;
	char* pathref;

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

/* card_id is some unique sequential identifier for this card
 * crtc is an allocation bitmap for output port<->display allocation
 * atomic is set if the driver kms side supports/needs atomic modesetting */
	bool wait_connector;
	int card_id;
	bool atomic;

/*
 * method is the key driver for most paths in here, see the M_ enum values
 * above to indicate which of the elements here that are valid.
 */
	enum buffer_method buftype;
	union {
		EGLDeviceEXT egldev;
		struct gbm_device* gbm;
	} buffer;

/* Display is the display system connection, not to be confused with our normal
 * display, for that we have configs derived from the display which match the
 * visual of our underlying buffer method - these combined give the surface
 * within the context */
	EGLint attrtbl[24];
	EGLConfig config;
	EGLDisplay display;

/* Each display has its own context in order to have different framebuffer out
 * configuration, then an outer headless context that all the other resources
 * are allocated with */
	EGLContext context;
	int context_refc;
	const char* context_state;

/*
 * to deal with multiple GPUs and multiple vendor libraries, these contexts are
 * managed per display and explicitly referenced / switched when we need to.
 */
	char* egllib;
	char* agplib;
	struct egl_env eglenv;
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
	OUTPUT_888 = 0,
	OUTPUT_10b = 1,
	OUTPUT_565 = 2,
	OUTPUT_64b = 3
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
		EGLConfig config;
		EGLContext context;
		EGLSurface esurf;
		EGLStreamKHR stream;
		struct gbm_bo* cur_bo, (* next_bo);
		uint32_t cur_fb;
		int format;
		struct gbm_surface* surface;
		struct drm_mode_map_dumb dumb;
		size_t dumb_pitch;
	} buffer;

	struct {
		bool reset_mode, primary;
		drmModeConnector* con;
		uint32_t con_id;
		drmModeModeInfo mode;
		int mode_set;
		drmModeCrtcPtr old_crtc;
		int crtc;
		int crtc_index;
		int plane_id;
		enum dpms_state dpms;
		char* edid_blob;
		size_t blob_sz;
		size_t gamma_size;
		uint16_t* orig_gamma;
	} display;

/* internal v-store and system mappings, rules for drawing final output */
	arcan_vobj_id vid;
	bool force_compose;
	bool disallow_rtproxy;
	bool skip_blit;
	size_t dispw, disph, dispx, dispy;
	float vrefresh;

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
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_UNUSED){
			displays[i].device = node;
			displays[i].id = i;
			displays[i].display.primary = false;

			node->refc++;
			displays[i].state = DISP_KNOWN;

/* we currently force composition on all displays unless
 * explicitly turned on, as there seem to be some driver
 * issues with scanning out fbo color attachments */
			displays[i].force_compose =
				!get_config("video_device_direct", 0, NULL, tag);
			displays[i].disallow_rtproxy =
				!get_config("video_device_rtproxy", 0, NULL, tag);
			debug_print("(%zu) added, force composition? %d",
				i, (int) displays[i].force_compose);
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

static void set_device_context(struct dev_node* node)
{
	verbose_print("context_state=device(%"PRIxPTR")", (uintptr_t)node->context);
	node->eglenv.make_current(node->display,
		EGL_NO_SURFACE, EGL_NO_SURFACE, node->context);
	node->context_state = "device";
}

static void set_display_context(struct dispout* d)
{
	if (d->buffer.context == EGL_NO_CONTEXT){
		verbose_print("context_state=display(%"PRIxPTR")", (uintptr_t)d->device->context);
		d->device->eglenv.make_current(
			d->device->display, d->buffer.esurf, d->buffer.esurf, d->device->context);
	}
	else {
		verbose_print("context_state=display(uniq_%"PRIxPTR")", (uintptr_t)d->buffer.context);
		d->device->eglenv.make_current(
			d->device->display, d->buffer.esurf, d->buffer.esurf, d->buffer.context);
	}

	d->device->context_state = "display";
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
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	if (get_config("video_device_nodpms", 0, NULL, tag)){
		return;
	}

/*
 * FIXME: this needs to be deferred in the same way as disable / etc.
 */
	drmModePropertyPtr prop;
	debug_print("dpms_set(%d) to %d", d->device->disp_fd, level);
	for (size_t i = 0; i < d->display.con->count_props; i++){
		prop = drmModeGetProperty(d->device->disp_fd, d->display.con->props[i]);
		if (!prop)
			continue;

		if (strcmp(prop->name, "DPMS") == 0){
			drmModeConnectorSetProperty(d->device->disp_fd,
				d->display.con->connector_id, prop->prop_id, level);
			i = d->display.con->count_props;
		}

		drmModeFreeProperty(prop);
	}
}

/*
 * free, dealloc, possibly re-index displays
 */
static void disable_display(struct dispout*, bool dealloc);

/*
 * assumes that the video pipeline is in a state to safely
 * blit, will take the mapped objects and schedule buffer transfer
 */
static bool update_display(struct dispout*);

static bool set_dumb_fb(struct dispout* d);

static void close_devices(struct dev_node* node)
{
/* we might have a different device for drawing than for scanout */
	int disp_fd = node->disp_fd;
	if (-1 != disp_fd){

/* the privsep- parent still has the device open in master */
		if (node->pathref){
			platform_device_release(node->pathref, 0);
			free(node->pathref);
			node->pathref = NULL;
		}
		close(disp_fd);
		node->disp_fd = -1;
	}

/* another node might be used for drawing, assumed this does not
 * actually need master, if that turns out incorrect - duplicate the
 * pathref parts to drawref as well */
	if (node->draw_fd != -1 && node->draw_fd != disp_fd){
		close(node->draw_fd);
		node->draw_fd = -1;
	}

/* render node */
	if (node->client_meta.fd != -1){
		close(node->client_meta.fd);
		node->client_meta.fd = -1;
	}
}

/*
 * Assumes that the individual displays allocated on the card have already
 * been properly disabled(disable_display(ptr, true))
 */
static void release_card(size_t i)
{
	if (!nodes[i].active)
		return;

	debug_print("release card (%d)", i);
	nodes[i].eglenv.make_current(nodes[i].display,
		EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

	if (nodes[i].context != EGL_NO_CONTEXT){
		nodes[i].eglenv.destroy_context(nodes[i].display, nodes[i].context);
		nodes[i].context = EGL_NO_CONTEXT;
	}

	switch (nodes[i].buftype){
	case BUF_GBM:
		if (nodes[i].buffer.gbm){
			debug_print("destroying device/gbm buffers");
			gbm_device_destroy(nodes[i].buffer.gbm);
			nodes[i].buffer.gbm = NULL;
		}
	break;
	case BUF_HEADLESS:
/* Should be destroyed with the EGL context */
	break;
	case BUF_STREAM:
/* Should be destroyed with the EGL context */
	break;
	}

	close_devices(&nodes[i]);

	if (nodes[i].display != EGL_NO_DISPLAY){
		debug_print("terminating card-egl display");
		nodes[i].eglenv.terminate(nodes[i].display);
		nodes[i].display = EGL_NO_DISPLAY;
	}

	nodes[i].context_refc = 0;
	nodes[i].active = false;
}

static bool sane_direct_vobj(arcan_vobject* vobj)
{
	return vobj
	&& vobj->vstore
	&& !vobj->txcos
	&& (!vobj->program || vobj->program == agp_default_shader(BASIC_2D))
	&& vobj->vstore->txmapped == TXSTATE_TEX2D
	&& vobj->vstore->refcount == 1;
}

static bool display_rtgt_proxy(struct agp_rendertarget* tgt, uintptr_t tag)
{
	struct dispout* d = (struct dispout*) tag;

/* The dispouts come frome a static pool, so they can never go memory-
 * wise UAF, though there are higher level states to consider, such as
 * mapped or not. Point being: don't need to consider 'unregister'. */
	if (d->state != DISP_MAPPED){
		verbose_print("(%d) reject unmapped fastpath", (int)d->id);
		return false;
	}

	arcan_vobject* vobj = arcan_video_getobject(d->vid);
	if (!vobj || !sane_direct_vobj(vobj)){
		verbose_print("(%d) reject unsound vobject", (int)d->id);
		return false;
	}
/* We have a vobj that can be mapped directly, and we know that we
 * have to compose into the egl display, so do that. */

	verbose_print("fastpath, proxy rendertarget");
	d->skip_blit = true;
	set_display_context(d);

	return true;
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
				fcntl(egl_dri.ledpair[i], F_SETFD, flags | FD_CLOEXEC);
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
	debug_print("EGLStream, building buffers for display");
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

	EGLAttrib layer_attrs[3] = {};
	if (d->display.plane_id){
		debug_print("(%d) match layer to drm plane (%d)", d->id, d->display.plane_id);
		layer_attrs[0] = EGL_DRM_PLANE_EXT;
		layer_attrs[1] = d->display.plane_id;
		layer_attrs[2] = EGL_NONE;
	}
	else {
		debug_print("(%d) match layer to crtc (%d)", d->id, d->display.crtc);
		layer_attrs[0] = EGL_DRM_CRTC_EXT;
		layer_attrs[1] = d->display.crtc;
		layer_attrs[2] = EGL_NONE;
	};

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
	EGLint stream_attrs[] = {
/*
 * EGL_STREAM_FIFO_LENGTH_KHR, 1,
 * EGL_CONSUMER_AUTO_ACQUIRE_EXT, EGL_TRUE,
 */
		EGL_NONE
	};
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

/* 4. Get config and context,
 * two possible variants here - the default:
 * all displays uses the device context, the 'mixed HDR/SDR' setup is a
 * different display context that shares parts of the device context */
	EGLint nc;
	if (!d->device->eglenv.choose_config(
		d->device->display, d->device->attrtbl, &d->buffer.config, 1, &nc)){
		debug_print("couldn't chose a configuration (%s)", egl_errstr());
		return -1;
	}

	const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	size_t devind = 0;
	for (; devind < COUNT_OF(nodes); devind++)
		if (&nodes[devind] == d->device)
			break;

	bool shared_dev = !get_config("video_display_context", devind, NULL, tag);
/* shared device context, no display context */
	if (shared_dev){
		debug_print("per-device context for display");
		d->buffer.context = EGL_NO_CONTEXT;

/* First display on the device re-creates the context, difference to the gbm
 * version here is that we still need to create the stream-bound surface even
 * if we have a context on the device. The reason for re-creating the context
 * is that the config the display needs is un-known at the time of first
 * creation */
		if (!d->device->context_refc){
			debug_print("first display on device, rebuild context to match");
			d->device->eglenv.destroy_context(d->device->display, d->device->context);
			d->device->context = d->device->eglenv.create_context(
				d->device->display, d->buffer.config, EGL_NO_CONTEXT, context_attribs);
		}
		d->device->context_refc++;
	}
	else {
		verbose_print("creating NEW context for display with SHARED device context");
		d->buffer.context = d->device->eglenv.create_context(
			d->device->display, d->buffer.config, d->device->context, context_attribs);

		if (d->buffer.context == NULL) {
			debug_print("couldn't create display context");
			return false;
		}
	}

/*
 * 5. Create stream-bound surface
 */
	EGLint surface_attrs[] = {
		EGL_WIDTH, d->display.mode.hdisplay,
		EGL_HEIGHT, d->display.mode.vdisplay,
		EGL_NONE
	};
	d->buffer.esurf = d->device->eglenv.create_stream_producer_surface(
		d->device->display, d->buffer.config, d->buffer.stream, surface_attrs);

	if (!d->buffer.esurf){
		d->device->eglenv.destroy_stream(d->device->display, d->buffer.stream);
		d->buffer.stream = EGL_NO_STREAM_KHR;
		d->device->eglenv.destroy_context(d->device->display, d->buffer.context);
		d->buffer.context = EGL_NO_CONTEXT;
		debug_print("EGLstreams - couldn't create output surface");
		return -1;
	}

/*
 * 6. Activate context and buffers
 */
	egl_dri.last_display = d;
	set_display_context(d);

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

/*
 * 8. make the drm node non-blocking (might be needed for
 * multiscreen, somewhat uncertain)
 */
	int flags = fcntl(d->device->disp_fd, F_GETFL);
	if (-1 != flags)
		fcntl(d->device->disp_fd, F_SETFL, flags | O_NONBLOCK);

/*
 * 8. we don't have a path for streaming the FBO directly,
 * (seems to be reasonably trivial though), so disable the
 * optimization for now
 */
	d->force_compose = true;

	set_device_context(d->device);
	return 0;
}

static int setup_buffers_gbm(struct dispout* d)
{
	SET_SEGV_MSG("libgbm(), creating ecanout buffer"
		" failed catastrophically.\n")

	if (!d->device->eglenv.create_image){
		map_eglext_functions(&d->device->eglenv,
			lookup_call, d->device->eglenv.get_proc_address);
	}

	int gbm_formats[] = {
		-1, /* 565 */
		-1, /* 10-bit, X */
		-1, /* 10-bit, A */
		-1, /* 64-bpp, XBGR16F */
		-1, /* 64-bpp, ABGR16F */
		GBM_FORMAT_XRGB8888,
		GBM_FORMAT_ARGB8888
	};

	const char* fmt_lbls[] = {
		"RGB565 16-bit",
		"xRGB 30-bit",
		"aRGB 30-bit",
		"xRGB 64-bit",
		"aRGB 64-bit",
		"xRGB 24-bit",
		"aRGB 24-bit"
	};

/*
 * 10-bit output has very spotty driver support, so only allow it if it has
 * been explicitly set as interesting - big note is that the creation order
 * is somewhat fucked, the gbm output buffer defines the configuration of
 * the EGL node, note the other way around.
 */
	if (d->output_format == OUTPUT_565){
		gbm_formats[0] = GBM_FORMAT_RGB565;
	}

	if (d->output_format == OUTPUT_10b){
		gbm_formats[1] = GBM_FORMAT_XRGB2101010;
		gbm_formats[2] = GBM_FORMAT_ARGB2101010;
	}
	else if (d->output_format == OUTPUT_64b){
/* older distributions may still carry a header without this one so go the
 * preprocessor route for enabling */
#ifdef GBM_FORMAT_XBGR16161616F
		gbm_formats[3] = GBM_FORMAT_XBGR16161616F;
		gbm_formats[4] = GBM_FORMAT_ABGR16161616F;
#endif
	}

/* first get the set of configs from the display */
	EGLint nc;
	d->device->eglenv.get_configs(d->device->display, NULL, 0, &nc);
	if (nc < 1){
		debug_print("no configurations found for display, (%s)", egl_errstr());
		return false;
	}

	EGLConfig configs[nc];
	EGLint match = 0;

/* filter them based on the desired attributes from the device itself */
	d->device->eglenv.choose_config(
		d->device->display, d->device->attrtbl, configs, nc, &match);
	if (!match)
		return -1;

/* then sweep the formats in desired order and look for a matching visual */
	for (size_t i = 0; i < COUNT_OF(gbm_formats); i++){
		if (gbm_formats[i] == -1)
			continue;

		bool got_config = false;
		for (size_t j = 0; j < nc && !got_config; j++){
			EGLint id;
			if (!d->device->eglenv.get_config_attrib(
				d->device->display, configs[j], EGL_NATIVE_VISUAL_ID, &id))
					continue;

			if (id == gbm_formats[i]){
				d->buffer.config = configs[j];
				got_config = true;
			}
		}

		if (!got_config){
			debug_print("no matching gbm-format <-> visual "
				"<-> egl config for fmt: %d", (int)gbm_formats[i]);
			continue;
		}

/* first time device setup will call this function in two stages, so there
 * might be a buffer already set when we get called the second time and it is
 * safe to actually bind the buffer to an EGL surface as the config should be
 * the right one */
		if (!d->buffer.surface)
			d->buffer.surface = gbm_surface_create(d->device->buffer.gbm,
				d->display.mode.hdisplay, d->display.mode.vdisplay,
				gbm_formats[i], GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);

		if (!d->buffer.surface)
			continue;

		if (!d->buffer.esurf)
			d->buffer.esurf = d->device->eglenv.create_window_surface(
				d->device->display, d->buffer.config,(uintptr_t)d->buffer.surface,NULL);

/* we can accept buffer setup failure in this stage if we are being init:ed
 * and the EGL configuration doesn't exist */
		if (d->buffer.esurf != EGL_NO_SURFACE){
			d->buffer.format = gbm_formats[i];
			debug_print("(gbm) picked output buffer format %s", fmt_lbls[i]);
			break;
		}

		gbm_surface_destroy(d->buffer.surface);
		d->buffer.surface = NULL;
	}

	if (!d->buffer.surface){
		debug_print("couldn't find a gbm buffer format matching EGL display");
		return -1;
	}

/* finally, build the display- specific context with the new surface and
 * context - might not always use it due to direct-scanout vs. shaders etc.
 * but still needed */
	const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

/*
 * Unfortunately there seem to be many strange driver issues with using a
 * headless shared context and doing the buffer swaps and scanout on the
 * others, we can solve that in two ways, one is simply force even the WORLDID
 * to be a FBO - which was already the default in the lwa backend.  This would
 * require making the vint_world() RT double-buffered with a possible 'do I
 * have a non-default shader' extra blit stage and then the drm_add_fb2 call.
 * It's a scanout path that we likely need anyway.
 */
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	size_t devind = 0;
	for (; devind < COUNT_OF(nodes); devind++)
		if (&nodes[devind] == d->device)
			break;

/* DEFAULT: per device context: let first display drive choice of config
 * and hope that other displays have the same preferred format */
	bool shared_dev = !get_config("video_display_context", devind, NULL, tag);
	if (shared_dev && d->device->context_refc > 0){
		d->buffer.context = EGL_NO_CONTEXT;
		egl_dri.last_display = d;
		set_device_context(d->device);
		d->device->context_refc++;
		return 0;
	}

	EGLContext context = d->device->eglenv.create_context(
		d->device->display, d->buffer.config,
		shared_dev ? NULL : d->device->context, context_attribs
	);

	if (!context){
		debug_print("couldn't create egl context for display");
		gbm_surface_destroy(d->buffer.surface);
		return -1;
	}
	set_device_context(d->device);

/* per device context */
	if (shared_dev){
		d->buffer.context = EGL_NO_CONTEXT;
		d->device->context_refc++;
		d->device->eglenv.destroy_context(d->device->display, d->device->context);
		d->device->context = context;
		egl_dri.last_display = d;
		return 0;
	}

/* per display (not EGLDisplay) context */
	d->buffer.context = context;

	egl_dri.last_display = d;
	set_device_context(d->device);

	return 0;
}

static int setup_buffers(struct dispout* d)
{
	switch (d->device->buftype){
	case BUF_GBM:
		return setup_buffers_gbm(d);
	break;
	case BUF_HEADLESS:
/* won't be needed, we only ever accept FBO management */
		return 0;
	break;
	case BUF_STREAM:
		return setup_buffers_stream(d);
	break;
	}
	return 0;
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
		debug_print("no format/modifiers query support, sending simple card");
		*metadata_sz = 0;
		*metadata = NULL;
	}

	if (buffer_method)
		*buffer_method = nodes[cardn].buftype;

	return nodes[cardn].client_meta.fd;
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	struct dispout* d = get_display(disp);

	if (!d || d->state != DISP_MAPPED || mode >= d->display.con->count_modes)

	if (memcmp(&d->display.mode,
		&d->display.con->modes[mode], sizeof(drmModeModeInfo)) == 0)
		return true;

	d->display.reset_mode = true;
	d->display.mode = d->display.con->modes[mode];
	d->display.mode_set = mode;

	debug_print("(%d) schedule mode switch to %zu * %zu", (int) disp,
		d->display.mode.hdisplay, d->display.mode.vdisplay);

	build_orthographic_matrix(d->projection,
		0, d->display.mode.hdisplay, d->display.mode.vdisplay, 0, 0, 1);
	d->dispw = d->display.mode.hdisplay;
	d->disph = d->display.mode.vdisplay;

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
	debug_print("modeset, destroy surface");
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
	switch (d->device->buftype){
	case BUF_GBM:
		gbm_surface_destroy(d->buffer.surface);
		d->buffer.surface = NULL;
		if (setup_buffers_gbm(d) != 0)
			return false;
	break;
	case BUF_HEADLESS:
	break;
	case BUF_STREAM:
		d->device->eglenv.destroy_stream(d->device->display, d->buffer.stream);
		d->buffer.stream = EGL_NO_STREAM_KHR;
		if (setup_buffers_stream(d) != 0)
			return false;
	break;
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

	drmModeCrtc* inf = drmModeGetCrtc(d->device->disp_fd, d->display.crtc);

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
		rv = drmModeCrtcSetGamma(d->device->disp_fd, d->display.crtc, n_ramps, r, g, b);
	}

	drmModeFreeCrtc(inf);
	return rv == 0;
}

bool platform_video_get_display_gamma(
	platform_display_id did, size_t* n_ramps, uint16_t** outb)
{
	struct dispout* d = get_display(did);
	if (!d || !n_ramps)
		return false;

	drmModeCrtc* inf = drmModeGetCrtc(d->device->disp_fd, d->display.crtc);
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
	if (drmModeCrtcGetGamma(d->device->disp_fd, d->display.crtc, *n_ramps,
		&ramps[0], &ramps[*n_ramps], &ramps[2 * *n_ramps])){
		free(ramps);
		rv = false;
	}
	*outb = ramps;
	drmModeFreeCrtc(inf);
	return rv;
}

bool platform_video_display_edid(
	platform_display_id did, char** out, size_t* sz)
{
	struct dispout* d = get_display(did);
	if (!d)
		return false;

	*out = NULL;
	*sz = 0;

/* allocate a new scratch copy of the cached blob */
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
	drmModeRes* res = drmModeGetResources(node->disp_fd);
	if (!res){
		fprintf(dst, "DRM dump, couldn't acquire resource list\n");
		return;
	}

	fprintf(dst, "DRM Dump: \n\tConnectors: %d\n", res->count_connectors);
	for (size_t i = 0; i < res->count_connectors; i++){
		drmModeConnector* conn = drmModeGetConnector(
			node->disp_fd, res->connectors[i]);
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

	switch (node->buftype){
	case BUF_GBM:
		attrtbl[attrofs++] = EGL_SURFACE_TYPE;
		attrtbl[attrofs++] = EGL_WINDOW_BIT;
	break;
	case BUF_HEADLESS:
	break;
	case BUF_STREAM:
		attrtbl[attrofs++] = EGL_SURFACE_TYPE;
		attrtbl[attrofs++] = EGL_STREAM_BIT_KHR;
	break;
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
 * now copy the attributes that match our choice in API etc. so that the
 * correct buffers can be selected
 */
	memcpy(node->attrtbl, attrtbl, sizeof(attrtbl));

	EGLint match = 0;
	node->eglenv.choose_config(node->display, node->attrtbl, &node->config, 1, &match);
	node->context = node->eglenv.create_context(
		node->display, node->config, EGL_NO_CONTEXT, context_attribs);

	if (!node->context){
		debug_print(
			"couldn't build an EGL context on the display, (%s)", egl_errstr());
		return false;
	}

	set_device_context(node);
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
static int setup_node_egl(int dst_ind, struct dev_node* node, int fd)
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
			node->buffer.egldev = devs[i];
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
				node->buffer.egldev = devs[i];
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
		node->disp_fd = node->draw_fd = fd;
		node->buftype = BUF_STREAM;
		node->atomic =
			drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) == 0 &&
			drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1) == 0;
		node->display = node->eglenv.get_platform_display(
			EGL_PLATFORM_DEVICE_EXT, node->buffer.egldev, attribs);
		node->eglenv.swap_interval(node->display, 0);
		return 0;
	}

	return -1;
}

static void cleanup_node_gbm(struct dev_node* node)
{
	close_devices(node);

	if (node->buffer.gbm)
		gbm_device_destroy(node->buffer.gbm);
	node->buffer.gbm = NULL;
}

static int setup_node_gbm(int devind,
	struct dev_node* node, int draw_fd, int disp_fd)
{
	SET_SEGV_MSG("libdrm(), open device failed (check permissions) "
		" or use ARCAN_VIDEO_DEVICE environment.\n");

	node->client_meta.fd = -1;
	node->client_meta.metadata = NULL;
	node->client_meta.metadata_sz = 0;
	node->disp_fd = disp_fd;
	node->draw_fd = draw_fd;

	SET_SEGV_MSG("libgbm(), create device failed catastrophically.\n");
	node->buffer.gbm = gbm_create_device(node->draw_fd);

	if (!node->buffer.gbm){
		debug_print("gbm, couldn't create gbm device on node");
		cleanup_node_gbm(node);
		return -1;
	}

	node->buftype = BUF_GBM;

	if (node->eglenv.get_platform_display){
		debug_print("gbm, using eglGetPlatformDisplayEXT");
		node->display = node->eglenv.get_platform_display(
			EGL_PLATFORM_GBM_KHR, (void*)(node->buffer.gbm), NULL);
	}
	else{
		debug_print("gbm, building display using native handle only");
		node->display = node->eglenv.get_display((void*)(node->buffer.gbm));
	}

/* This is kept optional as not all drivers have it, and not all drivers
 * work well with it. The current state is opt-in at a certain cost, but
 * don't want the bug reports. */
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	char* devstr, (* cfgstr), (* altstr);
	node->atomic =
		get_config("video_device_atomic", devind, NULL, tag) && (
		drmSetClientCap(node->disp_fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) == 0 &&
		drmSetClientCap(node->disp_fd, DRM_CLIENT_CAP_ATOMIC, 1) == 0
	);
	debug_print("gbm, node in atomic mode: %s", node->atomic ? "yes" : "no");

/* Set the render node environment variable here, this is primarily for legacy
 * clients that gets launched through arcan - the others should get the
 * descriptor from DEVICEHINT. It also won't work for multiple cards as the
 * last one would just overwrite */
	char pbuf[24] = "/dev/dri/renderD128";

	char* rdev = drmGetRenderDeviceNameFromFd(node->draw_fd);
	if (rdev){
		debug_print("derived render-node: %s", rdev);
		setenv("ARCAN_RENDER_NODE", rdev, 1);
		free(rdev);
	}
/* assume default */
	else {
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

/* We have a direct object that we want to push out rather than
 * blitting to any specific gbm buffer. Do this by:
 * 1. EGLImage from our texture,
 * 2. Dmabuf from 1.
 * 3. GBM-BO from DMAbuf.
 *
 * Then return that BO and attach it as a drm framebuffer
 */
static struct gbm_bo* vobj_to_bo(
	struct dispout* d, arcan_vobject* vobj, uintptr_t glid)
{
	struct gbm_bo* res = NULL;

/*
 * For direct-mapping an external source, we already have img
 * as the EGLimage to export, and we can go from there. It makes
 * more sense to just retain the dmabuf data when we receive
 * it though, but measure and see first if it is actually worth
 * the refactoring.
 *	vobj->vstore->vinf.text.tag = (uintptr_t) img;
 *  vobj->vstore->vinf.text.handle = handle;
 */

/* 1. EGLImage from texture - we can omit this step if we already
 *    have the appropriate dma-buffer-bound EGLimage in agp_vstore.
 */
	EGLImage newimg = d->device->eglenv.create_image(
		d->device->display,
		d->buffer.context ? d->buffer.context : d->device->context,
		EGL_GL_TEXTURE_2D_KHR,
		(EGLClientBuffer) glid, NULL
	);

	if (!newimg){
		debug_print("(%d) failed to convert vobject to eglimage", (int)d->id);
		return NULL;
	}

/* EGLImage to DMA-buf or direct to gbm_bo? */
	if (0){
		res = gbm_bo_import(
			d->device->buffer.gbm,
			GBM_BO_IMPORT_EGL_IMAGE, newimg,
			GBM_BO_USE_SCANOUT
		);

		if (!res){
			debug_print("(%d) dma-buf to gbm-scanout rejected", (int)d->id);
			goto bad;
		}
	}
	else {
		int fourcc, nplanes;
		if (!d->device->eglenv.query_image_format(
			d->device->display, newimg, &fourcc, &nplanes, NULL)){
			debug_print("(%d) couldn't query image format", (int) d->id);
			goto bad;
		}

		EGLint stride;
		int handle;
		if (!d->device->eglenv.export_dmabuf(
			d->device->display, newimg, &handle, &stride, NULL) || stride < 0){
			debug_print("(%d) could not export dma-buffer", (int) d->id);
			goto bad;
		}

		res = gbm_bo_import(d->device->buffer.gbm,
			GBM_BO_IMPORT_FD, &(struct gbm_import_fd_data){
			.width = vobj->vstore->w,
			.height = vobj->vstore->h,
			.format = fourcc,
			.stride = stride,
			.fd = handle
			}, GBM_BO_USE_SCANOUT
		);

		if (!res){
			uint8_t fcc[4] = {
				fourcc & 0xff,
				(fourcc >> 8) & 0xff,
				(fourcc >> 16) & 0xff,
				(fourcc >> 24) & 0xff
			};

			debug_print("(%d) couldn't convert dma-buffer, fourcc:"
				"%"PRIu32"(%c%c%c%c) w: %zu, height: %zu, stride: %zu",
				(int) d->id,
				(uint32_t)fourcc,
				fcc[0], fcc[1], fcc[2], fcc[3],
				(size_t) vobj->vstore->w,
				(size_t) vobj->vstore->h, (size_t) stride
			);
			close(handle);
		}
	}

/* safe to destroy the backing EGLimage as the BO resource lifetime
 * is independent, though we don't want to destroy it for the vobj
 * as it might be mapped / used elsewhere */
bad:
	d->device->eglenv.destroy_image(d->device->display, newimg);
	return res;
}

/*
 * called once per updated display per frame, as part of the normal
 * draw / flip / ... cycle, bo is the returned gbm_surface_lock_front
 */
static int get_gbm_fb(struct dispout* d,
	enum display_update_state dstate, struct gbm_bo* bo, uint32_t* dst)
{
	uint32_t new_fb;

/* convert the currently mapped object */
	if (dstate == UPDATE_DIRECT){
		arcan_vobject* vobj = arcan_video_getobject(d->vid);
		struct rendertarget* newtgt = arcan_vint_findrt(vobj);

/* though the rendertarget might not be ready for the first frame */
		if (newtgt){
			bool swap;
			unsigned col = agp_rendertarget_swap(newtgt->art, &swap);
			if (!swap)
				return 0;

			TRACE_MARK_ONESHOT("video", "rendertarget-swap", TRACE_SYS_DEFAULT, col, 0, "");
			bo = vobj_to_bo(d, vobj, col);
		}
		else
			bo = vobj_to_bo(d, vobj, vobj->vstore->vinf.text.glid);
	}

	if (!bo){
		TRACE_MARK_ONESHOT("video", "vobj-bo-fail", TRACE_SYS_DEFAULT, d->vid, 0, "");
		return -1;
	}

/* Three possible paths for getting the framebuffer id that can then be
 * scanned out: drmModeAddFB2WithModifiers, drmModeAddFB2 and drmModeAddFB
 * success rate depend on driver and overall config */
	ssize_t n_planes = gbm_bo_get_plane_count(bo);
	if (n_planes < 0)
		n_planes = 1;

	uint32_t handles[n_planes];
	uint32_t strides[n_planes];
	uint32_t offsets[n_planes];
	uint64_t modifiers[n_planes];

	TRACE_MARK_ONESHOT("video", "bo-gbm-planes", TRACE_SYS_DEFAULT, n_planes, 0, "");
	if (gbm_bo_get_handle_for_plane(bo, 0).s32 == -1){
		handles[0] = gbm_bo_get_handle(bo).u32;
		strides[0] = gbm_bo_get_stride(bo);
		modifiers[0] = DRM_FORMAT_MOD_INVALID;
		TRACE_MARK_ONESHOT("video", "bo-handle", TRACE_SYS_ERROR, 0, 0, "");
	}
	else {
		for (ssize_t i = 0; i < n_planes; i++){
			strides[i] = gbm_bo_get_stride_for_plane(bo, i);
			handles[i] = gbm_bo_get_handle_for_plane(bo, i).u32;
			offsets[i] = gbm_bo_get_offset(bo, i);
			modifiers[i] = gbm_bo_get_modifier(bo);
		}
	}

	size_t bo_width = gbm_bo_get_width(bo);
	size_t bo_height = gbm_bo_get_height(bo);

/* nop:ed for now, but the path for dealing with modifiers should be
 * considered as soon as we have the other setup for direct-scanout
 * of a client and metadata packing across the interface */
	if (0){
		if (drmModeAddFB2WithModifiers(d->device->disp_fd,
			bo_width, bo_height, gbm_bo_get_format(bo),
			handles, strides, offsets, modifiers, dst, 0)){
			TRACE_MARK_ONESHOT("video", "drm-gbm-addfb2-mods", TRACE_SYS_ERROR, 0, 0, "");
			return -1;
		}
		TRACE_MARK_ONESHOT("video", "drm-gbm-addfb2-mods", TRACE_SYS_DEFAULT, 0, 0, "");
	}
	else if (drmModeAddFB2(d->device->disp_fd, bo_width, bo_height,
			gbm_bo_get_format(bo), handles, strides, offsets, dst, 0)){

		if (drmModeAddFB(d->device->disp_fd,
			bo_width, bo_height, 24, 32, strides[0], handles[0], dst)){
			TRACE_MARK_ONESHOT("video", "drm-gbm-addfb", TRACE_SYS_ERROR, 0, 0, "");
			debug_print(
				"(%d) failed to add framebuffer (%s)", (int)d->id, strerror(errno));
			return -1;
		}

		TRACE_MARK_ONESHOT("video", "drm-gbm-addfb2", TRACE_SYS_DEFAULT, 0, 0, "");
	}
	else {
		TRACE_MARK_ONESHOT("video", "drm-gbm-addfb", TRACE_SYS_DEFAULT, 0, 0, "");
	}

	return 1;
}

static bool set_dumb_fb(struct dispout* d)
{
	struct drm_mode_create_dumb create = {
		.width = d->display.mode.hdisplay,
		.height = d->display.mode.vdisplay,
		.bpp = 32
	};
	int fd = d->device->disp_fd;
	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0){
		TRACE_MARK_ONESHOT("video", "create-dumb", TRACE_SYS_ERROR, 0, 0, "");
		debug_print("(%d) create dumb-fb (%d*%d@%d bpp) failed",
			(int) d->id, create.width, create.height, create.bpp);
		return false;
	}
	if (drmModeAddFB(fd,
		d->display.mode.hdisplay, d->display.mode.vdisplay, 24, 32,
		create.pitch, create.handle, &d->buffer.cur_fb)){
		TRACE_MARK_ONESHOT("video", "create-dumb-addfb", TRACE_SYS_ERROR, 0, 0, "");
		debug_print("(%d) couldn't add dumb-fb", (int) d->id);
		return false;
	}

	d->buffer.dumb.handle = create.handle;
	d->buffer.dumb_pitch = create.pitch;
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &d->buffer.dumb) < 0){
		drmModeRmFB(fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
		TRACE_MARK_ONESHOT("video", "create-dumb-fbmap", TRACE_SYS_ERROR, 0, 0, "");
		debug_print("(%d) couldn't map dumb-fb", (int) d->id);
		return false;
	}

	void* mem = mmap(0,
		create.size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, d->buffer.dumb.offset);
	if (MAP_FAILED == mem){
		debug_print("(%d) couldn't mmap dumb-fb", (int) d->id);
		TRACE_MARK_ONESHOT("video", "create-dumb-mmap", TRACE_SYS_ERROR, 0, 0, "");
		drmModeRmFB(fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
		return false;
	}

	TRACE_MARK_ONESHOT("video", "create-dumb", TRACE_SYS_DEFAULT, 0, 0, "");
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
	int fd = d->device->disp_fd;

	if (0 != drmModeCreatePropertyBlob(fd,
		&d->display.mode, sizeof(drmModeModeInfo), &mode)){
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
		debug_print("(%d) atomic-modeset, failed to get crtc prop", (int) d->id);
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

	unsigned width = d->display.mode.hdisplay << 16;
	unsigned height = d->display.mode.vdisplay << 16;

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
	drmModePlaneResPtr plane_res = drmModeGetPlaneResources(d->device->disp_fd);
	d->display.plane_id = 0;
	if (!plane_res){
		debug_print("(%d) atomic-modeset, couldn't find plane on device",(int)d->id);
		return false;
	}
	for (size_t i = 0; i < plane_res->count_planes; i++){
		drmModePlanePtr plane =
			drmModeGetPlane(d->device->disp_fd, plane_res->planes[i]);
		if (!plane){
			debug_print("(%d) atomic-modeset, couldn't get plane (%zu)",(int)d->id,i);
			return false;
		}
		uint32_t crtcs = plane->possible_crtcs;
		drmModeFreePlane(plane);
		if (0 == (crtcs & (1 << d->display.crtc_index)))
			continue;

		uint64_t val;
		if (!lookup_drm_propval(d->device->disp_fd,
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

/*
 * sweep all displays, and see if the referenced CRTC id is in use.
 */
static struct dispout* crtc_used(struct dev_node* dev, int crtc)
{
	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_UNUSED)
			continue;

		if (displays[i].device != dev)
			continue;

		if (displays[i].display.crtc == crtc)
			return &displays[i];
	}

	return NULL;
}

static int setup_kms(struct dispout* d, int conn_id, size_t w, size_t h)
{
	SET_SEGV_MSG("egl-dri(), enumerating connectors on device failed.\n");
	drmModeRes* res;

retry:
	res = drmModeGetResources(d->device->disp_fd);
	if (!res){
		debug_print("(%d) setup_kms, couldn't get resources (fd:%d)",
			(int)d->id, (int)d->device->disp_fd);
		return -1;
	}

/* for the default case we don't have a connector, but for
 * newly detected displays we store / reserve */
	if (!d->display.con)
	for (int i = 0; i < res->count_connectors; i++){
		d->display.con = drmModeGetConnector(d->device->disp_fd, res->connectors[i]);

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
 * If dimensions are specified, find the closest match and on collision,
 * the one with the highest refresh rate.
 */
	bool try_inherited_mode = true;
	int vrefresh = 0;

/*
 * will just nop- out unless verbose defined
 */
	for (ssize_t i = 0; i < d->display.con->count_modes; i++){
		drmModeModeInfo* cm = &d->display.con->modes[i];
		verbose_print("(%d) mode (%zu): %d*%d@%d Hz",
			d->id, i, cm->hdisplay, cm->vdisplay, cm->vrefresh);
	}

/*
 * w and h comes from the old- style command-line to video_init calls
 * sets to 0 if the user didn't explicitly request anything else
 */
	if (w != 0 && h != 0){
		bool found = false;

		for (ssize_t i = 0; i < d->display.con->count_modes; i++){
			drmModeModeInfo* cm = &d->display.con->modes[i];
/*
 * prefer exact match at highest vrefresh, otherwise we'll fall back to
 * whatever we inherit from the console or 'first best'
 */
			if (cm->hdisplay == w && cm->vdisplay == h && cm->vrefresh > vrefresh){
				d->display.mode = *cm;
				d->display.mode_set = i;
				d->dispw = cm->hdisplay;
				d->disph = cm->vdisplay;
				vrefresh = d->vrefresh = cm->vrefresh;
				try_inherited_mode = false;
				found = true;
				debug_print("(%d) hand-picked (-w, -h): "
					"%d*%d@%dHz", d->id, d->dispw, d->disph, vrefresh);
			}
		}

		if (!found){
/* but if not, drop the presets and return to auto-detect */
			w = 0;
			h = 0;
		}
	}

/*
 * If no dimensions are specified, grab the first one.  (according to drm
 * documentation, that should be the most 'fitting') but also allow the
 * 'try_inherited_mode' using what is already on the connector.
 *
 * Note for ye who ventures in here, seems like some drivers still enjoy
 * returning ones that are actually 0*0, skip those.
 */
	if (w == 0 && d->display.con->count_modes >= 1){
		bool found = false;

		for (ssize_t i = 0; i < d->display.con->count_modes; i++){
			drmModeModeInfo* cm = &d->display.con->modes[i];
			if (!cm->hdisplay || !cm->vdisplay)
				continue;

			d->display.mode = *cm;
			d->display.mode_set = 0;
			d->dispw = cm->hdisplay;
			d->disph = cm->vdisplay;
			d->vrefresh = cm->vrefresh;
			vrefresh = d->vrefresh;
			found = true;
			debug_print("(%d) default connector mode: %d*%d@%dHz",
				d->id, d->dispw, d->disph, vrefresh);
			break;
		}

/* everything is broken, just set a bad mode and let the rest of the error-
 * paths take care of the less-than-graceful exit */
		if (!found){
			d->display.mode = d->display.con->modes[0];
			d->display.mode_set = 0;
			d->dispw = d->display.mode.hdisplay;
			d->disph = d->display.mode.vdisplay;
			d->vrefresh = 0;
			debug_print("(%d) setup-kms, couldn't find any useful mode");
		}

		debug_print("(%d) setup-kms, default-picked %zu*%zu", (int)d->id,
			(size_t)d->display.mode.hdisplay, (size_t)d->display.mode.vdisplay);
	}

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
		prop = drmModeGetProperty(d->device->disp_fd, d->display.con->props[i]);
		if (!prop)
			continue;

		if ((prop->flags & DRM_MODE_PROP_BLOB) &&
			0 == strcmp(prop->name, "EDID")){
			drmModePropertyBlobPtr blob =
				drmModeGetPropertyBlob(d->device->disp_fd, d->display.con->prop_values[i]);

			if (blob && blob->length > 0){
				d->display.edid_blob = malloc(blob->length);
				if (d->display.edid_blob){
					d->display.blob_sz = blob->length;
					memcpy(d->display.edid_blob, blob->data, blob->length);
					done = true;
				}
			}
			else {
				debug_print("(%d) edid blob could not be retrieved\n", (int) d->id);
			}

			drmModeFreePropertyBlob(blob);
		}
		drmModeFreeProperty(prop);
	}

/*
 * foreach(encoder)
 *  check_default_crtc -> not used ? allocate -> go
 *   foreach possible_crtc -> first not used ? allocate -> go
 *
 *  note that practically, the crtc search must also find a crtcs that supports
 *  a certain 'plane configuration' that match the render configuration we want
 *  to perform, which triggers on each setup where we have a change in vid to
 *  display mappings (similar to defered modeset).
 */
	SET_SEGV_MSG("libdrm(), setting matching encoder failed.\n");
	bool crtc_found = false;

/* mimic x11 modesetting driver use, sweep all encoders and pick the crtcs
 * that all of them support, and bias against inherited crtc on the first
 * encoder that aren't already mapped */
	uint64_t mask = 0;
	mask = ~mask;
	uint64_t join = 0;

	for (int i = 0; i < res->count_encoders; i++){
		drmModeEncoder* enc = drmModeGetEncoder(d->device->disp_fd, res->encoders[i]);
		if (!enc)
			continue;

		for (int j = 0; j < res->count_crtcs; j++){
			if (!(enc->possible_crtcs & (1 << j)))
				mask &= enc->possible_crtcs;
			join |= enc->possible_crtcs;
		}

		drmModeFreeEncoder(enc);
	}

	if (!mask){
		debug_print("libdrm(), no shared mask of crtcs, take full set");
		mask = join;
	}

/* now sweep the list of possible crtcs and pick the first one we don't have
 * already allocated to a display, uncertain if the crtc size was 32 or 64
 * bit so might as well go for the higher */
	for (uint64_t i = 0; i < 64 && i < res->count_crtcs; i++){
		if (mask & ((uint64_t)1 << i)){
			uint32_t crtc_val = res->crtcs[i];
			struct dispout* crtc_disp = crtc_used(d->device, crtc_val);
			if (crtc_disp)
				continue;

			d->display.crtc = crtc_val;
			d->display.crtc_index = i;
			crtc_found = true;
			break;
		}
	}

	debug_print("(%d) picked crtc (%d) from encoder", (int)d->id, d->display.crtc);
	drmModeCrtc* crtc = drmModeGetCrtc(d->device->disp_fd, d->display.crtc);
	if (!crtc){
		debug_print("couldn't retrieve chose crtc, giving up");
		goto drop_disp;
	}

/* sanity-check inherited mode (weird drivers + "non-graphical" defaults? */
	if (crtc->mode_valid && try_inherited_mode && crtc->mode.hdisplay){
		d->display.mode = crtc->mode;
		d->display.mode_set = 0;

/* find the matching index */
		for (size_t i = 0; i < d->display.con->count_modes; i++){
			if (memcmp(&d->display.con->modes[i],
				&d->display.mode, sizeof(drmModeModeInfo)) == 0){
				d->display.mode_set = i;
				break;
			}
		}

		d->dispw = d->display.mode.hdisplay;
		d->disph = d->display.mode.vdisplay;
		debug_print("(%d) trying tty- inherited mode ", (int)d->id);
	}

	if (!crtc_found){
		debug_print("(%d) setup-kms, no working encoder/crtc", (int)d->id);
		goto drop_disp;
		return -1;
	}

/* now we have a mode that is either hand-picked, inherited from the TTY or the
 * DRM default - alas in many cases this is not the one with the highest refresh
 * at that resolution, so sweep yet again and try and find one for that */
	for (size_t i = 0; i < d->display.con->count_modes; i++){
		drmModeModeInfo* cm = &d->display.con->modes[i];
		if (cm->hdisplay == d->dispw &&
			cm->vdisplay == d->disph && cm->vrefresh > vrefresh){
			d->display.mode = *cm;
			d->display.mode_set = i;
			vrefresh = cm->vrefresh;
			debug_print(
				"(%d) higher refresh (%d) found at set resolution", vrefresh, (int)d->id);
		}
	}

/* find a matching output-plane for atomic/streams */
	if (d->device->atomic){
		bool ok = true;
		if (!find_plane(d)){
			debug_print("(%d) setup_kms, atomic-find_plane fail", (int)d->id);
			ok = false;
		}
		else if (!set_dumb_fb(d)){
			debug_print("(%d) setup_kms, atomic dumb-fb fail", (int)d->id);
			ok = false;
		}
		else if (!atomic_set_mode(d)){
			debug_print("(%d) setup_kms, atomic modeset fail", (int)d->id);
			drmModeRmFB(d->device->disp_fd, d->buffer.cur_fb);
			d->buffer.cur_fb = 0;
			ok = false;
		}
/* just disable atomic */
		if (!ok){
			debug_print("(%d) setup_kms, "
				"atomic modeset failed, fallback to legacy", d->id);
			d->device->atomic = false;
			drmModeFreeConnector(d->display.con);
			d->display.con = NULL;
			drmModeFreeResources(res);
			drmSetClientCap(d->device->disp_fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 0);
			drmSetClientCap(d->device->disp_fd, DRM_CLIENT_CAP_ATOMIC, 0);
			return setup_kms(d, conn_id, w, h);
		}
		else if (!ok)
			goto drop_disp;
	}

	build_orthographic_matrix(d->projection,
		0, d->display.mode.hdisplay, d->display.mode.vdisplay, 0, 0, 1);

	dpms_set(d, DRM_MODE_DPMS_ON);
	d->display.dpms = ADPMS_ON;

	drmModeFreeResources(res);
	return 0;

drop_disp:
	drmModeFreeConnector(d->display.con);
	d->display.con = NULL;
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
	switch (nodes[0].buftype){
	case BUF_GBM:
		return map_handle_gbm(dst, handle);
	break;
	case BUF_STREAM:
		return map_handle_stream(dst, handle);
	break;
	case BUF_HEADLESS:
		return false;
	break;
	}
	return false;
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
	drmModeRes* res = drmModeGetResources(d->device->disp_fd);

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

		if (d->device->disp_fd == fd &&
			 (d->display.con ? d->display.con->connector_id : d->display.con_id) == con->connector_id)
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
	debug_print("check resources on %i", node->disp_fd);

	drmModeRes* res = drmModeGetResources(node->disp_fd);
	if (!res){
		debug_print("couldn't get resources for rescan on %i", node->disp_fd);
		return;
	}

	for (size_t i = 0; i < res->count_connectors; i++){
		drmModeConnector* con = drmModeGetConnector(node->disp_fd, res->connectors[i]);
		struct dispout* d = match_connector(node->disp_fd, con);

/* no display on connector */
		if (con->connection != DRM_MODE_CONNECTED){
/* if there was one known, remove it and notify */
			debug_print("(%zu) lost, disabled", (int)i);
			if (d){
				debug_print("(%d) display lost, disabling", (int)d->id);
				disable_display(d, true);
				arcan_event ev = {
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_REMOVED,
					.vid.displayid = d->id,
					.vid.ledctrl = egl_dri.ledid,
					.vid.ledid = d->id
				};
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
				arcan_conductor_release_display(d->device->card_id, d->id);
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
		arcan_conductor_register_display(
			d->device->card_id, d->id, SYNCH_STATIC, d->vrefresh, d->vid);

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
		if (nodes[j].disp_fd != -1)
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

	set_display_context(d);
	debug_print("(%d) destroying EGL surface", (int)d->id);
	d->device->eglenv.destroy_surface(d->device->display, d->buffer.esurf);
	d->buffer.esurf = NULL;

/* destroying the context has triggered driver bugs and hard to attribute UAFs
 * in the past, monitor this closely */
	if (d->buffer.cur_fb){
		debug_print("(%d) removing framebuffer", (int)d->id);
		drmModeRmFB(d->device->disp_fd, d->buffer.cur_fb);
		d->buffer.cur_fb = 0;
	}

	if (d->buffer.context != EGL_NO_CONTEXT){
		debug_print("(%d) EGL - set device"
			"context, destroy display context", (int)d->id);
		set_device_context(d->device);
		d->device->eglenv.destroy_context(d->device->display, d->buffer.context);
		d->buffer.context = EGL_NO_CONTEXT;
	}

	if (d->device->buftype == BUF_GBM){
		if (d->buffer.surface){
			debug_print("destroy gbm surface");

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
		debug_print("(%d) restoring device color LUTs");
		drmModeCrtcSetGamma(d->device->disp_fd, d->display.crtc,
			d->display.gamma_size, d->display.orig_gamma,
			&d->display.orig_gamma[1*d->display.gamma_size],
			&d->display.orig_gamma[2*d->display.gamma_size]
		);
	}

/* in extended suspend, we have no idea which displays we are returning to so
 * the only real option is to fully deallocate even in EXTSUSP */
	debug_print("(%d) release crtc id (%d)", (int)d->id,(int)d->display.crtc);
	if (d->display.old_crtc){
		debug_print("(%d) old mode found, trying to reset", (int)d->id);
		if (d->device->atomic){
			d->display.mode = d->display.old_crtc->mode;
			if (atomic_set_mode(d)){
				debug_print("(%d) atomic-modeset failed on (%d)",
					(int)d->id, (int)d->display.con_id);
			}
		}
		else if (0 > drmModeSetCrtc(
			d->device->disp_fd,
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

	debug_print("(%d) freeing display connector", (int)d->id);
	drmModeFreeConnector(d->display.con);
	d->display.con = NULL;
	d->display.con_id = -1;
	d->display.mode_set = -1;

	drmModeFreeCrtc(d->display.old_crtc);
	d->display.old_crtc = NULL;

/*	d->device = NULL; */
	d->state = DISP_UNUSED;

	if (d->backlight){
		debug_print("(%d) resetting display backlight", (int)d->id);
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
	if (egl_dri.last_display && egl_dri.last_display->display.mode_set != -1){
		res.width = egl_dri.last_display->display.mode.hdisplay;
		res.height = egl_dri.last_display->display.mode.vdisplay;
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

static bool try_node(int draw_fd, int disp_fd, const char* pathref,
	int dst_ind, enum buffer_method method, int connid, int w, int h,
	bool ignore_display)
{
/* set default lookup function if none has been provided */
	if (!nodes[dst_ind].eglenv.get_proc_address){
		nodes[dst_ind].eglenv.get_proc_address =
			(PFNEGLGETPROCADDRESSPROC)eglGetProcAddress;
	}
	struct dev_node* node = &nodes[dst_ind];
	node->active = true;
	map_egl_functions(&node->eglenv, lookup, NULL);
	map_eglext_functions(
		&node->eglenv, lookup_call, node->eglenv.get_proc_address);

	switch (method){
	case BUF_GBM:
		if (0 != setup_node_gbm(dst_ind, node, draw_fd, disp_fd)){
			node->eglenv.get_proc_address = NULL;
			debug_print("couldn't open (%d:%s) in GBM mode",
				draw_fd, pathref ? pathref : "(no path)");
				release_card(dst_ind);
			return false;
		}
	break;
	case BUF_STREAM:
		if (0 != setup_node_egl(dst_ind, node, disp_fd)){
			debug_print("couldn't open (%d:%s) in EGLStreams mode",
				draw_fd, pathref ? pathref : "(no path)");
			release_card(dst_ind);
			return false;
		}
	break;
	case BUF_HEADLESS:
	break;
	}

	if (!setup_node(node)){
		debug_print("setup/configure [%d](%d:%s)",
			dst_ind, draw_fd, pathref ? pathref : "(no path)");
		release_card(dst_ind);
		return false;
	}

/* used when we already have one */
	if (ignore_display)
		return true;

	struct dispout* d = allocate_display(node);
	d->display.primary = dst_ind == 0;
	egl_dri.last_display = d;

	if (setup_kms(d, connid, w, h) != 0){
		disable_display(d, true);
		debug_print("card found, but no working/connected display");
		release_card(dst_ind);
		return false;
	}

	if (setup_buffers(d) == -1){
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
 * config/profile matching derived approach, for use when something more
 * specific and sophisticated is desired
 */
static bool try_card(size_t devind, int w, int h, size_t* dstind)
{
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	char* dispdevstr, (* cfgstr), (* altstr);
	int connind = -1;

	bool gbm = true;

/* basic device, device_1, device_2 etc. search path */
	if (!get_config("video_display_device", devind, &dispdevstr, tag))
		return false;

	char* drawdevstr = NULL;
	get_config("video_draw_device", devind, &drawdevstr, tag);

/* reference to another card_id, only one is active at any one moment
 * and card_1 should reference card_2 and vice versa. */
	if (get_config("video_device_alternate", devind, &cfgstr, tag)){
/* sweep from devind down to 0 and see if there is a card with the
 * specified path, if so, open but don't activate this one */
	}

	if (get_config("video_device_buffer", devind, &cfgstr, tag)){
		if (strcmp(cfgstr, "streams") == 0){
			gbm = false;
			debug_print("device_buffer forced to EGLstreams");
		}
		else {
			debug_print("device_buffer fallback to GBM");
		}
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

	nodes[devind].wait_connector =
		get_config("video_device_wait", devind, NULL, tag);

	int dispfd = platform_device_open(dispdevstr, O_RDWR | O_CLOEXEC);
	int drawfd = (drawdevstr ?
		platform_device_open(drawdevstr, O_RDWR | O_CLOEXEC) : dispfd);

	if (try_node(drawfd, dispfd, dispdevstr,
		*dstind, gbm ? BUF_GBM : BUF_STREAM, connind, w, h, false)){
		debug_print("card at %d added", *dstind);
		nodes[*dstind].pathref = dispdevstr;
		nodes[*dstind].card_id = *dstind;
		*dstind++;
		return true;
	}
/* don't need to close the disp/draw descriptors here, it is done in try_node */
	else{
		free(nodes[devind].egllib);
		free(nodes[devind].agplib);
		nodes[devind].egllib = nodes[devind].agplib = NULL;
		free(dispdevstr);
		free(drawdevstr);
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
/* on Linux (basically only place that'd be relevant for now) we could
 * check proc/modules for nvidia, then go the sysfs route for the card node,
 * grab the vendor string and switch to streams that way - if so we could
 * dynamically load the GL libs etc. */
			if (try_node(fd, fd, buf, 0, BUF_GBM, -1, w, h, false) ||
				try_node(fd, fd, buf, 0, BUF_GBM, -1, w, h, false)){
					nodes[0].pathref = strdup(buf);
					return true;
				}
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

	if (getenv("ARCAN_VIDEO_DEBUGSTALL")){
		volatile static bool spinwait = true;
		while (spinwait){}
	}

/*
 * init after recovery etc. won't need seeding
 */
	static bool seeded;
	if (!seeded){
		for (size_t i = 0; i < VIDEO_MAX_NODES; i++){
			nodes[i].disp_fd = -1;
			nodes[i].draw_fd = -1;
		}
		seeded = true;
	}

/*
 * temporarily override segmentation fault handler here because it has happened
 * in libdrm for a number of "user-managable" settings (i.e. drm locked to X,
 * wrong permissions etc.)
 */
	sigaction(SIGSEGV, &err_sh, &old_sh);

	if (setup_cards_db(w, h) || setup_cards_basic(w, h)){
		struct dispout* d = egl_dri.last_display;
		set_display_context(d);
		egl_dri.canvasw = d->display.mode.hdisplay;
		egl_dri.canvash = d->display.mode.vdisplay;
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
/* protect against some possible circular calls with VT switch invoked
 * while we are also trying to already go external */
	if (in_external)
		return;

	arcan_video_prepare_external(true);

/* at this stage, all the GPU resources should be non-volatile */
	if (id != -1 || swap){
/* these case are more difficult as we also need to modify vstore affinity
 * masks (so we don't synch to multiple GPUs), and verify that the swapped
 * in GPU actually works */
	}

/* this is slightly incorrect as the agp_init function- environment,
 * ideally we'd also terminate the agp environment and rebuild on the
 * new / different card */
	arcan_video_restore_external(true);

	in_external = false;
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
		.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
		.vid.ledctrl = egl_dri.ledid
	};
	debug_print("video_recovery, injecting 'added' for mapped displays");
	arcan_evctx* evctx = arcan_event_defaultctx();
	arcan_event_enqueue(evctx, &ev);

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (displays[i].state == DISP_MAPPED){
			platform_video_map_display(
				ARCAN_VIDEO_WORLDID, displays[i].id, HINT_NONE);
			displays[i].vid = ARCAN_VIDEO_WORLDID;
			ev.vid.displayid = displays[i].id;
			ev.vid.cardid = displays[i].device->card_id;
			arcan_event_enqueue(evctx, &ev);
		}
	}

/*
 * commented as it is quite expensive and shouldn't be necessary in short
 * resets, and the VT switching now has full card rebuild
 * platform_video_query_displays();
 */

/* rebuild so that we guaranteed have a rendertarget */
	arcan_video_display.no_stdout = false;
	arcan_video_resize_canvas(displays[0].dispw, displays[0].disph);
}

static void page_flip_handler(int fd, unsigned int frame,
	unsigned int sec, unsigned int usec, void* data)
{
	struct dispout* d = data;
	d->buffer.in_flip = 0;
	TRACE_MARK_EXIT("video", "vsynch-flip", TRACE_SYS_DEFAULT, d->id, 0, "flip");

	verbose_print("(%d) flip(frame: %u, @ %u.%u)", (int) d->id, frame, sec, usec);

	switch(d->device->buftype){
	case BUF_GBM:{
		if (d->buffer.cur_bo)
			gbm_surface_release_buffer(d->buffer.surface, d->buffer.cur_bo);

		verbose_print("(%d) gbm-bo, release %"PRIxPTR" with %"PRIxPTR,
			(int)d->id, (uintptr_t) d->buffer.cur_bo, (uintptr_t) d->buffer.next_bo);
		d->buffer.cur_bo = d->buffer.next_bo;
		d->buffer.next_bo = NULL;
	}
	break;
	case BUF_STREAM:
	break;
	case BUF_HEADLESS:
	break;
	}

	float deadline = 1000.0f / (float)(d->vrefresh ? d->vrefresh : 60.0);
	arcan_conductor_deadline(deadline);
}

static bool get_pending(bool primary_only)
{
	int i = 0;
	int pending = 0;
	struct dispout* d;

	while((d = get_display(i++))){
		if (!primary_only || d->display.primary)
			pending |= d->buffer.in_flip;
	}

	return pending > 0;
}

/*
 * Real synchronization work is in this function. Go through all mapped
 * displays and wait for any pending events to finish, or the specified
 * timeout(ms) to elapse.
 *
 * Timeout is typically used for shutdown / cleanup operations where
 * normal background processing need to be ignored anyhow.
 */
static void flush_display_events(int timeout, bool yield)
{
	struct dispout* d;
	verbose_print("flush display events, timeout: %d", timeout);

	unsigned long long start = arcan_timemillis();

	int period = 4;
	if (timeout > 0){
		period = timeout;
	}
/* only flush, don't iterate */
	else if (timeout == -1){
		period = 0;
	}

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
			.fd = nodes[0].disp_fd,
			.events = POLLIN | POLLERR | POLLHUP
		};

		int rv = poll(&fds, 1, period);
		if (rv == 1){
/* If we get HUP on a card we have open, it is basically as bad as a fatal
 * state, unless - we support hotplugging multi-GPUs, then that decision needs
 * to be re-evaluated as it is essentially a drop_card + drop all displays */
			if (fds.revents & (POLLHUP | POLLERR)){
				debug_print("(card-fd %d) broken/recovery missing", (int) nodes[0].disp_fd);
				arcan_fatal("GPU device lost / broken");
			}
			else
				drmHandleEvent(nodes[0].disp_fd, &evctx);

/* There is a special property here, 'PRIMARY'. The displays with this property
 * set are being used for synch, with the rest - we just accept the possibility
 * of tearing or ignore that display for another frame (extremes like 59.xx Hz
 * display main and a 30Hz secondary output) */
		}
		else if (yield) {
/*
 * With VFR changes, we should start passing the responsibility for dealing with
 * synch period and timeout here before proceeding with the next pass / cycle.
 */
			int yv = arcan_conductor_yield(NULL, 0);
			if (-1 == yv)
				break;
			else
				period = yv;
		}
	}
/* 3 possible timeouts: exit directly, wait indefinitely, wait for fixed period */
	while (timeout != -1 && get_pending(true) &&
		(!timeout || (timeout && arcan_timemillis() - start < timeout)));
}

static void flush_parent_commands()
{
/* Changed but not enough information to actually specify which card we need
 * to rescan in order for the changes to be detected. This needs cooperation
 * with the scripts anyhow as they need to rate-limit / invoke rescan. This
 * only takes care of an invalid or severed connection, moving device disc.
 * to a supervisory process would also require something in event.c */
	int pv = platform_device_poll(NULL);
	switch(pv){
	case -1:
		debug_print("parent connection severed");
		arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
			.category = EVENT_SYSTEM,
			.sys.kind = EVENT_SYSTEM_EXIT,
			.sys.errcode = EXIT_FAILURE
		});
	break;
	case 5:
		debug_print("parent requested termination");
		arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
			.category = EVENT_SYSTEM,
			.sys.kind = EVENT_SYSTEM_EXIT,
			.sys.errcode = EXIT_FAILURE
		});
	break;
	case 4:
/* restore / rebuild out of context */
		debug_print("received restore while not in suspend state");
	break;
	case 3:{
/* suspend / release, if the parent connection is severed while in this
 * state, we'll leave it to restore external to shutdown */
		debug_print("received tty switch request");

/* first release current resources, then ack the release on the tty */
		arcan_video_prepare_external(false);
		platform_device_release("TTY", -1);

		int sock = platform_device_pollfd();

		while (true){
			poll(&(struct pollfd){
				.fd = sock, .events = POLLIN | POLLERR | POLLHUP | POLLNVAL} , 1, -1);

			pv = platform_device_poll(NULL);

			if (pv == 4 || pv == -1){
				debug_print("received restore request (%d)", pv);
				arcan_video_restore_external(false);
				break;
			}
		}
	}
	break;
	case 2:
/* new display event */
		arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
			.category = EVENT_VIDEO,
			.vid.kind = EVENT_VIDEO_DISPLAY_CHANGED,
		});
	break;
	default:
	break;
	}
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
		flush_display_events(30, true);
		int ind = ffsll(egl_dri.destroy_pending) - 1;
		debug_print("synch, %d - destroy %d", ind);
		disable_display(&displays[ind], true);
		egl_dri.destroy_pending &= ~(1 << ind);
	}

/* Some strategies might leave us with a display still in pending flip state
 * even though it has finished by now. If we don't flush those out, they will
 * skip updating one frame, so do a quick no-yield flush first */
	if (get_pending(false))
		flush_display_events(-1, false);

	size_t nd;
	uint32_t cost_ms = arcan_vint_refresh(fract, &nd);

/*
 * At this stage, the contents of all RTs have been synched, with nd == 0,
 * nothing has changed from what was draw last time.
 *
 * The damage tracking is currently binary, a dirty- region style flow should
 * be added to the _agp layer in order to not miss anything (shaders, source-
 * updates and so on)
 */
	arcan_bench_register_cost( cost_ms );

	bool clocked = false;
	bool updated = false;
	int method = 0;

/*
 * If we have a real update, the display timing will request a deadline based
 * on whatever display that was updated so we can go with that
 */
	if (nd > 0){
		while ( (d = get_display(i++)) ){
			if (d->state == DISP_MAPPED && d->buffer.in_flip == 0){
				updated |= update_display(d);
				clocked |= d->device->vsynch_method == VSYNCH_CLOCK;
			}
		}
/*
 * Finally check for the callbacks, synchronize with the conductor and so on
 * the clocked is a failsafe for devices that don't support giving a vsynch
 * signal.
 */
		if (get_pending(false) || updated)
			flush_display_events(clocked ? 16 : 0, true);
	}
/*
 * If there are no updates, just 'fake' synch to the display with the lowest
 * refresh unless the yield function tells us to run in a processing- like
 * state (useful for displayless like processing).
 */
	else {
		verbose_print("nothing to update");
		float refresh = 60.0;
		i = 0;
		while ((d = get_display(i++))){
			if (d->state == DISP_MAPPED){
				if (d->vrefresh > 0 && d->vrefresh > refresh)
					refresh = d->vrefresh;
			}
		}

/*
 * The other option would be to to set left as the deadline here, but that
 * makes the platform even worse when it comes to testing strategies etc.
 */
		int left = 1000.0f / refresh;
		arcan_conductor_deadline(-1);
		arcan_conductor_fakesynch(left);
	}

/*
 * The LEDs that are mapped as backlights via the internal pipe-led protocol
 * needs to be flushed separately, here is a decent time to get that out of
 * the way.
 */
	flush_leds();

/*
 * Since we outsource device access to a possibly privileged layer, here is
 * the time to check for requests from the parent itself.
 */
	flush_parent_commands();

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
			unsigned long long start = arcan_timemillis();
			disable_display(&displays[i], true);
			debug_print("shutdown (%zu) took %d ms", i, (int)(arcan_timemillis() - start));
		}
		flush_display_events(30, false);
	} while (egl_dri.destroy_pending && rc-- > 0);

	for (size_t i = 0; i < sizeof(nodes)/sizeof(nodes[0]); i++)
		release_card(i);
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

size_t platform_video_decay()
{
	return 2;
}

static bool direct_scanout_alloc(
	struct agp_rendertarget* tgt, struct agp_vstore* vs, int action, void* tag)
{
	struct dispout* display = tag;

	if (action == RTGT_ALLOC_FREE){
		debug_print("scanout_free:card=%d", (int) display->id);

	}
	else if (action == RTGT_ALLOC_SETUP){
		debug_print("scanout_alloc:card=%d", (int) display->id);
/* fields:
 * w,
 * h,
 * bpp,
 * s_raw,
 * txmapped
 * s_fmt (GL_PIXEL_STORE)
 * d_fmt (GL_STORE_PIXEL_FORMAT)
 */
	}

	return false;
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
			d->display.con ? d->display.con->connector_id : -1,
			d->display.mode_set != -1 ? d->display.mode.hdisplay : 0,
			d->display.mode_set != -1 ? d->display.mode.vdisplay : 0) ||
			setup_buffers(d) == -1){
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
		arcan_conductor_release_display(d->device->card_id, d->id);

		return true;
	}

/* the more recent rpack- based mapping format could/should get special
 * consideration here as we could then raster into a buffer directly for a
 * non-GL scanout path, avoiding some of the possible driver fuzz and latency
 * */
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

/* this kind of hint management is implemented through texture coordinate
 * tricks, on a direct mapping, the capabilities of the output needs to be
 * checked as well in the same 'sane direct vobj' style to see if there are
 * layer flags that can be set to avoid a forced composition pass */
	size_t iframes = 0;
	arcan_vint_applyhint(vobj, hint,
		txcos, d->txcos, &d->dispx, &d->dispy, &d->dispw, &d->disph, &iframes);
	arcan_video_display.ignore_dirty += iframes;

/* turn on the display on mapping if it isn't already */
	if (d->display.dpms == ADPMS_OFF){
		dpms_set(d, DRM_MODE_DPMS_ON);
		d->display.dpms = ADPMS_ON;
	}

/* need to remove this from the mapping hint so that it doesn't
 * hit HINT_NONE tests */
	d->hint = hint & ~(HINT_FL_PRIMARY);
	d->vid = id;
	arcan_conductor_register_display(
		d->device->card_id, d->id, SYNCH_STATIC, d->vrefresh, d->vid);

/* we might have messed around with the projection, rebuild it to be sure */
	struct rendertarget* newtgt = arcan_vint_findrt(vobj);
	if (newtgt){
		newtgt->inv_y = false;
		build_orthographic_matrix(
			newtgt->projection, 0, vobj->origw, 0, vobj->origh, 0, 1);

		if (sane_direct_vobj(vobj)){
/* the rendertarget color attachment will need buffering in order to not have
 * tearing or implicit locks when attempting direct scanout, so enable that by
 * running a swap here. */
			if (!d->force_compose){
/* before swapping, set an allocator for the rendertarget so that we can ensure
 * that we allocate from scanout capable memory - note that in that case the
 * contents is invalidated and a new render pass on the target is needed. This
 * is not that problematic with the normal render loop as the map call will come
 * in a 'good enough' order. */
 				bool swap;
				agp_rendertarget_allocator(newtgt->art, direct_scanout_alloc, d);
				unsigned col = agp_rendertarget_swap(newtgt->art, &swap);
			}

/* even then we have an option for a mapped rendertarget, and that is to try
 * and proxy it -> can we forego it and use the egl buffer directly? that's
 * possible if the composition isn't used for anything else (recordtarget,
 * multiple users, ...) */
			else if (!d->disallow_rtproxy && newtgt->art) {
				agp_rendertarget_proxy(newtgt->art,
					display_rtgt_proxy, (uintptr_t)(void*)d);
/* but this requires a different projection than the default */
				newtgt->inv_y = true;
				build_orthographic_matrix(
					newtgt->projection, 0, vobj->origw, vobj->origh, 0, 0, 1);
			}
		}
	}
/* Heuristics are needed here to determine if we can do the vobj- direct
 * mapping with a render pass, these are not complete yet as we want to get the
 * rendertarget- mapping more robust first - the benefits is mainly if it comes
 * from an external source and we can send that external source scanout capable
 * buffers. There should also be a special 'non-GPU' approach for certain
 * sources here where we can just use a dumb framebuffer and directly raster
 * into */
	else if (0 && sane_direct_vobj(vobj)){
	}
	else {
	}

/* reset the 'force composition' output path, this may cost a frame
 * being slightly delayed on map operations should the direct-scanout
 * fail, causing force_composition to be set */
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	d->force_compose = !get_config("video_device_direct", 0, NULL, tag);

	return true;
}

static void drop_swapchain(struct dispout* d)
{
	arcan_vobject* vobj = arcan_video_getobject(d->vid);
	if (!vobj)
		return;

	struct rendertarget* newtgt = arcan_vint_findrt(vobj);
	if (!newtgt)
		return;

	agp_rendertarget_dropswap(newtgt->art);
	arcan_video_display.ignore_dirty += 3;
}

static enum display_update_state draw_display(struct dispout* d)
{
	bool swap_display = true;
	arcan_vobject* vobj = arcan_video_getobject(d->vid);
	agp_shader_id shid = agp_default_shader(BASIC_2D);

/*
 * If the following conditions are valid, we can simply add the source vid
 * to the display directly, saving a full screen copy.
 */
	if (sane_direct_vobj(vobj) && d->hint == HINT_NONE && !d->force_compose){
		swap_display = false;
		goto out;
	}

/*
 * object invalid or mapped poorly, just reset to whatever the clear color is
 */
	if (!vobj) {
		agp_rendertarget_clear();
		goto out;
	}
	else{
		if (vobj->program > 0)
			shid = vobj->program;

		agp_activate_vstore(
			d->vid == ARCAN_VIDEO_WORLDID ? arcan_vint_world() : vobj->vstore);
	}

/*
 * This is an ugly sinner, due to the whole 'anything can be mapped as
 * anything' with a lot of potential candidates being in non scanout- capable
 * memory. The multi-display strategy with first drawing into a rendertarget(RT),
 * then blitting this into the EGLDisplay here is very costly.
 *
 * There is a 'proxy' path where the various other RT uses are probed and if
 * the RT is not actually used for render-to-texture or other sharing /
 * effects (custom shaders), we ignore the use as a RT and just compose to
 * the underlying EGL bit. The flow for that is as follows:
 *
 *  map_display(obj) -> sanity check(is_rtgt?) -> set proxy.
 *
 *  in renderloop:
 *     activate_rtgt, has proxy? -> registered callback()
 *     in callback, if it is a valid direct target, switch the drawing
 *     destination to the direct display instead of rendertarget, flag
 *     the display as already drawn.
 */
		struct rendertarget* newtgt = arcan_vint_findrt(vobj);
		if (newtgt){
			size_t nd = agp_rendertarget_dirty(newtgt->art, NULL);
			verbose_print("(%d) draw display, dirty regions: %zu", nd);
			if (nd){
				agp_rendertarget_dirty_reset(newtgt->art, NULL);
			}
			else{
				verbose_print("(%d) no dirty, skip");
				return UPDATE_SKIP;
			}
		}

		if (d->skip_blit){
			verbose_print("(%d) skip draw, already composed", (int)d->id);
			d->skip_blit = false;
		}
		else {
			agp_shader_activate(shid);
			agp_shader_envv(PROJECTION_MATR, d->projection, sizeof(float)*16);
			agp_rendertarget_clear();
			agp_blendstate(BLEND_NONE);
			agp_draw_vobj(0, 0, d->dispw, d->disph, d->txcos, NULL);
			verbose_print("(%d) draw, shader: %d, %zu*%zu",
				(int)d->id, (int)shid, (size_t)d->dispw, (size_t)d->disph);
		}
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

	out:
		if (swap_display){
			verbose_print("(%d) pre-swap", (int)d->id);
				d->device->eglenv.swap_buffers(d->device->display, d->buffer.esurf);
			verbose_print("(%d) swapped", (int)d->id);
			return UPDATE_FLIP;
		}

		verbose_print("(%d) direct- path selected");
		return UPDATE_DIRECT;
	}

	static bool update_display(struct dispout* d)
	{
		if (d->display.dpms != ADPMS_ON)
			return false;

	/* we want to know how multiple- displays drift against eachother */
		d->last_update = arcan_timemillis();

	/*
	 * Make sure we target the right GL context
	 * Notice that the context being set is that of the display buffer,
	 * not the shared outer "headless" context.
	 *
	 * MULTIGPU> will also need to set the agp- current rendertarget
	 */
		set_display_context(d);
		egl_dri.last_display = d;

	/* activated- rendertarget covers scissor regions etc. so we want to reset */
		agp_blendstate(BLEND_NONE);
		agp_activate_rendertarget(NULL);

/*
 * Currently we only do binary damage / update tracking in that there are EGL
 * versions for saying 'this region is damaged, update that' to cut down on
 * fillrate/bw. This should likely be added to the agp_ layer as a simple dirty
 * list that the draw_vobj calls append to. Some is prepared for (see
 * agp_rendertarget_dirty), but more is needed in the drawing logic itself.
 */
	enum display_update_state dstate = draw_display(d);

	uint32_t next_fb = 0;
	switch(d->device->buftype){
	case BUF_STREAM:{
		EGLAttrib attr[] = {
			EGL_DRM_FLIP_EVENT_DATA_NV, (EGLAttrib) d,
			EGL_NONE,
		};
		if (d->device->vsynch_method == VSYNCH_FLIP){
			if (!d->device->eglenv.stream_consumer_acquire_attrib(
				d->device->display, d->buffer.stream, attr)){
				d->device->vsynch_method = VSYNCH_CLOCK;
				TRACE_MARK_ONESHOT("video", "eglstream-clock",
					TRACE_SYS_WARN, d->id, 0, "eglstream-vsynch fail");
				debug_print("(%d) - no acq-attr, revert to clock", (int)d->id);
			}
		}
/* dumb buffer, will never change */
		next_fb = d->buffer.cur_fb;
	}
	break;
	case BUF_GBM:{
		int rv = -1;
/* We use rendertarget_swap for implementing front/back buffering in the
 * case of rendertarget scanout. */
		if (dstate == UPDATE_DIRECT){
			if ((rv = get_gbm_fb(d, dstate, NULL, &next_fb)) == -1){

				TRACE_MARK_ONESHOT("video", "gbm-scanout",
					TRACE_SYS_WARN, d->id, 0, "gbm-direct scanout fail, compose");

				debug_print("(%d) direct-scanout buffer "
					"conversion failed, falling back to composition", true);
				d->force_compose = true;
				dstate = draw_display(d);

/* This will cause a possible rendertarget to have a useless swapchain,
 * so drop / remove that again and rebuild. This switch will also increment
 * the number of 'blackframes' dirty prefill */
				drop_swapchain(d);
			}
			else {
				TRACE_MARK_ONESHOT("video", "gbm-scanout", TRACE_SYS_WARN, d->id, 0, "");
			}
		}

		if (dstate == UPDATE_FLIP){
			if (!d->buffer.surface)
				goto out;

			d->buffer.next_bo = gbm_surface_lock_front_buffer(d->buffer.surface);
			if (!d->buffer.next_bo){
				TRACE_MARK_ONESHOT("video", "gbm-buffer-lock-fail", TRACE_SYS_ERROR, d->id, 0, "");
				verbose_print("(%d) update, failed to lock front buffer", (int)d->id);
				goto out;
			}
			if ((rv = get_gbm_fb(d, dstate, d->buffer.next_bo, &next_fb)) == -1){
				TRACE_MARK_ONESHOT("video", "gbm-framebuffer-fail", TRACE_SYS_ERROR, d->id, 0, "");
				debug_print("(%d) - couldn't get framebuffer handle", (int)d->id);
				gbm_surface_release_buffer(d->buffer.surface, d->buffer.next_bo);
				goto out;
			}
		}

		if (rv == 0){
			TRACE_MARK_ONESHOT("video", "gbm-buffer-release", TRACE_SYS_DEFAULT, d->id, 0, "");
			gbm_surface_release_buffer(d->buffer.surface, d->buffer.next_bo);
			verbose_print("(%d) - no update for display", (int)d->id);
			goto out;
		}
	}
	break;
	case BUF_HEADLESS:
	break;
	}

	bool new_crtc = false;
/* mode-switching is defered to the first frame that is ready as things
 * might've happened in the engine between _init and draw */
	if (d->display.reset_mode || !d->display.old_crtc){
/* save a copy of the old_crtc so we know what to restore on shutdown */
		if (!d->display.old_crtc)
			d->display.old_crtc = drmModeGetCrtc(d->device->disp_fd, d->display.crtc);
		d->display.reset_mode = false;

/* do any deferred ioctl- device actions to switch from text to graphics */
		platform_device_open("TTYGRAPHICS", 0);
		new_crtc = true;
	}

	if (new_crtc){
		debug_print("(%d) deferred modeset, switch now (%d*%d => %d*%d@%d)",
			(int) d->id, d->dispw, d->disph, d->display.mode.hdisplay,
			d->display.mode.vdisplay, d->display.mode.vrefresh
		);
		if (d->device->atomic){
			atomic_set_mode(d);
		}
		else {
			int rv = drmModeSetCrtc(d->device->disp_fd, d->display.crtc,
				next_fb, 0, 0, &d->display.con_id, 1, &d->display.mode);
			if (rv < 0){
				debug_print("(%d) error (%d) setting Crtc for %d:%d(con:%d)",
					(int)d->id, errno, d->device->disp_fd, d->display.crtc, d->display.con_id);
			}
		}
		arcan_conductor_register_display(
			d->device->card_id, d->id, SYNCH_STATIC, d->vrefresh, d->vid);
	}

/* let DRM drive synch and wait for vsynch events on the file descriptor */
	if (d->device->vsynch_method == VSYNCH_FLIP){
		verbose_print("(%d) request flip (fd: %d, crtc: %"PRIxPTR", fb: %d)",
			(int)d->id, (uintptr_t) d->display.crtc, (int) next_fb);

		if (!drmModePageFlip(d->device->disp_fd, d->display.crtc,
			next_fb, DRM_MODE_PAGE_FLIP_EVENT, d)){
			TRACE_MARK_ENTER("video", "vsync-flip", TRACE_SYS_DEFAULT, d->id, 0, "flip");
			d->buffer.in_flip = 1;
			verbose_print("(%d) in flip", (int)d->id);
		}
		else {
			debug_print("(%d) error scheduling vsynch-flip (%"PRIxPTR":%"PRIxPTR")",
				(int)d->id, (uintptr_t) d->buffer.cur_fb, (uintptr_t)next_fb);
		}
	}
	set_device_context(d->device);
	return true;

out:
	set_device_context(d->device);
	return false;
}

void platform_video_prepare_external()
{
	if (in_external)
		return;

	int rc = 10;
	debug_print("preparing external");
	TRACE_MARK_ENTER("video", "external-handover", TRACE_SYS_DEFAULT, 0, 0, "");

	do{
		for(size_t i = 0; i < MAX_DISPLAYS; i++)
			disable_display(&displays[i], false);
		if (egl_dri.destroy_pending)
			flush_display_events(30, false);
	} while(egl_dri.destroy_pending && rc-- > 0);

/* tell the privsep side that we no-longer need the GPU */
	char* pathref = nodes[0].pathref;
	nodes[0].pathref = NULL;
	if (pathref){
		platform_device_release(pathref, 0);
		close(nodes[0].disp_fd);
	}

/* this will actually kill the pathref, restore needs it */
	release_card(0);
	nodes[0].pathref = pathref;

	agp_dropenv(agp_env());

	in_external = true;
}

void platform_video_restore_external()
{
	debug_print("restoring external");
	if (!in_external)
		return;

	TRACE_MARK_EXIT("video", "external-handover", TRACE_SYS_DEFAULT, 0, 0, "");
	arcan_event_maskall(arcan_event_defaultctx());

/* this is a special place in malbolge, it is possible that the GPU has
 * disappeared when we restore, or that it has been replaced with a different
 * one - the setup for that is left hanging until the multi-GPU bits are in
 * place */
	int lfd = -1;
	if (nodes[0].pathref){
/* our options in this case if not getting the GPU back are currently slim,
 * with a fallback software or remote AGP layer, the rest of the engine can be
 * left going, we have enough state to release clients to migrate somewhere */
		lfd = platform_device_open(nodes[0].pathref, O_RDWR);
		if (-1 == lfd){
			debug_print("couldn't re-acquire GPU after suspend");
			goto give_up;
		}

/* and re-associate draw with disp if that was the case before */
		if (nodes[0].draw_fd != -1 && nodes[0].draw_fd == nodes[0].disp_fd){
			nodes[0].draw_fd = lfd;
		}
		nodes[0].disp_fd = lfd;
	}

/* rebuild the card itself now, if that fails, we are basically screwed,
 * go to crash recovery */
	if (!try_node(lfd, lfd,
		nodes[0].pathref, 0,nodes[0].buftype, -1, -1, -1, true)){
		debug_print("failed to rebuild display after external suspend");
		goto give_up;
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
			else if (setup_buffers(&displays[i]) == -1){
				debug_print(
					"(%d) restore external failed on buffer alloc", (int)displays[i].id);
				disable_display(&displays[i], true);
			}
			debug_print("(%d) restore ok, flag reset", (int)displays[i].id);
			displays[i].state = DISP_MAPPED;
			displays[i].display.reset_mode = true;
		}
	}

	set_device_context(&nodes[0]);
	agp_init();
	in_external = false;
	arcan_event_clearmask(arcan_event_defaultctx());
	return;

give_up:
	arcan_event_clearmask(arcan_event_defaultctx());
	arcan_event_enqueue(arcan_event_defaultctx(), &(struct arcan_event){
		.category = EVENT_SYSTEM,
		.sys.kind = EVENT_SYSTEM_EXIT,
		.sys.errcode = EXIT_FAILURE
	});
}
