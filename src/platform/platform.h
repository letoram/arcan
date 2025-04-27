/*
 * Copyright 2014-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * This file should define the generic types (and possibly header files) needed
 * for building / porting to a different platform. A working combination of all
 * platform/.h defined headers are needed for system integration.
 */
#ifndef HAVE_PLATFORM_HEADER
#define HAVE_PLATFORM_HEADER

#include <limits.h>
#include "platform_types.h"
#include "agp_platform.h"
#include "video_platform.h"
#include "audio_platform.h"
#include "fsrv_platform.h"
#include "os_platform.h"
#include "event_platform.h"

/*
 * Updated in the conductor stage with the latest known timestamp, Checked in
 * the platform/posix/psep_open and is used to either send SIGINT (first) then
 * if another timeout arrives, SIGKILL.
 *
 * The SIGINT is used in arcan_lua.c and used to trigger wraperr, which in turn
 * will log the event and rebuild the VM.
 *
 * This serves to protect against livelocks in general, but in particular for
 * the worst sinners, lua scripts getting stuck in while- loops from bad
 * programming, and complex interactions in the egl-dri platform.
 */
extern _Atomic uint64_t* volatile arcan_watchdog_ping;
#define WATCHDOG_ANR_TIMEOUT_MS 5000

/*
 * default, probed / replaced on some systems
 */
extern int system_page_size;

#endif
