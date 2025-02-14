// Single header for the whole Arcan libraries API

#include <stdio.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <limits.h>
#include <inttypes.h>

#include "arcan_shmif_event.h"
#include "arcan_shmif_control.h"

#ifdef BUILD_SHMIF
#include "arcan_shmif.h"
#include "arcan_shmif_control.h"
#include "arcan_shmif_interop.h"
#include "arcan_shmif_server.h"
#include "arcan_shmif_sub.h"
#endif // BUILD_SHMIF

#ifdef BUILD_TUI
#include "arcan_tuidefs.h"
#include "arcan_tuisym.h"
#include "arcan_tui.h"
#include "arcan_tui_bufferwnd.h"
#include "arcan_tui_linewnd.h"
#include "arcan_tui_listwnd.h"
#include "arcan_tui_readline.h"
#endif // BUILD_TUI

#ifdef BUILD_A12
#include "a12.h"
#endif // BUILD_A12
