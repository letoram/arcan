#define WANT_ARCAN_SHMIF_HELPER
#include <arcan_shmif.h>
#include <X11/Xlib.h>
#include <dlfcn.h>

/* #define WANT_GLX_FUNCTIONS */

/*
 * We also need to grab dlsym() to intercept calls that would look for
 * glx- dynamically. GLEW is often built to do that.
 */
/* #define GRAB_DLFCN */

/*
 * This library maps the common X* symbols to corresponding arcan_shmif calls
 * or stubs. It's intended for 'quick and dirty' legacy workarounds in cases
 * where a VM may be too cumbersome. Most functions are stubs, and filled out
 * as needed over time - the aim is not a complete implementation, but just
 * enough for some side-cases, e.g. when xcb/X/GLX comes as a parasitic
 * dependency rather than a desired one. Incidentally, some kbd/mouse games
 * that don't use a wrapper li
 */

#ifdef WANT_X_FUNCTIONS
/* Painful list of functions .. */
#endif

#ifdef WANT_XCB_FUNCTIONS
int xcb_flush(xcb_connection_t* c)
{
/* buffered output to server */
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
/*
 * A buffer so we can notify if anything actually is written to/from it
 */
static int junkptr[4096];
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
	return (XVisualInfo*) junk;
}

GLXContext glXCreateContext(Display* dpy,
	XVisualInfo* vis, GLXContext list, bool direct)
{
}

GLXPixmap glXCreateGLXPixmap(Display* dpy, XVisualInfo* vis, Pixmap pixmap)
{
}

GLXContext glXCreateNewContext(Display* dpy,
	GLXFBConfig cfg, int, GLXContext slist, bool direct)
{
}
i
GLXPbuffer glXCreatePbuffer(Display* dpy,
	GLXFBConfig config, const int *attrl)
{
}

GLXPixmap glXCreatePixmap(Display* dpy,
	GLXFBConfig cfg, Pixmap pmap, const int* attrl)
{
}

GLXWindow glXCreateWindow(Display* dpy,
	GLXFBConfig config, Window wnd, const int* attrl)
{
}

void glXDestroyContext(Display* dpy, GLXContext ctx)
{
}

void glXDestroyGLXPixmap(Display* dpy, GLXPixmap pix)
{
}

void glXDestroyPbuffer(Display GLXPbuffer pbuf)
{
}

void glXDestroyPixmap(Display* dpy, GLXPixmap pix)
{
}

void glXDestroyWindow(Display* dpy, GLXWindow win)
{
}

void glXFreeContextEXT(Display* dpy, GLXContext ctx)
{
}

const char* glXGetClientString(Display* dpy, int name)
{
	TRACE("glXGetClientString");
	switch (name){
	case GLX_VENDOR:
		return "doesnt_matter";
	break;
	case GLX_VERSION:
		return "1.4 faux-pas";
	break;
	case GLX_EXTENSIONS:
	default:
		return "";
	break;
	}
	return "";
}

int glXGetConfig(Display* dpy, XVisualInfo* vis, int attr, int* val)
{
	TRACE("glXGetConfig(%d)", attr);
	*val = 0;
	return GLX_BAD_ATTRIBUTE;
}

GLXContextID glXGetContextIDEXT(const GLXContext ctx)
{
	TRACE("glXGetContextIDEXT");
	return 0;
}

GLXContext glXGetCurrentContext()
{
	TRACE("glXGetCurrentContext");
}

Display* glXGetCurrentDisplay()
{
	return NULL;
}

GLXDrawable glXGetCurrentDrawable()
{
}

GLXDrawable glXGetCurrentReadDrawable()
{
}

int glXGetFBConfigAttrib(Display* dpy, GLXFBConfig cfg, int attr, int* val)
{
}

GLXFBConfig* glXGetFBConfigs(Display* dpy, int screen, int* nelem)
{
}

void(*)() glXGetProcAddress glXGetProcAddress(const uint8_t* procName)
{
	return NULL;
}

void glXGetSelectedEvent(Display* dpy, GLXDrawable draw, unsigned long* mask)
{
}

XVisualInfo* glXGetVisualFromFBConfig(Display* dpy, GLXFBConfig cfg)
{
}

GLXContext glXImportContextEXT(Display* dpy, GLXContextID cid)
{
}

bool glXIsDirect(Display* dpy, GLXContext ctx)
{
	return true;
}

void glXMakeContextCurrent(Display* dpy,
	GLXDrawable draw, GLXDrawable read, GLXContext ctx)
{
}

int glXQueryContext(Display* dpy, GLXContext ctx, int attr, int* val)
{
}

int glxQueryContextInfoEXT(Display* dpy, GLXContext ctx, int attr, int* val)
{
}

int glXQueryDrawable(Display* dpy, GLXDrawable draw, int attr, unsigned* val)
{
/* width, height, preserved contents, largest pbuffer, fbconfig_id */
	return 0;
}

bool glXQueryExtension(Display* dpy, int* errb, int* evb)
{
	*errb = 0;
	*evb = 0;
	return true;
}

const char* glXQueryExtensionsString(Display* dpy, int screen)
{
}

const char* glXQueryServerString(Display* dpy, int screen, int name)
{
}

bool glXQueryVersion(Display* dpy, int* maj, int* min)
{
	return false;
}

void glXSelectEvent(Display* dpy, GLXDrawable draw, unsigned long mask)
{
}

void glXSwapBuffers(Display* dpy, GLXDrawable draw)
{
/* signal on segment associated with draw? */
}

void glXUseXFont(Font font, int first, int count, int listb)
{
}

void glXWaitGL()
{
}

void glXWaitX()
{
}

#endif

