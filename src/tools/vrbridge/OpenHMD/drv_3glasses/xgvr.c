/*
 ***************************************************************************************************
 *                  3Glasses HMD Driver - HID/USB Driver Implementation
 *
 * File   : xgvr.c
 * Author : Duncan Li (duncan.li@3glasses.com)
 *          Douglas Xie (dongyang.xie@3glasses.com )
 * Version: V1.0
 * Date   : 10-June-2018
 ***************************************************************************************************
 * Copyright (C) 2018 VR Technology Holdings Limited.  All rights reserved.
 * Website:  www.3glasses.com    www.vrshow.com
 ***************************************************************************************************
 */

#include <stdlib.h>
#include <hidapi.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <assert.h>

#include "xgvr.h"
#include "../hid.h"

/* 3Glasses SKU id */
#define PLATFORM_SKU_D3V1_M41V2     0
#define PLATFORM_SKU_D3V2_M42V3     1
#define PLATFORM_SKU_D3C_M3V3       2
#define PLATFORM_SKU_D2C_M3V3       3
#define PLATFORM_SKU_S1_V5          4
#define PLATFORM_SKU_S1_V8          5

/* 3Glasses feature report id */
#define FEATURE_BUFFER_SIZE         256
#define FEATURE_SENSOR_ID           0x83
#define FEATURE_COMMAND_REPORT_ID   0x06

typedef struct {
    uint16_t usb_vid;
    uint16_t usb_pid;
    char *desc;
    int sku;
} xgvr_platform_sku_t;
xgvr_platform_sku_t platform_sku[] = {
    {
        0x2b1c, 0x0200, "3Glasses-D3V1", PLATFORM_SKU_D3V1_M41V2,
    },
    {
        0x2b1c, 0x0201, "3Glasses-D3V2", PLATFORM_SKU_D3V2_M42V3,
    },
    {
        0x2b1c, 0x0202, "3Glasses-D3C", PLATFORM_SKU_D3C_M3V3,
    },
    {
        0x2b1c, 0x0203, "3Glasses-D2C", PLATFORM_SKU_D2C_M3V3,
    },
    {
        0x2b1c, 0x0100, "3Glasses-S1V5", PLATFORM_SKU_S1_V5,
    },
    {
        0x2b1c, 0x0101, "3Glasses-S1V8", PLATFORM_SKU_S1_V8,
    },
};

typedef struct {
    ohmd_device device;
    hid_device* hid_handle;
    int sku;
    xgvr_hmd_data_t hmd_data;
    struct {
        uint8_t bootloader_version_major;
        uint8_t bootloader_version_minor;
        uint8_t runtime_version_major;
        uint8_t runtime_version_minor;
    } version;
} xgvr_priv;

static xgvr_priv* _xgvr_priv_get(ohmd_device* device)
{
    return (xgvr_priv*)device;
}

static int _get_feature_report(xgvr_priv* priv, unsigned char report_id, unsigned char* buf)
{
    memset(buf, 0, FEATURE_BUFFER_SIZE);
    buf[0] = report_id;
    return hid_get_feature_report(priv->hid_handle, buf, FEATURE_BUFFER_SIZE);
}

static int _send_feature_report(xgvr_priv* priv, const unsigned char *data, size_t length)
{
    return hid_send_feature_report(priv->hid_handle, data, length);
}

static void _priv_update_firmware_version(xgvr_priv* priv)
{
    unsigned char buf[FEATURE_BUFFER_SIZE];
    int size;

    size = _get_feature_report(priv, FEATURE_COMMAND_REPORT_ID, buf);
    if (size <= 0) {
        LOGE("error reading firmware version");
    } else {
        xgvr_decode_version_packet(buf, size, &priv->version.bootloader_version_major, &priv->version.bootloader_version_minor, &priv->version.runtime_version_major, &priv->version.runtime_version_minor);
        LOGD("Version Report: 3Glasses HMD");
        LOGD("  bootloader version:  %d.%02d", priv->version.bootloader_version_major, priv->version.bootloader_version_minor);
        LOGD("  runtime version   :  %d.%02d", priv->version.runtime_version_major, priv->version.runtime_version_minor);
    }
}

static void _priv_update_properties(xgvr_priv* priv)
{
    // TODO: update the device properties for d3 series
    priv->device.properties.hsize = 0.120960f;
    priv->device.properties.vsize = 0.068040f;
    priv->device.properties.hres = 2560;
    priv->device.properties.vres = 1440;
    priv->device.properties.lens_sep = 0.063000f;
    priv->device.properties.lens_vpos = priv->device.properties.vsize / 2;
    priv->device.properties.fov = DEG_TO_RAD(111.435f);
    priv->device.properties.ratio = (priv->device.properties.hres / 2.0f) / priv->device.properties.vres;

    // Some buttons and axes
    priv->device.properties.control_count = 3;
    priv->device.properties.controls_hints[0] = OHMD_MENU;        // button bit 0
    priv->device.properties.controls_hints[1] = OHMD_HOME;        // button bit 1
    priv->device.properties.controls_hints[2] = OHMD_TRIGGER;     // proxmity
    priv->device.properties.controls_types[0] = OHMD_DIGITAL;
    priv->device.properties.controls_types[1] = OHMD_DIGITAL;
    priv->device.properties.controls_types[2] = OHMD_DIGITAL;

    //setup generic distortion coeffs, from hand-calibration
    ohmd_set_universal_distortion_k(&(priv->device.properties), 0.75239515, -0.84751135, 0.42455423, 0.66200626);
    ohmd_set_universal_aberration_k(&(priv->device.properties), 1.0, 1.0, 1.0);
}

