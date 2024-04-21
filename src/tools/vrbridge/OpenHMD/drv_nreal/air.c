// Copyright 2023, Tobias Frisch
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  Nreal Air packet parsing implementation.
 * @author Tobias Frisch <thejackimonster@gmail.com>
 */

#include "air.h"

#include "../openhmdi.h"

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <math.h>
#include <hidapi.h>

#define SENSOR_BUFFER_SIZE 64
#define CONTROL_BUFFER_SIZE 64

#define SENSOR_HEAD 0xFD
#define CONTROL_HEAD 0xFD

typedef int64_t timepoint_ns;
typedef int64_t time_duration_ns;

#define OHMD_GRAVITY_EARTH 9.80665 // m/s²
#define U_TYPED_ARRAY_CALLOC(TYPE, COUNT) ((TYPE *)calloc((COUNT), sizeof(TYPE)))
#define CLAMP(X, A, B) (OHMD_MIN(OHMD_MAX((X), (A)), (B)))

/*!
 * Private struct for the nreal_air device.
 *
 * @ingroup drv_na
 * @implements ohmd_device
 */
struct na_hmd
{
	struct ohmd_device base;
	int id;

	//! Owned by the @ref oth thread.
	hid_device *hid_sensor;

	//! Owned and protected by the device_mutex.
	hid_device *hid_control;
	ohmd_mutex* device_mutex;

	//! Used to read sensor packets.
	ohmd_thread* oth;
	bool thread_running;
	ohmd_mutex* thread_mutex;

	//! Only touched from the sensor thread.
	timepoint_ns last_sensor_time;

	struct na_parsed_sensor last;

	struct
	{
		uint8_t brightness;
		uint8_t display_mode;
	} wants;

	struct
	{
		uint8_t brightness;
		uint8_t display_mode;
	} state;

	struct
	{
		float temperature;

		vec3f gyro;
		vec3f accel;
		vec3f mag;
	} read;

	uint32_t static_id;
	bool display_on;
	uint8_t imu_stream_state;

	// enum u_logging_level log_level;
	int log_level;

	uint32_t calibration_buffer_len;
	uint32_t calibration_buffer_pos;
	char *calibration_buffer;
	bool calibration_valid;

	struct na_parsed_calibration calibration;

	struct
	{
		bool last_frame;
		bool calibration;
	} gui;

	fusion fusion;
	struct m_relation_history *relation_hist;
};

/*
 *
 * Helper functions.
 *
 */

static inline struct na_hmd *
na_hmd(struct ohmd_device *dev)
{
	return (struct na_hmd *)dev;
}

const uint32_t crc32_table[256] = {
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3, 0x0EDB8832,
    0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91, 0x1DB71064, 0x6AB020F2,
    0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7, 0x136C9856, 0x646BA8C0, 0xFD62F97A,
    0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5, 0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
    0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B, 0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3,
    0x45DF5C75, 0xDCD60DCF, 0xABD13D59, 0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423,
    0xCFBA9599, 0xB8BDA50F, 0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB,
    0xB6662D3D, 0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01, 0x6B6B51F4,
    0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457, 0x65B0D9C6, 0x12B7E950,
    0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65, 0x4DB26158, 0x3AB551CE, 0xA3BC0074,
    0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB, 0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
    0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9, 0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525,
    0x206F85B3, 0xB966D409, 0xCE61E49F, 0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81,
    0xB7BD5C3B, 0xC0BA6CAD, 0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615,
    0x73DC1683, 0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7, 0xFED41B76,
    0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5, 0xD6D6A3E8, 0xA1D1937E,
    0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B, 0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6,
    0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79, 0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
    0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F, 0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7,
    0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D, 0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F,
    0x72076785, 0x05005713, 0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7,
    0x0BDBDF21, 0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45, 0xA00AE278,
    0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB, 0xAED16A4A, 0xD9D65ADC,
    0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9, 0xBDBDF21C, 0xCABAC28A, 0x53B39330,
    0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF, 0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
    0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D};

static uint32_t
crc32_checksum(const uint8_t *buf, uint32_t len)
{
	uint32_t CRC32_data = 0xFFFFFFFF;
	for (uint32_t i = 0; i < len; i++) {
		const uint8_t t = (CRC32_data ^ buf[i]) & 0xFFu;
		CRC32_data = ((CRC32_data >> 8u) & 0xFFFFFFu) ^ crc32_table[t];
	}

	return ~CRC32_data;
}

static uint8_t
scale_brightness(uint8_t brightness)
{
	float relative = ((float)brightness - NA_BRIGHTNESS_MIN) / (NA_BRIGHTNESS_MAX - NA_BRIGHTNESS_MIN);
	relative = CLAMP(relative, 0.0f, 1.0f);
	return (uint8_t)(relative * 100.0f);
}

