#ifndef LIBBACKLIGHT_H
#define LIBBACKLIGHT_H

#ifdef __cplusplus
extern "C" {
#endif

enum backlight_type {
	BACKLIGHT_RAW,
	BACKLIGHT_PLATFORM,
	BACKLIGHT_FIRMWARE,
};

struct backlight {
	char *path;
	int max_brightness;
	int brightness;
	enum backlight_type type;
};

/*
 * Find and set up a backlight for the given card/connector combination.
 */
struct backlight *backlight_init(int card, int connector_type, int connector_type_id);

/* Free backlight resources */
void backlight_destroy(struct backlight *backlight);

/* Provide the maximum backlight value */
long backlight_get_max_brightness(struct backlight *backlight);

/* Provide the cached backlight value */
long backlight_get_brightness(struct backlight *backlight);

/* Provide the hardware backlight value */
long backlight_get_actual_brightness(struct backlight *backlight);

/* Set the backlight to a value between 0 and max */
long backlight_set_brightness(struct backlight *backlight, long brightness);

#ifdef __cplusplus
}
#endif

#endif /* LIBBACKLIGHT_H */
