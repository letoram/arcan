/*
 * Copyright 2015-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 *
 * Description: This header is included as part of video.h but involves the Lua
 * layer, the frameservers and the 3d path as well. The approach is to avoid
 * the use of direct callbacks and instead use an 8-bit read-only indexed
 * lookup-table of pre-registered functions.
 */

#ifndef _HAVE_ARCAN_FFUNC_LUT
#define _HAVE_ARCAN_FFUNC_LUT

/*
 * all permitted ffuncs should be added to this enum and then explicitly mapped
 * in the underlying _ffunc_lut.c file in initlut()
 */
enum arcan_ffunc {
/* arcan_ffunc_lut.c */
	FFUNC_FATAL = 0,
	FFUNC_NULL  = 1,

/* arcan_frameserver.c */
	FFUNC_AVFEED,
	FFUNC_NULLFEED,
	FFUNC_FEEDCOPY,
	FFUNC_VFRAME,
	FFUNC_NULLFRAME,

/* arcan_lua.c */
	FFUNC_LUA_PROC,

/* arcan_3dbase.c */
	FFUNC_3DOBJ,

/* platform/arcan/video.c */
	FFUNC_LWA,

/* arcan_vr.c */
	FFUNC_VR,

/* defined in frameserver.h, implemented in platform */
	FFUNC_SOCKVER,
	FFUNC_SOCKPOLL
};

/*
 * Prototype and enumerations for frameserver- and other dynamic data sources
 */

enum arcan_ffunc_cmd {
	FFUNC_POLL    = 0, /* every frame, check for new data */
	FFUNC_RENDER  = 1, /* follows a GOTFRAME returning poll */
	FFUNC_TICK    = 2, /* logic pulse */
	FFUNC_DESTROY = 3, /* custom cleanup */
	FFUNC_READBACK= 4, /* recordtargets, when a readback is ready */
	FFUNC_READBACK_HANDLE = 5, /* accelerated form */
	FFUNC_ADOPT   = 6, /* outside context */
};

enum arcan_ffunc_rv {
	FRV_NOFRAME  = 0,
	FRV_GOTFRAME = 1, /* ready to transfer a frame to the object       */
	FRV_COPIED   = 2, /* means that the local storage has been updated */
	FRV_NOUPLOAD = 64 /* don't synch local storage with GPU buffer     */
};

typedef struct vfunc_state {
	volatile int tag;
	void* ptr;
} vfunc_state;

typedef uint8_t ffunc_ind;

/*
 * This is used in the defined prototypes and the defined implementation for
 * each ffunc to ensure system name use and trigger compile errors if we ever
 * need to change the prototype as the behavior is sensitive, e.g.
 * enum arcan_ffunc_rv ffunc_name FFUNC_HEAD; for prototype and
 * enum arcan_ffunc_rv ffunc_name FFUNC_HEAD { } for implementation
 */
#define FFUNC_HEAD (enum arcan_ffunc_cmd cmd,\
	av_pixel* buf, size_t buf_sz, uint16_t width, uint16_t height,\
	unsigned mode, vfunc_state state, arcan_vobj_id srcid)

typedef enum arcan_ffunc_rv(*arcan_vfunc_cb) FFUNC_HEAD;
void arcan_ffunc_initlut();

arcan_vfunc_cb arcan_ffunc_lookup(ffunc_ind);

/*
 * Extend feed function lookup table with a custom entry, this will
 * return an index that can be used to reference this function and
 * will resolve on arcan_ffunc_lookup.
 *
 * Returns -1 if there are no free slots.
 *
 * Use this function cautiously as it affects which functions that
 * are within simple reach from a sensitive context (frameserver
 * struct evaluation, ...)
 */
int arcan_ffunc_register(arcan_vfunc_cb);

#endif
