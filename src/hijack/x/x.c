/*
 * This library maps the common X* symbols to corresponding arcan_shmif calls
 * or stubs. It's intended for 'quick and dirty' legacy workarounds in cases
 * where a VM may be too cumbersome. Most functions are stubs, and filled out
 * as needed over time - the aim is not a complete implementation, but just
 * enough for some side-cases, e.g. when xcb/X/GLX comes as a parasitic
 * dependency rather than a desired one.
 *
 * Milestone 1 < glxgears >
 *  [*] First Contact (i.e. draws to the default size window)
 *  [ ] Proper context create / destroy / tracking
 *  [ ] CreateWindow tracking
 *  [ ] Input (XSyms for rotating etc.)
 *
 * Milestone 2 < some trivial GDK application >
 *  [ ] Respond and forward resize events
 *  [ ] Mouse
 *
 * Milestone 3 < Notepad in WINE >
 *  [ ] Subwindows -> Subsegments (popups as example)
 *  [ ] Paste Buffers
 *
 * Then lets see if we ever take this further or just laugh it off...
 */
#include <arcan_shmif.h>
//#define TRACE(...) {fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n");}
#define TRACE(...)

#ifdef WANT_GLX_FUNCTIONS

#define AGP_ENABLE_UNPURE 1
#include "video_platform.h"
#include "platform.h"

#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>

#endif

typedef unsigned long int XID;
typedef unsigned long int Atom;

/*
 * We also need to grab dlsym() to intercept calls that would look for
 * glx- dynamically. GLEW is often built to do that.
 */
/* #define GRAB_DLFCN */

#ifdef WANT_X_FUNCTIONS
/*
 * Could, of course, have pulled in the big mess of headers, but since this
 * is not for 100% compatibility but rather quick hack jobs where a full-VM
 * is not a solution, the dream of escaping the dependency one day wins out
 */
typedef void* Visual;
typedef XID VisualID;
typedef XID Window;
typedef XID Font;
typedef XID Drawable;
typedef XID Pixmap;
typedef XID KeySym;
typedef XID Colormap;
typedef XID Cursor;
typedef XID GContext;
typedef int Bool;
typedef unsigned long Time;
typedef char* XPointer;

typedef struct Display Display;

typedef struct {
	Visual* visual;
	VisualID visualid;
	int screen;
	int depth;
	int class;
	unsigned long red_mask;
	unsigned long green_mask;
	unsigned long blue_mask;
	int colormap_size;
	int bits_per_rgb;
} XVisualInfo;

typedef struct {
	int func;
	unsigned long mask;
	unsigned long fg;
	unsigned long bg;
	int linew;
	int linest;
	int capst;
	int joinst;
	int fillst;
	int fillr;
	int arc;
	Pixmap tile;
	Pixmap stiple;
	int tsx;
	int tsy;
	Font font;
	int subwnd;
	Bool xps;
	int clipx;
	int clipy;
	Pixmap clipm;
	int dasho;
	char dash;
} XGCValues;

typedef struct {
	void* ext_data;
	GContext gid;
	Bool rects;
	Bool dashes;
	unsigned long dirty;
	XGCValues values;
} GC;

typedef struct {
	void* ext;
	Display* dpy;
	Window root;
	int width, height;
	int mwidth, mheight;
	int ndepths;
	void* depths;
	int root_depth;
	Visual* root_visual;
	GC default_gc;
/* uncertains about offsets after these due to the definition of GC */
	Colormap cmap;
	unsigned long white;
	unsigned long black;
	int max_maps, min_maps;
	int backing_store;
	Bool save_unders;
	long root_input;
} Screen;

/*
 * Alas, tons of programs break the opaqueness of this structure because fuck
 * you - thanks to macros like DefaultScreen, RootWindow etc. so we have to
 * fake one and then add our own stuff afterwards, great.
 *
 * Worst sinners (found that is) are the *ofScreen, ScreenOf* etc. macros
 * (because having a symbol for those would of course be .. yeah..)
 * ScreenOfDisplay(dpy, scr)(&((_XPrivDisplay)dpy)->screens[scr]
 * RootWindow(dpy, scr)
 */
