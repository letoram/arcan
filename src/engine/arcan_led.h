/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef HAVE_ARCAN_LED
#define HAVE_ARCAN_LED

struct led_capabilities {
	int nleds;
	bool variable_brightness;
	bool rgb;
};

/* Initiate a rescan for supported LED controllers, can potentially
 * be called multiple times, both from the platform layer (though some
 * LED types there should be handled dynamically */
void arcan_led_init();

/* Get the current number of controllers, use to set specific leds */
unsigned int arcan_led_controllers();

/* Set a specific led (or negative index, all of them)
 * to whatever is a fullbright state for that device */
bool arcan_led_set(uint8_t device, int8_t led);

/* Clear a specific led (or negative index, all of them)
 * to whatever is a fullbright state for that device */
bool arcan_led_clear(uint8_t device, int8_t led);

/* Set a specific led to a specific intensity */
bool arcan_led_intensity(uint8_t device, int8_t led, uint8_t intensity);

/* Set a specific led to a specific rgb */
bool arcan_led_rgb(uint8_t device, int8_t led, uint8_t, uint8_t g, uint8_t b);

/* Used internally by the platform- layers for handling additional devices,
 * uses a simple pipe- protocol for updating. Initial state is always clear.
 * Returns device ID or -1 on failure.
 * cmd_ch is expected to be a non-blocking writable descriptor
 * 2-byte protocol (cmd, val):
 * [255 ind means apply to all]
 * 'r' (ind) - switch_subled_r
 * 'g' (ind) - switch_subled_g
 * 'b' (ind) - switch_subled_b
 * 'a' (ind) - switch_subled_rgba
 * 'i' (val) - set intensity (0 = off, 255 = full),
 *             implementation expected to normalize
 * 'o'       - deregistered, write end will be closed. */
int8_t arcan_led_register(int cmd_ch, const char* label,
	struct led_capabilities);

/*
 * Applicable to a LED controller that has been registered through
 * arcan_led_register, returns true if it was successfully removed.
 */
bool arcan_led_remove(uint8_t device);

/* Return the set of capabilities that a specific led device supports */
struct led_capabilities arcan_led_capabilities(uint8_t device);

/*
 * Free any USB resources lingering around, might (might) be needed when
 * launching a target externally that makes direct use of the same usb device.
 */
void arcan_led_shutdown();
#endif
