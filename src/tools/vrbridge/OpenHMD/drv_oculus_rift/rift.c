/*
 * Copyright 2013, Fredrik Hultin.
 * Copyright 2013, Jakob Bornecrantz.
 * Copyright 2016 Philipp Zabel
 * Copyright 2019 Jan Schmidt
 * SPDX-License-Identifier: BSL-1.0
 *
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* Oculus Rift Driver - HID/USB Driver Implementation */


#include <stdlib.h>
#include <hidapi.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <assert.h>

#include "rift.h"
#include "rift-hmd-radio.h"
#include "../hid.h"

#define OHMD_GRAVITY_EARTH 9.80665 // m/s²

#define UDEV_WIKI_URL "https://github.com/OpenHMD/OpenHMD/wiki/Udev-rules-list"
#define OCULUS_VR_INC_ID 0x2833
#define SAMSUNG_ELECTRONICS_CO_ID 0x04e8
#define RIFT_CV1_PID 0x0031

#define TICK_LEN (1.0f / 1000.0f) // 1000 Hz ticks
#define KEEP_ALIVE_VALUE (10 * 1000)
#define SETFLAG(_s, _flag, _val) (_s) = ((_s) & ~(_flag)) | ((_val) ? (_flag) : 0)

struct rift_hmd_s {
	ohmd_context* ctx;
	int use_count;

	hid_device* handle;
	hid_device* radio_handle;
	pkt_sensor_range sensor_range;
	pkt_sensor_display_info display_info;
	rift_coordinate_frame coordinate_frame, hw_coordinate_frame;
	pkt_sensor_config sensor_config;
	pkt_tracker_sensor sensor;
	uint32_t last_imu_timestamp;
	double last_keep_alive;
	fusion sensor_fusion;
	vec3f raw_mag, raw_accel, raw_gyro;

	struct {
		vec3f pos;
	} imu;

	uint8_t radio_address[5];
	rift_led *leds;
	uint8_t num_leds;

	uint16_t remote_buttons_state;

	/* OpenHMD output devices */
	rift_device_priv hmd_dev;
	rift_touch_controller_t touch_dev[2];
};

typedef struct device_list_s device_list_t;
struct device_list_s {
	char path[OHMD_STR_SIZE];
	rift_hmd_t *hmd;

	device_list_t* next;
};

typedef enum {
	REV_DK1,
	REV_DK2,
	REV_CV1,

	REV_GEARVR_GEN1
} rift_revision;

typedef struct {
	const char* name;
	int company;
	int id;
	int iface;
	rift_revision rev;
} rift_devices;

/* Global list of (probably 1) active HMD devices */
static device_list_t* rift_hmds;

static hid_device* open_hid_dev (ohmd_context* ctx, int vid, int pid, int iface_num);
static void close_hmd (rift_hmd_t *hmd);

static rift_hmd_t *find_hmd(char *hid_path)
{
	device_list_t* current = rift_hmds;

	while (current != NULL) {
		if (strcmp(current->path, hid_path)==0)
			return current->hmd;
		current = current->next;
	}
	return NULL;
}

static void push_hmd(rift_hmd_t *hmd, char *hid_path)
{
	device_list_t* d = calloc(1, sizeof(device_list_t));
	d->hmd = hmd;
	strcpy (d->path, hid_path);

	d->next = rift_hmds;
	rift_hmds = d;
}

static void release_hmd(rift_hmd_t *hmd)
{
	device_list_t* current, *prev;

	if (hmd->use_count > 1) {
		hmd->use_count--;
		return;
	}

	/* Use count on the HMD device hit 0, release it
	 * and remove from the list */
	current = rift_hmds;
	prev = NULL;
	while (current != NULL) {
		if (current->hmd == hmd) {
			close_hmd (current->hmd);

			if (prev == NULL)
				rift_hmds = current->next;
			else
				prev->next = current->next;
			free (current);
			return;
		}
		prev = current;
		current = current->next;
	}

	LOGE("Failed to find HMD in the active device list");
}

static rift_device_priv* rift_device_priv_get(ohmd_device* device)
{
	return (rift_device_priv*)device;
}

static int get_feature_report(rift_hmd_t* priv, rift_sensor_feature_cmd cmd, unsigned char* buf)
{
	memset(buf, 0, FEATURE_BUFFER_SIZE);
	buf[0] = (unsigned char)cmd;
	return hid_get_feature_report(priv->handle, buf, FEATURE_BUFFER_SIZE);
}

static int send_feature_report(rift_hmd_t* priv, const unsigned char *data, size_t length)
{
	return hid_send_feature_report(priv->handle, data, length);
}

static void set_coordinate_frame(rift_hmd_t* priv, rift_coordinate_frame coordframe)
{
	priv->coordinate_frame = coordframe;

	// set the RIFT_SCF_SENSOR_COORDINATES in the sensor config to match whether coordframe is hmd or sensor
	SETFLAG(priv->sensor_config.flags, RIFT_SCF_SENSOR_COORDINATES, coordframe == RIFT_CF_SENSOR);

	// encode send the new config to the Rift
	unsigned char buf[FEATURE_BUFFER_SIZE];
	int size = encode_sensor_config(buf, &priv->sensor_config);
	if(send_feature_report(priv, buf, size) == -1){
		ohmd_set_error(priv->ctx, "send_feature_report failed in set_coordinate frame");
		return;
	}

	// read the state again, set the hw_coordinate_frame to match what
	// the hardware actually is set to just in case it doesn't stick.
	size = get_feature_report(priv, RIFT_CMD_SENSOR_CONFIG, buf);
	if(size <= 0){
		LOGW("could not set coordinate frame");
		priv->hw_coordinate_frame = RIFT_CF_HMD;
		return;
	}

	decode_sensor_config(&priv->sensor_config, buf, size);
	priv->hw_coordinate_frame = (priv->sensor_config.flags & RIFT_SCF_SENSOR_COORDINATES) ? RIFT_CF_SENSOR : RIFT_CF_HMD;

	if(priv->hw_coordinate_frame != coordframe) {
		LOGW("coordinate frame didn't stick");
	}
}

