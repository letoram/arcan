/*
 * Copyright 2013, Fredrik Hultin.
 * Copyright 2013, Jakob Bornecrantz.
 * Copyright 2016 Philipp Zabel
 * Copyright 2019 Jan Schmidt
 * SPDX-License-Identifier: BSL-1.0
 *
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* Oculus Rift Driver - Packet Decoding and Utilities */


#include <stdio.h>
#include <string.h>
#include "rift.h"

#define SKIP8 (buffer++)
#define SKIP16 (buffer+=2)
#define SKIP_CMD (buffer++)
#define READ8 *(buffer++);
#define READ16 *buffer | (*(buffer + 1) << 8); buffer += 2;
#define READ32 *buffer | (*(buffer + 1) << 8) | (*(buffer + 2) << 16) | (*(buffer + 3) << 24); buffer += 4;
#define READFLOAT ((float)(*buffer)); buffer += 4;
#define READFIXED (float)(*buffer | (*(buffer + 1) << 8) | (*(buffer + 2) << 16) | (*(buffer + 3) << 24)) / 1000000.0f; buffer += 4;

#define WRITE8(_val) *(buffer++) = (_val);
#define WRITE16(_val) WRITE8((_val) & 0xff); WRITE8(((_val) >> 8) & 0xff);
#define WRITE32(_val) WRITE16((_val) & 0xffff) *buffer; WRITE16(((_val) >> 16) & 0xffff);

bool decode_position_info(pkt_position_info* p, const unsigned char* buffer, int size)
{
	if(size != 30) {
		LOGE("invalid packet size (expected 30 but got %d)", size);
		return false;
	}

	SKIP_CMD;
	SKIP16;
	p->flags = READ8;
	p->pos_x = READ32;
	p->pos_y = READ32;
	p->pos_z = READ32;
	p->dir_x = READ16;
	p->dir_y = READ16;
	p->dir_z = READ16;
	SKIP16;
	p->index = READ8;
	SKIP8;
	p->num = READ8;
	SKIP8;
	p->type = READ8;

	return true;
}

bool decode_led_pattern_info(pkt_led_pattern_report * p, const unsigned char* buffer, int size)
{
	if(size != 12) {
		LOGE("invalid packet size (expected 12 but got %d)", size);
		return false;
	}

	SKIP_CMD;
	SKIP16;
	p->pattern_length = READ8;
	p->pattern = READ32;
	p->index = READ16;
	p->num = READ16;

	return true;
}

bool decode_sensor_range(pkt_sensor_range* range, const unsigned char* buffer, int size)
{
	if(!(size == 8 || size == 9)){
		LOGE("invalid packet size (expected 8 or 9 but got %d)", size);
		return false;
	}

	SKIP_CMD;
	range->command_id = READ16;
	range->accel_scale = READ8;
	range->gyro_scale = READ16;
	range->mag_scale = READ16;

	return true;
}

bool decode_sensor_display_info(pkt_sensor_display_info* info, const unsigned char* buffer, int size)
{
	if(!(size == 56 || size == 57)){
		LOGE("invalid packet size (expected 56 or 57 but got %d)", size);
		return false;
	}

	SKIP_CMD;
	info->command_id = READ16;
	info->distortion_type = READ8;
	info->h_resolution = READ16;
	info->v_resolution = READ16;
	info->h_screen_size = READFIXED;
	info->v_screen_size = READFIXED;
	info->v_center = READFIXED;
	info->lens_separation = READFIXED;
	info->eye_to_screen_distance[0] = READFIXED;
	info->eye_to_screen_distance[1] = READFIXED;

	info->distortion_type_opts = 0;

	for(int i = 0; i < 6; i++){
		info->distortion_k[i] = READFLOAT;
	}

	return true;
}

bool decode_sensor_config(pkt_sensor_config* config, const unsigned char* buffer, int size)
{
	if(!(size == 7 || size == 8)){
		LOGE("invalid packet size (expected 7 or 8 but got %d)", size);
		return false;
	}

	SKIP_CMD;
	config->command_id = READ16;
	config->flags = READ8;
	config->packet_interval = READ8;
	config->keep_alive_interval = READ16;

	return true;
}

