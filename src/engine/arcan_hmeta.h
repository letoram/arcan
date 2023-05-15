#ifndef HAVE_ARCAN_HMETA
#define HAVE_ARCAN_HMETA

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <pthread.h>
#include <setjmp.h>
#include <assert.h>

#include <string.h>
#include <signal.h>
#include <fcntl.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>

#include <sys/resource.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>

#include <math.h>
#include <limits.h>
#include <errno.h>
#include <time.h>
#include <ctype.h>
#include <dlfcn.h>
#include <poll.h>

#include <sqlite3.h>
#include <lua.h>

#ifdef WITH_TRACY
#include "tracy/TracyC.h"
#endif

#include "getopt.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_audio.h"
#include "arcan_video.h"
#include "arcan_img.h"
#include "arcan_frameserver.h"
#include "arcan_lua.h"
#include "arcan_led.h"
#include "arcan_db.h"
#include "arcan_videoint.h"
#include "arcan_conductor.h"
#include "arcan_monitor.h"
#include "arcan_3dbase.h"
#include "arcan_renderfun.h"
#include "arcan_vr.h"

#endif
