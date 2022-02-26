/* header-split to re-use shmif/tui/nbio* */

#define WANT_ARCAN_BASE

#include "alt/opaque.h"
#include "arcan_mem.h"
#include "platform.h"
#include "platform_types.h"
#include "os_platform.h"
#include "arcan_lua.h"
#include "alt/support.h"
#include "alt/types.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_shmif_sub.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_frameserver.h"
#include "arcan_conductor.h"
