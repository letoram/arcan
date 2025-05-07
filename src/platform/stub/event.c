/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <unistd.h>

#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "event_platform.h"

void arcan_platform_event_setup(
	int (*event_enqueue_cb)(arcan_platform_evctx ctx, const struct arcan_event* const src))
{
}

void arcan_platform_event_samplebase(int devid, float xyz[3])
{
}

arcan_errc arcan_platform_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

void arcan_platform_event_analogall(bool enable, bool mouse)
{
}

int arcan_platform_event_translation(
	int devid, int action, const char** names, const char** err)
{
	*err = "Unsupported";
	return false;
}

int arcan_platform_event_device_request(int space, const char* path)
{
	return -1;
}

enum ARCAN_PLATFORM_EVENT_CAPABILITIES arcan_platform_event_capabilities(const char** out)
{
	if (out)
		*out = "stub";

	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH |
		ACAP_POSITION | ACAP_ORIENTATION;
}

void arcan_platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

void arcan_platform_event_process(arcan_platform_evctx ctx)
{
}

void arcan_platform_event_keyrepeat(arcan_platform_evctx ctx, int* rate, int* del)
{
}

void arcan_platform_event_rescan_idev(arcan_platform_evctx ctx)
{
}

const char* arcan_platform_event_devlabel(int devid)
{
	return NULL;
}

static char* envopts[] = {
	NULL
};

const char** arcan_platform_event_envopts()
{
	return (const char**) envopts;
}

void arcan_platform_event_deinit(arcan_platform_evctx ctx)
{
}

void arcan_platform_event_reset(arcan_platform_evctx ctx)
{
	arcan_platform_event_deinit(ctx);
}

void platform_device_lock(int devind, bool state)
{
}

void arcan_platform_event_preinit()
{
}

void arcan_platform_event_init(arcan_platform_evctx ctx)
{
}
