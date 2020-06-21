// Copyright 2019, Mark Nelson.
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 */

/* VR-Tek Driver */

#include <stdlib.h>
#include <hidapi.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>

#include "vrtek.h"
#include "../hid.h"

/* VR-Tek reuses the Oculus Vendor ID */
#define OCULUS_VR_INC_ID        0x2833
#define VRTEK_WVR_HMD           0x0001

#define REPORT_BUFFER_SIZE      128
#define RESPONSE_DATA_SIZE      64

#define MODEL_STRING_LENGTH     12

typedef struct {
    ohmd_device device;
    hid_device* hid_handle;
    vrtek_sensor_fusion_t* ofusion;
    vrtek_hmd_sku sku;
    char model_str[MODEL_STRING_LENGTH+1];
    uint32_t hmd_software_version;
    vrtek_display_type display_type;
    vrtek_hmd_data_t hmd_data;
} vrtek_priv;

static vrtek_priv* vrtek_priv_get(ohmd_device* device)
{
    return (vrtek_priv*)device;
}

static int vrtek_send_init(vrtek_priv* priv)
{
    uint8_t buf[] = { 0x1, 0x0 };
    int ret;
    ret = hid_write(priv->hid_handle, buf, 2);
    LOGD("%s: sent %d bytes\n", __func__, ret);

    if (ret == -1) {
        LOGE("%s: hid_write encountered an error: %ls", __func__,
             hid_error(priv->hid_handle));
    }

    ohmd_sleep(0.1);

    return ret;
}

static int send_command_packet(vrtek_priv* priv, const uint8_t* data,
                               size_t length)
{
    int ret = hid_write(priv->hid_handle, data, length);
    LOGD("%s: sent command packet of %d bytes\n", __func__, ret);

    if (ret == -1) {
        LOGE("%s: hid_write encountered an error: %ls", __func__,
             hid_error(priv->hid_handle));
    } else if (ret != length) {
        LOGE("%s: failed to send all bytes of command packet. "
             "Sent %d, expected %lu", __func__, ret, length);
    }

    return ret;
}

static int receive_response_packet(vrtek_priv* priv, uint8_t* buf,
                                   size_t buf_length)
{
    const size_t read_length = 64;
    const int    read_timeout = 100;
    assert(read_length <= buf_length);
    uint8_t report_num = 0;
    int ret = 0;
    int hid_reads = 0;
    const int max_hid_reads = 100;

    while (report_num != VRTEK_REPORT_CONTROL_INPUT) {
        ret = hid_read_timeout(priv->hid_handle, buf, read_length,
                               read_timeout);
        ++hid_reads;
        if (ret == -1) {
            LOGE("%s: hid_read_timeout hit an error: %ls",
                 __func__, hid_error(priv->hid_handle));
        } else if (ret == 0) {
            LOGW("%s: hid_read_timeout received no packet", __func__);
        }

        if (hid_reads == max_hid_reads) {
            LOGW("%s: received %d messages that were NOT valid responses\n",
                 __func__, hid_reads);

        }
        report_num = buf[0];
        if (report_num == VRTEK_REPORT_SENSOR) {
            /* skip any extraneous sensor messages */
            LOGD("%s: skipping sensor message\n", __func__);
            continue;
        } else if (ret != read_length) {
            LOGW("%s: received response packet with %d bytes, but expected %lu",
                 __func__, ret, read_length);
        }
    }

    return ret;
}

static void vrtek_send_command_and_receive_response(vrtek_priv* priv,
                                                    uint8_t command_num,
                                                    uint8_t command_arg,
                                                    uint8_t* command_data,
                                                    uint8_t command_data_len,
                                                    uint8_t* response_data,
                                                    uint8_t* response_data_len)
{
    uint8_t buf[REPORT_BUFFER_SIZE];
    uint8_t response_command_num;
    uint8_t response_command_arg;

    int size;
    int result;

    size = vrtek_encode_command_packet(command_num, command_arg, command_data,
                                       command_data_len, buf);
    result = send_command_packet(priv, buf, size);
    assert(result != -1);

    size = receive_response_packet(priv, buf, REPORT_BUFFER_SIZE);
    assert(size == RESPONSE_DATA_SIZE);
    result = vrtek_decode_command_packet(buf, &response_command_num,
                                         &response_command_arg, response_data,
                                         response_data_len);
    assert(result == 0);
    assert(response_command_num == command_num);
    assert(response_command_arg == command_arg);
}

