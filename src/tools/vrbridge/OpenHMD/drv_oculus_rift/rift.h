// Copyright 2013, Fredrik Hultin.
// Copyright 2013, Jakob Bornecrantz.
// Copyright 2015-2016 Philipp Zabel
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* Oculus Rift Driver Internal Interface */


#ifndef RIFT_H
#define RIFT_H

#include "../openhmdi.h"

#define FEATURE_BUFFER_SIZE 256

typedef enum {
	RIFT_CMD_SENSOR_CONFIG = 2,
	RIFT_CMD_IMU_CALIBRATION = 3, /* Not used. The HMD does calibration handling */
	RIFT_CMD_RANGE = 4,
	RIFT_CMD_DK1_KEEP_ALIVE = 8,
	RIFT_CMD_DISPLAY_INFO = 9,
	RIFT_CMD_TRACKING_CONFIG = 0xc,
	RIFT_CMD_POSITION_INFO = 0xf,
	RIFT_CMD_PATTERN_INFO = 0x10,
	RIFT_CMD_CV1_KEEP_ALIVE = 0x11,
	RIFT_CMD_RADIO_CONTROL = 0x1a,
	RIFT_CMD_RADIO_READ_DATA = 0x1b,
	RIFT_CMD_ENABLE_COMPONENTS = 0x1d,
} rift_sensor_feature_cmd;

typedef enum {
	RIFT_HMD_RADIO_READ_FLASH_CONTROL =	0x0a
} rift_hmd_radio_read_cmd;

typedef enum {
	RIFT_CF_SENSOR,
	RIFT_CF_HMD
} rift_coordinate_frame;

typedef enum {
	RIFT_IRQ_SENSORS_DK1 = 1,
	RIFT_IRQ_SENSORS_DK2 = 11
} rift_irq_cmd;

typedef enum {
	RIFT_DT_NONE,
	RIFT_DT_SCREEN_ONLY,
	RIFT_DT_DISTORTION
} rift_distortion_type;

typedef enum {
	RIFT_COMPONENT_DISPLAY = 1,
	RIFT_COMPONENT_AUDIO = 2,
	RIFT_COMPONENT_LEDS = 4
} rift_component_type;

// Sensor config flags
#define RIFT_SCF_RAW_MODE           0x01
#define RIFT_SCF_CALIBRATION_TEST   0x02
#define RIFT_SCF_USE_CALIBRATION    0x04
#define RIFT_SCF_AUTO_CALIBRATION   0x08
#define RIFT_SCF_MOTION_KEEP_ALIVE  0x10
#define RIFT_SCF_COMMAND_KEEP_ALIVE 0x20
#define RIFT_SCF_SENSOR_COORDINATES 0x40

typedef enum {
	RIFT_TRACKING_ENABLE        	= 0x01,
	RIFT_TRACKING_AUTO_INCREMENT	= 0x02,
	RIFT_TRACKING_USE_CARRIER    	= 0x04,
	RIFT_TRACKING_SYNC_INPUT    	= 0x08,
	RIFT_TRACKING_VSYNC_LOCK    	= 0x10,
	RIFT_TRACKING_CUSTOM_PATTERN	= 0x20
} rift_tracking_config_flags;

#define RIFT_TRACKING_EXPOSURE_US_DK2           350
#define RIFT_TRACKING_EXPOSURE_US_CV1           399
#define RIFT_TRACKING_PERIOD_US_DK2             16666
#define RIFT_TRACKING_PERIOD_US_CV1             19200
#define RIFT_TRACKING_VSYNC_OFFSET              0
#define RIFT_TRACKING_DUTY_CYCLE                0x7f

typedef struct {
	uint16_t command_id;
	uint16_t accel_scale;
	uint16_t gyro_scale;
	uint16_t mag_scale;
} pkt_sensor_range;

typedef struct {
	int32_t accel[3];
	int32_t gyro[3];
} pkt_tracker_sample;

typedef struct {
	uint8_t num_samples;
	uint16_t total_sample_count;
	int16_t temperature;
	uint32_t timestamp;
	pkt_tracker_sample samples[3];
	int16_t mag[3];

	uint16_t frame_count;        /* HDMI input frame count */
	uint32_t frame_timestamp;    /* HDMI vsync timestamp */
	uint8_t frame_id;            /* frame id pixel readback */
	uint8_t led_pattern_phase;
	uint16_t exposure_count;
	uint32_t exposure_timestamp;
} pkt_tracker_sensor;