static void handle_tracker_sensor_msg(rift_hmd_t* priv, unsigned char* buffer, int size)
{
	if (buffer[0] == RIFT_IRQ_SENSORS_DK1
	  && !decode_tracker_sensor_msg_dk1(&priv->sensor, buffer, size)){
		LOGE("couldn't decode tracker sensor message");
	}
	else if (buffer[0] == RIFT_IRQ_SENSORS_DK2 /* DK2 and CV1 variant */
	  && !decode_tracker_sensor_msg_dk2(&priv->sensor, buffer, size)){
		LOGE("couldn't decode tracker sensor message");
	}

	pkt_tracker_sensor* s = &priv->sensor;

	dump_packet_tracker_sensor(s);

	int32_t mag32[] = { s->mag[0], s->mag[1], s->mag[2] };
	vec3f_from_rift_vec(mag32, &priv->raw_mag);

	// TODO: handle overflows in a nicer way
	float dt = TICK_LEN; // TODO: query the Rift for the sample rate
	if (s->timestamp > priv->last_imu_timestamp)
	{
		dt = (s->timestamp - priv->last_imu_timestamp) / 1000000.0f;
		dt -= (s->num_samples - 1) * TICK_LEN; // TODO: query the Rift for the sample rate
	}

	for(int i = 0; i < s->num_samples; i++){
		vec3f_from_rift_vec(s->samples[i].accel, &priv->raw_accel);
		vec3f_from_rift_vec(s->samples[i].gyro, &priv->raw_gyro);

		ofusion_update(&priv->sensor_fusion, dt, &priv->raw_gyro, &priv->raw_accel, &priv->raw_mag);
		dt = TICK_LEN; // TODO: query the Rift for the sample rate
	}

	priv->last_imu_timestamp = s->timestamp;
}

static void handle_touch_controller_message(rift_hmd_t *hmd,
		rift_touch_controller_t *touch, pkt_rift_radio_message *msg)
{
	// The top bits are carrying something unknown. Ignore them
	uint8_t buttons = msg->touch.buttons & 0xf;
	rift_touch_calibration *c = &touch->calibration;

	if (touch->buttons != buttons) {
		LOGV ("touch controller %d buttons now %x",
				touch->base.id, buttons);
	}
	touch->buttons = buttons;

	if (!(msg->touch.timestamp ||
	      msg->touch.accel[0] || msg->touch.accel[1] || msg->touch.accel[2] ||
	      msg->touch.gyro[0] || msg->touch.gyro[1] || msg->touch.gyro[2]))
		return;

	if (!touch->have_calibration) {
		/* We need calibration data to do any more */
		if (rift_touch_get_calibration (hmd->radio_handle, touch->device_num,
				&touch->calibration) < 0)
			return;
		touch->have_calibration = true;
	}

	// time in microseconds
	int32_t dt;
	if (touch->time_valid)
		dt = msg->touch.timestamp - touch->last_timestamp;
	else
		dt = 0;

	const double dt_s = 1e-6 * dt;
	double a[3] = {
		OHMD_GRAVITY_EARTH / 2048 * msg->touch.accel[0],
		OHMD_GRAVITY_EARTH / 2048 * msg->touch.accel[1],
		OHMD_GRAVITY_EARTH / 2048 * msg->touch.accel[2],
	};
	double g[3] = {
		2.0 / 2048 * msg->touch.gyro[0],
		2.0 / 2048 * msg->touch.gyro[1],
		2.0 / 2048 * msg->touch.gyro[2],
	};
	vec3f mag = {{0.0f, 0.0f, 0.0f}};
	vec3f gyro;
	vec3f accel;

	/* Apply correction offsets first - bottom row of the
	 * calibration 3x4 matrix */
	int i;
	for (i = 0; i < 3; i++) {
		a[i] -= c->acc_calibration[9 + i];
		g[i] -= c->gyro_calibration[9 + i];
	}
	/* Then the 3x3 rotation matrix in row-major order */
	accel.x = c->acc_calibration[0] * a[0] +
			  c->acc_calibration[1] * a[1] +
			  c->acc_calibration[2] * a[2];
	accel.y = c->acc_calibration[3] * a[0] +
			  c->acc_calibration[4] * a[1] +
			  c->acc_calibration[5] * a[2];
	accel.z = c->acc_calibration[6] * a[0] +
			  c->acc_calibration[7] * a[1] +
			  c->acc_calibration[8] * a[2];
	gyro.x = c->gyro_calibration[0] * g[0] +
			  c->gyro_calibration[1] * g[1] +
			  c->gyro_calibration[2] * g[2];
	gyro.y = c->gyro_calibration[3] * g[0] +
			  c->gyro_calibration[4] * g[1] +
			  c->gyro_calibration[5] * g[2];
	gyro.z = c->gyro_calibration[6] * g[0] +
			  c->gyro_calibration[7] * g[1] +
			  c->gyro_calibration[8] * g[2];

	ofusion_update(&touch->imu_fusion, dt_s, &gyro, &accel, &mag);
	touch->last_timestamp = msg->touch.timestamp;
	touch->time_valid = true;

	float t;
	if (msg->touch.trigger < c->trigger_mid_range) {
		t = 1.0f - ((float)msg->touch.trigger - c->trigger_min_range) /
		    (c->trigger_mid_range - c->trigger_min_range) * 0.5f;
	} else {
		t = 0.5f - ((float)msg->touch.trigger - c->trigger_mid_range) /
		    (c->trigger_max_range - c->trigger_mid_range) * 0.5f;
	}
	touch->trigger = t;

	float gr;
	if (msg->touch.grip < c->middle_mid_range) {
		gr = 1.0f - ((float)msg->touch.grip - c->middle_min_range) /
		     (c->middle_mid_range - c->middle_min_range) * 0.5f;
	} else {
		gr = 0.5f - ((float)msg->touch.grip - c->middle_mid_range) /
		     (c->middle_max_range - c->middle_mid_range) * 0.5f;
	}
	touch->grip = gr;

	float joy[2];
	if (msg->touch.stick[0] >= c->joy_x_dead_min && msg->touch.stick[0] <= c->joy_x_dead_max &&
	    msg->touch.stick[1] >= c->joy_y_dead_min && msg->touch.stick[1] <= c->joy_y_dead_max) {
		joy[0] = 0.0f;
		joy[1] = 0.0f;
	} else {
		joy[0] = ((float)msg->touch.stick[0] - c->joy_x_range_min) /
			 (c->joy_x_range_max - c->joy_x_range_min) * 2.0f - 1.0f;
		joy[1] = ((float)msg->touch.stick[1] - c->joy_y_range_min) /
			 (c->joy_y_range_max - c->joy_y_range_min) * 2.0f - 1.0f;
	}
	touch->stick[0] = joy[0];
	touch->stick[1] = joy[1];

	switch (msg->touch.adc_channel) {
	case RIFT_TOUCH_CONTROLLER_HAPTIC_COUNTER:
		/*
		 * The haptic counter seems to be used as read pointer into a
		 * 256-byte ringbuffer. It is incremented 320 times per second:
		 *
		 * https://developer.oculus.com/documentation/pcsdk/latest/concepts/dg-input-touch-haptic/
		 */
		touch->haptic_counter = msg->touch.adc_value;
		break;
	case RIFT_TOUCH_CONTROLLER_ADC_STICK:
		touch->cap_stick = ((float)msg->touch.adc_value - c->cap_sense_min[0]) /
				   (c->cap_sense_touch[0] - c->cap_sense_min[0]);
		break;
	case RIFT_TOUCH_CONTROLLER_ADC_B_Y:
		touch->cap_b_y = ((float)msg->touch.adc_value - c->cap_sense_min[1]) /
				 (c->cap_sense_touch[1] - c->cap_sense_min[1]);
		break;
	case RIFT_TOUCH_CONTROLLER_ADC_TRIGGER:
		touch->cap_trigger = ((float)msg->touch.adc_value - c->cap_sense_min[2]) /
				     (c->cap_sense_touch[2] - c->cap_sense_min[2]);
		break;
	case RIFT_TOUCH_CONTROLLER_ADC_A_X:
		touch->cap_a_x = ((float)msg->touch.adc_value - c->cap_sense_min[3]) /
				 (c->cap_sense_touch[3] - c->cap_sense_min[3]);
		break;
	case RIFT_TOUCH_CONTROLLER_ADC_REST:
		touch->cap_rest = ((float)msg->touch.adc_value - c->cap_sense_min[7]) /
				  (c->cap_sense_touch[7] - c->cap_sense_min[7]);
		break;
	}
}