static const char* vrtek_get_display_type_string(vrtek_display_type display)
{
    switch(display) {
        case VRTEK_DISP_LCD2880X1440:
            return "2880x1440 (dual 2.89\" 1440x1440 Sharp panels)";
        case VRTEK_DISP_LCD1440X2560_ROTATED:
            return "2560x1440 (single 5.5\" 1440x2560 Sharp panel rotated)";
        case VRTEK_DISP_UNKNOWN:
            return "Unknown";
        default:
            assert(false);
    }
}

static void vrtek_update_display_properties(vrtek_priv* priv,
                                            uint8_t display_type)
{
    switch(display_type) {
        case 4:
            /* WVR3 has two 2.89" 1440x1440 LCDs */
            priv->display_type = VRTEK_DISP_LCD2880X1440;
            priv->device.properties.hsize = 0.103812f;
            priv->device.properties.vsize = 0.051905f;
            priv->device.properties.hres = 2880;
            priv->device.properties.vres = 1440;
            priv->device.properties.lens_sep = 0.054;  /* FIXME */
            priv->device.properties.lens_vpos
                                   = priv->device.properties.vsize / 2;
            priv->device.properties.fov = DEG_TO_RAD(100.0f);
            priv->device.properties.ratio
                                   = 1.0f;  /* (2880.0f / 1440.0f) / 2.0f */

            /* FIXME: work out the real values */
            ohmd_set_universal_distortion_k(&(priv->device.properties),
                                            0.098, .324, -0.241, 0.819);
            ohmd_set_universal_aberration_k(&(priv->device.properties),
                                            0.9952420, 1.0, 1.0008074);
            break;
        case 5:
            /* WVR2 has one 5.5" 1440x2560 LCD rotated left*/
            /* NOTE: The user is expected to have rotated the display with:
             *   xrandr --output HDMI-A-1 --rotate left */
            priv->display_type = VRTEK_DISP_LCD1440X2560_ROTATED;
            priv->device.properties.hsize = 0.120960f;  /* FIXME */
            priv->device.properties.vsize = 0.068040f;  /* FIXME */
            priv->device.properties.hres = 2560;
            priv->device.properties.vres = 1440;
            priv->device.properties.lens_sep = 0.063f;  /* FIXME */
            priv->device.properties.lens_vpos
                                   = priv->device.properties.vsize / 2;
            priv->device.properties.fov = DEG_TO_RAD(100.0f);
            priv->device.properties.ratio
                                   = (priv->device.properties.hres / 2.0f)
                                               / priv->device.properties.vres;

            /* FIXME: work out the real values */
            ohmd_set_universal_distortion_k(&(priv->device.properties),
                                            0, 0, 0, 1);
            ohmd_set_universal_aberration_k(&(priv->device.properties),
                                            1.0, 1.0, 1.0);
            break;
        default:
            priv->display_type = VRTEK_DISP_UNKNOWN;
    }

    LOGI("HMD display type is %s",
         vrtek_get_display_type_string(priv->display_type));
}

