/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <sys/mman.h>

#define FRAMESERVER_PRIVATE
#define LUA_PRIVATE
#define A3D_PRIVATE

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_audio.h"
#include "arcan_general.h"
#include "arcan_event.h"

#include PLATFORM_HEADER
#include "arcan_video.h"
#include "arcan_frameserver.h"
#include "arcan_lua.h"
#include "arcan_3dbase.h"

/*
 * will be allocated / initialized once
 */
static arcan_vfunc_cb* f_lut;
extern int system_page_size;

static enum arcan_ffunc_rv fatal_ffunc(enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t buf_sz, uint16_t width, uint16_t height,
	unsigned mode, vfunc_state state)
{
/* avoid the possible infinite recursion in delete(broken ffunc)->
 * fatal->delete->... */
	static bool in_fatal;
	if (in_fatal)
		return FRV_NOFRAME;

	abort();
	in_fatal = true;
	arcan_fatal("ffunc_lut(), invalid index used in ffunc CB - \n"
		"\tinvestigate malicious activity or data corruption\n");

	return FRV_NOFRAME;
}

static enum arcan_ffunc_rv null_ffunc(enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t buf_sz, uint16_t width, uint16_t height,
	unsigned mode, vfunc_state state)
{
	return FRV_NOFRAME;
}

void arcan_ffunc_initlut()
{
/* recovery scripts might force this to be called multiple times */
	if (f_lut){
		munmap(f_lut, system_page_size);
		f_lut= NULL;
	}

	f_lut = mmap(NULL, system_page_size,
		PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);

	if (!f_lut)
		arcan_fatal("ffunc_lut() investigate memory issues");

	for (size_t i = 0; i < system_page_size / sizeof(arcan_vfunc_cb*); i++)
		f_lut[i] = fatal_ffunc;

	f_lut[FFUNC_NULL] = null_ffunc;

	f_lut[FFUNC_AVFEED] = arcan_frameserver_avfeedframe;
	f_lut[FFUNC_FEEDCOPY] = arcan_frameserver_feedcopy;
	f_lut[FFUNC_NULLFRAME] = arcan_frameserver_emptyframe;
	f_lut[FFUNC_VFRAME] = arcan_frameserver_vdirect;

	f_lut[FFUNC_LUA_PROC] = arcan_lua_proctarget;
	f_lut[FFUNC_3DOBJ] = arcan_ffunc_3dobj;
	f_lut[FFUNC_SOCKVER] = arcan_frameserver_socketverify;
	f_lut[FFUNC_SOCKPOLL] = arcan_frameserver_socketpoll;

	mprotect(f_lut, system_page_size, PROT_READ);
}

arcan_vfunc_cb arcan_ffunc_lookup(ffunc_ind ind)
{
	return f_lut[ind];
}
