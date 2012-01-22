/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include "hidapi/hidapi.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_led.h"

#ifndef MAX_LED_CONTROLLERS
#define MAX_LED_CONTROLLERS 8
#endif

/* to add more devices,
 * 1. patch in the type in the enum.
 * 2. add a constant for corresponding VID/PID,
 *    or alter the init function to actually scan for it and if found, forcecontroller (get the returned index and patch type).
 * 3. add the corresponding enum to the switch in set/unset */

enum controller_types {
	NONE = 0,
	ULTIMARC_PACDRIVE = 1
};

struct led_controller {
	enum controller_types type;
	hid_device* handle;
	uint16_t ledmask;
};

const int ULTIMARC_VID = 0xd209;
const int ULTIMARC_PID = 0x1500; /* 1501 .. 1508 */

static struct led_controller controllers[MAX_LED_CONTROLLERS] = {0};
int n_controllers = 0;

int arcan_led_forcecontroller(int vid, int pid)
{
	if (n_controllers == MAX_LED_CONTROLLERS)
		return -1;

	controllers[n_controllers].handle = hid_open(vid, pid, NULL);
	controllers[n_controllers].type = ULTIMARC_PACDRIVE;

	if (controllers[n_controllers].handle == NULL)
		return -1;
	else
		return n_controllers++;
}

void arcan_led_init()
{
	if (n_controllers > 0)
		arcan_led_cleanup();

	/* pacdrive scan */
	for (int i= 0; i < MAX_LED_CONTROLLERS && i < 8 && n_controllers < MAX_LED_CONTROLLERS; i++)
		arcan_led_forcecontroller(ULTIMARC_VID, ULTIMARC_PID + i);
}

unsigned int arcan_led_controllers()
{
	return n_controllers;
}

/* for the pacdrive, at least,
 * each bit set represents a led (thus 16 possible leds / device) */
bool arcan_led_set(uint8_t device, int8_t led)
{
	bool rv = false;
	unsigned char dbuf[5] = {0};

	if (n_controllers > 0 && device < n_controllers)
		switch (controllers[device].type) {
			case ULTIMARC_PACDRIVE:
				if (led < 0)
					controllers[device].ledmask = 0xffff;
				else
					controllers[device].ledmask |= 1 << led;

				dbuf[2] = 0xdd;
				dbuf[3] = (char) controllers[device].ledmask;
				dbuf[4] = (char)(controllers[device].ledmask >> 8) & 0xff;
				hid_write(controllers[device].handle, dbuf, sizeof(dbuf) / sizeof(dbuf[0]));

				break;

			default:
				arcan_warning("Warning: arcan_led_set(), unknown LED controller type: %i\n", controllers[device].type);
		}

	return rv;
}

bool arcan_led_clear(uint8_t device, int8_t led)
{
	bool rv = false;
	unsigned char dbuf[5] = {0};

	if (n_controllers > 0 && device < n_controllers)
		switch (controllers[device].type) {
			case ULTIMARC_PACDRIVE:
				if (led < 0)
					controllers[device].ledmask = 0x0000;
				else
					controllers[device].ledmask &= ~(1 << led);

				dbuf[2] = 0xdd;
				dbuf[3] = (char)(controllers[device].ledmask);
				dbuf[4] = (char)((controllers[device].ledmask >> 8) & 0xff);

				hid_write(controllers[device].handle, dbuf, sizeof(dbuf) / sizeof(dbuf[0]));
				break;

			default:
				arcan_warning("Warning: arcan_led_unset(), unknown LED controller type: %i\n", controllers[device].type);
		}

	return rv;
}

bool arcan_led_intensity(uint8_t device, int8_t led, uint8_t intensity)
{
	bool rv = false;

	if (n_controllers > 0 && device < n_controllers)
		switch (controllers[device].type) {
			case ULTIMARC_PACDRIVE:
				/* doesn't support this feature */

			default:
				arcan_warning("Warning: arcan_led_intensity(), unknown LED / unsupported mode for device type: %i\n", controllers[device].type);
		}

	return rv;
}

bool arcan_led_rgb(uint8_t device, int8_t led, uint8_t r, uint8_t g, uint8_t b)
{
	bool rv = false;

	if (n_controllers > 0 && device < n_controllers)
		switch (controllers[device].type) {
			case ULTIMARC_PACDRIVE:
				/* doesn't support this feature */

			default:
				arcan_warning("Warning: arcan_led_rgb(), unknown LED / unsupported mode for device type: %i\n", controllers[device].type);
		}

	return rv;
}


led_capabilities arcan_led_capabilities(uint8_t device)
{
	led_capabilities rv = {0};

	if (n_controllers > device) {
		switch (controllers[device].type) {
			case ULTIMARC_PACDRIVE:
				rv.nleds = 16;
				rv.variable_brightness = false;
				rv.rgb = false;
				break;

			default:
				arcan_warning("Warning: arcan_led_capabilities(), unknown LED controller type: %i\n", controllers[device].type);
				break;
		}
	}

	return rv;
}


void arcan_led_cleanup()
{
	for (int i = 0; i < n_controllers; i++)
		hid_close(controllers[i].handle);

	n_controllers = 0;
}