typedef struct {
    uint16_t command_id;
    uint8_t flags;
    uint16_t packet_interval;
    uint16_t keep_alive_interval; // in ms
} pkt_sensor_config;

typedef struct {
	uint16_t command_id;
	uint8_t pattern;
	uint8_t flags;
	uint8_t reserved;
	uint16_t exposure_us;
	uint16_t period_us;
	uint16_t vsync_offset;
	uint8_t duty_cycle;
} pkt_tracking_config;

typedef struct {
	uint16_t command_id;
	rift_distortion_type distortion_type;
	uint8_t distortion_type_opts;
	uint16_t h_resolution, v_resolution;
	float h_screen_size, v_screen_size;
	float v_center;
	float lens_separation;
	float eye_to_screen_distance[2];
	float distortion_k[6];
} pkt_sensor_display_info;

typedef struct {
	uint16_t command_id;
	uint16_t keep_alive_interval;
} pkt_keep_alive;

typedef struct {
	uint8_t flags;
	int32_t pos_x;
	int32_t pos_y;
	int32_t pos_z;
	int16_t dir_x;
	int16_t dir_y;
	int16_t dir_z;
	uint8_t index;
	uint8_t num;
	uint8_t type;
} pkt_position_info;

typedef struct {
	uint8_t pattern_length;
	uint32_t pattern;
	uint16_t index;
	uint16_t num;
} pkt_led_pattern_report;

typedef struct {
	// Relative position in micrometers
	vec3f pos;
	// Normal
	vec3f dir;
	// Blink pattern
	uint16_t pattern;
} rift_led;

typedef struct {
	vec3f imu_position;
	float gyro_calibration[12];
	float acc_calibration[12];
	uint16_t joy_x_range_min;
	uint16_t joy_x_range_max;
	uint16_t joy_x_dead_min;
	uint16_t joy_x_dead_max;
	uint16_t joy_y_range_min;
	uint16_t joy_y_range_max;
	uint16_t joy_y_dead_min;
	uint16_t joy_y_dead_max;
	uint16_t trigger_min_range;
	uint16_t trigger_mid_range;
	uint16_t trigger_max_range;
	uint16_t middle_min_range;
	uint16_t middle_mid_range;
	uint16_t middle_max_range;
	bool middle_flipped;
	uint16_t cap_sense_min[8];
	uint16_t cap_sense_touch[8];
} rift_touch_calibration;

typedef struct rift_hmd_s rift_hmd_t;
typedef struct rift_device_priv_s rift_device_priv;
typedef struct rift_touch_controller_s rift_touch_controller_t;

struct rift_device_priv_s {
	ohmd_device base;
	int id;
	bool opened;

	rift_hmd_t *hmd;
};

struct rift_touch_controller_s {
	rift_device_priv base;

	int device_num;
	fusion imu_fusion;

	bool have_calibration;
	rift_touch_calibration calibration;

	bool time_valid;
	uint32_t last_timestamp;

	uint8_t buttons;

	float trigger;
	float grip;
	float stick[2];
	float cap_a_x;
	float cap_b_y;
	float cap_rest;
	float cap_stick;
	float cap_trigger;
	uint8_t haptic_counter;
};

#define RIFT_RADIO_REPORT_ID			0x0c
#define RIFT_RADIO_REPORT_SIZE			64

#define RIFT_REMOTE				1
#define RIFT_TOUCH_CONTROLLER_LEFT		2
#define RIFT_TOUCH_CONTROLLER_RIGHT		3

#define RIFT_REMOTE_BUTTON_UP			0x001
#define RIFT_REMOTE_BUTTON_DOWN			0x002
#define RIFT_REMOTE_BUTTON_LEFT			0x004
#define RIFT_REMOTE_BUTTON_RIGHT		0x008
#define RIFT_REMOTE_BUTTON_OK			0x010
#define RIFT_REMOTE_BUTTON_PLUS			0x020
#define RIFT_REMOTE_BUTTON_MINUS		0x040
#define RIFT_REMOTE_BUTTON_OCULUS		0x080
#define RIFT_REMOTE_BUTTON_BACK			0x100

