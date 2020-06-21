/*
 * Oculus Rift CV1 Radio
 * Copyright 2016 Philipp Zabel
 * Copyright 2019 Jan Schmidt
 * SPDX-License-Identifier:	BSL-1.0
 */
#include <stdint.h>
#include <string.h>

#include "rift-hmd-radio.h"
#include "../ext_deps/nxjson.h"

static int get_feature_report(hid_device *handle, rift_sensor_feature_cmd cmd, unsigned char* buf)
{
	memset(buf, 0, FEATURE_BUFFER_SIZE);
	buf[0] = (unsigned char)cmd;
	return hid_get_feature_report(handle, buf, FEATURE_BUFFER_SIZE);
}

static int send_feature_report(hid_device *handle, unsigned char* buf, int length)
{
	return hid_send_feature_report(handle, buf, length);
}

static bool rift_hmd_radio_send_cmd(hid_device *handle, uint8_t a, uint8_t b, uint8_t c)
{
	unsigned char buffer[FEATURE_BUFFER_SIZE];
	int cmd_size = encode_radio_control_cmd(buffer, a, b, c);
	int ret_size;

	if (send_feature_report(handle, buffer, cmd_size) < 0)
		return false;

	do {
		ret_size = get_feature_report(handle, RIFT_CMD_RADIO_CONTROL, buffer);
		if (ret_size < 1) {
			LOGE("HMD radio command 0x%02x/%02x/%02x failed - response too small", a, b, c);
			return false;
		}
	} while (buffer[3] & 0x80);

	/* 0x08 means the device isn't responding */
	if (buffer[3] & 0x08)
		return false;

	return true;
}

static int rift_radio_read_flash(hid_device *handle, uint8_t device_type,
				uint16_t offset, uint16_t length, uint8_t *flash_data)
{
	int ret;
	unsigned char buffer[FEATURE_BUFFER_SIZE];
	int cmd_size = encode_radio_data_read_cmd(buffer, offset, length);

	ret = send_feature_report(handle, buffer, cmd_size);
	if (ret < 0)
		goto done;

	if (!rift_hmd_radio_send_cmd (handle, 0x03, RIFT_HMD_RADIO_READ_FLASH_CONTROL,
				  device_type)) {
		ret = -1;
		goto done;
	}

	ret = get_feature_report(handle, RIFT_CMD_RADIO_READ_DATA, buffer);
	if (ret < 0)
		goto done;

	memcpy (flash_data, buffer+7, length);

done:
	return ret;
}

static int rift_radio_read_calibration_hash(hid_device *handle, uint8_t device_type,
					    uint8_t hash[16])
{
	return rift_radio_read_flash(handle, device_type, 0x1bf0, 16, hash);
}

static int rift_radio_read_calibration(hid_device *handle, uint8_t device_type,
		char **json_out, uint16_t *length)
{
	char *json;
	int ret;
	uint8_t flash_data[20];
	uint16_t json_length;
	uint16_t offset;

	ret = rift_radio_read_flash(handle, device_type, 0, 20, flash_data);
	if (ret < 0)
		return ret;

	if (flash_data[0] != 1 || flash_data[1] != 0)
		return -1; /* Invalid data */
	json_length = (flash_data[3] << 8) | flash_data[2];

	json = calloc(1, json_length + 1);
	memcpy(json, flash_data + 4, 16);

	for (offset = 20; offset < json_length + 4; offset += 20) {
		uint16_t json_offset = offset - 4;

		ret = rift_radio_read_flash(handle, device_type, offset, 20, flash_data);
		if (ret < 0) {
			free(json);
			return ret;
		}

		memcpy(json + json_offset, flash_data, OHMD_MIN (20, json_length - json_offset));
	}

	*json_out = json;
	*length = json_length;

	return 0;
}

static bool json_read_vec3(const nx_json *nxj, const char *key, vec3f *out)
{
	const nx_json *member = nx_json_get (nxj, key);

	if (member->type != NX_JSON_ARRAY)
		return false;

	out->x = nx_json_item (member, 0)->dbl_value;
	out->y = nx_json_item (member, 1)->dbl_value;
	out->z = nx_json_item (member, 2)->dbl_value;

	return true;
}

