#include <stdlib.h>
#include <stdint.h>
#include <assert.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <dev/wscons/wsconsio.h>
#include "platform.h"

#include "../egl-dri/libbacklight.h"

static int console_fd = -1;
static int backlight_ref = 0;

long backlight_get_brightness(struct backlight *backlight)
{
	if (!backlight || -1 == console_fd)
		return 1;

	struct wsdisplay_param disp = {
		.param = WSDISPLAYIO_PARAM_BRIGHTNESS
	};

	if (-1 == ioctl(console_fd, WSDISPLAYIO_GETPARAM, &disp))
		return 1;

	return disp.curval;
}

long backlight_get_max_brightness(struct backlight *backlight)
{
	if (!backlight || -1 == console_fd)
		return 1;

	struct wsdisplay_param disp = {
		.param = WSDISPLAYIO_PARAM_BRIGHTNESS
	};

	if (-1 == ioctl(console_fd, WSDISPLAYIO_GETPARAM, &disp))
		return 1;

	return disp.max;
}

long backlight_get_actual_brightness(struct backlight *backlight)
{
	return backlight_get_brightness(backlight);
}

long backlight_set_brightness(struct backlight *backlight, long brightness)
{
	if (!backlight || -1 == console_fd)
		return -1;

	struct wsdisplay_param disp = {
		.param = WSDISPLAYIO_PARAM_BRIGHTNESS,
		.curval = brightness
	};

	return ioctl(console_fd, WSDISPLAYIO_SETPARAM, &disp);
}

void backlight_destroy(struct backlight *backlight)
{
	if (!backlight)
		return;

	assert(backlight_ref > 0);
	backlight_ref--;

	if (backlight_ref == 0){
		close(console_fd);
		console_fd = -1;
	}

	free(backlight);
}

/*
 * current version just assumes backlight control over one display,
 * this is mainly to get laptops working where the backlight need is
 * more pressing.
 */
struct backlight *backlight_init(int card, int connector_type, int connector_type_id)
{
	if (-1 == console_fd)
		console_fd = platform_device_open("/dev/ttyC0", O_RDWR);

	if (-1 == console_fd)
		return NULL;

	struct backlight* ctx = malloc(sizeof(struct backlight));
	*ctx = (struct backlight){};

	backlight_ref++;
	return ctx;
}
