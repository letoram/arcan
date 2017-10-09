#include <stdint.h>
#include <stdbool.h>
#include "arcan_math.h"
#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <hidapi/hidapi.h>
#include <pthread.h>
#include "vrbridge.h"
#include "avr_psvr.h"
#include "ahrs.h"

static const uint16_t psvr_vid = 0x54c;
static const uint16_t psvr_pid = 0x9af;

static hid_device* dev;

/*
 * The basics for this device isn't too bad, some reports for switching
 * modes, then a big blob parser for extracting sensor data
 */

void psvr_sample(struct dev_ent* dev, struct vr_limb* limb, unsigned id)
{
}

bool psvr_init(struct dev_ent* ent,
	struct arcan_shmif_vr* vr, struct arg_arr* arg)
{
	return false;
}

void psvr_control(struct dev_ent* ent, enum ctrl_cmd cmd)
{
}
