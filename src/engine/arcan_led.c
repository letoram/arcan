/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: LED controller interface, originally just written
 * as a hack to get ultimarc- style controller working and has since been
 * expanded to allow platform- layer to register custom controllers
 * to handle things like laptop display backlight
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include <sys/types.h>
#include <unistd.h>

#ifdef USB_SUPPORT
#include <hidapi/hidapi.h>
#else
	typedef struct hid_device hid_device;
#endif

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_led.h"
#include "arcan_shmif.h"
#include "arcan_event.h"

/* to add more device types,
 * 1. patch in the type in the controller_types enum.
 * 2. for usb-devices, add a vid/pid to type mapping in the usb_tbl
 *    or alter the init function to actually scan for it and if found,
 *    forcecontroller (get the returned index and patch type).
 * 3. modify the places marked as PROTOCOL INSERTION POINT
 */
enum controller_types {
	ULTIMARC_PACDRIVE = 1,
	ARCAN_LEDCTRL = 2
};

struct led_controller {
	enum controller_types type;
	struct led_capabilities caps;
	uint64_t devid;

	union {
	hid_device* handle;
	int fd;
	};
	uint16_t ledmask;
};

struct usb_ent {
	uint16_t vid, pid;
	enum controller_types type;
	struct led_capabilities caps;
};

/* one of the C fuglyness, static const struct led_capabilities paccap would
 * still yield that the initialization is not constant */
#define paccap { .variable_brightness = false, .rgb = false, .nleds = 32 }
static const struct usb_ent usb_tbl[] =
{
	{.vid = 0xd209, .pid = 0x1500, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1501, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1502, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1503, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1504, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1505, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1506, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1507, .type = ULTIMARC_PACDRIVE, .caps = paccap},
	{.vid = 0xd209, .pid = 0x1508, .type = ULTIMARC_PACDRIVE, .caps = paccap}
};
#undef paccap

/*
 * not worth spending time on dynamic array management,
 * just limit to 64, have index % 64 to skip overflow checks
 */
#define MAX_LED_CONTROLLERS 64
static struct led_controller controllers[MAX_LED_CONTROLLERS] = {0};
static uint64_t ctrl_mask;
static int n_controllers = 0;

static int find_free_ind()
{
	for (size_t i = 0; i < MAX_LED_CONTROLLERS; i++)
		if ((ctrl_mask & (1 << i)) == 0)
			return i;
	return -1;
}

static struct led_controller* get_device(uint8_t devind)
{
	if ((ctrl_mask & devind) == 0)
		return NULL;

	return &controllers[devind];
}

static struct led_controller* find_devid(uint64_t devid)
{
	if (devid == 0)
		return NULL;

	for (size_t i = 0; i < MAX_LED_CONTROLLERS; i++)
		if ((ctrl_mask & (1 << i)) && controllers[i].devid == devid)
			return &controllers[i];

	return NULL;
}

static void forcecontroller(int vid, int pid,
	enum controller_types type, struct led_capabilities caps)
{
	int ind = find_free_ind();
	if (-1 == ind)
		return;

	uint64_t devid = ((vid & 0xffff) << 16) | (pid & 0xffff);
/* other option would be to close and reopen the device as an attempt
 * to reset to a possibly safer state */
	if (find_devid(devid))
		return;

#ifdef USB_SUPPORT
/* blacklist here so that the event platform does not try to fight us */

	controllers[ind].handle = hid_open(vid, pid, NULL);
	controllers[ind].type = type;
	controllers[ind].caps = caps;
#else
	return;
#endif

	if (controllers[ind].handle == NULL)
		return;

	arcan_event_enqueue(arcan_event_defaultctx(),
		&(struct arcan_event){
		.category = EVENT_IO,
		.io.kind = EVENT_IO_STATUS,
		.io.devkind = EVENT_IDEVKIND_STATUS,
		.io.devid = ind,
		.io.input.status.devkind = EVENT_IDEVKIND_LEDCTRL,
		.io.input.status.action = EVENT_IDEV_ADDED
	});

	ctrl_mask |= 1 << ind;
	n_controllers++;
}

int8_t arcan_led_register(int cmd_ch, const char* label,
	struct led_capabilities caps)
{
	int8_t id = find_free_ind();
	if (-1 == id)
		return -1;

	arcan_event_enqueue(arcan_event_defaultctx(),
		&(struct arcan_event){
		.category = EVENT_IO,
		.io.kind = EVENT_IO_STATUS,
		.io.devkind = EVENT_IDEVKIND_STATUS,
		.io.devid = id,
		.io.input.status.devkind = EVENT_IDEVKIND_LEDCTRL,
		.io.input.status.action = EVENT_IDEV_ADDED
	});

	ctrl_mask |= 1 << id;
	controllers[id].devid = id;
	controllers[id].fd = cmd_ch;
	controllers[id].type = ARCAN_LEDCTRL;
	controllers[id].ledmask = 0;
	controllers[id].caps = caps;
	n_controllers++;
	return id;
}

bool arcan_led_remove(uint8_t device)
{
	struct led_controller* leddev = get_device(device);
	if (!leddev)
		return false;

	switch(leddev->type){
	case ARCAN_LEDCTRL:
		write(leddev->fd, (char[]){'o', '\0'}, 2);
	break;
	default:
#ifdef USB_SUPPORT
		if (leddev->handle)
			hid_close(leddev->handle);
#endif	
	break;
	}
	ctrl_mask &= ~(1 << device);
	n_controllers--;
	arcan_event_enqueue(arcan_event_defaultctx(),
		&(struct arcan_event){
		.category = EVENT_IO,
		.io.kind = EVENT_IO_STATUS,
		.io.devkind = EVENT_IDEVKIND_STATUS,
		.io.devid = device,
		.io.input.status.devkind = EVENT_IDEVKIND_LEDCTRL,
		.io.input.status.action = EVENT_IDEV_REMOVED
	});
	return true;
}

