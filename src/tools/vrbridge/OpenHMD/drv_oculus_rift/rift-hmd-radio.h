/*
 * Oculus Rift CV1 Radio
 * Copyright 2016 Philipp Zabel
 * Copyright 2019 Jan Schmidt
 * SPDX-License-Identifier:	BSL-1.0
 */
#ifndef RIFT_HMD_RADIO_H
#define RIFT_HMD_RADIO_H

#include <hidapi.h>
#include "rift.h"

int rift_touch_get_calibration(hid_device *handle,
		int device_id,
		rift_touch_calibration *calibration);
bool rift_hmd_radio_get_address(hid_device *handle, uint8_t address[5]);
#endif /* RIFT_HMD_RADIO_H */