struct Display {
	void* ext_data;
	void* priv1;
	int fd;
	int private2;
	int maj;
	int min;
	char* vend;
	XID priv3_5[3];
	int priv6;
	XID (*alloc)(void*);
	int bo;
	int bunit;
	int bpad;
	int bbito;
	int nfmt;
	void* pfmt;
	int private8;
	int release;
	void* priv9;
	void* priv10;
	int qlen;
	unsigned long last_req;
	unsigned long req;
	char* priv11_14[4];
	unsigned max_req;
	void* hash_bucket;
	int (*priv15)(void*);
	char* disp_name;
	int defscr;
	int nscr;
	Screen* screens;
	unsigned long mbuf;
	unsigned long priv16;
	int min_keyc;
	int max_keyc;
	char* priv17;
	char* priv18;
	int priv19;
	char* xdef;
/* just for some illusion of safety */
	uint8_t pad[256];
	XVisualInfo vi;
	struct arcan_shmif_cont con;
	bool gl;
#ifdef WANT_GLX_FUNCTIONS
	struct agp_rendertarget* rtgt;
	struct storage_info_t vstore;
#endif
};

typedef struct {
	XPointer compose_ptr;
	int chars_matched;
} XComposeStatus;

typedef struct {
	long flags;
	int x, y;
	int width, height;
	int min_width, min_height;
	int max_width, max_height;
	int width_inc, height_inc;
	struct {
		int x;
		int y;
	} min_aspect, max_aspect;
	int base_width, base_height;
	int win_gravity;
} XSizeHints;

typedef struct {
	Pixmap background;
	unsigned long bgpx;
	Pixmap border;
	unsigned long borderpx;
	int bit_gravity;
	int win_gravity;
	int backing;
	unsigned long backing_planes;
	unsigned long backing_px;
	Bool save_under;
	long evmask;
	long do_not_prop;
	Bool override_redir;
	Colormap colormap;
	Cursor cursor;
} XSetWindowAttributes;

typedef struct {
	int x, y;
	int width, height;
	int border_width;
	int depth;
	Visual* visual;
	Window root;
	int class;
	int bit_gravity;
	int win_gravity;
	int backing_store;
	unsigned long backing_planes;
	unsigned long backing_pixel;
	Bool save_under;
	int map_state;
	long all_event_masks;
	long your_event_mask;
	long do_not_propagate_mask;
	Bool override_redirect;
	Screen* screen;
} XWindowAttributes;

typedef struct {
	int type;
	unsigned long serial;
	bool send;
	Display* dpy;
	Window wnd;
	Window root;
	Window subwnd;
	Time time;
	int x, y;
	int x_root, y_root;
	unsigned int state;
	unsigned int keycode;
	Bool same_screen;
	char trans_chars[4];
} XKeyEvent;

/*
 * Cringe ..
 */
typedef union XEvent {
	int type;
	XKeyEvent xkey;
	long pad[24];
} XEvent;

typedef XKeyEvent XKeyPressedEvent;
typedef XKeyEvent XKeyReleasedEvent;

KeySym XLookupKeysym(XKeyEvent* event, int index)
{
	TRACE("XLookupKeysym");
	return 0;
}

struct dispscr {
	Display dpy;
	Screen scr;
};

Display* XOpenDisplay(char* name)
{
	TRACE("XOpenDisplay(%s)", name ? name : "no name");

	struct dispscr* dscr = malloc(sizeof(struct dispscr));
	if (!dscr)
		return NULL;
	memset(dscr, '\0', sizeof(struct dispscr));

/* fake enough to satisify the garbage macros */
	dscr->dpy.screens = &dscr->scr;
	dscr->dpy.nscr = 1;
	dscr->dpy.defscr = 0;
	dscr->dpy.maj = 11;
	dscr->dpy.min = 7;
	dscr->dpy.vend = "Org.X";
	dscr->dpy.disp_name = "Display";
	dscr->scr.dpy = &dscr->dpy;
	dscr->scr.root = 0;
	dscr->scr.ndepths = 1;
	dscr->scr.root_depth = 32;
	dscr->scr.white = 0xffffff;
	dscr->scr.black = 0x000000;

/* we provide one display, one screen, one visual - deal with it */
	dscr->dpy.vi.visualid = 127; /* whatever */
	dscr->dpy.vi.screen = 0;
	dscr->dpy.vi.depth = 32;
	dscr->dpy.vi.class = 4;
	dscr->dpy.vi.red_mask = 0xff0000;
	dscr->dpy.vi.green_mask = 0x00ff00;
	dscr->dpy.vi.blue_mask = 0x0000ff;
	dscr->dpy.vi.colormap_size = 8;

/* setup one connection, that gives us our first window,
 * although it is not currently mapped */
	struct arg_arr* arr;
	dscr->dpy.con = arcan_shmif_open(SEGID_APPLICATION, 0, &arr);
	if (!dscr->dpy.con.addr){
		free(dscr);
		return NULL;
	}

	return &dscr->dpy;
}