void arcan_led_init()
{
	for (size_t i = 0; i < sizeof(usb_tbl) / sizeof(usb_tbl[0]); i++)
		forcecontroller(usb_tbl[i].vid,
			usb_tbl[i].pid, usb_tbl[i].type, usb_tbl[i].caps);
}

unsigned int arcan_led_controllers()
{
	return n_controllers;
}

static void ultimarc_update(struct led_controller* ctrl)
{
/*
 * These should really be moved outside the core engine as well when
 * we have a more thought out way of dealing with normal usb devices
 * (being the added/removed + queuing and buffering + multiple-
 * device sensor fusion) as the current approach is rather hackish
 */
#ifdef USB_SUPPORT
	uint8_t dbuf[] = {
		0x00, 0x00, 0xdd, (char)ctrl->ledmask, (char)(ctrl->ledmask >> 8) & 0xff};
	hid_write(ctrl->handle, dbuf, sizeof(dbuf) / sizeof(dbuf[0]));
#endif
}

bool arcan_led_set(uint8_t device, int8_t led)
{
	unsigned char dbuf[5] = {0};
	struct led_controller* leddev = get_device(device);
	if (!leddev)
		return false;

	leddev->ledmask |= (led < 0 ? 0xffff : 1 << led);
/* PROTOCOL INSERTION POINT */
	switch (controllers[device].type) {
	case ULTIMARC_PACDRIVE:
		ultimarc_update(leddev);
	break;
	case ARCAN_LEDCTRL:
		write(leddev->fd, (char[]){'a', led < 0 ? 255 : led, 'i', 255}, 4);
	break;
	default:
		arcan_warning("Warning: arcan_led_set(), "
			"unknown LED controller type: %i\n", controllers[device].type);
		return false;
	}
	return true;
}

bool arcan_led_clear(uint8_t device, int8_t led)
{
	bool rv = false;
	unsigned char dbuf[5] = {0};
	struct led_controller* leddev = get_device(device);
	if (!leddev)
		return false;

	leddev->ledmask = led < 0 ? 0x000 : leddev->ledmask & ~(1 << led);

/* PROTOCOL INSERTION POINT */
	switch (leddev->type) {
	case ULTIMARC_PACDRIVE:
		ultimarc_update(leddev);
	break;
	case ARCAN_LEDCTRL:
		write(leddev->fd, (char[]){'a', led < 0 ? 255 : led, 'i', 0}, 4);
	break;
	default:
		arcan_warning("Warning: arcan_led_unset(), "
			"unknown LED controller type: %i\n", controllers[device].type);
		return false;
	}

	return true;
}

bool arcan_led_intensity(uint8_t device, int8_t led, uint8_t intensity)
{
	bool rv = false;
	struct led_controller* leddev = get_device(device);
	uint8_t di = led < 0 ? 255 : led;

	if (!leddev)
		return false;

	if (di > leddev->caps.nleds-1 && di != 255)
		return false;

	if (!leddev->caps.variable_brightness)
		return (intensity > 0 ?
			arcan_led_set(device, led) : arcan_led_clear(device, led));

/* PROTOCOL INSERTION POINT */
	switch (controllers[device].type) {
	case ARCAN_LEDCTRL:
		write(leddev->fd, (char[]){'a', di, 'i', intensity}, 4);
	break;
	default:
		arcan_warning("Warning: arcan_led_intensity(), unknown LED / "
			"unsupported mode for device type: %i\n", controllers[device].type);
		return false;
	}

	return true;
}

bool arcan_led_rgb(uint8_t device, int8_t led, uint8_t r, uint8_t g, uint8_t b)
{
	bool rv = false;
	struct led_controller* leddev = get_device(device);
	if (!leddev)
		return false;

	uint8_t di = led < 0 ? 255 : led;
	if ( (di != 255 && di > leddev->caps.nleds) || !leddev->caps.rgb)
		return false;

	switch (leddev->type){
	case ARCAN_LEDCTRL:
		write(leddev->fd, (char[]){
			'r', di, 'i', r,
			'g', di, 'i', g,
			'b', di, 'i', b}, 6
		);
	default:
		arcan_warning("Warning: arcan_led_rgb(), unknown LED / unsupported mode"
			"	for device type: %i\n", leddev->type);
		return false;
	}
	return true;
}

struct led_capabilities arcan_led_capabilities(uint8_t device)
{
	struct led_capabilities rv = {0};
	struct led_controller* leddev = get_device(device);
	if (!leddev)
		return rv;
	return leddev->caps;
}

void arcan_led_shutdown()
{

	for (int i = 0; i < MAX_LED_CONTROLLERS && n_controllers > 0; i++)
		if ((ctrl_mask & (1 << i)) > 0){
			n_controllers--;
			switch(controllers[i].type){
				case ULTIMARC_PACDRIVE:
#ifdef USB_SUPPORT
					hid_close(controllers[i].handle);
#endif
				break;
				case ARCAN_LEDCTRL:{
					char cmd = 'o';
					write(controllers[i].fd, &cmd, 1);
					close(controllers[i].fd);
				}
				break;
			}
		}

	ctrl_mask = 0;
}
