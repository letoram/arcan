// Copyright 2019, Mark Nelson.
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* VR-Tek Driver */

#include <stdio.h>
#include <string.h>
#include "vrtek.h"

#ifdef _MSC_VER
#define inline __inline
#endif

inline static uint8_t read_uint8(const uint8_t** buffer)
{
    uint8_t ret = **buffer;
    *buffer += 1;
    return ret;
}

inline static int16_t read_int16_2bu(const uint8_t** buffer)
{
    int16_t ret = **buffer | (*(*buffer + 1) << 8);
    *buffer += 2;
    return ret;
}

inline static int16_t read_int16_2bs(const uint8_t** buffer)
{
    const int8_t** buffer_s = (const int8_t**) buffer;
    int16_t ret = **buffer_s | (*(*buffer_s + 1) << 8);
    *buffer += 2;
    return ret;
}

inline static void write_uint8(uint8_t** buffer, uint8_t val)
{
    **buffer = val;
    *buffer += 1;
}

int vrtek_encode_command_packet(uint8_t command_num, uint8_t command_arg,
                                uint8_t* data_buffer, uint8_t data_length,
                                uint8_t* comm_packet)
{
    uint8_t* buffer = comm_packet;
    write_uint8(&buffer, VRTEK_REPORT_CONTROL_OUTPUT);
    write_uint8(&buffer, command_num);
    write_uint8(&buffer, command_arg);
    write_uint8(&buffer, data_length);

    if (data_length) {
        memcpy(buffer, data_buffer, data_length);
        buffer += data_length;
    }

    uint8_t parity_byte = *comm_packet;
    for (int i = 1; i < (data_length + 4); ++i) {
        parity_byte ^= *(comm_packet + i);
    }
    write_uint8(&buffer, parity_byte);

    /* return the total number of bytes in the command packet */
    return (buffer - comm_packet);
}

int vrtek_decode_command_packet(const uint8_t* comm_packet,
                                uint8_t* command_num, uint8_t* command_arg,
                                uint8_t* data_buffer, uint8_t* data_length)
{
    const uint8_t* buffer = comm_packet;
    uint8_t report_num = read_uint8(&buffer);
    if (report_num != VRTEK_REPORT_CONTROL_INPUT) {
        LOGE("received invalid report number for command packet response "
             "(expected %d but got %d)",
             VRTEK_REPORT_CONTROL_INPUT, report_num);
        return -1;
    }

    *command_num = read_uint8(&buffer);
    *command_arg = read_uint8(&buffer);
    *data_length = read_uint8(&buffer);

    if (*data_length) {
        memcpy(data_buffer, buffer, *data_length);
        buffer += *data_length;
    }

    uint8_t checksum = *(comm_packet + 1);
    for (int i = 2; i < (*data_length + 4 + 1); ++i) {
        checksum ^= *(comm_packet + i);
    }

    /* checksum should be zero if parity byte was correct */
    if (checksum) {
        return -2;
    }

    return 0;
}

static inline void hmd_quat_rotate(float* out, float* in)
{
    double pos_val = sin(M_PI/4);
    double neg_val = pos_val * -1;

    /* out[x] = (in[w] * 0.7071) - (in[x] * 0.7071) */
    out[0] = (in[3] * pos_val) - (in[0] * pos_val);
    /* out[y] = (in[z] * -0.7071) - (in[y] * 0.7071) */
    out[1] = (in[2] * neg_val) - (in[1] * pos_val);
    /* out[z] = (in[y] * 0.7071) - (in[z] * 0.7071) */
    out[2] = (in[1] * pos_val) - (in[2] * pos_val);
    /* out[w] = (in[w] * -0.7071) - (in[x] * 0.7071) */
    out[3] = (in[3] * neg_val) - (in[0] * pos_val);
}

int vrtek_decode_hmd_data_packet(const uint8_t* buffer, int size,
                                 vrtek_hmd_data_t* data)
{
    float mult = 0.00006103515625;
    float div  = 100.0;
    float quat[4];

    if (size != 64) {
        LOGE("received invalid VR-Tek message packet size (expected 64 bytes "
             "but got %d)", size);
        return -1;
    }

    /* skip report number */
    ++buffer;

    data->message_num = read_uint8(&buffer);

    /* quaternion */
    for (int i = 0; i < 4; ++i) {
        float f = read_int16_2bu(&buffer);
        quat[i] = f * mult;
    }
    hmd_quat_rotate(data->quaternion, quat);

    /* euler */
    for (int i = 0; i < 3; ++i) {
        double d = read_int16_2bs(&buffer);
        data->euler[i] = d / div;
    }

    /* acceleration */
    for (int i = 0; i < 3; ++i) {
        data->acceleration[i] = read_int16_2bu(&buffer);
    }

    /* gyroscope */
    for (int i = 0; i < 3; ++i) {
        data->gyroscope[i] = read_int16_2bu(&buffer);
    }

    /* magnetometer */
    for (int i = 0; i < 3; ++i) {
        data->magnetometer[i] = read_int16_2bu(&buffer);
    }

    return 0;
}