int XLookupString(XKeyEvent* event, char* out, int out_sz,
	KeySym* keysym_ret, XComposeStatus* status)
{
	TRACE("XLookupString");
	return 0;
}

void XFree(void* data)
{
	TRACE("XFree");
}

static int counter;
Window XCreateWindow(Display* dpy, Window win, int x, int y,
	unsigned width, unsigned height, unsigned int borderw, unsigned int depth,
	unsigned int class, Visual* visual, unsigned long valuemask,
	XSetWindowAttributes* attributes)
{
	TRACE("XCreateWindow(%d * %d @ %d, %d)", width, height, x, y);
	arcan_shmif_resize(&dpy->con, width, height);

/* request a new one on the segment associated with the display,
 * this will be set in pending state with the Window ID used for the
 * request, and when activated, set the width/height to what was requested */
	return counter++;
}

Bool XRRQueryExtension(Display* dpy, int* ev_base_ret, int* err_base_ret)
{
	TRACE("XRRQueryExtension");
	return false;
}

Bool XQueryExtension(Display* dpy, char* name, int *major_opc,
	int* first_event_ret, int* first_error_ret)
{
	TRACE("XQueryExtension(%s)\n", name ? name : "");
	return false;
}

Window XCreateSimpleWindow(Display* dpy, Window parent, int x, int y,
	unsigned width, unsigned height, unsigned borderw, unsigned long border,
		unsigned long background)
{
	TRACE("XCreateSimpleWindow(%d * %d @ %d, %d)", width, height, x, y);
	return counter++;
}

Colormap XCreateColormap(Display* dpy, Window win, Visual* visual, int alloc)
{
	TRACE("XCreateColormap (%d)", alloc);
	return 0;
}

int XDestroyWindow(Display* dpy, Window win)
{
	TRACE("XDestroyWindow");
	return 1;
}

int XCloseDisplay(Display* dpy)
{
	TRACE("XCloseDisplay");
	if (dpy && dpy->con.addr){
		arcan_shmif_drop(&dpy->con);
	}
	return 0;
}

int XNextEvent(Display* dpy, XEvent* ev)
{
	TRACE("XNextEvent");
	return 0;
}

int XMapWindow(Display* dpy, Window win)
{
	TRACE("XMapWindow");
	return 1;
}

XVisualInfo* XGetVisualInfo(Display* dpy,
	long vinfo_mask, XVisualInfo* tmpl, int* nret)
{
	TRACE("XGetVisualInfo");
	if (tmpl->screen == 0){
		XVisualInfo* vi = malloc(sizeof(XVisualInfo));
		if (!vi){
			if (nret)
				*nret = 0;
				return NULL;
		}

		if (nret)
			*nret = 1;
		*vi = dpy->vi;
		return vi;
	}
	else if (nret){
		*nret = 0;
	}

	return NULL;
}

void XSetNormalHints(Display* dpy, Window win, XSizeHints* hints)
{
	TRACE("XSetNormalHints");
}

int XChangeProperty(Display* dpy, Window win, Atom prop, Atom type, int format,
	int mode, unsigned char* data, int nelts)
{
	TRACE("XChangeProperty");
	return 1;
}

void XSetStandardProperties(Display* dpy, Window win, char* wname,
	char* iname, Pixmap ipixmap, char** argv, int argc, XSizeHints* hints)
{
	TRACE("XSetStandardProperties(%d * %d, %s)", hints->width, hints->height,
		wname ? wname : "no name");
/* width, height, and wname are interesting */
}

Atom XInternAtom(Display* dpy, char* name, bool exists)
{
	TRACE("XInternAtom(%s)", name ? name : "no name");
	return 0;
}