static void handle_rift_radio_message(rift_hmd_t *hmd, pkt_rift_radio_message *msg)
{
	switch (msg->device_type) {
		case RIFT_REMOTE:
			if (hmd->remote_buttons_state != msg->remote.buttons) {
				LOGV ("Remote buttons state 0x%02x", msg->remote.buttons);
			}
			hmd->remote_buttons_state = msg->remote.buttons;
			break;
		case RIFT_TOUCH_CONTROLLER_RIGHT:
			handle_touch_controller_message (hmd, &hmd->touch_dev[0], msg);
			break;
		case RIFT_TOUCH_CONTROLLER_LEFT:
			handle_touch_controller_message (hmd, &hmd->touch_dev[1], msg);
			break;
	}
}

static void handle_rift_radio_report(rift_hmd_t* hmd, unsigned char* buffer, int size)
{
	pkt_rift_radio_report r;

	if (!decode_rift_radio_report(&r, buffer, size))
		return;

	if (r.message[0].valid)
		handle_rift_radio_message(hmd, &r.message[0]);
	if (r.message[1].valid)
		handle_rift_radio_message(hmd, &r.message[1]);
}

static void update_hmd(rift_hmd_t *priv)
{
	unsigned char buffer[FEATURE_BUFFER_SIZE];

	// Handle keep alive messages
	double t = ohmd_get_tick();
	if(t - priv->last_keep_alive >= (double)priv->sensor_config.keep_alive_interval / 1000.0 - .2){
		// send keep alive message
		pkt_keep_alive keep_alive = { 0, priv->sensor_config.keep_alive_interval };
		int ka_size = encode_dk1_keep_alive(buffer, &keep_alive);
		if (send_feature_report(priv, buffer, ka_size) == -1)
			LOGE("error sending keepalive");

		// Update the time of the last keep alive we have sent.
		priv->last_keep_alive = t;
	}

	// Read all the messages from the device.
	while(true){
		int size = hid_read(priv->handle, buffer, FEATURE_BUFFER_SIZE);
		if(size < 0){
			LOGE("error reading from device");
			break;
		} else if(size == 0) {
			break; // No more messages, return.
		}

		// currently the only message type the hardware supports (I think)
		if(buffer[0] == RIFT_IRQ_SENSORS_DK1 || buffer[0] == RIFT_IRQ_SENSORS_DK2) {
			handle_tracker_sensor_msg(priv, buffer, size);
		}else{
			LOGE("unknown message type: %u", buffer[0]);
		}
	}

	if (priv->radio_handle == NULL)
		return;

	// Read all the controller messages from the radio device.
	while(true){
		int size = hid_read(priv->radio_handle, buffer, FEATURE_BUFFER_SIZE);
		if(size < 0){
			LOGE("error reading from device");
			break;
		} else if(size == 0) {
			break; // No more messages, return.
		}

		if (buffer[0] == RIFT_RADIO_REPORT_ID)
			handle_rift_radio_report (priv, buffer, size);
	}
}

