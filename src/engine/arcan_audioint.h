/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_AUDIOINT
#define _HAVE_ARCAN_AUDIOINT

#include "platform_types.h"

void arcan_aid_refresh(arcan_aobj_id aid);

/* just a wrapper around alBufferData that takes monitors into account */
void arcan_audio_buffer(void* aobj, ssize_t buffer, void* abuf,
	size_t abuf_sz, unsigned channels, unsigned samplerate, void* tag);

#endif