int XInternAtoms(Display* display, char** names, int count, Bool exists,
	Atom* atoms_return)
{
	TRACE("XInternAtoms");
	for (size_t i = 0; i < count; i++)
		atoms_return[i] = XInternAtom(display, names[i], exists);
	return 0;
}

int XPending(Display* dpy)
{
	TRACE("XPending");
	return 0;
}

int XParseGeometry(char* geom, int* x, int* y, unsigned int* w, unsigned int* h)
{
	TRACE("XParseGeometry");
	return 0;
}

void XSelectInput(Display* dpy, Window wnd, long event_mask)
{
	TRACE("Input Mask (%ld)", event_mask);
}

/* GDK expose some simple calls we could wrap too,
 * _x11_get_default_display, x11_display_get_xdisplay, _lookup_visual,
 * _x11_window_get_xid, x11_visual_get_xvisual, ... */
#endif

#ifdef WANT_XCB_FUNCTIONS
int xcb_flush(xcb_connection_t* c)
{
}

uint32_t xcb_get_maximum_request_length(xcb_connection_t* c)
{
	return (uint32_t)-1;
}

void xcb_prefetch_maximum_request_length(xcb_connection_t* c)
{
}

xcb_generic_event_t* xcb_wait_for_event(xcb_connection_t* c)
{
	return NULL;
}

xcb_generic_event_t* xcb_poll_for_event(xcb_connection_t* c)
{
	return NULL;
}

xcb_generic_event_t* xcb_poll_for_queued_event(xcb_connection_t* c)
{
	return xcb_poll_for_event(c);
}

xcb_generic_event_t* xcb_wait_for_special_event(xcb_connection_t* c, xcb_special_event_t* se)
{
	return NULL;
}

xcb_generic_event_t* xcb_request_check(xcb_connection_t* c, xcb_void_cookie_t cookie)
{
	return -1;
}

void xcb_discard_reply(xcb_connection_t* c, unsigned seq)
{
}

void xcb_discard_reply64(xcb_connection_t* c, uint64_t seq)
{
}

const struct xcb_query_extension_reply_t* xcb_get_extension_data(xcb_connection_t* c, xcb_extension_t* ext)
{
}
	return NULL;

int xcb_get_file_descriptor(xcb_connection_t* c)
{
	return -1;
}

int xcb_connection_has_error(xcb_connection_t* c)
{
	return 1;
}

xcb_connection_t* xcb_connect_to_fd(int fd, xcb_auth_info_t* auth_info)
{
	return NULL;
}

void xcb_disconnect(xcb_connection_t* c)
{
}

xcb_connection_t* xcb_connect(const char* dname, int* screenp)
{
	return NULL;
}

xcb_connection_t* xcb_connect_to_display_with_auth_info(const char* disp,
	xcb_auth_info_t* auth, int* screen)
{
	return NULL;
}

#endif

#ifdef WANT_GLX_FUNCTIONS

struct __GLXFBConfigRec {
	void* ptr;
};

struct __GLXContextRec {
	void* ptr;
};

typedef XID GLXPixmap;
typedef XID GLXDrawable;
typedef XID GLXFBConfigID;
typedef XID GLXWindow;
typedef XID GLXPbuffer;
typedef XID GLXContextID;
typedef struct __GLXFBConfigRec* GLXFBConfig;

/*
 * A buffer so we can notify if anything actually is written to/from it
 */
typedef void* GLXContext;
static int junk[4096];
static GLXContext current_ctx;

GLXFBConfig* glXChooseFBConfig(Display* dpy, int screen, const int* attrib_list,
	int* nelements)
{
	TRACE("glXChooseFBConfig");
	return (GLXFBConfig*) junk;
}

XVisualInfo* glXChooseVisual(Display* dpy, int screen, int* attrib_list)
{
	TRACE("glXChooseFBConfig");
	return (XVisualInfo*) junk;
}

void glXCopyContext(Display* dpy,
	GLXContext src, GLXContext dst, unsigned long mask)
{
	TRACE("glXCopyContext");
}

