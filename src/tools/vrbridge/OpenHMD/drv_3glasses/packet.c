/*
 ***************************************************************************************************
 *                  3Glasses HMD Driver - Packet Decoding and Utilities
 *
 * File   : packet.h
 * Author : Duncan Li (duncan.li@3glasses.com)
 *          Douglas Xie (dongyang.xie@3glasses.com )
 * Version: V1.0
 * Date   : 10-June-2018
 ***************************************************************************************************
 * Copyright (C) 2018 VR Technology Holdings Limited.  All rights reserved.
 * Website:  www.3glasses.com    www.vrshow.com
 ***************************************************************************************************
 */

#include <stdio.h>
#include <stdint.h>
#include "xgvr.h"

#ifdef _MSC_VER
#define inline __inline
#endif

typedef union {
    float fdata;
    unsigned long ldata;
} float_long_t;

inline static void float_to_byte(const float f, unsigned char *byte)
{
    float_long_t fl;
    fl.fdata = f;
    byte[0] = (unsigned char)fl.ldata;
    byte[1] = (unsigned char)(fl.ldata >> 8);
    byte[2] = (unsigned char)(fl.ldata >> 16);
    byte[3] = (unsigned char)(fl.ldata >> 24);
}

inline static void byte_to_float(float *f, const unsigned char *byte)
{
    float_long_t fl;
    fl.ldata = 0;
    fl.ldata = byte[3];
    fl.ldata = (fl.ldata << 8) | byte[2];
    fl.ldata = (fl.ldata << 8) | byte[1];
    fl.ldata = (fl.ldata << 8) | byte[0];
    *f = fl.fdata;
}

inline static uint8_t read_uint8(const unsigned char** buffer)
{
    uint8_t ret = **buffer;
    *buffer += 1;
    return ret;
}

inline static uint16_t read_uint16(const unsigned char** buffer)
{
    uint16_t ret = **buffer | (*(*buffer + 1) << 8);
    *buffer += 2;
    return ret;
}

inline static int16_t read_int16(const unsigned char** buffer)
{
    int16_t ret = **buffer | (*(*buffer + 1) << 8);
    *buffer += 2;
    return ret;
}

inline static uint32_t read_uint32(const unsigned char** buffer)
{
    uint32_t ret = **buffer | (*(*buffer + 1) << 8) | (*(*buffer + 2) << 16) | (*(*buffer + 3) << 24);
    *buffer += 4;
    return ret;
}

inline static int32_t read_int32(const unsigned char** buffer)
{
    int32_t ret = **buffer | (*(*buffer + 1) << 8) | (*(*buffer + 2) << 16) | (*(*buffer + 3) << 24);
    *buffer += 4;
    return ret;
}

inline static float read_float(const unsigned char** buffer)
{
    float ret = 0;
    byte_to_float(&ret, *buffer);
    *buffer += 4;
    return ret;
}

static inline void _quat_norm(float *in, float *out)
{
    double m = sqrt(in[0] * in[0] + in[1] * in[1] + in[2] * in[2] + in[3] * in[3]);
    out[0] = in[0] / m;
    out[1] = in[1] / m;
    out[2] = in[2] / m;
    out[3] = in[3] / m;
}

static inline void _quat_mul(float *in1, float *in2, float *out)
{
    out[0] = in1[0] * in2[3] + in1[1] * in2[2] - in1[2] * in2[1] + in1[3] * in2[0];
    out[1] = -in1[0] * in2[2] + in1[1] * in2[3] + in1[2] * in2[0] + in1[3] * in2[1];
    out[2] = in1[0] * in2[1] - in1[1] * in2[0] + in1[2] * in2[3] + in1[3] * in2[2];
    out[3] = -in1[0] * in2[0] - in1[1] * in2[1] - in1[2] * in2[2] + in1[3] * in2[3];
    _quat_norm(out, out);
}

static inline void _quat_inv(float *in, float *out)
{
    float _buf[4];
    _quat_norm(in, _buf);
    out[0] = -_buf[0];
    out[1] = -_buf[1];
    out[2] = -_buf[2];
    out[3] = _buf[3];
}

static void _hmd_v2_quat_rotate(float *in, float *out)
{
    float _buf[4] = {0, 0.70710678118, 0, 0.70710678118};
    float _buf2[4];
    _quat_mul(in, _buf, _buf2);
    out[0] = -_buf2[1]; // x
    out[1] = _buf2[2]; // y
    out[2] = -_buf2[0]; // z
    out[3] = _buf2[3]; // w
}

int xgvr_decode_version_packet(const unsigned char* buffer, int size,  uint8_t *bootloader_version_major, uint8_t *bootloader_version_minor, uint8_t *runtime_version_major, uint8_t *runtime_version_minor)
{
    if (size != 8) {
        LOGE("invalid 3glasses version packet size (expected 8 but got %d)", size);
        return -1;
    }

    // skip report_id
    read_uint8(&buffer);

    *bootloader_version_major = read_uint8(&buffer);
    *bootloader_version_minor = read_uint8(&buffer);
    *runtime_version_major = read_uint8(&buffer);
    *runtime_version_minor = read_uint8(&buffer);

    return 0;
}

int xgvr_decode_hmd_data_packet(const unsigned char* buffer, int size, xgvr_hmd_data_t *data)
{
    uint8_t i = 0;
    float quat[4];

    if (size != 64) {
        LOGE("invalid 3glasses message revd packet size (expected 64 but got %d)", size);
        return -1;
    }

    // skip Report ID, 1Byte
    buffer += 1;
    data->panel_status = read_uint8(&buffer);
    data->timestamp = read_uint16(&buffer);
    data->temperature = read_uint8(&buffer);
    // skip IPD, 1Byte
    buffer += 1;
    // skip pad, 4Byte align
    buffer += 2;
    for (i = 0; i < 4; i++) {
        quat[i] = read_float(&buffer);
    }
    _hmd_v2_quat_rotate(quat, data->quat);
    for (i = 0; i < 3; i++) {
        data->acc[i] = read_float(&buffer);
    }
    for (i = 0; i < 3; i++) {
        data->gyr[i] = read_float(&buffer);
    }
    for (i = 0; i < 3; i++) {
        data->mag[i] = read_float(&buffer);
    }
    data->touch[0] = read_uint8(&buffer);
    data->touch[1] = read_uint8(&buffer);
    data->als = read_uint8(&buffer);
    data->button = read_uint8(&buffer);

    return 0;
}
