/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
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

