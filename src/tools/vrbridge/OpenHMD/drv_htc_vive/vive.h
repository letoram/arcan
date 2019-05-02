// Copyright 2013, Fredrik Hultin.
// Copyright 2013, Jakob Bornecrantz.
// Copyright 2013, Joey Ferwerda.
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* HTC Vive Driver */


#ifndef VIVE_H
#define VIVE_H

#include <stdint.h>
#include <stdbool.h>

#include "../openhmdi.h"
#include "magic.h"

typedef enum
{
	VIVE_IMU_RANGE_MODES_PACKET_ID = 1,
	VIVE_CONFIG_START_PACKET_ID = 16,
	VIVE_CONFIG_READ_PACKET_ID = 17,
	VIVE_HMD_IMU_PACKET_ID = 32,
} vive_irq_cmd;

typedef struct
{
	int16_t acc[3];
	int16_t rot[3];
	uint32_t time_ticks;
	uint8_t seq;
} vive_headset_imu_sample;

typedef struct
{
	uint8_t report_id;
	vive_headset_imu_sample samples[3];
} vive_headset_imu_packet;

typedef struct
{
	uint8_t report_id;
	uint16_t length;
	unsigned char config_data[99999];
} vive_config_packet;

typedef struct
{
	uint8_t id;
	uint8_t gyro_range;
	uint8_t accel_range;
	uint8_t unknown[61];
} vive_imu_range_modes_packet;

typedef struct
{
	vec3f acc_bias, acc_scale;
	float acc_range;
	vec3f gyro_bias, gyro_scale;
	float gyro_range;
} vive_imu_config;

void vec3f_from_vive_vec(const int16_t* smp, vec3f* out_vec);
bool vive_decode_sensor_packet(vive_headset_imu_packet* pkt,
                               const unsigned char* buffer,
                               int size);
bool vive_decode_config_packet(vive_imu_config* result,
                               const unsigned char* buffer,
                               uint16_t size);

#endif