static void update_device(ohmd_device* device)
{
	rift_device_priv* dev_priv = rift_device_priv_get(device);
	rift_hmd_t *hmd = dev_priv->hmd;

	/* Update on whichever is the lowest open id device */
	if (dev_priv->id == 2) {
		if (hmd->hmd_dev.opened)
			return;
		if (hmd->touch_dev[0].base.opened)
			return;
	}
	else if (dev_priv->id == 1) {
		if (hmd->hmd_dev.opened)
			return;
	}
	update_hmd (dev_priv->hmd);
}

static int getf_hmd(rift_hmd_t *hmd, ohmd_float_value type, float* out)
{
	switch(type){
	case OHMD_DISTORTION_K: {
			for (int i = 0; i < 6; i++) {
				out[i] = hmd->display_info.distortion_k[i];
			}
			break;
		}

	case OHMD_ROTATION_QUAT: {
			*(quatf*)out = hmd->sensor_fusion.orient;
			break;
		}

	case OHMD_POSITION_VECTOR:
		out[0] = out[1] = out[2] = 0;
		break;

	case OHMD_CONTROLS_STATE:
		out[0] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_UP) != 0;
		out[1] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_DOWN) != 0;
		out[2] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_LEFT) != 0;
		out[3] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_RIGHT) != 0;
		out[4] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_OK) != 0;
		out[5] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_PLUS) != 0;
		out[6] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_MINUS) != 0;
		out[7] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_OCULUS) != 0;
		out[8] = (hmd->remote_buttons_state & RIFT_REMOTE_BUTTON_BACK) != 0;
		break;

	default:
		ohmd_set_error(hmd->ctx, "invalid type given to getf (%ud)", type);
		return -1;
		break;
	}

	return 0;
}

static int getf_touch_controller(rift_device_priv* dev_priv, ohmd_float_value type, float* out)
{
	rift_touch_controller_t *touch = (rift_touch_controller_t *)(dev_priv);

	switch(type){
	case OHMD_ROTATION_QUAT: {
			*(quatf*)out = touch->imu_fusion.orient;
			break;
		}
	case OHMD_POSITION_VECTOR:
		out[0] = out[1] = out[2] = 0;
		break;
	case OHMD_DISTORTION_K:
		return -1;
	case OHMD_CONTROLS_STATE:
		if (dev_priv->id == 1) { // right control
			out[0] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_A) != 0;
			out[1] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_B) != 0;
			out[2] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_OCULUS) != 0;
			out[3] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_STICK) != 0;
		}
		else { // left control, id == 2
			out[0] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_X) != 0;
			out[1] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_Y) != 0;
			out[2] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_MENU) != 0;
			out[3] = (touch->buttons & RIFT_TOUCH_CONTROLLER_BUTTON_STICK) != 0;
		}
		out[4] = touch->trigger;
		out[5] = touch->grip;
		out[6] = touch->stick[0];
		out[7] = touch->stick[1];
		break;
	default:
		ohmd_set_error(dev_priv->hmd->ctx, "invalid type given to getf (%u)", type);
		return -1;
	}

	return 0;
}

static int getf(ohmd_device* device, ohmd_float_value type, float* out)
{
	rift_device_priv* dev_priv = rift_device_priv_get(device);
	if (dev_priv->id == 0)
		return getf_hmd (dev_priv->hmd, type, out);
	else if (dev_priv->id == 1 || dev_priv->id == 2)
		return getf_touch_controller (dev_priv, type, out);

	return -1;
}

static void close_device(ohmd_device* device)
{
	LOGD("closing device");
	rift_device_priv* dev_priv = rift_device_priv_get(device);
	dev_priv->opened = false;
	release_hmd (dev_priv->hmd);
}

/*
 * Obtains the positions and blinking patterns of the IR LEDs from the Rift.
 */
