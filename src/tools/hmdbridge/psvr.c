#include <arcan_shmif.h>
#include "arcan_math.h"
#include <arcan_shmif_sub.h>
#include <hidapi/hidapi.h>
#include <pthread.h>
#include "hmdbridge.h"
#include "psvr.h"
#include "ahrs.h"

static const uint16_t psvr_vid = 0x54c;
static const uint16_t psvr_pid = 0x9af;

static hid_device* dev;

/*
 * The basics for this device isn't too bad, some reports for switching
 * modes, then a big blob parser for extracting sensor data
 */

void psvr_sample(struct dev_ent* dev)
{
}

bool psvr_init(struct dev_ent* ent)
{
	if (dev){
/* allocate limb for head, if we don't get one - easy job */
		return true;
	}
	return false;
}

void psvr_control(struct dev_ent* ent, enum ctrl_cmd cmd, int id)
{
}
