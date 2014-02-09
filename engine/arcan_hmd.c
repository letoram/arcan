#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_hmd.h"

#include <hidapi/hidapi.h>

static const int RIFT_VID = 0x2833;
static const int RIFT_PID = 0x0001;

static hid_device* hmd_handle;

/* 
static arcan_vobj_id hmd_dvobj = ARCAN_EID;

static uint8_t keepalive[5] = {
	8, 0, 0, interval lower 0, interval upper 
};


 * (u,s)int16 ( [1] << 8 | 0)
 * -> uint32, recast as float
 *  -> uint32 (0 | [1] << 8, [2] << 16 | [3] << 24

static bool scale_range(uint8_t accel_scale, 
	uint16_t gyro_scale, uint16_t mag_scale)
{
	uint8_t cmd[8] = {0};
	cmd[3] = accel_scale;
	cmd[4] = gyro_scale & 0xff;
	cmd[5] = gyro_scale >> 8;
	cmd[6] = mag_scale & 0xff;
	cmd[7] = mag_scale >> 8;

	return hid_send_feature_report(hmd_handle, cmd, 8) == 8;
}
*/
/* config; 7 len (2, 0, 0, flags, interval, keepalive_lower, keeplaive_upper) */

bool arcan_hmd_setup()
{
	if (hmd_handle != NULL){
		arcan_hmd_shutdown();
	}

	hmd_handle = hid_open(RIFT_VID, RIFT_PID, NULL);

/* extract sensor information */
	if (hmd_handle) {
		uint8_t raw[56];
		if (hid_get_feature_report(hmd_handle, raw, 56) < 0)
			return ((hmd_handle = NULL), false);
		
		/* uint16(hres), uint16(vres), uint32(hscreen), uint32(vscreen),
		 * uint32(center), uint32(lenssep), uint32(leyetos), uint32(reyetos),
		 * dist[0..5] (float4) */
	
		hid_set_nonblocking(hmd_handle, 1);
	}

	return hmd_handle != NULL;
}

void arcan_hmd_targetobj(arcan_vobj_id vid)
{
	if (!hmd_handle)
		return;
}

void arcan_hmd_update()
{
	if (!hmd_handle)
		return;
	
	unsigned char hmdbuf[64];  
	hid_read(hmd_handle, hmdbuf, 64); 

/*
 * 1. Scan USB device for sensor information
 * 2. Recalc. orientation quaternion
 * 3. Set the orientation quaternion for the targetobj
 *    (typically a camtagged obj.)
 * 4. Send keepalive if it's "time", just use global clock

	hid_send_feature_report(hmd_handle, keepalive, 5); */
}

void arcan_hmd_shutdown()
{
	if (hmd_handle != NULL)
		hid_close(hmd_handle);
	
	hmd_handle = NULL;
}