static int rift_get_led_info(rift_hmd_t *priv)
{
	int first_index = -1;
	unsigned char buf[FEATURE_BUFFER_SIZE];
	int size;
	int num_leds = 0;

	//Get LED positions
	while (true) {
		pkt_position_info pos;

		size = get_feature_report(priv, RIFT_CMD_POSITION_INFO, buf);
		if (size <= 0 || !decode_position_info(&pos, buf, size) ||
		    first_index == pos.index) {
			break;
		}

		if (first_index < 0) {
			first_index = pos.index;
			priv->leds = calloc(pos.num, sizeof(rift_led));
		}

		if (pos.flags == 1) { //reports 0's
			priv->imu.pos.x = (float)pos.pos_x;
			priv->imu.pos.y = (float)pos.pos_y;
			priv->imu.pos.z = (float)pos.pos_z;
			LOGV ("IMU index %d pos x/y/x %d/%d/%d\n", pos.index, pos.pos_x, pos.pos_y, pos.pos_z);
		} else if (pos.flags == 2) {
			rift_led *led = &priv->leds[pos.index];
			led->pos.x = (float)pos.pos_x;
			led->pos.y = (float)pos.pos_y;
			led->pos.z = (float)pos.pos_z;
			led->dir.x = (float)pos.dir_x;
			led->dir.y = (float)pos.dir_y;
			led->dir.z = (float)pos.dir_z;
			ovec3f_normalize_me(&led->dir);
			if (pos.index >= num_leds)
				num_leds = pos.index + 1;
			LOGV ("LED index %d pos x/y/x %d/%d/%d\n", pos.index, pos.pos_x, pos.pos_y, pos.pos_z);
		}
	}
	priv->num_leds = num_leds;

	// Get LED patterns
	first_index = -1;
	while (true) {
		pkt_led_pattern_report pkt;
		int8_t pattern_length;
		int32_t pattern;

		size = get_feature_report(priv, RIFT_CMD_PATTERN_INFO, buf);
		if (size <= 0 || !decode_led_pattern_info(&pkt, buf, size) ||
		    first_index == pkt.index) {
			break;
		}

		if (first_index < 0) {
			first_index = pkt.index;
			if (priv->num_leds != pkt.num) {
				LOGE("LED positions count doesn't match pattern count - got %d patterns for %d LEDs", pkt.num, priv->num_leds);
				return -1;
			}
		}
		if (pkt.index >= priv->num_leds) {
			LOGE("Invalid LED pattern index %d (%d LEDs)", pkt.index, priv->num_leds);
			return -1;
		}

		pattern_length = pkt.pattern_length;
		pattern = pkt.pattern;

		/* pattern_length should be 10 */
		if (pattern_length != 10) {
			LOGE("Rift: Unexpected LED pattern length: %d\n",
				pattern_length);
			return -1;
		}

		LOGV ("LED index %d pattern 0x%08x\n", pkt.index, pkt.pattern);
		/*
		 * pattern should consist of 10 2-bit values that are either
		 * 1 (dark) or 3 (bright).
		 */
		if ((pattern & ~0xaaaaa) != 0x55555) {
			LOGE("Rift: Unexpected pattern: 0x%x", pattern);
			return -1;
		}

		/* Convert into 10 single-bit values 1 -> 0, 3 -> 1 */
		pattern &= 0xaaaaa;
		pattern |= pattern >> 1;
		pattern &= 0x66666;
		pattern |= pattern >> 2;
		pattern &= 0xe1e1e;
		pattern |= pattern >> 4;
		pattern &= 0xe01fe;
		pattern |= pattern >> 8;
		pattern = (pattern >> 1) & 0x3ff;

		priv->leds[pkt.index].pattern = pattern;
	}

	return 0;
}

/*
 * Sends a tracking report to enable the IR tracking LEDs.
 */
static int rift_send_tracking_config(rift_hmd_t *rift, bool blink,
    uint16_t exposure_us, uint16_t period_us)
{
	pkt_tracking_config tracking_config = { 0, };
	unsigned char buf[FEATURE_BUFFER_SIZE];
	int size;

	tracking_config.vsync_offset = RIFT_TRACKING_VSYNC_OFFSET;
	tracking_config.duty_cycle = RIFT_TRACKING_DUTY_CYCLE;
	tracking_config.exposure_us = exposure_us;
	tracking_config.period_us = period_us;

	if (blink) {
		tracking_config.pattern = 0;
		tracking_config.flags = RIFT_TRACKING_ENABLE |
		                        RIFT_TRACKING_USE_CARRIER |
		                        RIFT_TRACKING_AUTO_INCREMENT;
	} else {
		tracking_config.pattern = 0xff;
		tracking_config.flags = RIFT_TRACKING_ENABLE |
		                        RIFT_TRACKING_USE_CARRIER;
	}

	size = encode_tracking_config(buf, &tracking_config);
	if (send_feature_report(rift, buf, size) == -1) {
		LOGE("Error sending LED tracking config");
	  return -1;
	}

	return 0;
}

static void init_touch_device(rift_touch_controller_t *touch, int id, int device_num)
{
	ohmd_device *ohmd_dev = &touch->base.base;

	touch->device_num = device_num;
	ofusion_init(&touch->imu_fusion);
	touch->time_valid = false;

	ohmd_set_default_device_properties(&ohmd_dev->properties);

	ohmd_dev->properties.control_count = 8;

	if (id == 0) {
		ohmd_dev->properties.controls_hints[0] = OHMD_BUTTON_A;
		ohmd_dev->properties.controls_hints[1] = OHMD_BUTTON_B;
		ohmd_dev->properties.controls_hints[2] = OHMD_HOME; // Oculus button
		ohmd_dev->properties.controls_hints[3] = OHMD_ANALOG_PRESS; // stick button
	} else {
		ohmd_dev->properties.controls_hints[0] = OHMD_BUTTON_X;
		ohmd_dev->properties.controls_hints[1] = OHMD_BUTTON_Y;
		ohmd_dev->properties.controls_hints[2] = OHMD_MENU;
		ohmd_dev->properties.controls_hints[3] = OHMD_ANALOG_PRESS; // stick button
	}
	ohmd_dev->properties.controls_types[0] = OHMD_DIGITAL;
	ohmd_dev->properties.controls_types[1] = OHMD_DIGITAL;
	ohmd_dev->properties.controls_types[2] = OHMD_DIGITAL;
	ohmd_dev->properties.controls_types[3] = OHMD_DIGITAL;

	ohmd_dev->properties.controls_hints[4] = OHMD_TRIGGER;
	ohmd_dev->properties.controls_hints[5] = OHMD_SQUEEZE;
	ohmd_dev->properties.controls_hints[6] = OHMD_ANALOG_X;
	ohmd_dev->properties.controls_hints[7] = OHMD_ANALOG_Y;
	ohmd_dev->properties.controls_types[4] = OHMD_ANALOG;
	ohmd_dev->properties.controls_types[5] = OHMD_ANALOG;
	ohmd_dev->properties.controls_types[6] = OHMD_ANALOG;
	ohmd_dev->properties.controls_types[7] = OHMD_ANALOG;
}