static void vrtek_update_hmd_software_version(vrtek_priv* priv,
                                              const uint8_t* response,
                                              uint8_t size)
{
    const int min_packet_response_len = 24;
    if (size < min_packet_response_len) {
        LOGW("unknown command packet response format (expected at least %d "
             "bytes got %d)", min_packet_response_len, size);
        return;
    }

    /* HMD software version starts at byte 20 in the response */
    response += 20;

    uint32_t hmd_soft_ver = (*response << 24) | (*(response + 1) << 16) |
                            (*(response + 2) << 8) | *(response + 3);

    LOGI("HMD software version is 0x%4x", hmd_soft_ver);

    /* This driver does not work with HMD software versions greater than
     * 0x30010100 because the HMD packet format is different */
    const uint32_t max_supported_hmd_soft_ver = 0x30010100;
    if (hmd_soft_ver > max_supported_hmd_soft_ver) {
        LOGE("HMD software version 0x%4x incompatible, expected <= 0x%4x",
             max_supported_hmd_soft_ver, hmd_soft_ver);
        assert(hmd_soft_ver <= 0x30010100);
    }

    priv->hmd_software_version = hmd_soft_ver;
}

static const char* vrtek_get_model_string(vrtek_hmd_sku model)
{
    switch(model) {
        case VRTEK_SKU_WVR_UNKNOWN:
            return "Unknown VR-Tek WVR";
        case VRTEK_SKU_WVR1:
            return "VR-Tek WVR1";
        case VRTEK_SKU_WVR2:
            return "VR-Tek WVR2";
        case VRTEK_SKU_WVR3:
            return "VR-Tek WVR3";
        case VRTEK_SKU_UNKNOWN_UNKNOWN:
            return "Unknown HMD";
        default:
            assert(false);
    }
}

#define OHMD_GRAVITY_EARTH 9.80665    /* m/s² */

static void vrtek_update_hmd_model(vrtek_priv* priv, const char* model,
                                   uint8_t length)
{
    if (length < MODEL_STRING_LENGTH) {
        priv->sku = VRTEK_SKU_UNKNOWN_UNKNOWN;
        LOGW("unknown command packet response format (expected at least %d "
             "bytes got %d)\n", MODEL_STRING_LENGTH, length);
        return;
    }

    memcpy(priv->model_str, model, MODEL_STRING_LENGTH);
    priv->model_str[12] = '\0';

    vrtek_sensor_fusion_t* ofusion = priv->ofusion;

    /* HMD model number starts at the beginning of the response */
    if (strncmp(model, "WVR", 3) == 0) {
        switch(*(model + 3)) {
            case '1':
                priv->sku = VRTEK_SKU_WVR1;
                if (ofusion) {
                    /* FIXME: add offset support for WVR1 */
                    ofusion->gyro_offset[0] = 0;
                    ofusion->gyro_offset[1] = 0;
                    ofusion->gyro_offset[2] = 0;
                }
                break;
            case '2':
                priv->sku = VRTEK_SKU_WVR2;
                if (ofusion) {
                    /* FIXME: Can we query the headset for these? */
                    ofusion->gyro_offset[0] = 19;
                    ofusion->gyro_offset[1] = 52;
                    ofusion->gyro_offset[2] = 23;
                }
                break;
            case '3':
                priv->sku = VRTEK_SKU_WVR3;
                if (ofusion) {
                    /* FIXME: Can we query the headset for these? */
                    ofusion->gyro_offset[0] = 32;
                    ofusion->gyro_offset[1] = 36;
                    ofusion->gyro_offset[2] = -12;
                }
                break;
            default:
                priv->sku = VRTEK_SKU_WVR_UNKNOWN;
                LOGW("Unknown VR-Tek HMD model: %s\n", priv->model_str);
        }
    } else {
        priv->sku = VRTEK_SKU_UNKNOWN_UNKNOWN;
        LOGE("Unknown HMD model: %s\n", priv->model_str);
        return;
    }

    LOGI("HMD model is %s (%s)", vrtek_get_model_string(priv->sku),
         priv->model_str);

    if (ofusion) {
        /*
         * The WVR3 and WVR2 IMUs are configured with a gyro full scale range
         * of +/-2000°/s (the IMU itself can operate with +/-250°/s, +/-500°/s,
         * +/-1000°/s, or +/-2000°/s). Convert this into rad/s.
         * The accel full scale range is +/-4g (the IMU itself can operate with
         * +/-2g, +/-4g, +/-8g, or +/-16g). Convert this to m/s².
         *
         * NOTE: Right now we assume that the WVR1 is the same. This is
         * probably a fair assumption because the WVR1 looks like a WVR2 with
         * a lower resolution panel.
         */

        /* FIXME: Can we query the headset for these? */
        double gyro_range = M_PI / 180.0 * (250 << 3);
        ofusion->gyro_range = (float) gyro_range;
        double accel_range = OHMD_GRAVITY_EARTH * (2 << 1);
        ofusion->accel_range = (float) accel_range;

        LOGI("Using gyro offsets %hd, %hd, %hd", ofusion->gyro_offset[0],
                                                 ofusion->gyro_offset[1],
                                                 ofusion->gyro_offset[2]);
        LOGI("Using gyro range %lf", gyro_range);
        LOGI("Using accel range %lf", accel_range);
    }
}

