/*
 ***************************************************************************************************
 *                     3Glasses HMD Driver - Internal Interface
 *
 * File   : xgvr.h
 * Author : Duncan Li (duncan.li@3glasses.com)
 *          Douglas Xie (dongyang.xie@3glasses.com )
 * Version: V1.0
 * Date   : 10-June-2018
 ***************************************************************************************************
 * Copyright (C) 2018 VR Technology Holdings Limited.  All rights reserved.
 * Website:  www.3glasses.com    www.vrshow.com
 ***************************************************************************************************
 */

#ifndef XGVR_H
#define XGVR_H

#include <stdint.h>
#include "../openhmdi.h"

typedef struct {
    float acc[3];
    float gyr[3];
    float mag[3];
    float quat[4];
    uint16_t timestamp;
    uint8_t temperature;
    uint8_t panel_status;   // 0 for init, 1 for suspend, 2 for run.
    uint8_t als;            // 0 for open, 1 for close
    uint8_t button;         // 0 for open, 1 for pressed
    uint8_t touch[2];       // not support.
} xgvr_hmd_data_t;

int xgvr_decode_version_packet(const unsigned char* buffer, int size,  uint8_t *bootloader_version_major, uint8_t *bootloader_version_minor, uint8_t *runtime_version_major, uint8_t *runtime_version_minor);
int xgvr_decode_hmd_data_packet(const unsigned char* buffer, int size, xgvr_hmd_data_t *data);

#endif