static rift_hmd_t *open_hmd(ohmd_driver* driver, ohmd_device_desc* desc)
{
	rift_hmd_t* priv = ohmd_alloc(driver->ctx, sizeof(rift_hmd_t));
	rift_device_priv *hmd_dev;
	if(!priv)
		goto cleanup;

	hmd_dev = &priv->hmd_dev;

	priv->use_count = 1;
	priv->ctx = driver->ctx;

	priv->last_imu_timestamp = -1;

	// Open the HID device
	priv->handle = hid_open_path(desc->path);

	if(!priv->handle) {
		char* path = _hid_to_unix_path(desc->path);
		ohmd_set_error(driver->ctx, "Could not open %s.\n"
		                            "Check your permissions: "
		                            UDEV_WIKI_URL, path);
		free(path);
		goto cleanup;
	}

	if(hid_set_nonblocking(priv->handle, 1) == -1){
		ohmd_set_error(driver->ctx, "failed to set non-blocking on device");
		goto cleanup;
	}

	/* For the CV1, try and open the radio HID device */
	if (desc->revision == REV_CV1) {
		priv->radio_handle = open_hid_dev (driver->ctx, OCULUS_VR_INC_ID, RIFT_CV1_PID, 1);
		if (priv->radio_handle == NULL)
			goto cleanup;
		if(hid_set_nonblocking(priv->radio_handle, 1) == -1){
			ohmd_set_error(driver->ctx, "Failed to set non-blocking on radio device");
			goto cleanup;
		}
	}

	unsigned char buf[FEATURE_BUFFER_SIZE];

	int size;

	// Read and decode the sensor range
	size = get_feature_report(priv, RIFT_CMD_RANGE, buf);
	decode_sensor_range(&priv->sensor_range, buf, size);
	dump_packet_sensor_range(&priv->sensor_range);

	// Read and decode display information
	size = get_feature_report(priv, RIFT_CMD_DISPLAY_INFO, buf);
	decode_sensor_display_info(&priv->display_info, buf, size);
	dump_packet_sensor_display_info(&priv->display_info);

	// Read and decode the sensor config
	size = get_feature_report(priv, RIFT_CMD_SENSOR_CONFIG, buf);
	decode_sensor_config(&priv->sensor_config, buf, size);
	dump_packet_sensor_config(&priv->sensor_config);

	// if the sensor has display info data, use HMD coordinate frame
	priv->coordinate_frame = priv->display_info.distortion_type != RIFT_DT_NONE ? RIFT_CF_HMD : RIFT_CF_SENSOR;

	// enable calibration
	SETFLAG(priv->sensor_config.flags, RIFT_SCF_USE_CALIBRATION, 1);
	SETFLAG(priv->sensor_config.flags, RIFT_SCF_AUTO_CALIBRATION, 1);

	// apply sensor config
	set_coordinate_frame(priv, priv->coordinate_frame);

	// Turn the screens on
	if (desc->revision == REV_CV1)
	{
		size = encode_enable_components(buf, true, true, true);
		if (send_feature_report(priv, buf, size) == -1)
			LOGE("error turning the screens on");

		rift_send_tracking_config (priv, false, RIFT_TRACKING_EXPOSURE_US_CV1,
				RIFT_TRACKING_PERIOD_US_CV1);

		/* Read the radio ID for CV1 to enable camera sensor sync */
		rift_hmd_radio_get_address(priv->handle, priv->radio_address);
	}
	else if (desc->revision == REV_DK2)
	{
		rift_send_tracking_config (priv, false, RIFT_TRACKING_EXPOSURE_US_DK2,
				RIFT_TRACKING_PERIOD_US_DK2);
	}

	/* We only need the LED info if we have a sensor to observe them with,
	   so we could skip this */
	if (rift_get_led_info (priv) < 0) {
		ohmd_set_error(driver->ctx, "failed to read LED info from device");
		goto cleanup;
	}

	// set keep alive interval to n seconds
	pkt_keep_alive keep_alive = { 0, KEEP_ALIVE_VALUE };
	size = encode_dk1_keep_alive(buf, &keep_alive);
	if (send_feature_report(priv, buf, size) == -1)
		LOGE("error setting up keepalive");

	// Update the time of the last keep alive we have sent.
	priv->last_keep_alive = ohmd_get_tick();

	// update sensor settings with new keep alive value
	// (which will have been ignored in favor of the default 1000 ms one)
	size = get_feature_report(priv, RIFT_CMD_SENSOR_CONFIG, buf);
	decode_sensor_config(&priv->sensor_config, buf, size);
	dump_packet_sensor_config(&priv->sensor_config);

	// Set default device properties
	ohmd_set_default_device_properties(&hmd_dev->base.properties);

	// Set device properties
	hmd_dev->base.properties.hsize = priv->display_info.h_screen_size;
	hmd_dev->base.properties.vsize = priv->display_info.v_screen_size;
	hmd_dev->base.properties.hres = priv->display_info.h_resolution;
	hmd_dev->base.properties.vres = priv->display_info.v_resolution;
	hmd_dev->base.properties.lens_sep = priv->display_info.lens_separation;
	hmd_dev->base.properties.lens_vpos = priv->display_info.v_center;
	hmd_dev->base.properties.ratio = ((float)priv->display_info.h_resolution / (float)priv->display_info.v_resolution) / 2.0f;

	if (desc->revision == REV_CV1) {
		/* On the CV1, add some control mappings for the simple Oculus remote control buttons */
		hmd_dev->base.properties.control_count = 9;
		hmd_dev->base.properties.controls_hints[0] = OHMD_BUTTON_Y; // UP
		hmd_dev->base.properties.controls_hints[1] = OHMD_BUTTON_A; // DOWN
		hmd_dev->base.properties.controls_hints[2] = OHMD_BUTTON_X; // LEFT
		hmd_dev->base.properties.controls_hints[3] = OHMD_BUTTON_B; // RIGHT
		hmd_dev->base.properties.controls_hints[4] = OHMD_GENERIC; // OK button
		hmd_dev->base.properties.controls_hints[5] = OHMD_VOLUME_PLUS;
		hmd_dev->base.properties.controls_hints[6] = OHMD_VOLUME_MINUS;
		hmd_dev->base.properties.controls_hints[7] = OHMD_MENU; // OCULUS button
		hmd_dev->base.properties.controls_hints[8] = OHMD_HOME; // Back button

		hmd_dev->base.properties.controls_types[0] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[1] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[2] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[3] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[4] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[5] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[6] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[7] = OHMD_DIGITAL;
		hmd_dev->base.properties.controls_types[8] = OHMD_DIGITAL;

		/* And initialise state trackers for the 2 touch controllers */
		init_touch_device (&priv->touch_dev[0], 0, RIFT_TOUCH_CONTROLLER_RIGHT);
		init_touch_device (&priv->touch_dev[1], 1, RIFT_TOUCH_CONTROLLER_LEFT);
	}

	//setup generic distortion coeffs, from hand-calibration
	switch (desc->revision) {
		case REV_DK2:
			ohmd_set_universal_distortion_k(&(hmd_dev->base.properties), 0.247, -0.145, 0.103, 0.795);
			ohmd_set_universal_aberration_k(&(hmd_dev->base.properties), 0.985, 1.000, 1.015);
			break;
		case REV_DK1:
			ohmd_set_universal_distortion_k(&(hmd_dev->base.properties), 1.003, -1.005, 0.403, 0.599);
			ohmd_set_universal_aberration_k(&(hmd_dev->base.properties), 0.985, 1.000, 1.015);
			break;
		case REV_CV1:
			ohmd_set_universal_distortion_k(&(hmd_dev->base.properties), 0.098, .324, -0.241, 0.819);
			ohmd_set_universal_aberration_k(&(hmd_dev->base.properties), 0.9952420, 1.0, 1.0008074);
			/* CV1 reports IPD, but not lens center, at least not anywhere I could find, so use the manually measured value of 0.054 */
			priv->display_info.lens_separation = 0.054;
			hmd_dev->base.properties.lens_sep = priv->display_info.lens_separation;
		default:
			break;
	}

	// calculate projection eye projection matrices from the device properties
	//ohmd_calc_default_proj_matrices(&hmd_dev->base.properties);
	float l,r,t,b,n,f;
	// left eye screen bounds
	l = -1.0f * (priv->display_info.h_screen_size/2 - priv->display_info.lens_separation/2);
	r = priv->display_info.lens_separation/2;
	t = priv->display_info.v_screen_size - priv->display_info.v_center;
	b = -1.0f * priv->display_info.v_center;
	n = priv->display_info.eye_to_screen_distance[0];
	f = n*10e6;
	//LOGD("l: %0.3f, r: %0.3f, b: %0.3f, t: %0.3f, n: %0.3f, f: %0.3f", l,r,b,t,n,f);
	/* eye separation is handled by IPD in the Modelview matrix */
	omat4x4f_init_frustum(&hmd_dev->base.properties.proj_left, l, r, b, t, n, f);
	//right eye screen bounds
	l = -1.0f * priv->display_info.lens_separation/2;
	r = priv->display_info.h_screen_size/2 - priv->display_info.lens_separation/2;
	n = priv->display_info.eye_to_screen_distance[1];
	f = n*10e6;
	//LOGD("l: %0.3f, r: %0.3f, b: %0.3f, t: %0.3f, n: %0.3f, f: %0.3f", l,r,b,t,n,f);
	/* eye separation is handled by IPD in the Modelview matrix */
	omat4x4f_init_frustum(&hmd_dev->base.properties.proj_right, l, r, b, t, n, f);

	hmd_dev->base.properties.fov = 2 * atan2f(
			priv->display_info.h_screen_size/2 - priv->display_info.lens_separation/2,
			priv->display_info.eye_to_screen_distance[0]);
	hmd_dev->id = 0;
	hmd_dev->hmd = priv;

	// initialize sensor fusion
	ofusion_init(&priv->sensor_fusion);

	return priv;

cleanup:
	if (priv)
		close_hmd (priv);
	return NULL;
}