static void decode_sample(const unsigned char* buffer, int32_t* smp)
{
	/*
	 * Decode 3 tightly packed 21 bit values from 4 bytes.
	 * We unpack them in the higher 21 bit values first and then shift
	 * them down to the lower in order to get the sign bits correct.
	 */

	int x = (buffer[0] << 24)          | (buffer[1] << 16) | ((buffer[2] & 0xF8) << 8);
	int y = ((buffer[2] & 0x07) << 29) | (buffer[3] << 21) | (buffer[4] << 13) | ((buffer[5] & 0xC0) << 5);
	int z = ((buffer[5] & 0x3F) << 26) | (buffer[6] << 18) | (buffer[7] << 10);

	smp[0] = x >> 11;
	smp[1] = y >> 11;
	smp[2] = z >> 11;
}

bool decode_tracker_sensor_msg_dk1(pkt_tracker_sensor* msg, const unsigned char* buffer, int size)
{
	if(!(size == 62 || size == 64)){
		LOGE("invalid packet size (expected 62 or 64 but got %d)", size);
		return false;
	}

	SKIP_CMD;
	msg->num_samples = READ8;
	msg->total_sample_count = 0; /* No sample count in DK1 */
	msg->timestamp = READ16;
	msg->timestamp *= 1000; // DK1 timestamps are in milliseconds
	buffer += 2; /* Skip unused last_command_id */
	msg->temperature = READ16;

	msg->num_samples = OHMD_MIN(msg->num_samples, 3);
	for(int i = 0; i < msg->num_samples; i++){
		decode_sample(buffer, msg->samples[i].accel);
		buffer += 8;

		decode_sample(buffer, msg->samples[i].gyro);
		buffer += 8;
	}

	// Skip empty samples
	buffer += (3 - msg->num_samples) * 16;
	for(int i = 0; i < 3; i++){
		msg->mag[i] = READ16;
	}

	// positional tracking data and frame data - do these exist on DK1?
	msg->frame_count = 0;
	msg->frame_timestamp = 0;
	msg->frame_id = 0;
	msg->led_pattern_phase = 0;
	msg->exposure_count = 0;
	msg->exposure_timestamp = 0;

	return true;
}

bool decode_tracker_sensor_msg_dk2(pkt_tracker_sensor* msg, const unsigned char* buffer, int size)
{
	if(!(size == 64)){
		LOGE("invalid packet size (expected 64 but got %d)", size);
		return false;
	}

	SKIP_CMD;
	SKIP16;
	msg->num_samples = READ8;
	/* Next is the number of samples since start, excluding the samples
	contained in this packet */
	msg->total_sample_count = READ16;
	msg->temperature = READ16;
	msg->timestamp = READ32;

	/* Second sample value is junk (outdated/uninitialized) value if
	num_samples < 2. */
	msg->num_samples = OHMD_MIN(msg->num_samples, 2);
	for(int i = 0; i < msg->num_samples; i++){
		decode_sample(buffer, msg->samples[i].accel);
		buffer += 8;

		decode_sample(buffer, msg->samples[i].gyro);
		buffer += 8;
	}

	// Skip empty samples
	buffer += (2 - msg->num_samples) * 16;

	for(int i = 0; i < 3; i++){
		msg->mag[i] = READ16;
	}

	// positional tracking data and frame data
	msg->frame_count = READ16;
	msg->frame_timestamp = READ32;
	msg->frame_id = READ8;
	msg->led_pattern_phase = READ8;
	msg->exposure_count = READ16;
	msg->exposure_timestamp = READ32;

	return true;
}

bool decode_radio_address(uint8_t radio_address[5], const unsigned char* buffer, int size)
{
	if (size < 8)
		return false;

	/* Ignore the command and echo bytes, then 5 bytes of radio address payload */
	SKIP_CMD;
	SKIP16;

	memcpy (radio_address, buffer, 5);

	return true;
}