static void _update_device(ohmd_device* device)
{
    int size = 0;
    unsigned char buffer[FEATURE_BUFFER_SIZE];
    xgvr_priv* priv = _xgvr_priv_get(device);

    while ((size = hid_read(priv->hid_handle, buffer, FEATURE_BUFFER_SIZE)) > 0) {
        if (buffer[0] == FEATURE_SENSOR_ID) {
            xgvr_decode_hmd_data_packet(buffer, size, &priv->hmd_data);
        } else {
            LOGE("unknown message type: %u", buffer[0]);
        }
    }

    if (size < 0) {
        LOGE("error reading from device");
    }
}

static int _getf(ohmd_device* device, ohmd_float_value type, float* out)
{
    xgvr_priv* priv = _xgvr_priv_get(device);


    switch (type) {
    case OHMD_ROTATION_QUAT:
        *(quatf*)out = *(quatf*)&priv->hmd_data.quat;
        break;

    case OHMD_POSITION_VECTOR:
        out[0] = out[1] = out[2] = 0;
        break;

    case OHMD_DISTORTION_K:
        // TODO this should be set to the equivalent of no distortion
        memset(out, 0, sizeof(float) * 6);
        break;

    case OHMD_CONTROLS_STATE:
        out[0] = priv->hmd_data.button & 0x01;
        out[1] = priv->hmd_data.button & 0x02;
        out[2] = priv->hmd_data.als;
        break;

    default:
        ohmd_set_error(priv->device.ctx, "invalid type given to getf (%ud)", type);
        return -1;
        break;
    }

    return 0;
}

static void _close_device(ohmd_device* device)
{
    LOGD("closing device");
    xgvr_priv* priv = _xgvr_priv_get(device);
    hid_close(priv->hid_handle);
    free(priv);
}

#define UDEV_WIKI_URL "https://github.com/OpenHMD/OpenHMD/wiki/Udev-rules-list"
static ohmd_device* _open_device(ohmd_driver* driver, ohmd_device_desc* desc)
{
    xgvr_priv* priv = ohmd_alloc(driver->ctx, sizeof(xgvr_priv));
    if (!priv)
        goto cleanup;

    priv->device.ctx = driver->ctx;

    // Open the HID device
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

    // Set default device properties
    ohmd_set_default_device_properties(&priv->device.properties);

    if ((priv->sku == PLATFORM_SKU_D3V1_M41V2) || (priv->sku == PLATFORM_SKU_D3V2_M42V3) || (priv->sku == PLATFORM_SKU_D3C_M3V3) || (priv->sku == PLATFORM_SKU_D2C_M3V3)) {
        _priv_update_firmware_version(priv);
        _priv_update_properties(priv);
        priv->device.update = _update_device;
        priv->device.close = _close_device;
        priv->device.getf = _getf;
        priv->device.settings.automatic_update = 0;
    } else if ((priv->sku == PLATFORM_SKU_S1_V5) || (priv->sku == PLATFORM_SKU_S1_V8)) {
        // TODO
    } else {
        LOGE("unknown sku id: %04x", priv->sku);
    }

    // calculate projection eye projection matrices from the device properties
    ohmd_calc_default_proj_matrices(&priv->device.properties);

    return &priv->device;

cleanup:
    if (priv)
        free(priv);

    return NULL;
}

static void _get_device_list(ohmd_driver* driver, ohmd_device_list* list)
{
    int i;

    // enumerate HID devices and add any 3Glasses HMD found to the device list
    for (i = 0; i < sizeof(platform_sku) / sizeof(xgvr_platform_sku_t); i++) {
        struct hid_device_info* devs = hid_enumerate(platform_sku[i].usb_vid, platform_sku[i].usb_pid);
        struct hid_device_info* cur_dev = devs;

        if (devs == NULL)
            continue;

        while (cur_dev) {
            ohmd_device_desc* desc = &list->devices[list->num_devices++];

            strcpy(desc->driver, "OpenHMD 3Glasses Driver");
            strcpy(desc->vendor, "3Glasses");
            strcpy(desc->product, platform_sku[i].desc);

            desc->id = platform_sku[i].sku;

            desc->device_class = OHMD_DEVICE_CLASS_HMD;
            desc->device_flags = OHMD_DEVICE_FLAGS_ROTATIONAL_TRACKING;

            strcpy(desc->path, cur_dev->path);
            desc->driver_ptr = driver;
            cur_dev = cur_dev->next;
        }

        hid_free_enumeration(devs);
    }
}

static void _destroy_driver(ohmd_driver* drv)
{
    LOGD("shutting down 3Glasses driver");
    hid_exit();
    free(drv);
}

ohmd_driver* ohmd_create_xgvr_drv(ohmd_context* ctx)
{
    ohmd_driver* drv = ohmd_alloc(ctx, sizeof(ohmd_driver));
    if (drv == NULL)
        return NULL;

    drv->get_device_list = _get_device_list;
    drv->open_device = _open_device;
    drv->destroy = _destroy_driver;
    drv->ctx = ctx;

    return drv;
}
