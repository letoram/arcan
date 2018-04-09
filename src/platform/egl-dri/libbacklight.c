/*
 * libbacklight - userspace interface to Linux backlight control
 *
 * Copyright 2010 Red Hat <mjg@redhat.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice (including the next
 * paragraph) shall be included in all copies or substantial portions of the
 * Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 * Authors:
 *    Matthew Garrett <mjg@redhat.com>
 */

#include "libbacklight.h"
#include <stdio.h>
#include <sys/types.h>
#include <linux/types.h>
#include <dirent.h>
#include <sys/stat.h>
#include <drm_mode.h>
#include <fcntl.h>
#include <malloc.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>
#include "platform.h"

static const char *output_names[] = { "Unknown",
                                      "VGA",
                                      "DVI-I",
                                      "DVI-D",
                                      "DVI-A",
                                      "Composite",
                                      "SVIDEO",
                                      "LVDS",
                                      "Component",
                                      "9-pin DIN",
				                              "DisplayPort",
                                      "HDMI Type A",
                                      "HDMI Type B",
                                      "TV",
		                         		      "eDP",
																			"VIRTUAL",
																			"DSI"

};

static long backlight_get(struct backlight *backlight, char *node)
{
	char buffer[100];
	char *path;
	int fd;
	long value, ret;

	if (asprintf(&path, "%s/%s", backlight->path, node) < 0)
		return -ENOMEM;

	fd = platform_device_open(path, O_RDONLY);
	if (fd < 0) {
		ret = -1;
		goto out;
	}

	ret = read(fd, &buffer, sizeof(buffer));
	if (ret < 1) {
		ret = -1;
		goto out;
	}

	value = strtol(buffer, NULL, 10);
	ret = value;
out:
	close(fd);
	if (path)
		free(path);
	return ret;
}

long backlight_get_brightness(struct backlight *backlight)
{
	return backlight_get(backlight, "brightness");
}

long backlight_get_max_brightness(struct backlight *backlight)
{
	return backlight_get(backlight, "max_brightness");
}

long backlight_get_actual_brightness(struct backlight *backlight)
{
	return backlight_get(backlight, "actual_brightness");
}

long backlight_set_brightness(struct backlight *backlight, long brightness)
{
	char *path;
	char *buffer = NULL;
	int fd;
	long ret;

	if (asprintf(&path, "%s/%s", backlight->path, "brightness") < 0)
		return -ENOMEM;

	fd = platform_device_open(path, O_RDWR);
	if (fd < 0) {
		ret = -1;
		goto out;
	}

	ret = read(fd, &buffer, sizeof(buffer));
	if (ret < 1) {
		ret = -1;
		goto out;
	}

	if (asprintf(&buffer, "%ld", brightness) < 0){
		close(fd);
		ret = -1;
		goto out;
	}

	ret = write(fd, buffer, strlen(buffer));
	if (ret < 0) {
		ret = -1;
		goto out;
	}

	ret = backlight_get_brightness(backlight);
	backlight->brightness = ret;
out:
	if (buffer)
		free(buffer);
	if (path)
		free(path);
	close(fd);
	return ret;
}

void backlight_destroy(struct backlight *backlight)
{
	if (!backlight)
		return;

	if (backlight->path)
		free(backlight->path);

	free(backlight);
}

struct backlight *backlight_init(
	int card, int connector_type, int connector_type_id)
{
	char *drm_name = NULL;
	char *chosen_path = NULL;
	DIR *backlights;
	struct dirent *entry;
	enum backlight_type type = 0;
	char buffer[100];
	struct backlight *backlight;
	int err;

	if (card >= 0) {
		err = asprintf(&drm_name, "card%d-%s-%d", card,
			       output_names[connector_type], connector_type_id);
		if (err < 0)
			return NULL;
	}

	backlights = opendir("/sys/class/backlight");

	if (!backlights)
		return NULL;

	while ((entry = readdir(backlights))) {
		char *backlight_path;
		char *parent;
		char *path;
		enum backlight_type entry_type;
		int fd, ret;

		if (entry->d_name[0] == '.')
			continue;

		if (asprintf(&backlight_path, "%s/%s", "/sys/class/backlight",
			     entry->d_name) < 0)
			return NULL;

		if (asprintf(&path, "%s/%s", backlight_path, "type") < 0)
			return NULL;

		fd = platform_device_open(path, O_RDONLY);

		if (fd < 0)
			goto out;

		ret = read (fd, &buffer, sizeof(buffer));
		close (fd);

		if (ret < 1)
			goto out;

		buffer[ret] = '\0';

		if (!strncmp(buffer, "raw\n", sizeof(buffer)))
			entry_type = BACKLIGHT_RAW;
		else if (!strncmp(buffer, "platform\n", sizeof(buffer)))
			entry_type = BACKLIGHT_PLATFORM;
		else if (!strncmp(buffer, "firmware\n", sizeof(buffer)))
			entry_type = BACKLIGHT_FIRMWARE;
		else
			goto out;

		if (connector_type != DRM_MODE_CONNECTOR_LVDS &&
		    connector_type != DRM_MODE_CONNECTOR_eDP) {
			/* External displays are assumed to require
			   gpu control at the moment */
			if (entry_type != BACKLIGHT_RAW)
				goto out;
		}

		free (path);

		if (asprintf(&path, "%s/%s", backlight_path, "device") < 0)
			return NULL;

		ret = readlink(path, buffer, sizeof(buffer)-1);

		if (ret < 0)
			goto out;

		buffer[ret] = '\0';

		parent = basename(buffer);

		/* Perform matching for raw and firmware backlights -
		   platform backlights have to be assumed to match */
		if (entry_type == BACKLIGHT_RAW ||
		    entry_type == BACKLIGHT_FIRMWARE) {
			if (!((drm_name && !strcmp(drm_name, parent))))
				goto out;
		}

		if (entry_type < type)
			goto out;

		type = entry_type;

		if (chosen_path)
			free(chosen_path);
		chosen_path = strdup(backlight_path);

	out:
		free(backlight_path);
		free(path);
	}

	if (!chosen_path)
		return NULL;

	backlight = malloc(sizeof(struct backlight));

	if (!backlight)
		goto err;

	backlight->path = chosen_path;
	backlight->type = type;

	backlight->max_brightness = backlight_get_max_brightness(backlight);
	if (backlight->max_brightness < 0)
		goto err;

	backlight->brightness = backlight_get_actual_brightness(backlight);
	if (backlight->brightness < 0)
		goto err;

	if (drm_name)
		free(drm_name);

	return backlight;
err:
	if (drm_name)
		free(drm_name);
	if (chosen_path)
		free(chosen_path);
	free (backlight);
	return NULL;
}