GLXContext glXCreateContext(Display* dpy,
	XVisualInfo* vis, GLXContext list, bool direct)
{
	TRACE("glXCreateContext");
	if (!dpy || !dpy->con.addr)
		return 0;

	if (SHMIFEXT_OK != arcan_shmifext_headless_setup(
		&dpy->con, arcan_shmifext_headless_defaults()))
		return 0;

	agp_init();
	agp_empty_vstore(&dpy->vstore, dpy->con.w, dpy->con.h);
	dpy->rtgt = agp_setup_rendertarget(
		&dpy->vstore, RENDERTARGET_COLOR_DEPTH_STENCIL);
	agp_activate_rendertarget(dpy->rtgt);

	return (GLXContext) 1;
}

GLXPixmap glXCreateGLXPixmap(Display* dpy, XVisualInfo* vis, Pixmap pixmap)
{
	TRACE("glXCreateGLXPixmap");
	return 0;
}

GLXContext glXCreateNewContext(Display* dpy,
	GLXFBConfig cfg, int type, GLXContext slist, bool direct)
{
/* if we're in GL for the current display, we are already there, else
 * set it up */
	TRACE("glXCreateNewContext");
	return 0;
}

GLXPbuffer glXCreatePbuffer(Display* dpy,
	GLXFBConfig config, const int *attrl)
{
	TRACE("glXCreatePbuffer");
	return 0;
}

GLXPixmap glXCreatePixmap(Display* dpy,
	GLXFBConfig cfg, Pixmap pmap, const int* attrl)
{
	TRACE("glXCreatePixmap");
	return 0;
}

GLXWindow glXCreateWindow(Display* dpy,
	GLXFBConfig config, Window wnd, const int* attrl)
{
	TRACE("glXCreateWindow");
	return 0;
}

void glXDestroyContext(Display* dpy, GLXContext ctx)
{
	TRACE("glXDestroyContext");
}

void glXDestroyGLXPixmap(Display* dpy, GLXPixmap pix)
{
	TRACE("glXDestroyGLXPixmap");
}

void glXDestroyPbuffer(Display* dpy, GLXPbuffer pbuf)
{
	TRACE("glXDestroyPbuffer");
}

void glXDestroyPixmap(Display* dpy, GLXPixmap pix)
{
	TRACE("glXDestroyPixmap");
}

void glXDestroyWindow(Display* dpy, GLXWindow win)
{
	TRACE("glXDestroyWindow");
}

void glXFreeContextEXT(Display* dpy, GLXContext ctx)
{
	TRACE("glXFreeContext");
}

const char* glXGetClientString(Display* dpy, int name)
{
	TRACE("glXGetClientString(%d)", name);
	return "";
}

int glXGetConfig(Display* dpy, XVisualInfo* vis, int attr, int* val)
{
	TRACE("glXGetConfig(%d)", attr);
	*val = 0;
/*
 * some constants: GLX_USE_GL,
 * GLX_BUFFER_SIZE, GLX_LEVEL, GLX_RGBA..
 */
	return 0;
}

GLXContextID glXGetContextIDEXT(const GLXContext ctx)
{
	TRACE("glXGetContextIDEXT");
	return 0;
}

GLXContext glXGetCurrentContext()
{
	TRACE("glXGetCurrentContext");
	return 0;
}

Display* glXGetCurrentDisplay()
{
	TRACE("glXGetCurrentDisplay");
	return NULL;
}

GLXDrawable glXGetCurrentDrawable()
{
	TRACE("glXGetCurrentDrawable");
	return 0;
}

GLXDrawable glXGetCurrentReadDrawable()
{
	TRACE("glXGetCurrentReadDrawable");
	return 0;
}

int glXGetFBConfigAttrib(Display* dpy, GLXFBConfig cfg, int attr, int* val)
{
	TRACE("glXGetFBConfigAttrib");
	return 0;
}

GLXFBConfig* glXGetFBConfigs(Display* dpy, int screen, int* nelem)
{
	TRACE("glXGetFBConfig");
	return NULL;
}

void* glXGetProcAddress(const char* proc)
{
	TRACE("glXGetProcAddress(%s)", proc ? proc : "no proc");
	struct arcan_shmif_cont* con = arcan_shmif_primary(SHMIF_INPUT);
	return arcan_shmifext_headless_lookup(con, proc);
}

void* glXGetProcAddressARB(const char* proc)
{
	return glXGetProcAddress(proc);
}

void glXGetSelectedEvent(Display* dpy, GLXDrawable draw, unsigned long* mask)
{
	TRACE("glXGetSelectedEvent");
}

