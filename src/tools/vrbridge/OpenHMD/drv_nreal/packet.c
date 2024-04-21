// Copyright 2023, Tobias Frisch
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  Nreal Air packet parsing implementation.
 * @author Tobias Frisch <thejackimonster@gmail.com>
 */

#include "air.h"

#include "../ext_deps/nxjson.h"
#include <string.h>
#include <stdint.h>


/*
 *
 * Buffer reading helpers.
 *
 */

static inline void
skip(const uint8_t **buffer, size_t num)
{
	*buffer += num;
}

static inline void
read_i16(const uint8_t **buffer, int16_t *out_value)
{
	*out_value = (*(*buffer + 0) << 0u) | // Byte 0
	             (*(*buffer + 1) << 8u);  // Byte 1
	*buffer += 2;
}

static inline void
read_i24_to_i32(const uint8_t **buffer, int32_t *out_value)
{
	*out_value = (*(*buffer + 0) << 0u) | // Byte 0
	             (*(*buffer + 1) << 8u) | // Byte 1
	             (*(*buffer + 2) << 16u); // Byte 2
	if (*(*buffer + 2) & 0x80u)
		*out_value |= (0xFFu << 24u); // Properly sign extend.
	*buffer += 3;
}

static inline void
read_i32(const uint8_t **buffer, int32_t *out_value)
{
	*out_value = (*(*buffer + 0) << 0u) |  // Byte 0
	             (*(*buffer + 1) << 8u) |  // Byte 1
	             (*(*buffer + 2) << 16u) | // Byte 2
	             (*(*buffer + 3) << 24u);  // Byte 3
	*buffer += 4;
}

static inline void
read_i16_rev(const uint8_t **buffer, int16_t *out_value)
{
	*out_value = (*(*buffer + 1) << 0u) | // Byte 1
	             (*(*buffer + 0) << 8u);  // Byte 2
	*buffer += 2;
}

static inline void
read_i15_to_i32(const uint8_t **buffer, int32_t *out_value)
{
	int16_t v = (*(*buffer + 0) << 0u) | // Byte 0
	            (*(*buffer + 1) << 8u);  // Byte 1
	v = (v ^ 0x8000);                    // Flip sign bit
	*out_value = v;                      // Properly sign extend.
	*buffer += 2;
}

static inline void
read_i32_rev(const uint8_t **buffer, int32_t *out_value)
{
	*out_value = (*(*buffer + 3) << 0u) |  // Byte 3
	             (*(*buffer + 2) << 8u) |  // Byte 2
	             (*(*buffer + 1) << 16u) | // Byte 1
	             (*(*buffer + 0) << 24u);  // Byte 0
	*buffer += 4;
}

static inline void
read_u8(const uint8_t **buffer, uint8_t *out_value)
{
	*out_value = **buffer;
	*buffer += 1;
}

static inline void
read_u16(const uint8_t **buffer, uint16_t *out_value)
{
	*out_value = (*(*buffer + 0) << 0u) | // Byte 0
	             (*(*buffer + 1) << 8u);  // Byte 1
	*buffer += 2;
}

static inline void
read_u32(const uint8_t **buffer, uint32_t *out_value)
{
	*out_value = (*(*buffer + 0) << 0u) |  // Byte 0
	             (*(*buffer + 1) << 8u) |  // Byte 1
	             (*(*buffer + 2) << 16u) | // Byte 2
	             (*(*buffer + 3) << 24u);  // Byte 3
	*buffer += 4;
}

static inline void
read_u64(const uint8_t **buffer, uint64_t *out_value)
{
	*out_value = ((uint64_t) * (*buffer + 0) << 0u) |  // Byte 0
	             ((uint64_t) * (*buffer + 1) << 8u) |  // Byte 1
	             ((uint64_t) * (*buffer + 2) << 16u) | // Byte 2
	             ((uint64_t) * (*buffer + 3) << 24u) | // Byte 3
	             ((uint64_t) * (*buffer + 4) << 32u) | // Byte 4
	             ((uint64_t) * (*buffer + 5) << 40u) | // Byte 5
	             ((uint64_t) * (*buffer + 6) << 48u) | // Byte 6
	             ((uint64_t) * (*buffer + 7) << 56u);  // Byte 7
	*buffer += 8;
}

static inline void
read_u8_array(const uint8_t **buffer, uint8_t *out_value, size_t num)
{
	memcpy(out_value, (*buffer), num);
	*buffer += num;
}


/*
 *
 * JSON helpers.
 *
 */

static void
read_json_vec3(const nx_json *object, const char *const string, vec3f *out_vec3)
{
	const nx_json *obj_vec3 = nx_json_get(object, string);

	if ((!obj_vec3) || (obj_vec3->type != NX_JSON_ARRAY) || (obj_vec3->length != 3)) {
		return;
	}

	const nx_json *obj_x = nx_json_item(obj_vec3, 0);
	const nx_json *obj_y = nx_json_item(obj_vec3, 1);
	const nx_json *obj_z = nx_json_item(obj_vec3, 2);

	out_vec3->x = (float)obj_x->dbl_value;
	out_vec3->y = (float)obj_y->dbl_value;
	out_vec3->z = (float)obj_z->dbl_value;
}

