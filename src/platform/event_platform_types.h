#ifndef HAVE_EVENT_PLATFORM_TYPES
#define HAVE_EVENT_PLATFORM_TYPES

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

#include "../shmif/arcan_shmif_event.h"

/*
 * Some platforms can statically/dynamically determine what kinds of events
 * they are capable of emitting. This is helpful when determining what input
 * mode to expect (window manager that requires translated inputs and waits
 * because none are available
 */
enum ARCAN_PLATFORM_EVENT_CAPABILITIES {
	ACAP_TRANSLATED = 1,
	ACAP_MOUSE = 2,
	ACAP_GAMING = 4,
	ACAP_TOUCH = 8,
	ACAP_POSITION = 16,
	ACAP_ORIENTATION = 32,
	ACAP_EYES = 64
};

typedef int8_t arcan_errc;
typedef void *arcan_platform_evctx;

enum ARCAN_ANALOGFILTER_KIND {
	ARCAN_ANALOGFILTER_NONE = 0,
	ARCAN_ANALOGFILTER_PASS = 1,
	ARCAN_ANALOGFILTER_AVG  = 2,
	ARCAN_ANALOGFILTER_FORGET = 3,
 	ARCAN_ANALOGFILTER_ALAST = 4
};

// #include "platform_types.h"

#endif