XVisualInfo* glXGetVisualFromFBConfig(Display* dpy, GLXFBConfig cfg)
{
	TRACE("glXGetVisualFromFBConfig");
	return NULL;
}

GLXContext glXImportContextEXT(Display* dpy, GLXContextID cid)
{
	TRACE("glXImportContextEXT");
	return 0;
}

bool glXIsDirect(Display* dpy, GLXContext ctx)
{
	TRACE("glXIsDirect");
	return true;
}

void glXMakeCurrent(Display* dpy,
	GLXDrawable draw, GLXDrawable read, GLXContext ctx)
{
	TRACE("glXMakeCurrent");
}

int glXQueryContext(Display* dpy, GLXContext ctx, int attr, int* val)
{
	TRACE("glXQueryContext");
	return 0;
}

int glxQueryContextInfoEXT(Display* dpy, GLXContext ctx, int attr, int* val)
{
	TRACE("glXQueryContextInfoEXT");
	return 0;
}

int glXQueryDrawable(Display* dpy, GLXDrawable draw, int attr, unsigned* val)
{
	TRACE("glXQueryDrawable");
/* width, height, preserved contents, largest pbuffer, fbconfig_id */
	return 0;
}

bool glXQueryExtension(Display* dpy, int* errb, int* evb)
{
	TRACE("glXQueryExtension");
	if (errb)
		*errb = 200;

	if (evb)
		*evb = 100;

	*evb = 0;
	return true;
}

const char* glXQueryExtensionsString(Display* dpy, int screen)
{
	TRACE("glXQueryExtensionsString");
	if (!dpy || !dpy->con.addr)
		return NULL;

	uintptr_t edisp;
	arcan_shmifext_egl_meta(&dpy->con, &edisp, NULL, NULL);
	return eglQueryString((EGLDisplay) edisp, EGL_EXTENSIONS);
}

const char* glXQueryServerString(Display* dpy, int screen, int name)
{
	TRACE("glXQueryServerString");
	return "";
}

bool glXQueryVersion(Display* dpy, int* maj, int* min)
{
	TRACE("glXQueryVersion");
	if (!dpy || !dpy->con.addr)
		return false;

	if (maj)
		*maj = 1;

	if (min)
		*min = 4;

	return true;
}

void glXSelectEvent(Display* dpy, GLXDrawable draw, unsigned long mask)
{
	TRACE("glXSelectEvent");
/* set the GLX event mask for pbuffer or window,
 * only used with GLX_PBUFFER_CLOBBER_MASK, just ignore. */
}

void glXSwapBuffers(Display* dpy, GLXDrawable draw)
{
	TRACE("glXSwapBuffers");
	uintptr_t display;
  if (!arcan_shmifext_egl_meta(&dpy->con, &display, NULL, NULL))
		return;

	glFlush();
	if (arcan_shmifext_eglsignal(&dpy->con, display,
		SHMIF_SIGVID, dpy->vstore.vinf.text.glid) >= 0)
		return;

	struct storage_info_t store = dpy->vstore;
	store.vinf.text.raw = dpy->con.vidp;
	agp_activate_rendertarget(NULL);
	agp_readback_synchronous(&store);

	arcan_shmif_signal(&dpy->con, SHMIF_SIGVID);
}

void glXUseXFont(Font font, int first, int count, int listb)
{
	TRACE("glXUseXFont");
/*
 * create bitmap display list from XFont, just ignore
 */
}

void glXWaitGL()
{
	TRACE("glXWaitGL");
/*
 * We'll always be on 'the same server' so the distinction doesn't help
 */
	glFinish();
}

void glXWaitX()
{
	TRACE("glXWaitX");
/*
 * Since we have no X rendering calls, this is void. Different scenario if
 * we expose a bytecode format and protocol for the _lua.c layer
 */
}

#endif

#ifdef WANT_WINE_FUNCTIONS
void* wine_dlsym(void* handle, const char* symbol, char* error, size_t errorsize)
{
	const char* err();
	struct symentry* syment = find_symbol(symbol);

	if (syment){
		return (syment->bounce ? syment->bounce : syment->ptr);
	} else;

/* s'ppose the calls are to flush lookup errors or something.. */
	dlerror(); dlerror();
	void* rv = dlsym(handle, symbol);
	dlerror();
	return rv;
}
#endif