static uint8_t
unscale_brightness(uint8_t scaled_brightness)
{
	float relative = ((float)scaled_brightness) / 100.0f;
	relative = CLAMP(relative, 0.0f, 1.0f);
	return (uint8_t)(relative * (NA_BRIGHTNESS_MAX - NA_BRIGHTNESS_MIN)) + NA_BRIGHTNESS_MIN;
}

/*
 *
 * Sensor functions.
 *
 */

static bool
send_payload_to_sensor(struct na_hmd *hmd, uint8_t msgid, const uint8_t *data, uint8_t len)
{
	uint8_t payload[SENSOR_BUFFER_SIZE];

	const uint16_t packet_len = 3 + len;
	const uint16_t payload_len = 5 + packet_len;

	payload[0] = 0xAA;
	payload[5] = (packet_len & 0xFFu);
	payload[6] = ((packet_len >> 8u) & 0xFFu);
	payload[7] = msgid;

	memcpy(payload + 8, data, len);

	const uint32_t checksum = crc32_checksum(payload + 5, packet_len);

	payload[1] = (checksum & 0xFFu);
	payload[2] = ((checksum >> 8u) & 0xFFu);
	payload[3] = ((checksum >> 16u) & 0xFFu);
	payload[4] = ((checksum >> 24u) & 0xFFu);

	return hid_write(hmd->hid_sensor, payload, payload_len);
}

static void
pre_biased_coordinate_system(vec3f *out)
{
	const float y = out->y;
	out->x = -out->x;
	out->y = -out->z;
	out->z = -y;
}

static void
post_biased_coordinate_system(const vec3f *in, vec3f *out)
{
	out->x = in->x;
	out->y = -in->y;
	out->z = -in->z;
}

static void
read_sample_and_apply_calibration(struct na_hmd *hmd,
                                  struct na_parsed_sample *sample,
                                  vec3f *out_accel,
                                  vec3f *out_gyro,
                                  vec3f *out_mag)
{
	const float accel_factor = (float)sample->accel_multiplier / (float)sample->accel_divisor;
	const float gyro_factor = (float)sample->gyro_multiplier / (float)sample->gyro_divisor;
	const float mag_factor = (float)sample->mag_multiplier / (float)sample->mag_divisor;

	// Convert from raw values to real ones.

	vec3f accel;
	accel.x = (float)sample->accel.x;
	accel.y = (float)sample->accel.y;
	accel.z = (float)sample->accel.z;

	vec3f gyro;
	gyro.x = (float)sample->gyro.x;
	gyro.y = (float)sample->gyro.y;
	gyro.z = (float)sample->gyro.z;

	vec3f mag;
	mag.x = (float)sample->mag.x;
	mag.y = (float)sample->mag.y;
	mag.z = (float)sample->mag.z;

	accel.x *= accel_factor;
	accel.y *= accel_factor;
	accel.z *= accel_factor;

	gyro.x *= gyro_factor;
	gyro.y *= gyro_factor;
	gyro.z *= gyro_factor;
	
	mag.x *= mag_factor;
	mag.y *= mag_factor;
	mag.z *= mag_factor;

	// Apply misalignment via quaternions.

	quatf accel_q_mag;
	oquatf_mult(&hmd->calibration.accel_q_gyro, &hmd->calibration.gyro_q_mag, &accel_q_mag);
	oquatf_get_rotated(&hmd->calibration.accel_q_gyro, &gyro, &gyro);
	oquatf_get_rotated(&accel_q_mag, &mag, &mag);

	// Go from Gs to m/s2.
	accel.x *= (float)+OHMD_GRAVITY_EARTH;
	accel.y *= (float)+OHMD_GRAVITY_EARTH;
	accel.z *= (float)+OHMD_GRAVITY_EARTH;

	// Got from angles to radians.
	gyro.x *= (float)+M_PI / 180.0f;
	gyro.y *= (float)+M_PI / 180.0f;
	gyro.z *= (float)+M_PI / 180.0f;

	// Apply bias correction and scaling factors.

	pre_biased_coordinate_system(&accel);
	pre_biased_coordinate_system(&gyro);
	pre_biased_coordinate_system(&mag);

	ovec3f_subtract(&accel, &hmd->calibration.accel_bias, &accel);
	ovec3f_subtract(&gyro, &hmd->calibration.gyro_bias, &gyro);
	ovec3f_subtract(&mag, &hmd->calibration.mag_bias, &mag);

	accel.x *= hmd->calibration.scale_accel.x;
	accel.y *= hmd->calibration.scale_accel.y;
	accel.z *= hmd->calibration.scale_accel.z;

	gyro.x *= hmd->calibration.scale_gyro.x;
	gyro.y *= hmd->calibration.scale_gyro.y;
	gyro.z *= hmd->calibration.scale_gyro.z;

	mag.x *= hmd->calibration.scale_mag.x;
	mag.y *= hmd->calibration.scale_mag.y;
	mag.z *= hmd->calibration.scale_mag.z;

	post_biased_coordinate_system(&accel, out_accel);
	post_biased_coordinate_system(&gyro, out_gyro);
	post_biased_coordinate_system(&mag, out_mag);
}