static int rift_touch_parse_calibration(char *json,
		rift_touch_calibration *c)
{
	const nx_json* nxj, *obj, *version, *array;
	int version_number = -1;
	unsigned int i;

	nxj = nx_json_parse (json, 0);
	if (nxj == NULL)
		return -1;

	obj = nx_json_get(nxj, "TrackedObject");
	if (obj->type == NX_JSON_NULL)
		goto fail;

	version = nx_json_get (obj, "JsonVersion");
	if (version->type != NX_JSON_INTEGER || version->int_value != 2) {
		version_number = version->int_value;
		goto fail;
	}
	version_number = version->int_value;

	if (!json_read_vec3 (obj, "ImuPosition", &c->imu_position))
		goto fail;

	c->joy_x_range_min = nx_json_get (obj, "JoyXRangeMin")->int_value;
	c->joy_x_range_max = nx_json_get (obj, "JoyXRangeMax")->int_value;
	c->joy_x_dead_min = nx_json_get (obj, "JoyXDeadMin")->int_value;
	c->joy_x_dead_max = nx_json_get (obj, "JoyXDeadMax")->int_value;
	c->joy_y_range_min = nx_json_get (obj, "JoyYRangeMin")->int_value;
	c->joy_y_range_max = nx_json_get (obj, "JoyYRangeMax")->int_value;
	c->joy_y_dead_min = nx_json_get (obj, "JoyYDeadMin")->int_value;
	c->joy_y_dead_max = nx_json_get (obj, "JoyYDeadMax")->int_value;

	c->trigger_min_range = nx_json_get (obj, "TriggerMinRange")->int_value;
	c->trigger_mid_range = nx_json_get (obj, "TriggerMidRange")->int_value;
	c->trigger_max_range = nx_json_get (obj, "TriggerMaxRange")->int_value;

	array = nx_json_get (obj, "GyroCalibration");
	for (i = 0; i < 12; i++)
		c->gyro_calibration[i] = nx_json_item (array, i)->dbl_value;

	c->middle_min_range = nx_json_get (obj, "MiddleMinRange")->int_value;
	c->middle_mid_range = nx_json_get (obj, "MiddleMidRange")->int_value;
	c->middle_max_range = nx_json_get (obj, "MiddleMaxRange")->int_value;

	c->middle_flipped = nx_json_get (obj, "MiddleFlipped")->int_value;

	array = nx_json_get (obj, "AccCalibration");
	for (i = 0; i < 12; i++)
		c->acc_calibration[i] = nx_json_item (array, i)->dbl_value;

	array = nx_json_get (obj, "CapSenseMin");
	for (i = 0; i < 8; i++)
		c->cap_sense_min[i] = nx_json_item (array, i)->int_value;

	array = nx_json_get (obj, "CapSenseTouch");
	for (i = 0; i < 8; i++)
		c->cap_sense_touch[i] = nx_json_item (array, i)->int_value;

	nx_json_free (nxj);
	return 0;
fail:
	LOGW ("Unrecognised Touch Controller JSON data version %d\n%s\n", version_number, json);
	nx_json_free (nxj);
	return -1;
}

int rift_touch_get_calibration(hid_device *handle, int device_id,
		rift_touch_calibration *calibration)
{
	uint8_t hash[16];
	uint16_t length;
	char *json = NULL;
	int ret = -1;

	/* If the controller isn't on yet, we might fail to read the calibration data */
	ret = rift_radio_read_calibration_hash(handle, device_id, hash);
	if (ret < 0) {
		LOGV ("Failed to read calibration hash from device %d", device_id);
		return ret;
	}

	/* TODO: We need a persistent store for the calibration data to
	 * save time - we only need to re-read the calibration data from the
	 * device if the hash changes. */

	ret = rift_radio_read_calibration(handle, device_id, &json, &length);
	if (ret < 0)
		return ret;

	rift_touch_parse_calibration(json, calibration);

	free(json);
	return 0;
}

bool rift_hmd_radio_get_address(hid_device *handle, uint8_t radio_address[5])
{
	unsigned char buf[FEATURE_BUFFER_SIZE];
	int ret_size;

	if (!rift_hmd_radio_send_cmd (handle, 0x05, 0x03, 0x05))
		return false;

	ret_size = get_feature_report(handle, RIFT_CMD_RADIO_READ_DATA, buf);
	if (ret_size < 0)
		return false;

	if (!decode_radio_address (radio_address, buf, ret_size)) {
		LOGE("Failed to decode received radio address");
		return false;
	}

	return true;
}

