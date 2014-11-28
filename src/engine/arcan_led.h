/*
 * Copyright 2003-2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_LED
#define _HAVE_ARCAN_LED

/* Only tested with (1) ultimarc pac-drive,
 * might be trivial to included more devices, but nothing to test with :/
 * at least added decent entry points so it should be easy to fix.
 */
typedef struct {
	int nleds;
	bool variable_brightness;
	bool rgb;
} led_capabilities;

/* Basic foreplay, any USB initialization needed, scanning for controllers,
 * can be called multiple times (rescan) ... */
void arcan_led_init();

/* try to forcibly load a specific LED controller
 * returns index if successfull, -1 otherwise. */
int arcan_led_forcecontroller(int vid, int pid);

/* Get the current number of controllers, use to set specific leds */
unsigned int arcan_led_controllers();

/* Set a specific lamp (or negative index, all of them)
 * to whatever is a fullbright state for that device */
bool arcan_led_set(uint8_t device, int8_t led);

/* Clear a specific lamp (or negative index, all of them)
 * to whatever is a fullbright state for that device */
bool arcan_led_clear(uint8_t device, int8_t led);

/* Set a specific lamp to a specific intensity */
bool arcan_led_intensity(uint8_t device, int8_t led, uint8_t intensity);

/* Set a specific lamp to a specific rgb */
bool arcan_led_rgb(uint8_t device, int8_t led, uint8_t, uint8_t g, uint8_t b);

/* Return how many leds are supported by a specific device */
led_capabilities arcan_led_capabilities(uint8_t device);

/* Free any USB resources lingering around,
 * might (might) be needed when launching a target externally that makes
 * direct use of the same usb device. */
void arcan_led_shutdown();
#endif