static void
update_fusion_locked(struct na_hmd *hmd, struct na_parsed_sample *sample, uint64_t delta_ns)
{
	read_sample_and_apply_calibration(hmd, sample, &hmd->read.accel, &hmd->read.gyro, &hmd->read.mag);
	float delta_s = delta_ns * 1e-9f; 
	ofusion_update(&hmd->fusion, delta_s, &hmd->read.gyro, &hmd->read.accel, &hmd->read.mag);
}

static void
update_fusion(struct na_hmd *hmd, struct na_parsed_sample *sample, uint64_t delta_ns)
{
	ohmd_lock_mutex(hmd->device_mutex);
	update_fusion_locked(hmd, sample, delta_ns);
	ohmd_unlock_mutex(hmd->device_mutex);
}

static uint32_t
calc_delta_and_handle_rollover(uint32_t next, uint32_t last)
{
	uint32_t tick_delta = next - last;

	// The 24-bit tick counter has rolled over,
	// adjust the "negative" value to be positive.
	if (tick_delta > 0xffffff) {
		tick_delta += 0x1000000;
	}

	return tick_delta;
}

static void
request_sensor_control_get_cal_data_length(struct na_hmd *hmd)
{
	// Request calibration data length.

	if (!send_payload_to_sensor(hmd, NA_MSG_GET_CAL_DATA_LENGTH, NULL, 0)) {
		LOGE("Failed to send payload for receiving calibration data length!");
	}
}

static void
request_sensor_control_cal_data_get_next_segment(struct na_hmd *hmd)
{
	// Request next segment of calibration data.

	if (!send_payload_to_sensor(hmd, NA_MSG_CAL_DATA_GET_NEXT_SEGMENT, NULL, 0)) {
		LOGE("Failed to send payload for receiving next calibration data segment! %d / %d",
		         hmd->calibration_buffer_pos, hmd->calibration_buffer_len);
	}
}

static void
request_sensor_control_get_static_id(struct na_hmd *hmd)
{
	// Request the static id.

	if (!send_payload_to_sensor(hmd, NA_MSG_GET_STATIC_ID, NULL, 0)) {
		LOGE("Failed to send payload for receiving static id!");
	}
}

static void
request_sensor_control_start_imu_data(struct na_hmd *hmd, uint8_t imu_stream_state)
{
	// Request to change the imu stream state.

	if (!send_payload_to_sensor(hmd, NA_MSG_START_IMU_DATA, &imu_stream_state, 1)) {
		LOGE("Failed to send payload for changing the imu stream state! %d", imu_stream_state);
	}
}

static void
handle_sensor_control_get_cal_data_length(struct na_hmd *hmd, const struct na_parsed_sensor_control_data *data)
{
	// Read calibration data length.
	const uint32_t calibration_data_length =
	    ((data->data[0] << 0u) | (data->data[1] << 8u) | (data->data[2] << 16u) | (data->data[3] << 24u));

	hmd->calibration_buffer_len = calibration_data_length;

	if (hmd->calibration_buffer_len > 0) {
		if (hmd->calibration_buffer) {
			free(hmd->calibration_buffer);
		}

		// Allocate calibration buffer.
		hmd->calibration_buffer = U_TYPED_ARRAY_CALLOC(char, hmd->calibration_buffer_len);
		hmd->calibration_buffer_pos = 0;
	}

	if (hmd->calibration_buffer) {
		request_sensor_control_cal_data_get_next_segment(hmd);
	}
}

static void
handle_sensor_control_cal_data_get_next_segment(struct na_hmd *hmd, const struct na_parsed_sensor_control_data *data)
{
	if (hmd->calibration_buffer_len == 0) {
		request_sensor_control_get_cal_data_length(hmd);
		return;
	}

	if (hmd->calibration_buffer_len <= hmd->calibration_buffer_pos) {
		LOGE("Failed to receive next calibration data segment! %d / %d", hmd->calibration_buffer_pos,
		         hmd->calibration_buffer_len);
		return;
	}

	const uint32_t remaining = (hmd->calibration_buffer_len - hmd->calibration_buffer_pos);
	const uint8_t next = (remaining > 56 ? 56 : remaining);

	if (hmd->calibration_buffer) {
		memcpy(hmd->calibration_buffer + hmd->calibration_buffer_pos, data->data, next);
	} else {
		request_sensor_control_get_cal_data_length(hmd);
		return;
	}

	hmd->calibration_buffer_pos += next;

	if (hmd->calibration_buffer_pos == hmd->calibration_buffer_len) {
		// Parse calibration data from raw json.
		if (!na_parse_calibration_buffer(&hmd->calibration, hmd->calibration_buffer,
		                                 hmd->calibration_buffer_len)) {
			LOGE("Failed parse calibration data!");
		} else {
			hmd->calibration_valid = true;

			// Switch to imu sensor data stream
			request_sensor_control_start_imu_data(hmd, 0x01);
		}

		// Free calibration buffer.
		free(hmd->calibration_buffer);
		hmd->calibration_buffer = NULL;
		hmd->calibration_buffer_len = 0;
		hmd->calibration_buffer_pos = 0;
	} else {
		request_sensor_control_cal_data_get_next_segment(hmd);
	}
}

