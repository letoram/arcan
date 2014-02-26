#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include <GLES2/gl2.h>
#include <EGL/egl.h>

static struct {
	EGLDisplay disp;
	EGLContext ctx;
	EGLSurface surf;
	EGLConfig cfg;
	EGLNativeWindowType wnd;
} egl;

#ifdef RPI_BCM
#include <bcm_host.h>
bool alloc_bcm_wnd()
{
	bcm_host_init();

	DISPMANX_ELEMENT_HANDLE_T elem;
	DISPMANX_DISPLAY_HANDLE_T disp;
	DISPMANX_UPDATE_HANDLE_T upd;

  int dw;
  int dh;

  if (graphics_get_display_size(0, &dw, &dh) < 0){
		return false;					
  }
  
	VC_RECT_T ddst = {
		.x = 0,
		.y = 0
	};

	VC_RECT_T dsrc = {
		.x = 0,
		.y = 0
	};

	dw = 640;
	dh = 480;

	ddst.width = dw;
	ddst.height = dh;

	dsrc.width = ddst.width << 16;
	dsrc.height = ddst.height << 16;

	disp = vc_dispmanx_display_open(0); 
	upd = vc_dispmanx_update_start(0);
	elem = vc_dispmanx_element_add(upd, disp,
		0, /* layer */
		&ddst,
		0,
		&dsrc,
		DISPMANX_PROTECTION_NONE,
		0 /* alpha */,
		0 /* clamp */,
		0 /*transform */);

	static EGL_DISPMANX_WINDOW_T wnd = {0};
	wnd.element = elem;
	wnd.width = dw;
	wnd.height = dh;
   
	vc_dispmanx_update_submit_sync(upd); 
	egl.wnd = &wnd;

	return true;
}

#endif

void platform_video_bufferswap()
{
	eglSwapBuffers(egl.disp, egl.surf);
}

bool platform_video_init(uint16_t w, uint16_t h, uint8_t bpp, bool fs,
	bool frames)
{
	EGLint ca[] = { 
		EGL_CONTEXT_CLIENT_VERSION, 2, 
		EGL_NONE, 
		EGL_NONE 
	};

	EGLint attrlst[] = {
		EGL_RED_SIZE, 5,
		EGL_GREEN_SIZE, 6,
		EGL_BLUE_SIZE, 5,
		EGL_ALPHA_SIZE, EGL_DONT_CARE,
		EGL_DEPTH_SIZE, 8,
		EGL_STENCIL_SIZE, 8,
		EGL_SAMPLE_BUFFERS, 0,
		EGL_NONE
	};

	EGLint nc;

#ifdef RPI_BCM
	alloc_bcm_wnd();
#endif

	egl.disp = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	EGLint major, minor;
	eglInitialize(egl.disp, &major, &minor);
	eglGetConfigs(egl.disp, NULL, 0, &nc);
	eglChooseConfig(egl.disp, attrlst, &egl.cfg, 1, &nc);
	egl.surf = eglCreateWindowSurface(egl.disp, egl.cfg, egl.wnd, NULL);
	egl.ctx = eglCreateContext(egl.disp, egl.cfg, EGL_NO_CONTEXT, ca);
	eglMakeCurrent(egl.disp, egl.surf, egl.surf, egl.ctx);

	return true;
}

void platform_video_prepare_external()
{}

void platform_video_restore_external()
{}

void platform_video_shutdown()
{}

void platform_video_timing(float* vsync, float* stddev, float* variance)
{
	*vsync = 16.667;
	*stddev = 0.01;
	*variance = 0.01;
}

void platform_video_minimize()
{
}