static void close_hmd(rift_hmd_t *hmd)
{
	if (hmd->leds)
		free (hmd->leds);

	if (hmd->radio_handle)
		hid_close(hmd->radio_handle);
	hid_close(hmd->handle);
	free(hmd);
}

/* FIXME: This opens the first device that matches the
 * requested VID/PID/interface, which works fine if there's
 * 1 rift attached. To support multiple rift, we need to
 * match parent USB devices like ouvrt does */
static hid_device* open_hid_dev(ohmd_context* ctx,
		int vid, int pid, int iface_num)
{
	struct hid_device_info* devs = hid_enumerate(vid, pid);
	struct hid_device_info* cur_dev = devs;
	hid_device *handle = NULL;

	if(devs == NULL)
		return NULL;

	while (cur_dev) {
		if (cur_dev->interface_number == iface_num) {
			handle = hid_open_path(cur_dev->path);
			if (handle)
				break;
			else {
				char* path = _hid_to_unix_path(cur_dev->path);
				ohmd_set_error(ctx, "Could not open %s.\n"
				               "Check your permissions: "
				               UDEV_WIKI_URL, path);
				free(path);
			}
		}
		cur_dev = cur_dev->next;
	}

	hid_free_enumeration(devs);
	return handle;
}

static ohmd_device* open_device(ohmd_driver* driver, ohmd_device_desc* desc)
{
	rift_device_priv *dev = NULL;
	rift_hmd_t *hmd = find_hmd(desc->path);

	if (hmd == NULL) {
		hmd = open_hmd (driver, desc);
		if (hmd == NULL)
			return NULL;
		push_hmd (hmd, desc->path);
	}

	if (desc->id == 0)
		dev = &hmd->hmd_dev;
	else if (desc->id == 1)
		dev = &hmd->touch_dev[0].base;
	else if (desc->id == 2)
		dev = &hmd->touch_dev[1].base;
	else {
		LOGE ("Invalid device description passed to open_device()");
		return NULL;
	}

	// set up device callbacks
	dev->hmd = hmd;
	dev->id = desc->id;
	dev->opened = true;

	dev->base.update = update_device;
	dev->base.close = close_device;
	dev->base.getf = getf;

	return &dev->base;
}

