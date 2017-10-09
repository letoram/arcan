#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include "arcan_math.h"
#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <hidapi/hidapi.h>
#include <pthread.h>
#include <openhmd.h>
#include "vrbridge.h"
#include "avr_openhmd.h"

#define ID_NECK 0
#define ID_LTOOL 1
#define ID_RTOOL 2

static ohmd_context* ohmd;

struct driver_state {
	ohmd_device* hmd;
	quat last_quat;
};

/*
 * doesn't seem to have any interface for us to just block / wait on to
 * update unfortunately
 */
void openhmd_sample(struct dev_ent* dev, struct vr_limb* limb, unsigned id)
{
	struct driver_state* state = dev->state;
	quat quat;

	while(1){
		switch(id){
		case ID_NECK:
			ohmd_device_getf(state->hmd, OHMD_ROTATION_QUAT, quat.xyzw);
			if (memcmp(state->last_quat.xyzw, quat.xyzw, sizeof(float)*4) != 0){
				limb->data.orientation = state->last_quat = quat;
				return;
			}
			else{
				arcan_timesleep(4);
			}
		break;
		}
	}
}

void openhmd_control(struct dev_ent* ent, enum ctrl_cmd cmd)
{
}

extern bool in_openhmd_mode;
bool openhmd_init(struct dev_ent* ent,
	struct arcan_shmif_vr* vr, struct arg_arr* arg)
{
/* don't use OpenHMD if we already have a HMD display */
	if (vr->meta.hres){
		debug_print(0, "HMD already present, ignoring openHMD");
		return false;
	}

	if (!ohmd){
		ohmd = ohmd_ctx_create();
		if (!ohmd){
			debug_print(0, "couldn't initialize openHMD");
			return false;
		}
	}

	int nd = ohmd_ctx_probe(ohmd);
	debug_print(1, "%d devices found", nd);
	if (nd <= 0)
		return false;

	struct driver_state* state = malloc(sizeof(struct driver_state));
	if (!state){
		debug_print(0, "couldn't allocate state");
		return false;
	}

/* should likely just sweep unless we explicitly get index set */
	int devind = 0;
	const char(* str);
	if (arg_lookup(arg, "ohmd_index", 0, &str)){
		devind = strtoul(str, NULL, 10) % INT_MAX;
	}

	state->hmd = ohmd_list_open_device(ohmd, devind);
	if (!state->hmd){
		free(state);
		return false;
	}

#define geti(X, Y) ohmd_device_geti(state->hmd, X, Y)
#define getf(X, Y) ohmd_device_getf(state->hmd, X, Y)

	int ival;
	geti(OHMD_SCREEN_HORIZONTAL_RESOLUTION, &ival);
	vr->meta.hres = ival;
	geti(OHMD_SCREEN_VERTICAL_RESOLUTION, &ival);
	vr->meta.vres = ival;
	getf(OHMD_SCREEN_HORIZONTAL_SIZE, &vr->meta.h_size);
	getf(OHMD_SCREEN_VERTICAL_SIZE, &vr->meta.v_size);
	getf(OHMD_LENS_HORIZONTAL_SEPARATION, &vr->meta.hsep);
	getf(OHMD_LENS_VERTICAL_POSITION, &vr->meta.vpos);
 	getf(OHMD_LEFT_EYE_FOV, &vr->meta.left_fov);
	getf(OHMD_RIGHT_EYE_FOV, &vr->meta.right_fov);
	getf(OHMD_LEFT_EYE_ASPECT_RATIO, &vr->meta.left_ar);
	getf(OHMD_RIGHT_EYE_ASPECT_RATIO, &vr->meta.right_ar);
	getf(OHMD_EYE_IPD, &vr->meta.ipd);
 	getf(OHMD_UNIVERSAL_DISTORTION_K, vr->meta.distortion);
 	getf(OHMD_UNIVERSAL_ABERRATION_K, vr->meta.abberation);

/*
 * OHMD_BUTTON_COUNT,
 * we can _enqueue IO_EVENT for each button, the engine doesn't
 * really care about count
 */
	vrbridge_alloc_limb(ent, NECK, ID_NECK);

	return true;
}
