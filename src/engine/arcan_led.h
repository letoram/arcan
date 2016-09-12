/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef HAVE_ARCAN_LED
#define HAVE_ARCAN_LED

/*
 * set #define LED_STANDALONE and implement these three symbols
 * (default in arcan_event.c) to use this compilation unit for a
 * library or standalone software.
 *
 * [devid] is the identifier for the new led device
 * [refdev] is -1 or an identifier for an event/platform layer
 * device to which this led controller is coupled
 *
 * arcan_warning(const_char*, ...);
 */
void arcan_led_added(int devid, int refdev, const char* label);
void arcan_led_removed(int devid);

struct led_capabilities {
	int nleds;
	bool variable_brightness;
	bool rgb;
};

/* Initiate a rescan for supported LED controllers, can potentially
 * be called multiple times, both from the platform layer (though some
 * LED types there should be handled dynamically */
void arcan_led_init();

/*
 * Query if there's support for a specific usb device
 */
bool arcan_led_known(uint16_t vid, uint16_t pid);

/* Get the current allocation bitfield */
uint64_t arcan_led_controllers();

/* Set a specific led (or negative index, all of them)
 * to whatever is a fullbright state for that device */
int arcan_led_set(uint8_t device, int16_t led);

/* Clear a specific led (or negative index, all of them)
 * to whatever is a fullbright state for that device */
int arcan_led_clear(uint8_t device, int16_t led);

/* Set a specific led to a specific intensity */
int arcan_led_intensity(uint8_t device, int16_t led, uint8_t intensity);

/* Set a specific led to a specific rgb, if buffer is set the actual changes
 * should be deferred until a non-buffered update is set. For large numbers of
 * LEDs, this saves bandwidth with devices that require header/footer */
int arcan_led_rgb(uint8_t device,
	int16_t led, uint8_t, uint8_t g, uint8_t b, bool buffer);

/* Used internally by the platform- layers for handling additional devices,
 * uses a simple pipe- protocol for updating. Initial state is always clear.
 * Returns device ID or -1 on failure.
 * cmd_ch is expected to be a non-blocking writable descriptor
 * 2-byte protocol (cmd, val):
 * 'A' (   ) - set active led to ALL
 * 'a' (ind) - set active index to ind
 * 'r' (val) - set subchannel R value
 * 'g' (val) - set subchannel G value
 * 'b' (val) - set subchannel B value
 * 'i' (val) - set subchannel ALL value (intensity)
 * 'c' (buf) - commit, update the set led or if buf is !0, queue
 * 'o'       - deregistered, write end will be closed.
 *
 * [cmd_ch] is a writable file descriptor (non-blocking)
 * [devref] is a caller defined reference device (or -1)
 */
int8_t arcan_led_register(int cmd_ch, int devref,
	const char* label, struct led_capabilities);

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
