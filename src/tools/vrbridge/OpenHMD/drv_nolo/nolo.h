// Copyright 2017, Joey Ferwerda.
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 * Original implementation by: Yann Vernier.
 */

/* NOLO VR - Internal Interface */


#ifndef NOLODRIVER_H
#define NOLODRIVER_H

#include "../openhmdi.h"
#include <hidapi.h>

#define FEATURE_BUFFER_SIZE 64

typedef struct
{
	int16_t accel[3];
	int16_t gyro[3];
	uint64_t tick;
} nolo_sample;

typedef struct {
	ohmd_device base;

	hid_device* handle;
	int id;
	int rev;
	float controller_values[8];

	nolo_sample sample;
	fusion sensor_fusion;
	vec3f raw_accel, raw_gyro;
} drv_priv;

typedef enum
{
	//LEGACY firmware < 2.0
	NOLO_LEGACY_CONTROLLER_TRACKER = 165,
	NOLO_LEGACY_HMD_TRACKER = 166,
	//firmware > 2.0
	NOLO_CONTROLLER_0_HMD_SMP1 = 16,
	NOLO_CONTROLLER_1_HMD_SMP2 = 17,
} nolo_irq_cmd;

typedef struct{
	char path[OHMD_STR_SIZE];
	drv_priv* hmd_tracker;
	drv_priv* controller0;
	drv_priv* controller1;
} drv_nolo;

typedef struct devices{
	drv_nolo* drv;
	struct devices * next;
} devices_t;

void btea_decrypt(uint32_t *v, int n, int base_rounds, uint32_t const key[4]);
void nolo_decrypt_data(unsigned char* buf);

void nolo_decode_base_station(drv_priv* priv, const unsigned char* data);
void nolo_decode_hmd_marker(drv_priv* priv, const unsigned char* data);
void nolo_decode_controller(drv_priv* priv, const unsigned char* data);
void nolo_decode_quat_orientation(const unsigned char* data, quatf* quat);
void nolo_decode_orientation(const unsigned char* data, nolo_sample* smp);
void nolo_decode_position(const unsigned char* data, vec3f* pos);

#endif