static void
handle_sensor_control_start_imu_data(struct na_hmd *hmd, const struct na_parsed_sensor_control_data *data)
{
	// Read the imu stream state.
	const uint8_t imu_stream_state = data->data[0];

	hmd->imu_stream_state = imu_stream_state;

	if (hmd->static_id == 0) {
		request_sensor_control_get_static_id(hmd);
	} else if (!hmd->calibration_valid) {
		request_sensor_control_get_cal_data_length(hmd);
	}
}

static void
handle_sensor_control_get_static_id(struct na_hmd *hmd, const struct na_parsed_sensor_control_data *data)
{
	// Read the static id.
	const uint32_t static_id =
	    ((data->data[0] << 0u) | (data->data[1] << 8u) | (data->data[2] << 16u) | (data->data[3] << 24u));

	hmd->static_id = static_id;

	if (!hmd->calibration_valid) {
		request_sensor_control_get_cal_data_length(hmd);
	}
}

static void
handle_sensor_control_data_msg(struct na_hmd *hmd, unsigned char *buffer, int size)
{
	struct na_parsed_sensor_control_data data;

	if (!na_parse_sensor_control_data_packet(&data, buffer, size)) {
		LOGE("Could not decode sensor control data packet");
	}

	hmd->imu_stream_state = 0xAA;

	switch (data.msgid) {
	case NA_MSG_GET_CAL_DATA_LENGTH: handle_sensor_control_get_cal_data_length(hmd, &data); break;
	case NA_MSG_CAL_DATA_GET_NEXT_SEGMENT: handle_sensor_control_cal_data_get_next_segment(hmd, &data); break;
	case NA_MSG_ALLOCATE_CAL_DATA_BUFFER: break;
	case NA_MSG_WRITE_CAL_DATA_SEGMENT: break;
	case NA_MSG_FREE_CAL_BUFFER: break;
	case NA_MSG_START_IMU_DATA: handle_sensor_control_start_imu_data(hmd, &data); break;
	case NA_MSG_GET_STATIC_ID: handle_sensor_control_get_static_id(hmd, &data); break;
	default: LOGE("Got unknown sensor control data msgid, 0x%02x", data.msgid); break;
	}
}

static void
handle_sensor_msg(struct na_hmd *hmd, unsigned char *buffer, int size)
{
	if (buffer[0] == 0xAA) {
		handle_sensor_control_data_msg(hmd, buffer, size);
		return;
	}

	uint64_t last_timestamp = hmd->last.timestamp;

	if (!na_parse_sensor_packet(&hmd->last, buffer, size)) {
		LOGE("Could not decode sensor packet");
	} else {
		hmd->imu_stream_state = 0x1;
	}

	if (!hmd->calibration_valid) {
		request_sensor_control_start_imu_data(hmd, 0xAA);
	}

	struct na_parsed_sensor *s = &hmd->last;

	// According to the ICM-42688-P datasheet: (offset: 25 °C, sensitivity: 132.48 LSB/°C)
	hmd->read.temperature = ((float)s->temperature) / 132.48f + 25.0f;

	uint32_t delta = calc_delta_and_handle_rollover(s->timestamp, last_timestamp);

	time_duration_ns inter_sample_duration_ns = delta;

	// If this is larger then one second something bad is going on.
	// Before checking this, be shure that fusion not in initial state
	if (hmd->fusion.iterations != 0 &&
	    inter_sample_duration_ns >= (time_duration_ns)1e9) {
		LOGE("Drop packet (sensor too slow): %lu", inter_sample_duration_ns);
		return;
	}

	// Update the fusion with the sample.
	update_fusion(hmd, &s->sample, inter_sample_duration_ns);
}

static void
sensor_clear_queue(struct na_hmd *hmd)
{
	uint8_t buffer[SENSOR_BUFFER_SIZE];

	hid_set_nonblocking(hmd->hid_sensor, 1);
	while (hid_read(hmd->hid_sensor, buffer, SENSOR_BUFFER_SIZE) > 0) {
		// Just drop the packets.
	}
	hid_set_nonblocking(hmd->hid_sensor, 0);
}

static int
sensor_read_one_packet(struct na_hmd *hmd)
{
	uint8_t buffer[SENSOR_BUFFER_SIZE];

	int size = hid_read_timeout(hmd->hid_sensor, buffer, SENSOR_BUFFER_SIZE, 500);
	if (size <= 0) {
		return size;
	}

	handle_sensor_msg(hmd, buffer, size);
	return 0;
}

