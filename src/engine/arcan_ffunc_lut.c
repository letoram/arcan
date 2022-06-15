/*
 * Copyright 2015-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <lua.h>

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
#include "arcan_ffunc_lut.h"
#include "arcan_vr.h"

#ifdef ARCAN_LWA
extern enum arcan_ffunc_rv arcan_lwa_ffunc FFUNC_HEAD;
#endif

/*
 * will be allocated / initialized once
 */
static arcan_vfunc_cb* f_lut;
extern int system_page_size;

static enum arcan_ffunc_rv fatal_ffunc FFUNC_HEAD
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

static enum arcan_ffunc_rv null_ffunc FFUNC_HEAD
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
	f_lut[FFUNC_NULLFEED] = arcan_frameserver_nullfeed;
	f_lut[FFUNC_LUA_PROC] = arcan_lua_proctarget;
	f_lut[FFUNC_3DOBJ] = arcan_ffunc_3dobj;
	f_lut[FFUNC_SOCKVER] = arcan_frameserver_verifyffunc;
	f_lut[FFUNC_SOCKPOLL] = arcan_frameserver_pollffunc;
	f_lut[FFUNC_VR] = arcan_vr_ffunc;

#ifdef ARCAN_LWA
	f_lut[FFUNC_LWA] = arcan_lwa_ffunc;
#else
	f_lut[FFUNC_LWA] = fatal_ffunc;
#endif

	mprotect(f_lut, system_page_size, PROT_READ);
}

int arcan_ffunc_register(arcan_vfunc_cb cb)
{
	int found = -1;

/* sweep the adressable range, look for one entry that is not 0 or
 * LWA and that references the fatal ffunc */
	for (size_t i = 1; i < 256; i++){
		if (f_lut[i] == fatal_ffunc && i != FFUNC_LWA){
			found = i;
			break;
		}
	}

/* out of space */
	if (found == -1)
		return -1;

/* protect against multiple register calls on the same function */
	for (size_t i = 0; i < 256; i++){
		if (f_lut[i] == cb)
			return i;
	}

/* register (need to unprotect) */
	mprotect(f_lut, system_page_size, PROT_READ | PROT_WRITE);
	f_lut[found] = cb;
	mprotect(f_lut, system_page_size, PROT_READ);

	return found;
}

arcan_vfunc_cb arcan_ffunc_lookup(ffunc_ind ind)
{
	return f_lut[ind];
}
