// Copyright 2019, Mark Nelson.
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* VR-Tek Driver */

#ifndef VRTEK_H
#define VRTEK_H

#include <stdint.h>
#include "../openhmdi.h"

typedef struct {
    uint16_t message_num;
    float    quaternion[4];
    double   euler[3];
    int16_t  acceleration[3];
    int16_t  gyroscope[3];
    int16_t  magnetometer[3];
} vrtek_hmd_data_t;

typedef struct {
    /* sensor fusion working data */
    vec3f raw_gyro, raw_accel, raw_mag;
    fusion sensor_fusion;

    /* IMU config */
    float gyro_range;
    int16_t gyro_offset[3];    /* x, y, z */
    float accel_range;
} vrtek_sensor_fusion_t;

typedef enum {
    VRTEK_REPORT_CONTROL_OUTPUT = 0x01,    /* control to HMD */
    VRTEK_REPORT_CONTROL_INPUT  = 0x02,    /* control from HMD */
    VRTEK_REPORT_SENSOR         = 0x13     /* sensor report from HMD */
} vrtek_report_num;

typedef enum {
    VRTEK_SKU_WVR_UNKNOWN,
    VRTEK_SKU_WVR1,
    VRTEK_SKU_WVR2,
    VRTEK_SKU_WVR3,
    VRTEK_SKU_UNKNOWN_UNKNOWN
} vrtek_hmd_sku;

typedef enum {
    VRTEK_DISP_LCD2880X1440 = 4,
    VRTEK_DISP_LCD1440X2560_ROTATED = 5,
    VRTEK_DISP_UNKNOWN = 0xFF
} vrtek_display_type;

typedef enum {
    VRTEK_COMMAND_CONFIGURE_HMD = 2,
    VRTEK_COMMAND_QUERY_HMD = 3
} vrtek_command_num;

typedef enum {
    VRTEK_CONFIG_ARG_HMD_IMU = 4
} vrtek_config_command_arg;

typedef enum {
    VRTEK_QUERY_ARG_HMD_CONFIG = 5,
    VRTEK_QUERY_ARG_HMD_MODEL = 7
} vrtek_query_command_arg;


int vrtek_encode_command_packet(uint8_t command_num, uint8_t command_arg,
                                uint8_t* data_buffer, uint8_t data_length,
                                uint8_t* comm_packet);
int vrtek_decode_command_packet(const uint8_t* comm_packet,
                                uint8_t* command_num, uint8_t* command_arg,
                                uint8_t* data_buffer, uint8_t* data_length);

int vrtek_decode_hmd_data_packet(const uint8_t* buffer, int size,
                                 vrtek_hmd_data_t* data);

#endif
