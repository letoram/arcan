/*
 * Basic TOBII- stream engine API input driver
 */
#include <arcan_shmif.h>

#include <tobii/tobii.h>
#include <tobii/tobii_streams.h>

static struct arcan_shmif_cont conn;
static bool running = true;

/* aggregate last known data into one event that we requeue when dirty */
static arcan_event outev = {
	.category = EVENT_IO,
	.io = {
		.devid = 0x2122,
		.subid = 1,
		.kind = EVENT_IO_EYES,
		.datatype = EVENT_IDATATYPE_EYES,
		.devkind = EVENT_IDEVKIND_EYETRACKER,
	}
};
static bool dirty = false;

/*
 * other callbacks include gaze point and gaze origin,
 * where gaze_point gives position_xy
 * and gaze_origin_t gives left_validity, left_xyz, right_xyz
 *
 * but our current data model just gives where each cuts the plane and no data
 * about the precision as such.
 *
 * validity_t is just a constant, TOBII_VALIDITY_INVALID, VALID?
 */

void on_presence(tobii_user_presence_status_t status, int64_t timestamp_us, void* tag)
{
/* detail here, the timestamp_us a. not necessarily in the clock of the recipient,
 * and that multiple events might arrive at different timestamps I guess -
 * TOBII_USER_PRESENCE_STATUS_UNKOWN, AWAY, PRESENCE */
	bool new_state = TOBII_USER_PRESENCE_STATUS_AWAY != status;
	if (outev.io.input.eyes.present != new_state){
		outev.io.input.eyes.present = new_state;
		dirty = true;
	}
}

void on_head(tobii_head_pose_t const* head_pose, void* tag)
{
/* structure has: timestamp_us, position_validity,
 * positionm_xyz, rotation_xyz, rotation_validity_xyz
 *
 * with validity in tobii_validitiy_t
 */
}

void on_gaze(const tobii_gaze_point_t* gaze, void* tag)
{
	outev.io.input.eyes.gaze_x1 = outev.io.input.eyes.gaze_x2 = gaze->position_xy[0];
	outev.io.input.eyes.gaze_y1 = outev.io.input.eyes.gaze_y2 = gaze->position_xy[1];
	dirty = true;
}

/*
 * device detection is done via a callback drivern url system
 */
static void devpath(const char* url, void* tag)
{
	char** buf = tag;
	if( *buf != NULL || !url)
		return;

	*buf = strdup(url);
}

int main(int argc, char** argv)
{
	tobii_api_t* api;
	tobii_error_t error = tobii_api_create(&api, NULL, NULL);
	if (error != TOBII_ERROR_NO_ERROR){
		fprintf(stderr, "Couldn't create api: %d\n", error);
		return EXIT_FAILURE;
	}

	char* dev = NULL;
	error = tobii_enumerate_local_device_urls(api, devpath, &dev);
	if (error != TOBII_ERROR_NO_ERROR){
		fprintf(stderr, "Couldn't scan devices: %d\n", error);
		return EXIT_FAILURE;
	}

	if (!dev){
		fprintf(stderr, "No device detected\n");
		return EXIT_FAILURE;
	}

	tobii_device_t* device;
	error = tobii_device_create(api, dev, &device);
	if (error != TOBII_ERROR_NO_ERROR){
		fprintf(stderr, "Couldn't create device\n");
		return EXIT_FAILURE;
	}

	tobii_supported_t supported;
	error = tobii_stream_supported(device, TOBII_STREAM_GAZE_POINT, &supported);
	if (supported == TOBII_SUPPORTED){
		fprintf(stderr, "Gaze point for %s\n", dev);
		tobii_gaze_point_subscribe(device, on_gaze, NULL);
	}
	else {
		fprintf(stderr, "Device (%s) does not support gaze point stream.\n", dev);
/* gaze origin subscribe */
	}

	tobii_state_string_t value;
	error = tobii_get_state_string(device, TOBII_STATE_FAULT, value);
	fprintf(stderr, "Device state: %s\n", value);

	conn = arcan_shmif_open_ext(SHMIF_ACQUIRE_FATALFAIL,
		NULL, (struct shmif_open_ext){.type = SEGID_SENSOR},
		sizeof(struct shmif_open_ext)
	);

/* Need to push the first signal for all the server-side
 * resources to be setup-/ allocated-. */
	arcan_shmif_signal(&conn, SHMIF_SIGVID);

	while (running){
		tobii_wait_for_callbacks(1, &device);
		tobii_device_process_callbacks(device);
		tobii_update_timesync(device);
		if (dirty){
			arcan_shmif_enqueue(&conn, &outev);
			dirty = false;
		}
	}

	tobii_device_destroy(device);
	tobii_api_destroy(api);

	return EXIT_SUCCESS;
}