#define RIFT_ID_COUNT 5

static void get_device_list(ohmd_driver* driver, ohmd_device_list* list)
{
	// enumerate HID devices and add any Rifts found to the device list

	rift_devices rd[RIFT_ID_COUNT] = {
		{ "Rift (DK1)", OCULUS_VR_INC_ID, 0x0001,	-1, REV_DK1 },
		{ "Rift (DK2)", OCULUS_VR_INC_ID, 0x0021,	-1, REV_DK2 },
		{ "Rift (DK2)", OCULUS_VR_INC_ID, 0x2021,	-1, REV_DK2 },
		{ "Rift (CV1)", OCULUS_VR_INC_ID, RIFT_CV1_PID,	 0, REV_CV1 },

		{ "GearVR (Gen1)", SAMSUNG_ELECTRONICS_CO_ID, 0xa500,	 0, REV_GEARVR_GEN1 },
	};

	for(int i = 0; i < RIFT_ID_COUNT; i++){
		struct hid_device_info* devs = hid_enumerate(rd[i].company, rd[i].id);
		struct hid_device_info* cur_dev = devs;

		if(devs == NULL)
			continue;

		while (cur_dev) {
			// We need to check the manufacturer because other companies (eg: VR-Tek)
			// are reusing the Oculus DK1 USB ID for their own HMDs
			if((wcscmp(cur_dev->manufacturer_string, L"Oculus VR, Inc.") == 0) &&
			   (rd[i].iface == -1 || cur_dev->interface_number == rd[i].iface)) {
				int id = 0;
				ohmd_device_desc* desc = &list->devices[list->num_devices++];

				strcpy(desc->driver, "OpenHMD Rift Driver");
				strcpy(desc->vendor, "Oculus VR, Inc.");
				strcpy(desc->product, rd[i].name);

				desc->revision = rd[i].rev;
		
				desc->device_class = OHMD_DEVICE_CLASS_HMD;
				desc->device_flags = OHMD_DEVICE_FLAGS_ROTATIONAL_TRACKING;

				strcpy(desc->path, cur_dev->path);

				desc->driver_ptr = driver;
				desc->id = id++;

				/* For CV1, publish touch controllers */
				if (desc->revision == REV_CV1) {
					//Controller 0 (right)
					desc = &list->devices[list->num_devices++];
					desc->revision = rd[i].rev;

					strcpy(desc->driver, "OpenHMD Rift Driver");
					strcpy(desc->vendor, "Oculus VR, Inc.");
					sprintf(desc->product, "%s: Right Controller", rd[i].name);

					strcpy(desc->path, cur_dev->path);

					desc->device_flags =
						//OHMD_DEVICE_FLAGS_POSITIONAL_TRACKING |
						OHMD_DEVICE_FLAGS_ROTATIONAL_TRACKING |
						OHMD_DEVICE_FLAGS_RIGHT_CONTROLLER;

					desc->device_class = OHMD_DEVICE_CLASS_CONTROLLER;
					desc->driver_ptr = driver;
					desc->id = id++;

					// Controller 1 (left)
					desc = &list->devices[list->num_devices++];
					desc->revision = rd[i].rev;

					strcpy(desc->driver, "OpenHMD Rift Driver");
					strcpy(desc->vendor, "Oculus VR, Inc.");
					sprintf(desc->product, "%s: Left Controller", rd[i].name);

					strcpy(desc->path, cur_dev->path);

					desc->device_flags =
						//OHMD_DEVICE_FLAGS_POSITIONAL_TRACKING |
						OHMD_DEVICE_FLAGS_ROTATIONAL_TRACKING |
						OHMD_DEVICE_FLAGS_LEFT_CONTROLLER;

					desc->device_class = OHMD_DEVICE_CLASS_CONTROLLER;
					desc->driver_ptr = driver;
					desc->id = id++;
				}
			}
			cur_dev = cur_dev->next;
		}

		hid_free_enumeration(devs);
	}
}

static void destroy_driver(ohmd_driver* drv)
{
	LOGD("shutting down driver");
	hid_exit();
	free(drv);

	ohmd_toggle_ovr_service(1); //re-enable OVRService if previously running
}

ohmd_driver* ohmd_create_oculus_rift_drv(ohmd_context* ctx)
{
	ohmd_driver* drv = ohmd_alloc(ctx, sizeof(ohmd_driver));
	if(drv == NULL)
		return NULL;

	ohmd_toggle_ovr_service(0); //disable OVRService if running

	drv->get_device_list = get_device_list;
	drv->open_device = open_device;
	drv->destroy = destroy_driver;
	drv->ctx = ctx;

	return drv;
}