static int
read_one_control_packet(struct na_hmd *hmd);

static unsigned int
read_thread(void *ptr)
{
	struct na_hmd *hmd = (struct na_hmd *)ptr;
	int ret = 0;

	ohmd_lock_mutex(hmd->thread_mutex);

	request_sensor_control_start_imu_data(hmd, 0xAA);

	while (hmd->thread_running && ret >= 0) {
		ohmd_unlock_mutex(hmd->thread_mutex);

		ret = read_one_control_packet(hmd);

		if (ret >= 0) {
			ret = sensor_read_one_packet(hmd);
		}

		ohmd_lock_mutex(hmd->thread_mutex);
	}

	if (hmd->calibration_buffer) {
		// Free calibration buffer
		free(hmd->calibration_buffer);
		hmd->calibration_buffer = NULL;
		hmd->calibration_buffer_len = 0;
		hmd->calibration_buffer_pos = 0;
	}

	ohmd_unlock_mutex(hmd->thread_mutex);

	return 0;
}

/*
 *
 * Control functions.
 *
 */
static bool
send_payload_to_control(struct na_hmd *hmd, uint16_t msgid, const uint8_t *data, uint8_t len)
{
	uint8_t payload[CONTROL_BUFFER_SIZE];

	const uint16_t packet_len = 17 + len;
	const uint16_t payload_len = 5 + packet_len;

	payload[0] = CONTROL_HEAD;
	payload[5] = (packet_len & 0xFFu);
	payload[6] = ((packet_len >> 8u) & 0xFFu);

	// Timestamp
	memset(payload + 7, 0, 8);

	payload[15] = (msgid & 0xFFu);
	payload[16] = ((msgid >> 8u) & 0xFFu);

	// Reserved
	memset(payload + 17, 0, 5);

	memcpy(payload + 22, data, len);

	const uint32_t checksum = crc32_checksum(payload + 5, packet_len);

	payload[1] = (checksum & 0xFFu);
	payload[2] = ((checksum >> 8u) & 0xFFu);
	payload[3] = ((checksum >> 16u) & 0xFFu);
	payload[4] = ((checksum >> 24u) & 0xFFu);

	return hid_write(hmd->hid_control, payload, payload_len);
}

static void
handle_control_brightness(struct na_hmd *hmd, const struct na_parsed_control *control)
{
	// Check status
	if (control->data[0] != 0) {
		return;
	}

	// Brightness
	const uint8_t brightness = scale_brightness(control->data[1]);

	hmd->state.brightness = brightness;
	hmd->wants.brightness = brightness;
}

static void
handle_control_display_mode(struct na_hmd *hmd, const struct na_parsed_control *control)
{
	// Check status
	if (control->data[0] != 0) {
		return;
	}

	// Display mode
	const uint8_t display_mode = control->data[1];

	hmd->state.display_mode = display_mode;
	hmd->wants.display_mode = display_mode;
}

static void
handle_control_heartbeat_start(struct na_hmd *hmd, const struct na_parsed_control *control)
{
	// TODO
}

static void
handle_control_button(struct na_hmd *hmd, const struct na_parsed_control *control)
{
	// Physical button
	const uint8_t phys_button = control->data[0];

	// Virtual button
	const uint8_t virt_button = control->data[4];

	// Brightness if the button changes it (or display state)
	const uint8_t value = control->data[8];

	switch (virt_button) {
	case NA_BUTTON_VIRT_DISPLAY_TOGGLE: {
		hmd->display_on = value;
		break;
	}
	case NA_BUTTON_VIRT_MENU_TOGGLE: break;
	case NA_BUTTON_VIRT_BRIGHTNESS_UP:
	case NA_BUTTON_VIRT_BRIGHTNESS_DOWN: {
		const uint8_t brightness = scale_brightness(value);

		hmd->state.brightness = brightness;
		hmd->wants.brightness = brightness;
		break;
	}
	case NA_BUTTON_VIRT_MODE_UP: {
		const uint8_t display_mode = hmd->state.display_mode;

		if (display_mode == NA_DISPLAY_MODE_2D) {
			hmd->wants.display_mode = NA_DISPLAY_MODE_3D;
		}

		break;
	}
	case NA_BUTTON_VIRT_MODE_DOWN: {
		const uint8_t display_mode = hmd->state.display_mode;

		if (display_mode == NA_DISPLAY_MODE_3D) {
			hmd->wants.display_mode = NA_DISPLAY_MODE_2D;
		}

		break;
	}
	default: {
		LOGE("Got unknown button pressed, 0x%02x (0x%02x)", virt_button, phys_button);
		break;
	}
	}
}

