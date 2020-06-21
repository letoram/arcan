// Copyright 2018, Philipp Zabel.
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* Windows Mixed Reality Driver */


#ifndef WMR_H
#define WMR_H

#include <stdint.h>
#include <stdbool.h>

#include "../openhmdi.h"

typedef enum
{
	HOLOLENS_IRQ_SENSORS = 1,
	HOLOLENS_IRQ_CONTROL = 2,
	HOLOLENS_IRQ_DEBUG = 3,
} hololens_sensors_irq_cmd;

typedef struct
{
        uint8_t id;
        uint16_t temperature[4];
        uint64_t gyro_timestamp[4];
        int16_t gyro[3][32];
        uint64_t accel_timestamp[4];
        int32_t accel[3][4];
        uint64_t video_timestamp[4];
} hololens_sensors_packet;

static const unsigned char hololens_sensors_imu_on[64] = {
	0x02, 0x07
};

typedef struct {
        uint32_t json_start;
        uint32_t json_size;
        char manufacturer[0x40];
        char device[0x40];
        char serial[0x40];
        char uid[0x26];
        char unk[0xd5];
        char name[0x40];
        char revision[0x20];
        char revision_date[0x20];
} wmr_config_header;

bool hololens_sensors_decode_packet(hololens_sensors_packet* pkt, const unsigned char* buffer, int size);

#endif
