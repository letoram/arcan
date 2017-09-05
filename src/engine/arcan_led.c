/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: LED controller interface,
 *
 * By defining LED_STANDALONE it can be built separately from the
 * main engine to allow other projects to just re-use the LED control
 * interface.
 *
 * Setting the 'ext_led' database config value to a path name pointing
 * to an existing named pipe will have the engine map that as an
 * external led controller that speaks the protocol mentioned in the
 * header.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

#ifdef USB_SUPPORT
#include <hidapi/hidapi.h>
#else
	typedef struct hid_device hid_device;
#endif

#include "arcan_led.h"
#ifndef LED_STANDALONE
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_db.h"
#else
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

/* to add more device types,
 * 1. patch in the type in the controller_types enum.
 * 2. for usb-devices, add a vid/pid to type mapping in the usb_tbl
 *    or alter the init function to actually scan for it and if found,
 *    forcecontroller (get the returned index and patch type).
 * 3. modify the places marked as PROTOCOL INSERTION POINT
 */
enum controller_types {
	PACDRIVE = 1,
	ARCAN_LEDCTRL = 2
};

struct led_controller {
	enum controller_types type;
	struct led_capabilities caps;
	uint64_t devid;
	int errc;

	union {
		hid_device* handle;
		int fd;
	};

/* some need a big table, others do fine with a simple bitmask */
	uint32_t table[256];
	uint16_t ledmask;

/* for FIFOs, we may need to try open the path during writes */
	char* path;
	bool no_close;
};

struct usb_ent {
	uint16_t vid, pid;
	enum controller_types type;
	struct led_capabilities caps;
	char label[16];
};

/* one of the C fuglyness, static const struct led_capabilities paccap would
 * still yield that the initialization is not constant */
#define paccap { .variable_brightness = false, .rgb = false, .nleds = 32 }

/*
 * nleds is just max, not all of these will map due to layout variations
 * that don't necessarily (?) has a different vid/pid pair
 */