typedef struct {
	uint16_t buttons;
} pkt_rift_remote_message;

#define RIFT_TOUCH_CONTROLLER_BUTTON_A		0x01
#define RIFT_TOUCH_CONTROLLER_BUTTON_X		0x01
#define RIFT_TOUCH_CONTROLLER_BUTTON_B		0x02
#define RIFT_TOUCH_CONTROLLER_BUTTON_Y		0x02
#define RIFT_TOUCH_CONTROLLER_BUTTON_MENU	0x04
#define RIFT_TOUCH_CONTROLLER_BUTTON_OCULUS	0x04
#define RIFT_TOUCH_CONTROLLER_BUTTON_STICK	0x08

#define RIFT_TOUCH_CONTROLLER_ADC_STICK		0x01
#define RIFT_TOUCH_CONTROLLER_ADC_B_Y		0x02
#define RIFT_TOUCH_CONTROLLER_ADC_TRIGGER	0x03
#define RIFT_TOUCH_CONTROLLER_ADC_A_X		0x04
#define RIFT_TOUCH_CONTROLLER_ADC_REST		0x08

#define RIFT_TOUCH_CONTROLLER_HAPTIC_COUNTER	0x23

typedef struct {
	uint32_t timestamp;
	int16_t accel[3];
	int16_t gyro[3];
	uint8_t buttons;
	uint16_t trigger;
	uint16_t grip;
	uint16_t stick[2];
	uint8_t adc_channel;
	uint16_t adc_value;
} pkt_rift_touch_message;

/* Not actually implemented yet
typedef struct rift_pairing_message {
	uint8_t unknown_1;
	uint8_t maybe_rssi;
	uint8_t buttons;
	uint8_t device_type;
	uint32_t id[2];
	uint8_t unknown[2];
	uint8_t firmware[8];
	uint8_t padding[3];
} pkt_rift_pairing_message;
*/

typedef struct {
  bool valid;
	uint16_t flags;
	uint8_t device_type;
	union {
		pkt_rift_remote_message remote;
		pkt_rift_touch_message touch;
		/* struct rift_pairing_message pairing; */
	};
} pkt_rift_radio_message;

typedef struct {
	uint8_t id;
	pkt_rift_radio_message message[2];
} pkt_rift_radio_report;

bool decode_sensor_range(pkt_sensor_range* range, const unsigned char* buffer, int size);
bool decode_sensor_display_info(pkt_sensor_display_info* info, const unsigned char* buffer, int size);
bool decode_sensor_config(pkt_sensor_config* config, const unsigned char* buffer, int size);
bool decode_tracker_sensor_msg_dk1(pkt_tracker_sensor* msg, const unsigned char* buffer, int size);
bool decode_tracker_sensor_msg_dk2(pkt_tracker_sensor* msg, const unsigned char* buffer, int size);
bool decode_position_info(pkt_position_info* p, const unsigned char* buffer, int size);
bool decode_led_pattern_info(pkt_led_pattern_report * p, const unsigned char* buffer, int size);
bool decode_radio_address(uint8_t radio_address[5], const unsigned char* buffer, int size);

bool decode_rift_radio_report(pkt_rift_radio_report *r, const unsigned char* buffer, int size);

void vec3f_from_rift_vec(const int32_t* smp, vec3f* out_vec);

int encode_tracking_config(unsigned char* buffer, const pkt_tracking_config* tracking);
int encode_sensor_config(unsigned char* buffer, const pkt_sensor_config* config);
int encode_dk1_keep_alive(unsigned char* buffer, const pkt_keep_alive* keep_alive);
int encode_enable_components(unsigned char* buffer, bool display, bool audio, bool leds);
int encode_radio_control_cmd(unsigned char* buffer, uint8_t a, uint8_t b, uint8_t c);
int encode_radio_data_read_cmd (unsigned char *buffer, uint16_t offset, uint16_t length);

void dump_packet_sensor_range(const pkt_sensor_range* range);
void dump_packet_sensor_config(const pkt_sensor_config* config);
void dump_packet_sensor_display_info(const pkt_sensor_display_info* info);
void dump_packet_tracker_sensor(const pkt_tracker_sensor* sensor);

#endif