static void
handle_control_async_text(struct na_hmd *hmd, const struct na_parsed_control *control)
{
	// Event only appears if the display is active!
	hmd->display_on = true;

	LOGD("Control message: %s", (const char *)control->data);
}

static void
handle_control_heartbeat_end(struct na_hmd *hmd, const struct na_parsed_control *control)
{
	// TODO
}

static void
handle_control_action_locked(struct na_hmd *hmd, const struct na_parsed_control *control)
{
	switch (control->action) {
	case NA_MSG_R_BRIGHTNESS: handle_control_brightness(hmd, control); break;
	case NA_MSG_W_BRIGHTNESS: break;
	case NA_MSG_R_DISP_MODE: handle_control_display_mode(hmd, control); break;
	case NA_MSG_W_DISP_MODE: break;
	case NA_MSG_P_START_HEARTBEAT: handle_control_heartbeat_start(hmd, control); break;
	case NA_MSG_P_BUTTON_PRESSED: handle_control_button(hmd, control); break;
	case NA_MSG_P_ASYNC_TEXT_LOG: handle_control_async_text(hmd, control); break;
	case NA_MSG_P_END_HEARTBEAT: handle_control_heartbeat_end(hmd, control); break;
	default: LOGE("Got unknown control action, 0x%02x", control->action); break;
	}
}

static void
handle_control_msg(struct na_hmd *hmd, unsigned char *buffer, int size)
{
	struct na_parsed_control control;

	if (!na_parse_control_packet(&control, buffer, size)) {
		LOGE("Could not decode control packet");
	}

	ohmd_lock_mutex(hmd->device_mutex);
	handle_control_action_locked(hmd, &control);
	ohmd_unlock_mutex(hmd->device_mutex);
}

static void
control_clear_queue(struct na_hmd *hmd)
{
	uint8_t buffer[CONTROL_BUFFER_SIZE];

	while (hid_read(hmd->hid_control, buffer, CONTROL_BUFFER_SIZE) > 0) {
		// Just drop the packets.
	}
}

static int
read_one_control_packet(struct na_hmd *hmd)
{
	static uint8_t buffer[CONTROL_BUFFER_SIZE];
	int size = 0;

	size = hid_read(hmd->hid_control, buffer, CONTROL_BUFFER_SIZE);
	if (size == 0) {
		return 0;
	}
	if (size < 0) {
		return -1;
	}

	handle_control_msg(hmd, buffer, size);
	return size;
}

static bool
wait_for_brightness(struct na_hmd *hmd)
{
	for (int i = 0; i < 5000; i++) {
		read_one_control_packet(hmd);

		if (hmd->state.brightness <= 100) {
			return true;
		}

		ohmd_sleep(1e-3); // 1MS
	}

	return false;
}

static bool
wait_for_display_mode(struct na_hmd *hmd)
{
	for (int i = 0; i < 5000; i++) {
		read_one_control_packet(hmd);

		if ((hmd->state.display_mode == NA_DISPLAY_MODE_2D) ||
		    (hmd->state.display_mode == NA_DISPLAY_MODE_3D)) {
			return true;
		}

		ohmd_sleep(1e-3);  // 1MS
	}

	return false;
}

static bool
control_brightness(struct na_hmd *hmd)
{
	if (!send_payload_to_control(hmd, NA_MSG_R_BRIGHTNESS, NULL, 0)) {
		LOGE("Failed to send payload for initial brightness value!");
		return false;
	}

	if (!wait_for_brightness(hmd)) {
		LOGE("Failed to wait for valid brightness value!");
		return false;
	}

	return true;
}

static bool
control_display_mode(struct na_hmd *hmd)
{
	if (!send_payload_to_control(hmd, NA_MSG_R_DISP_MODE, NULL, 0)) {
		LOGE("Failed to send payload for initial display mode!");
		return false;
	}

	if (!wait_for_display_mode(hmd)) {
		LOGE("Failed to wait for valid display mode!");
		return false;
	}

	return true;
}

static bool
switch_display_mode(struct na_hmd *hmd, uint8_t display_mode)
{
	if ((display_mode != NA_DISPLAY_MODE_2D) && (display_mode > NA_DISPLAY_MODE_3D)) {
		return false;
	}

	ohmd_device_properties *info = &hmd->base.properties;

	info->hres = 1920;
	info->vres = 1080;

	info->ratio = (info->hres / (info->vres)) * 0.875f; 
	info->fov = DEG_TO_RAD(46.0f / 2.0f);
	
	info->hsize = 0.13f;
	info->vsize = 0.07f;
	info->lens_sep = 0.13f / 2.0f;
	info->lens_vpos = 0.07f / 2.0f;

	if (display_mode == NA_DISPLAY_MODE_3D) {
		info->hres *= 2;
		info->ratio *= 2.0f;
	}
	
	return true;
}

/*
 *
 * Misc functions.
 *
 */

