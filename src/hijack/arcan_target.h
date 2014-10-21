/*
 * Used within the arcan_target.c / arcan_target_platform.c
 * parts of the hijack library.
 *
 * Just a list of "forward functions" for symbols that should be hijacked
 * and a table that maintains the original function pointers
 */

#ifndef _HAVE_ARCAN_TARGET
#define _HAVE_ARCAN_TARGET

/* prototypes matching arcan_target.c */
SDL_GrabMode ARCAN_SDL_WM_GrabInput(SDL_GrabMode mode);
void ARCAN_target_init();
void ARCAN_target_shmsize(int w, int h, int bpp);
int ARCAN_SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained);
SDL_Surface* ARCAN_SDL_CreateRGBSurface(Uint32 flags, int width, int height,
	int depth, Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask);
SDL_Surface* ARCAN_SDL_SetVideoMode(int w, int h, int ncps, Uint32 flags);
int ARCAN_SDL_PollEvent(SDL_Event* inev);
int ARCAN_SDL_Flip(SDL_Surface* screen);
void ARCAN_SDL_UpdateRect(SDL_Surface* screen,
	Sint32 x, Sint32 y, Uint32 w, Uint32 h);
void ARCAN_SDL_UpdateRects(SDL_Surface* screen,
	int numrects, SDL_Rect* rects);
int ARCAN_SDL_UpperBlit(SDL_Surface* src, const SDL_Rect* srcrect,
	SDL_Surface *dst, SDL_Rect *dstrect);
void ARCAN_SDL_GL_SwapBuffers();
void ARCAN_glFinish();
void ARCAN_glFlush();

#ifdef ENABLE_X11_HIJACK
int ARCAN_XNextEvent(Display* disp, XEvent* ev);
int ARCAN_XPeekEvent(Display* disp, XEvent* ev);
Bool ARCAN_XGetEventData(Display* display, XGenericEventCookie* event);
void ARCAN_glXSwapBuffers (Display *dpy, GLXDrawable drawable);
Bool ARCAN_XQueryPointer(Display* display, Window w,
	Window* root_return, Window* child_return, int* rxret,
	int* ryret, int* wxret, int* wyret, unsigned* maskret);
int ARCAN_XCheckIfEvent(Display *display, XEvent *event_return,
	Bool (*predicate)(Display*, XEvent*, XPointer), XPointer arg);
Bool ARCAN_XFilterEvent(XEvent* ev, Window m);
#endif

struct hijack_fwdtbl {
/* SDL */
	void (*sdl_swapbuffers)(void);
	SDL_Surface* (*sdl_setvideomode)(int, int, int, Uint32);
	int (*sdl_pollevent)(SDL_Event*);
	int (*sdl_pushevent)(SDL_Event*);
	int (*sdl_peepevents)(SDL_Event*, int, SDL_eventaction, Uint32);
	int (*sdl_openaudio)(SDL_AudioSpec*, SDL_AudioSpec*);
	SDL_GrabMode (*sdl_grabinput)(SDL_GrabMode);
	int (*sdl_iconify)(void);
	void (*sdl_updaterect)(SDL_Surface*, Sint32, Sint32, Uint32, Uint32);
	void (*sdl_updaterects)(SDL_Surface*, int, SDL_Rect*);
	int (*sdl_upperblit)(SDL_Surface *src, const SDL_Rect *srcrect,
		SDL_Surface *dst, SDL_Rect *dstrect);
	int (*sdl_flip)(SDL_Surface*);
	SDL_Surface* (*sdl_creatergbsurface)(Uint32, int, int,
		int, Uint32, Uint32, Uint32, Uint32);
	int (*audioproxy)(int, int);

	void (*glLineWidth)(float);
	void (*glPointSize)(float);
	void (*glFinish)(void);
	void (*glFlush)(void);

#ifdef ENABLE_X11_HIJACK
	XVisualInfo* (*glXChooseVisual)(Display* dpy, int screen, int* attribList);
	Window (*XCreateWindow)(Display* display, Window parent,
		int x, int y, unsigned int width,
		unsigned int height, unsigned int border_width,
		int depth, unsigned int class, Visual* visual,
		unsigned long valuemask, XSetWindowAttributes* attributes);

	Window (*XCreateSimpleWindow)(Display* display, Window parent,
		int x, int y, unsigned int width, unsigned int height,
		unsigned int border_width,
		unsigned long border, unsigned long background);

	void* (*glXGetProcAddress)(const GLubyte* name);

	Bool (*XQueryPointer)(Display* display, Window w,
		Window* root_return, Window* child_return, int* rxret,
		int* ryret, int* wxret, int* wyret, unsigned* maskret);
	Bool (*XGetEventData)(Display*, XGenericEventCookie*);
	int (*XCheckIfEvent)(Display*, XEvent*, Bool (*predicate)(), XPointer);
	Bool (*XFilterEvent)(XEvent*, Window);
	int (*XNextEvent)(Display*, XEvent*);
	int (*XPeekEvent)(Display*, XEvent*);

/* could take the CheckMaskEvent, CheckTypedEvent etc.
 * as well as we're just filtering input */

	void (*glXSwapBuffers)(Display *dpy, GLXDrawable drawable);
#endif
};

#endif