static const struct usb_ent usb_tbl[] =
{
	{.vid = 0xd209, .pid = 0x1500, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1501, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1502, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1503, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1504, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1505, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1506, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1507, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"},
	{.vid = 0xd209, .pid = 0x1508, .type = PACDRIVE,
		.caps = paccap, .label = "Pacdrive"}
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
	if (devind > MAX_LED_CONTROLLERS ||
		(ctrl_mask & (1 << devind)) == 0)
		return NULL;

	return &controllers[devind];
}

static struct led_controller* find_devid(uint64_t devid)
{
	if (devid == 0)
		return NULL;

	for (size_t i = 0; i < MAX_LED_CONTROLLERS; i++)
		if ((ctrl_mask & ((size_t)1 << i)) && controllers[i].devid == devid)
			return &controllers[i];

	return NULL;
}

static void forcecontroller(const struct usb_ent* ent)
{
	int ind = find_free_ind();
	if (-1 == ind)
		return;

/* the USB standard doesn't mandate a serial number (facepalm)
 * and hidraw doesn't really have something akin to an instance id */

	uint64_t devid = (
		(uint64_t)(ent->vid & 0xffff) << 16) | ((uint64_t)ent->pid & 0xffff);
/* other option would be to close and reopen the device as an attempt
 * to reset to a possibly safer state */
	if (find_devid(devid))
		return;

#ifdef USB_SUPPORT
	controllers[ind].handle = hid_open(ent->vid, ent->pid, NULL);
	controllers[ind].type = ent->type;
	controllers[ind].caps = ent->caps;
	if (controllers[ind].handle == NULL)
		return;

/* PROTOCOL_INSERTION_POINT */
	switch(ent->type){
	default:
	break;
	}
#else
	return;
#endif

	ctrl_mask |= 1 << ind;
	n_controllers++;
	arcan_led_added(ind, -1, ent->label);
}

int8_t arcan_led_register(int cmd_ch, int devref,
	const char* label, struct led_capabilities caps)
{
	int8_t id = find_free_ind();
	if (-1 == id)
		return -1;

	ctrl_mask |= 1 << id;
	controllers[id].devid = id;
	controllers[id].fd = cmd_ch;
	controllers[id].type = ARCAN_LEDCTRL;
	controllers[id].ledmask = 0;
	controllers[id].caps = caps;
	controllers[id].errc = 0;
	controllers[id].no_close = false;

	n_controllers++;
	arcan_led_added(id, devref, label);
	return id;
}

static int write_leddev(
	struct led_controller* dev, int ind, uint8_t* buf, size_t sz)
{
	int rv;

	if (-1 == dev->fd){
		dev->fd = open(dev->path, O_NONBLOCK | O_WRONLY);
		if (-1 == dev->fd)
			return 0;
	}

	while ((rv = write(dev->fd, buf, sz)) == -1){
		if (errno == EAGAIN)
			return 0;

		if (errno == EPIPE){
			if (!dev->no_close){
				arcan_led_remove(ind);
				return -1;
			}
			else
				break;
		}
	}

	if (rv == sz)
		return 1;

	return 0;
}

bool arcan_led_remove(uint8_t device)
{
	struct led_controller* leddev = get_device(device);
	if (!leddev)
		return false;

	switch(leddev->type){
	case ARCAN_LEDCTRL:
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
	leddev->handle = NULL;
	arcan_led_removed(device);

	return true;
}

bool arcan_led_known(uint16_t vid, uint16_t pid)
{
	for (size_t i = 0; i < COUNT_OF(usb_tbl); i++)
		if (usb_tbl[i].vid == vid && usb_tbl[i].pid == pid)
			return true;

	return false;
}

#ifndef LED_STANDALONE
static bool register_fifo(char* path, int ind)
{
	if (ind < 0 || ind > 99)
		return false;

/* label will only be used for the event to the scripting layer, no ref */
	char buf[ sizeof("(led-fifo 10)") ];
	snprintf(buf, sizeof(buf), "(led-fifo %d)", ind);
	int ledid = arcan_led_register(-1, -1, buf,
		(struct led_capabilities){
			.nleds = 255,
			.variable_brightness = true,
			.rgb = true
		}
	);

/* delete- protect the LED so we won't close on EPIPE */
	if (-1 != ledid){
		controllers[ledid].no_close = true;
		controllers[ledid].path = path;
		return true;
	}
	return false;
}
#endif

void arcan_led_init()
{

/* register up to 10 custom LED devices that follow our FIFO protocol.
 * leddev- takes control over appl_val dynamic string ownership */
#ifndef LED_STANDALONE
	const char* appl;
	struct arcan_dbh* dbh = arcan_db_get_shared(&appl);

	char* kv = arcan_db_appl_val(dbh, appl, "ext_led");
	if (kv && register_fifo(kv, 1)){
		char work[sizeof("ext_led_1")];

		for (size_t i = 2; i < 10; i++){
			snprintf(work, sizeof(work), "ext_led_%zu", i);
			kv = arcan_db_appl_val(dbh, appl, work);
			if (!kv || !register_fifo(kv, i)){
				free(kv);
			}
		}
	}
	else
		free(kv);
#endif

	for (size_t i = 0; i < sizeof(usb_tbl) / sizeof(usb_tbl[0]); i++)
		forcecontroller(&usb_tbl[i]);
}

uint64_t arcan_led_controllers()
{
	return ctrl_mask;
}

static void ultimarc_update(uint8_t device, struct led_controller* ctrl)
{
#ifdef USB_SUPPORT
	uint8_t dbuf[] = {
		0x00, 0x00, 0xdd, (char)ctrl->ledmask, (char)(ctrl->ledmask >> 8) & 0xff};
	int val = hid_write(ctrl->handle, dbuf, sizeof(dbuf) / sizeof(dbuf[0]));
	if (-1 == val){
		ctrl->errc++;
		if (ctrl->errc > 10){
			arcan_led_remove(device);
		}
	}
#endif
}

int arcan_led_intensity(uint8_t device, int16_t led, uint8_t intensity)
{
	bool rv = false;
	struct led_controller* leddev = get_device(device);
	uint8_t di = led < 0 ? 255 : led;
	if (!leddev)
		return false;

	if (di > leddev->caps.nleds-1 && di != 255)
		return false;

	if (!leddev->caps.variable_brightness)
		intensity = intensity > 0 ? 255 : 0;

/* PROTOCOL INSERTION POINT */
	switch (controllers[device].type) {
	case ARCAN_LEDCTRL:
		if (led < 0)
			return write_leddev(leddev, device, (uint8_t[]){
				'A', '\0', 'i', intensity, 'c', '\0'}, 6);
		else
			return write_leddev(leddev, device, (uint8_t[]){
				'a', (uint8_t)led, 'i', intensity, 'c', '\0'}, 6);
	break;
	case PACDRIVE:
		if (intensity)
			leddev->ledmask |= 1 << led;
		else
			leddev->ledmask &= ~(1 << led);
		ultimarc_update(device, leddev);
	break;
	default:
		arcan_warning("Warning: arcan_led_intensity(), unknown LED / "
			"unsupported mode for device type: %i\n", controllers[device].type);
		return false;
	}

	return true;
}

int arcan_led_rgb(uint8_t device,
	int16_t led, uint8_t r, uint8_t g, uint8_t b, bool buffer)
{
	struct led_controller* leddev = get_device(device);
	if (!leddev || !leddev->caps.rgb || led > (int)leddev->caps.nleds)
		return -1;

	switch (leddev->type){
	case ARCAN_LEDCTRL:{
		int v;
		if (led < 0)
			v = write_leddev(leddev, device, (uint8_t[]){'A', '\0'}, 2);
		else
			v = write_leddev(leddev, device, (uint8_t[]){'a', (uint8_t)led}, 2);

		if (1 == v)
			return write_leddev(leddev, device, (uint8_t[]){
				'r', r, 'g', g, 'b', b, 'c', buffer ? 255 : 0}, 8);
		else
			return v;
	}
	break;
	default:
		arcan_warning("Warning: arcan_led_rgb(), unknown LED / unsupported mode"
			"	for device type: %i\n", leddev->type);
		return -1;
	}
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
			case PACDRIVE:
#ifdef USB_SUPPORT
				hid_close(controllers[i].handle);
#endif
			break;
			case ARCAN_LEDCTRL:{
				if (-1 == write(controllers[i].fd, (char[]){'o', '\0'}, 2))
					arcan_warning("arcan_led_shutdown(), error sending shutdown\n");
				close(controllers[i].fd);
				free(controllers[i].path);
				controllers[i].path = NULL;
			}
			break;
			}
		}

	ctrl_mask = 0;
}