static bool decode_rift_radio_message(pkt_rift_radio_message *m, const unsigned char* buffer)
{
	int i;

	m->flags = READ16;
	m->device_type = READ8;

	/* 2019-6 All the valid messages I've seen have 0x1c or 0x5 in these 16 bits - JS */
	/* 0x5 always seems to be the rift remote, and there are 2 other cases I've seen:
	 * device type 0x22 flags 0x0000 and device type 0x04 flags 0x7600 */
	m->valid = (m->flags == 0x1c || m->flags == 0x05);

	if (!m->valid) {
		LOGV ("Invalid radio report from unknown remote device type 0x%02x flags 0x%04x",
				m->device_type, m->flags);
		return true;
	}

	switch (m->device_type) {
		case RIFT_REMOTE:
			m->remote.buttons = READ16;
			break;
		case RIFT_TOUCH_CONTROLLER_LEFT:
		case RIFT_TOUCH_CONTROLLER_RIGHT: {
			uint8_t tgs[5];

			m->touch.timestamp = READ32;
			for (i = 0; i < 3; i++) {
				m->touch.accel[i] = READ16;
			}
			for (i = 0; i < 3; i++) {
				m->touch.gyro[i] = READ16;
			}

			m->touch.buttons = READ8;

			for (i = 0; i < 5; i++) {
				tgs[i] = READ8;
			}

			m->touch.trigger = tgs[0] | ((tgs[1] & 0x03) << 8);
			m->touch.grip = ((tgs[1] & 0xfc) >> 2) | ((tgs[2] & 0x0f) << 6);
			m->touch.stick[0] = ((tgs[2] & 0xf0) >> 4) | ((tgs[3] & 0x3f) << 4);
			m->touch.stick[1] = ((tgs[3] & 0xc0) >> 6) | ((tgs[4] & 0xff) << 2);

			m->touch.adc_channel = READ8;
			m->touch.adc_value = READ16;
			break;
		}
		default:
			LOGE ("Radio report from unknown remote device type 0x%02x flags 0x%04x",
					m->device_type, m->flags);
			return false;
	}

	return true;
}

bool decode_rift_radio_report(pkt_rift_radio_report *r, const unsigned char* buffer, int size)
{
	if (size != RIFT_RADIO_REPORT_SIZE) {
		LOGE("invalid packet size (expected 64 but got %d)", size);
		return false;
	}

	if (buffer[0] != RIFT_RADIO_REPORT_ID) {
		LOGE("Unknown radio report id 0x%02x\n", buffer[0]);
		return false;
	}

	r->id = READ8;
	SKIP16; // Ignore the echo

	for (int i = 0; i < 2; i++) {
		if (!decode_rift_radio_message (&r->message[i], buffer))
			return false;
		buffer += 28;
	}

	return true;
}

// TODO do we need to consider HMD vs sensor "centric" values
void vec3f_from_rift_vec(const int32_t* smp, vec3f* out_vec)
{
	out_vec->x = (float)smp[0] * 0.0001f;
	out_vec->y = (float)smp[1] * 0.0001f;
	out_vec->z = (float)smp[2] * 0.0001f;
}

int encode_sensor_config(unsigned char* buffer, const pkt_sensor_config* config)
{
	WRITE8(RIFT_CMD_SENSOR_CONFIG);
	WRITE16(config->command_id);
	WRITE8(config->flags);
	WRITE8(config->packet_interval);
	WRITE16(config->keep_alive_interval);
	return 7; // sensor config packet size
}

int encode_tracking_config(unsigned char* buffer, const pkt_tracking_config* tracking)
{
	WRITE8(RIFT_CMD_TRACKING_CONFIG);
	WRITE16(tracking->command_id);
	WRITE8(tracking->pattern);
	WRITE8(tracking->flags);
	WRITE8(tracking->reserved);
	WRITE16(tracking->exposure_us);
	WRITE16(tracking->period_us);
	WRITE16(tracking->vsync_offset);
	WRITE8 (tracking->duty_cycle);

	return 13;
}

int encode_dk1_keep_alive(unsigned char* buffer, const pkt_keep_alive* keep_alive)
{
	WRITE8(RIFT_CMD_DK1_KEEP_ALIVE);
	WRITE16(keep_alive->command_id);
	WRITE16(keep_alive->keep_alive_interval);
	return 5; // keep alive packet size
}

int encode_enable_components(unsigned char* buffer, bool display, bool audio, bool leds)
{
	uint8_t flags = 0;

	WRITE8(RIFT_CMD_ENABLE_COMPONENTS);
	WRITE16(0); // last command ID

	if (display)
		flags |= RIFT_COMPONENT_DISPLAY;
	if (audio)
		flags |= RIFT_COMPONENT_AUDIO;
	if (leds)
		flags |= RIFT_COMPONENT_LEDS;
	WRITE8(flags);
	return 4; // component flags packet size
}