static void vrtek_set_imu_state(vrtek_priv* priv, bool state)
{
    uint8_t response_data[RESPONSE_DATA_SIZE];
    uint8_t response_data_len;

    uint8_t imu_state = state;  /* 1 = enabled, 0 = disabled */

    vrtek_send_command_and_receive_response(priv, VRTEK_COMMAND_CONFIGURE_HMD,
                                            VRTEK_CONFIG_ARG_HMD_IMU,
                                            &imu_state, sizeof(uint8_t),
                                            response_data, &response_data_len);
    assert(response_data_len == 1);
    assert(response_data[0] == 0);

    LOGI("HMD IMU %s", imu_state ? "enabled" : "disabled");

    ohmd_sleep(0.1);
}

static void vrtek_read_config(vrtek_priv* priv)
{
    uint8_t response_data[RESPONSE_DATA_SIZE];
    uint8_t response_data_len;

    vrtek_send_command_and_receive_response(priv, VRTEK_COMMAND_QUERY_HMD,
                                            VRTEK_QUERY_ARG_HMD_CONFIG,
                                            NULL, 0,
                                            response_data, &response_data_len);
    assert(response_data_len == 26);

    /* display type is the second byte of the response */
    uint8_t display_type = response_data[1];
    vrtek_update_display_properties(priv, display_type);
    vrtek_update_hmd_software_version(priv, response_data, response_data_len);
}

static void vrtek_read_model(vrtek_priv* priv)
{
    uint8_t response_data[RESPONSE_DATA_SIZE];
    uint8_t response_data_len;

    vrtek_send_command_and_receive_response(priv, VRTEK_COMMAND_QUERY_HMD,
                                            VRTEK_QUERY_ARG_HMD_MODEL,
                                            NULL, 0,
                                            response_data, &response_data_len);
    assert(response_data_len == 56);

    const char* model = (const char*) response_data;
    vrtek_update_hmd_model(priv, model, response_data_len);
}

static void gyro_from_hmd_data(const vrtek_sensor_fusion_t* ofusion,
                               const int16_t* smp, vec3f* out_vec)
{
    float range = ofusion->gyro_range / 32768.0f;
    out_vec->x = range * (float)(smp[0] - ofusion->gyro_offset[0]) * -1.0f;
    out_vec->y = range * (float)(smp[1] - ofusion->gyro_offset[1]);
    out_vec->z = range * (float)(smp[2] - ofusion->gyro_offset[2]) * -1.0f;
}

static void accel_from_hmd_data(const vrtek_sensor_fusion_t* ofusion,
                                const int16_t* smp, vec3f* out_vec)
{
    float range = ofusion->accel_range / 32768.0f;
    out_vec->x = range * (float)(smp[0]) * -1.0f;
    out_vec->y = range * (float)smp[1];
    out_vec->z = range * (float)(smp[2]) * -1.0f;
}

static void mag_from_hmd_data(const vrtek_sensor_fusion_t* ofusion,
                              const int16_t* smp, vec3f* out_vec)
{
    /* FIXME: Update this when we start using magnetometer readings */
    out_vec->x = (float)smp[0];
    out_vec->y = (float)smp[1];
    out_vec->z = (float)smp[2];
}