static void
teardown(struct na_hmd *hmd)
{
	// Shutdown the sensor thread early.
	ohmd_lock_mutex(hmd->thread_mutex);
	hmd->thread_running = false;
	ohmd_unlock_mutex(hmd->thread_mutex);

	if (hmd->hid_control != NULL) {
		hid_close(hmd->hid_control);
		hmd->hid_control = NULL;
	}

	if (hmd->hid_sensor != NULL) {
		hid_close(hmd->hid_sensor);
		hmd->hid_sensor = NULL;
	}

	// Teardown could happen before thread init, so check it initialized.
	if (hmd->oth) {
		ohmd_destroy_thread(hmd->oth);
	}
	ohmd_destroy_mutex(hmd->thread_mutex);
	ohmd_destroy_mutex(hmd->device_mutex);
}

static void
adjust_brightness(struct na_hmd *hmd)
{
	if (hmd->wants.brightness > 100) {
		return;
	}

	if (hmd->wants.brightness == hmd->state.brightness) {
		return;
	}

	const uint8_t raw_brightness = unscale_brightness(hmd->wants.brightness);
	const uint8_t brightness = scale_brightness(raw_brightness);

	if (brightness == hmd->state.brightness) {
		return;
	}

	if (!send_payload_to_control(hmd, NA_MSG_W_BRIGHTNESS, &raw_brightness, 1)) {
		LOGE("Failed to send payload setting custom brightness value!");
		return;
	}

	hmd->state.brightness = brightness;
}

static void
adjust_display_mode(struct na_hmd *hmd)
{
	if ((hmd->wants.display_mode != NA_DISPLAY_MODE_2D) && (hmd->wants.display_mode != NA_DISPLAY_MODE_3D)) {
		return;
	}

	if (hmd->wants.display_mode == hmd->state.display_mode) {
		return;
	}

	const uint8_t display_mode = hmd->wants.display_mode;

	if (!send_payload_to_control(hmd, NA_MSG_W_DISP_MODE, &display_mode, 1)) {
		LOGE("Failed to send payload setting custom display mode!");
		return;
	}

	hmd->state.display_mode = display_mode;
}

/*
 *
 * ohmd_device functions.
 *
 */

static void
na_hmd_update_inputs(struct ohmd_device *xdev)
{
	struct na_hmd *hmd = na_hmd(xdev);

	ohmd_lock_mutex(hmd->device_mutex);

	// Adjust brightness
	adjust_brightness(hmd);

	// Adjust display mode
	adjust_display_mode(hmd);

	ohmd_unlock_mutex(hmd->device_mutex);
}

static void
na_hmd_destroy(struct ohmd_device *xdev)
{
	struct na_hmd *hmd = (struct na_hmd*)xdev;
	teardown(hmd);

	free(&hmd->base);
}

/*
 *
 * Exported functions.
 *
 */

struct ohmd_device *
na_hmd_create_device(
					 struct na_hmd *hmd,
					 hid_device *sensor_device,
                     hid_device *control_device
					)
{
	ofusion_init(&hmd->fusion);

	hmd->static_id = 0;
	hmd->display_on = false;
	hmd->imu_stream_state = 0;

	hmd->calibration_buffer = NULL;
	hmd->calibration_buffer_len = 0;
	hmd->calibration_buffer_pos = 0;
	hmd->calibration_valid = false;

	hmd->state.brightness = 0xFF;
	hmd->state.display_mode = 0x00;

	hmd->wants.brightness = 0xFF;
	hmd->wants.display_mode = 0x00;


	// Do mutex init before any call to teardown happens.
	hmd->device_mutex = ohmd_create_mutex(hmd->base.ctx);
	hmd->thread_mutex = ohmd_create_mutex(hmd->base.ctx);

	if (!sensor_device) {
		goto cleanup;
	}

	hmd->hid_sensor = sensor_device;

	// Empty the queue
	sensor_clear_queue(hmd);

	if (!control_device) {
		goto cleanup;
	}

	hmd->hid_control = control_device;

	// Empty the queue
	control_clear_queue(hmd);

	// Thread init and start
	hmd->thread_running = true;
	hmd->oth = ohmd_create_thread(hmd->base.ctx, read_thread, (void *)hmd);

	if (hmd->oth == 0) {
		goto cleanup;
	}

	if (!control_brightness(hmd) || !control_display_mode(hmd)) {
		goto cleanup;
	}

	/*
	 * Device setup.
	 */

	if (!switch_display_mode(hmd, hmd->state.display_mode)) {
		goto cleanup;
	}

	/*
	 * Finishing touches.
	 */

	LOGD("YES!");

	return &hmd->base;

cleanup:
	LOGD("NO! :(");

	if (hmd->calibration_buffer) {
		free(hmd->calibration_buffer);
	}

	teardown(hmd);
	free(hmd);

	return NULL;
}

// OpenHMD functions

static void update_device(ohmd_device* device)
{
	na_hmd_update_inputs(device);
}

