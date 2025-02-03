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

void platform_event_samplebase(int devid, float xyz[3])
{
}

arcan_errc platform_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

void platform_event_analogall(bool enable, bool mouse)
{
}

int platform_event_translation(
	int devid, int action, const char** names, const char** err)
{
	*err = "Unsupported";
	return false;
}

int platform_event_device_request(int space, const char* path)
{
	return -1;
}

enum PLATFORM_EVENT_CAPABILITIES platform_event_capabilities(const char** out)
{
	if (out)
		*out = "stub";

	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH |
		ACAP_POSITION | ACAP_ORIENTATION;
}

void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

void platform_event_process(struct arcan_evctx* ctx)
{
}

void platform_event_keyrepeat(struct arcan_evctx* ctx, int* rate, int* del)
{
}

void platform_event_rescan_idev(struct arcan_evctx* ctx)
{
}

const char* platform_event_devlabel(int devid)
{
	return NULL;
}

static char* envopts[] = {
	NULL
};

const char** platform_event_envopts()
{
	return (const char**) envopts;
}

void platform_event_deinit(struct arcan_evctx* ctx)
{
}

void platform_event_reset(struct arcan_evctx* ctx)
{
	platform_event_deinit(ctx);
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_preinit()
{
}

void platform_event_init(struct arcan_evctx* ctx)
{
}