int encode_radio_control_cmd(unsigned char* buffer, uint8_t a, uint8_t b, uint8_t c)
{
	WRITE8(RIFT_CMD_RADIO_CONTROL);
	WRITE16(0); // last command ID
	WRITE8(a);
	WRITE8(b);
	WRITE8(c);

	return 6;
}

int encode_radio_data_read_cmd(unsigned char *buffer, uint16_t offset, uint16_t length)
{
	int i;
	WRITE8(RIFT_CMD_RADIO_READ_DATA);
	WRITE16(0); // last command ID
	WRITE16(offset);
	WRITE16(length);

	for (i = 0; i < 28; i++) {
		WRITE8(0);
	}

	return 31;
}

void dump_packet_sensor_range(const pkt_sensor_range* range)
{
	(void)range;

	LOGD("sensor range\n");
	LOGD("  command id:  %d", range->command_id);
	LOGD("  accel scale: %d", range->accel_scale);
	LOGD("  gyro scale:  %d", range->gyro_scale);
	LOGD("  mag scale:   %d", range->mag_scale);
}

void dump_packet_sensor_display_info(const pkt_sensor_display_info* info)
{
	(void)info;

	LOGD("display info");
	LOGD("  command id:             %d", info->command_id);
	LOGD("  distortion_type:        %d", info->distortion_type);
	LOGD("  resolution:             %d x %d", info->h_resolution, info->v_resolution);
	LOGD("  screen size:            %f x %f", info->h_screen_size, info->v_screen_size);
	LOGD("  vertical center:        %f", info->v_center);
	LOGD("  lens_separation:        %f", info->lens_separation);
	LOGD("  eye_to_screen_distance: %f, %f", info->eye_to_screen_distance[0], info->eye_to_screen_distance[1]);
	LOGD("  distortion_k:           %f, %f, %f, %f, %f, %f",
		info->distortion_k[0], info->distortion_k[1], info->distortion_k[2],
		info->distortion_k[3], info->distortion_k[4], info->distortion_k[5]);
}

void dump_packet_sensor_config(const pkt_sensor_config* config)
{
	(void)config;

	LOGD("sensor config");
	LOGD("  command id:          %u", config->command_id);
	LOGD("  flags:               %02x", config->flags);
	LOGD("    raw mode:                  %d", !!(config->flags & RIFT_SCF_RAW_MODE));
	LOGD("    calibration test:          %d", !!(config->flags & RIFT_SCF_CALIBRATION_TEST));
	LOGD("    use calibration:           %d", !!(config->flags & RIFT_SCF_USE_CALIBRATION));
	LOGD("    auto calibration:          %d", !!(config->flags & RIFT_SCF_AUTO_CALIBRATION));
	LOGD("    motion keep alive:         %d", !!(config->flags & RIFT_SCF_MOTION_KEEP_ALIVE));
	LOGD("    motion command keep alive: %d", !!(config->flags & RIFT_SCF_COMMAND_KEEP_ALIVE));
	LOGD("    sensor coordinates:        %d", !!(config->flags & RIFT_SCF_SENSOR_COORDINATES));
	LOGD("  packet interval:     %u", config->packet_interval);
	LOGD("  keep alive interval: %u", config->keep_alive_interval);
}

void dump_packet_tracker_sensor(const pkt_tracker_sensor* sensor)
{
	(void)sensor;

	LOGD("tracker sensor:");
	LOGD("  total sample count: %u", sensor->total_sample_count);
	LOGD("  timestamp:       %u", sensor->timestamp);
	LOGD("  temperature:     %d", sensor->temperature);
	LOGD("  num samples:     %u", sensor->num_samples);
	LOGD("  magnetic field:  %i %i %i", sensor->mag[0], sensor->mag[1], sensor->mag[2]);

	for(int i = 0; i < sensor->num_samples; i++){
		LOGD("    accel: %d %d %d", sensor->samples[i].accel[0], sensor->samples[i].accel[1], sensor->samples[i].accel[2]);
		LOGD("    gyro:  %d %d %d", sensor->samples[i].gyro[0], sensor->samples[i].gyro[1], sensor->samples[i].gyro[2]);
	}
	LOGD("frame_id %u frame count %u timestamp %u led pattern %u exposure_count %u exposure time %u",
		sensor->frame_id,
		sensor->frame_count, sensor->frame_timestamp,
		sensor->led_pattern_phase, sensor->exposure_count,
		sensor->exposure_timestamp);
}
