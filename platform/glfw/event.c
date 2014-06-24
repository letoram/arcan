#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

#include "../../arcan_math.h"
#include "../../arcan_general.h"
#include "../../arcan_event.h"

struct axis_opts {
/* none, avg, drop */
	enum ARCAN_ANALOGFILTER_KIND mode;
	enum ARCAN_ANALOGFILTER_KIND oldmode;

	int lower, upper, deadzone;

	int kernel_sz;
	int kernel_ofs;
	int32_t flt_kernel[64];
};

static struct {
		struct axis_opts mx, my,
			mx_r, my_r;

		bool sticks_init;
		unsigned short n_joy;
		struct arcan_stick* joys;
} iodev = {0};

struct arcan_stick {
/* if we can get a repeatable identifier to expose
 * to higher layers in order to retain / track settings
 * for a certain device, put that here */
	char label[256];
	SDL_Joystick* handle;

	unsigned long hashid;

	unsigned short devnum;
	unsigned short axis;

/* these map to digital events */
	unsigned short buttons;
	unsigned short balls;

	unsigned* hattbls;
	unsigned short hats;

	struct axis_opts* adata;
};

arcan_errc arcan_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
	return ARCAN_ERRC_NO_SUCH_OBJECT;
}

void arcan_event_analogall(bool enable, bool mouse)
{
}

void arcan_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

static unsigned long djb_hash(const char* str)
{
	unsigned long hash = 5381;
	int c;

	while ((c = *(str++)))
		hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

	return hash;
}

const char* arcan_event_devlabel(int devid)
{
	return "no device";
}

void platform_event_process(arcan_evctx* ctx)
{
}

void arcan_event_rescan_idev(arcan_evctx* ctx)
{
}

void platform_key_repeat(arcan_evctx* ctx, unsigned int rate)
{
}

void platform_event_deinit(arcan_evctx* ctx)
{
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_init(arcan_evctx* ctx)
{
}

