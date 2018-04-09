#include <stdlib.h>
#include <stdint.h>
#include "../egl-dri/libbacklight.h"

long backlight_get_brightness(struct backlight *backlight)
{
	return 1;
}

long backlight_get_max_brightness(struct backlight *backlight)
{
	return 1;
}

long backlight_get_actual_brightness(struct backlight *backlight)
{
	return 1;
}

long backlight_set_brightness(struct backlight *backlight, long brightness)
{
	return 0;
}

void backlight_destroy(struct backlight *backlight)
{
}

struct backlight *backlight_init(int card, int connector_type, int connector_type_id)
{
	return NULL;
}