static uint16_t calc_delta_and_handle_rollover(uint16_t next, uint16_t last)
{
    uint16_t message_num_delta = next - last;

    /* The 8-bit message number has rolled over,
     * adjust the "negative" value to be positive. */
    if (message_num_delta > 0xff) {
        message_num_delta += 0x100;
    }

    return message_num_delta;
}

#define TICK_LEN (1.0f / 500.0f)    /* 500 Hz ticks */

static void handle_hmd_data_packet(vrtek_priv* priv, uint8_t* buf, int size)
{
    vrtek_hmd_data_t* hmd_data = &priv->hmd_data;
    uint16_t last_message_num = hmd_data->message_num;

    int decode_res = vrtek_decode_hmd_data_packet(buf, size, hmd_data);
    if (decode_res != 0) {
        LOGE("couldn't decode HMD sensor data");
    }

    /* If we're not doing our own sensor fusion then we're done */
    if (!priv->ofusion) {
        return;
    }

    vrtek_sensor_fusion_t* ofusion = priv->ofusion;

    float dt = TICK_LEN;

    /* Startup correction */
    if (last_message_num != 256) {
        uint8_t delta = calc_delta_and_handle_rollover(hmd_data->message_num,
                                                       last_message_num);
        dt *= delta;
    }

    gyro_from_hmd_data(ofusion, hmd_data->gyroscope, &ofusion->raw_gyro);
    accel_from_hmd_data(ofusion, hmd_data->acceleration, &ofusion->raw_accel);
    mag_from_hmd_data(ofusion, hmd_data->magnetometer, &ofusion->raw_mag);

    ofusion_update(&ofusion->sensor_fusion, dt,
                   &ofusion->raw_gyro, &ofusion->raw_accel, &ofusion->raw_mag);
}

static void update_device(ohmd_device* device)
{
    int size = 0;
    uint8_t buf[REPORT_BUFFER_SIZE];
    vrtek_priv* priv = vrtek_priv_get(device);

    while ((size = hid_read(priv->hid_handle, buf, REPORT_BUFFER_SIZE)) > 0) {
        if (buf[0] == VRTEK_REPORT_SENSOR) {
            handle_hmd_data_packet(priv, buf, size);
        } else {
            LOGE("unknown message type: %u", buf[0]);
        }
    }

    if (size < 0) {
        LOGE("error reading from device");
    }
}

static int getf(ohmd_device* device, ohmd_float_value type, float* out)
{
    vrtek_priv* priv = vrtek_priv_get(device);

    switch (type) {
    case OHMD_ROTATION_QUAT:
        if (priv->ofusion) {
            *(quatf*)out = priv->ofusion->sensor_fusion.orient;
        } else {
            *(quatf*)out = *(quatf*)&priv->hmd_data.quaternion;
        }

        break;

    case OHMD_POSITION_VECTOR:
        out[0] = out[1] = out[2] = 0;
        break;

    case OHMD_DISTORTION_K:
        /* FIXME: update this with real values */
        memset(out, 0, sizeof(float) * 6);
        break;

    default:
        ohmd_set_error(priv->device.ctx, "invalid type given to getf (%ud)",
                       type);
        return -1;
        break;
    }

    return 0;
}

static void close_device(ohmd_device* device)
{
    LOGD("closing device");
    vrtek_priv* priv = vrtek_priv_get(device);
    hid_close(priv->hid_handle);
    free(priv->ofusion);
    free(priv);
}