static void
read_json_quat(const nx_json *object, const char *const string, quatf *out_quat)
{
	const nx_json *obj_quat = nx_json_get(object, string);

	if ((!obj_quat) || (obj_quat->type != NX_JSON_ARRAY) || (obj_quat->length != 4)) {
		return;
	}

	const nx_json *obj_x = nx_json_item(obj_quat, 0);
	const nx_json *obj_y = nx_json_item(obj_quat, 1);
	const nx_json *obj_z = nx_json_item(obj_quat, 2);
	const nx_json *obj_w = nx_json_item(obj_quat, 3);

	out_quat->x = (float)obj_x->dbl_value;
	out_quat->y = (float)obj_y->dbl_value;
	out_quat->z = (float)obj_z->dbl_value;
	out_quat->w = (float)obj_w->dbl_value;
}

static void
read_json_array(const nx_json *object, const char *const string, int size, float *out_array)
{
	const nx_json *obj_array = nx_json_get(object, string);

	if ((!obj_array) || (obj_array->type != NX_JSON_ARRAY) || (obj_array->length != size)) {
		return;
	}

	for (int i = 0; i < size; i++) {
		const nx_json *obj_i = nx_json_item(obj_array, i);

		if (!obj_i) {
			break;
		}

		out_array[i] = (float)obj_i->dbl_value;
	}
}


/*
 *
 * Helpers.
 *
 */

static void
read_sample(const uint8_t **buffer, struct na_parsed_sample *sample)
{
	read_i16(buffer, &sample->gyro_multiplier);
	read_i32(buffer, &sample->gyro_divisor);

	read_i24_to_i32(buffer, &sample->gyro.x);
	read_i24_to_i32(buffer, &sample->gyro.y);
	read_i24_to_i32(buffer, &sample->gyro.z);

	read_i16(buffer, &sample->accel_multiplier);
	read_i32(buffer, &sample->accel_divisor);

	read_i24_to_i32(buffer, &sample->accel.x);
	read_i24_to_i32(buffer, &sample->accel.y);
	read_i24_to_i32(buffer, &sample->accel.z);

	read_i16_rev(buffer, &sample->mag_multiplier);
	read_i32_rev(buffer, &sample->mag_divisor);

	read_i15_to_i32(buffer, &sample->mag.x);
	read_i15_to_i32(buffer, &sample->mag.y);
	read_i15_to_i32(buffer, &sample->mag.z);
}


/*
 *
 * Exported functions.
 *
 */

bool
na_parse_calibration_buffer(struct na_parsed_calibration *calibration, char *buffer, size_t size)
{
	const nx_json *root = nx_json_parse(buffer, 0);

	const nx_json *imu = nx_json_get(root, "IMU");
	const nx_json *dev1 = nx_json_get(imu, "device_1");

	read_json_vec3(dev1, "accel_bias", &calibration->accel_bias);
	read_json_quat(dev1, "accel_q_gyro", &calibration->accel_q_gyro);
	read_json_vec3(dev1, "gyro_bias", &calibration->gyro_bias);
	read_json_quat(dev1, "gyro_q_mag", &calibration->gyro_q_mag);
	read_json_vec3(dev1, "mag_bias", &calibration->mag_bias);

	read_json_vec3(dev1, "scale_accel", &calibration->scale_accel);
	read_json_vec3(dev1, "scale_gyro", &calibration->scale_gyro);
	read_json_vec3(dev1, "scale_mag", &calibration->scale_mag);

	read_json_array(dev1, "imu_noises", 4, calibration->imu_noises);

	nx_json_free(root);
	return true;
}

bool
na_parse_sensor_packet(struct na_parsed_sensor *sensor, const uint8_t *buffer, int size)
{
	const uint8_t *start = buffer;

	if (size != 64) {
		return false;
	}

	if (buffer[0] != 1) {
		return false;
	}

	// Header
	skip(&buffer, 2);

	// Temperature
	read_i16(&buffer, &sensor->temperature);

	// Timestamp
	read_u64(&buffer, &sensor->timestamp);

	// Sample
	read_sample(&buffer, &sensor->sample);

	// Checksum
	skip(&buffer, 4);

	// Unknown, skip 6 bytes.
	skip(&buffer, 6);

	return (size_t)buffer - (size_t)start == 64;
}

bool
na_parse_sensor_control_data_packet(struct na_parsed_sensor_control_data *data, const uint8_t *buffer, int size)
{
	const uint8_t *start = buffer;

	if (size != 64) {
		return false;
	}

	// Header
	skip(&buffer, 1);

	// Checksum
	skip(&buffer, 4);

	// Length
	read_u16(&buffer, &data->length);

	// MSGID
	read_u8(&buffer, &data->msgid);

	// Sensor control data depending on action
	read_u8_array(&buffer, data->data, 56);

	return (size_t)buffer - (size_t)start == 64;
}

bool
na_parse_control_packet(struct na_parsed_control *control, const uint8_t *buffer, int size)
{
	const uint8_t *start = buffer;

	if (size != 64) {
		return false;
	}

	// Header
	skip(&buffer, 1);

	// Checksum
	skip(&buffer, 4);

	// Length
	read_u16(&buffer, &control->length);

	// Timestamp
	read_u64(&buffer, &control->timestamp);

	// Action
	read_u16(&buffer, &control->action);

	// Reserved, skip 5 bytes.
	skip(&buffer, 5);

	// Control data depending on action
	read_u8_array(&buffer, control->data, 42);

	return (size_t)buffer - (size_t)start == 64;
}