static int getf(ohmd_device* device, ohmd_float_value type, float* out)
{
	struct na_hmd* priv = (struct na_hmd*)device;

	switch(type){
	case OHMD_ROTATION_QUAT:
		*(quatf*)out = priv->fusion.orient;
		break;

	case OHMD_POSITION_VECTOR:
		out[0] = out[1] = out[2] = 0;
		break;

	case OHMD_DISTORTION_K:
		// TODO this should be set to the equivalent of no distortion
		memset(out, 0, sizeof(float) * 6);
		break;
	
	case OHMD_CONTROLS_STATE:
		break;

	default:
		ohmd_set_error(priv->base.ctx, "invalid type given to getf (%ud)", type);
		return OHMD_S_INVALID_PARAMETER;
		break;
	}

	return OHMD_S_OK;
}

static void close_device(ohmd_device* device)
{
	LOGD("closing Nreal Air device");
	struct na_hmd *hmd = (struct na_hmd*)device;
	teardown(hmd);

	free(&hmd->base);
}

static hid_device* open_device_idx(int manufacturer, int product, int iface, int device_index)
{
	struct hid_device_info* devs = hid_enumerate(manufacturer, product);
	struct hid_device_info* cur_dev = devs;

	int idx = 0;
	hid_device* ret = NULL;

	while (cur_dev) {
		LOGI("%04x:%04x %s", manufacturer, product, cur_dev->path);

		if (cur_dev->interface_number == iface) {
			if(idx == device_index){
				LOGI("\topening '%s'", cur_dev->path);
				ret = hid_open_path(cur_dev->path);
				break;
			}

			idx++;
		}

		cur_dev = cur_dev->next;
	}

	hid_free_enumeration(devs);

	return ret;
}

static ohmd_device* open_device(ohmd_driver* driver, ohmd_device_desc* desc)
{
	struct na_hmd* priv = ohmd_alloc(driver->ctx, sizeof(struct na_hmd));

	if(!priv)
		return NULL;

	priv->base.ctx = driver->ctx;

	int idx = atoi(desc->path);

	// Open the HMD sensoe device
	hid_device *sensor = open_device_idx(NA_VID, NA_PID, NA_HANDLE_IFACE, idx);

	if(!sensor)
		goto cleanup;

	// Open the HMD Control device
	hid_device *control = open_device_idx(NA_VID, NA_PID, NA_CONTROL_IFACE, idx);

	if(!control)
		goto cleanup;

	if(hid_set_nonblocking(control, 1) == -1){
		ohmd_set_error(driver->ctx, "failed to set non-blocking on device");
		goto cleanup;
	}

	// Original init
	if (!na_hmd_create_device(priv, sensor, control)){
		ohmd_set_error(driver->ctx, "failed to create device");
		goto cleanup;
	}
	
	// Set default device properties
	ohmd_set_default_device_properties(&priv->base.properties);

	// Set device properties
	switch_display_mode(priv, priv->state.display_mode);

	// calculate projection eye projection matrices from the device properties
	ohmd_calc_default_proj_matrices(&priv->base.properties);

	// set up device callbacks
	priv->base.update = update_device;
	priv->base.close = close_device;
	priv->base.getf = getf;
	
	return (ohmd_device*)priv;

cleanup:
	if (priv) {
		na_hmd_destroy(&priv->base);
	}

	return NULL;
}

static void get_device_list(ohmd_driver* driver, ohmd_device_list* list)
{
	struct hid_device_info* devs = hid_enumerate(NA_VID, NA_PID);
	struct hid_device_info* cur_dev = devs;

	int idx = 0;
	while (cur_dev) {
		if (cur_dev->interface_number == NA_CONTROL_IFACE) {
			ohmd_device_desc* desc = &list->devices[list->num_devices++];

			strcpy(desc->driver, "Nreal Air HMD Driver");
			strcpy(desc->vendor, "Nreal");
			strcpy(desc->product, "Air");
			snprintf(desc->path, OHMD_STR_SIZE, "%d", idx);

			desc->revision = 0;
			desc->id = idx++;

			desc->device_class = OHMD_DEVICE_CLASS_HMD;
			desc->device_flags = OHMD_DEVICE_FLAGS_ROTATIONAL_TRACKING;

			desc->driver_ptr = driver;
		}

		cur_dev = cur_dev->next;
	}

	hid_free_enumeration(devs);
}

static void destroy_driver(ohmd_driver* drv)
{
	LOGD("Shutting down Nreal Air driver");
	free(drv);
}

ohmd_driver* ohmd_create_nreal_drv(ohmd_context* ctx)
{
	ohmd_driver* drv = ohmd_alloc(ctx, sizeof(ohmd_driver));
	if(!drv)
		return NULL;

	drv->get_device_list = get_device_list;
	drv->open_device = open_device;
	drv->destroy = destroy_driver;
	drv->ctx = ctx;

	return drv;
}