#define UDEV_WIKI_URL "https://github.com/OpenHMD/OpenHMD/wiki/Udev-rules-list"
static ohmd_device* open_device(ohmd_driver* driver, ohmd_device_desc* desc)
{
    vrtek_priv* priv = ohmd_alloc(driver->ctx, sizeof(vrtek_priv));
    if (!priv)
        goto cleanup;

    priv->device.ctx = driver->ctx;

    /* Open the HID device */
    priv->hid_handle = hid_open_path(desc->path);

    if (!priv->hid_handle) {
        char* path = _hid_to_unix_path(desc->path);
        ohmd_set_error(driver->ctx, "Could not open %s.\n"
                       "Check your permissions: "
                       UDEV_WIKI_URL, path);
        free(path);
        goto cleanup;
    }

    if (hid_set_nonblocking(priv->hid_handle, 1) == -1) {
        ohmd_set_error(driver->ctx, "failed to set non-blocking on device");
        goto cleanup;
    }

    /* Set default device properties */
    ohmd_set_default_device_properties(&priv->device.properties);

    /* Use the orientation quaternion provided directly by the headset
     * if the user requested it */
    const char* use_direct_quat = getenv("OHMD_VRTEK_USE_DIRECT_QUATERNION");
    if (use_direct_quat && (strncmp(use_direct_quat, "true", 5) == 0)) {
        LOGI("Using orientation quaternion directly from HMD");
    } else {
        priv->ofusion = ohmd_alloc(driver->ctx, sizeof(vrtek_sensor_fusion_t));
        if (priv->ofusion) {
            LOGI("Using OpenHMD sensor fusion for orientation quaternion");
        } else {
            LOGW("Alloc failed. Falling back to using orientation quaternion "
                 "directly from HMD");
        }
    }

    vrtek_send_init(priv);

    /* Disable IMU */
    vrtek_set_imu_state(priv, false);

    /* Read the config */
    vrtek_read_config(priv);

    /* Read the model */
    vrtek_read_model(priv);

    /* Enable IMU */
    vrtek_set_imu_state(priv, true);

    priv->device.update = update_device;
    priv->device.close = close_device;
    priv->device.getf = getf;
    priv->device.settings.automatic_update = 0;

    /* calculate eye projection matrices from the device properties */
    ohmd_calc_default_proj_matrices(&priv->device.properties);

    if (priv->ofusion) {
        ofusion_init(&priv->ofusion->sensor_fusion);

        /* Known initial value for startup correction */
        priv->hmd_data.message_num = 256;
    }

    return &priv->device;

cleanup:
    if (priv)
        free(priv);

    return NULL;
}

static void get_device_list(ohmd_driver* driver, ohmd_device_list* list)
{
    /* Enumerate HID devices and add any VR-Tek HMDs found to the device list.
     * VR-Tek reuses the Oculus Vendor ID, but the manufacturer string is
     * "STMicroelectronics" rather than "Oculus VR, Inc." and the product
     * string is "HID". */
    struct hid_device_info* devs = hid_enumerate(OCULUS_VR_INC_ID,
                                                 VRTEK_WVR_HMD);
    struct hid_device_info* cur_dev = devs;

    while (cur_dev) {
        if (wcscmp(cur_dev->manufacturer_string, L"STMicroelectronics")==0 &&
                        wcscmp(cur_dev->product_string, L"HID")==0) {
            ohmd_device_desc* desc = &list->devices[list->num_devices++];

            strcpy(desc->driver, "OpenHMD VR-Tek Driver");
            strcpy(desc->vendor, "VR-Tek");
            strcpy(desc->product, "VR-Tek WVR");

            desc->device_class = OHMD_DEVICE_CLASS_HMD;
            desc->device_flags = OHMD_DEVICE_FLAGS_ROTATIONAL_TRACKING;

            strcpy(desc->path, cur_dev->path);
            desc->driver_ptr = driver;
        }
        cur_dev = cur_dev->next;
    }

    hid_free_enumeration(devs);
}

static void destroy_driver(ohmd_driver* drv)
{
    LOGD("Shutting down VR-Tek driver");
    hid_exit();
    free(drv);
}

ohmd_driver* ohmd_create_vrtek_drv(ohmd_context* ctx)
{
    ohmd_driver* drv = ohmd_alloc(ctx, sizeof(ohmd_driver));
    if (drv == NULL)
        return NULL;

    drv->get_device_list = get_device_list;
    drv->open_device = open_device;
    drv->destroy = destroy_driver;
    drv->ctx = ctx;

    return drv;
}
