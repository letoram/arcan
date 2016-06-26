/*
 * No copyright claimed, Public Domain
 */

#ifndef HAVE_SDL12
#define HAVE_SDL12

SDL_GrabMode ARCAN_SDL_WM_GrabInput(SDL_GrabMode mode);
void ARCAN_target_shmsize(int w, int h, int bpp);
int ARCAN_SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained);
SDL_Surface* ARCAN_SDL_CreateRGBSurface(Uint32 flags, int width, int height,
	int depth, Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask);
SDL_Surface* ARCAN_SDL_SetVideoMode(int w, int h, int ncps, Uint32 flags);
int ARCAN_SDL_VideoInit(const char*, Uint32);
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
void build_forwardtbl();

struct hijack_fwdtbl {
	void (*sdl_swapbuffers)(void);
	SDL_Surface* (*sdl_setvideomode)(int, int, int, Uint32);
	int (*sdl_pollevent)(SDL_Event*);
	int (*sdl_waitevent)(SDL_Event*);
	int (*sdl_pushevent)(SDL_Event*);
	int (*sdl_peepevents)(SDL_Event*, int, SDL_eventaction, Uint32);
	int (*sdl_openaudio)(SDL_AudioSpec*, SDL_AudioSpec*);
	SDL_GrabMode (*sdl_grabinput)(SDL_GrabMode);
	int (*sdl_iconify)(void);
	void (*sdl_videoinit)(const char* driver, Uint32 flags);
	void (*sdl_updaterect)(SDL_Surface*, Sint32, Sint32, Uint32, Uint32);
	void (*sdl_updaterects)(SDL_Surface*, int, SDL_Rect*);
	int (*sdl_upperblit)(SDL_Surface *src, const SDL_Rect *srcrect,
		SDL_Surface *dst, SDL_Rect *dstrect);
	int (*sdl_flip)(SDL_Surface*);
	SDL_Surface* (*sdl_creatergbsurface)(Uint32, int, int,
		int, Uint32, Uint32, Uint32, Uint32);
	int (*audioproxy)(int, int);
	int (*sdl_starteventloop)(Uint32);
	void (*glLineWidth)(float);
	void (*glPointSize)(float);
	void (*glFinish)(void);
	void (*glFlush)(void);
};

#endif

