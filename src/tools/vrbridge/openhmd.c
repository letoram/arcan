#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include "arcan_math.h"
#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <hidapi.h>
#include <pthread.h>
#include <openhmd.h>
#include "vrbridge.h"
#include "avr_openhmd.h"

#define ID_NECK 0
#define ID_LTOOL 1
#define ID_RTOOL 2

static ohmd_context* ohmd;

struct driver_state {
	pthread_mutex_t lock;
	ohmd_device* hmd;
	volatile quat last_quat;
	volatile bool got_ref;
	volatile quat ref_quat;
};

/*
 * doesn't seem to have any interface for us to just block / wait on to
 * update unfortunately
 */
void openhmd_sample(struct dev_ent* dev, struct vr_limb* limb, unsigned id)
{
	struct driver_state* state = dev->state;
	quat orient;

	while(1){
		switch(id){
		case 0:
			ohmd_ctx_update(ohmd);
			ohmd_device_getf(state->hmd, OHMD_ROTATION_QUAT, orient.xyzw);
			orient = inv_quat(orient);
			debug_print(1, "orientation: %f, %f, %f, %f",
				orient.x, orient.y, orient.z, orient.w);

			quat lq = state->last_quat;
			if (memcmp(lq.xyzw, orient.xyzw, sizeof(float)*4) != 0){
				state->last_quat = orient;

/* account for a set base orientation */
				pthread_mutex_lock(&state->lock);
				if (state->got_ref)
					orient = mul_quat(orient, state->ref_quat);
				pthread_mutex_unlock(&state->lock);

/* apply and forward */
				limb->data.orientation = orient;
				return;
			}
/* would be nice to get something else to wait on here .. */
			else{
				arcan_timesleep(1);
			}
		break;
		}
	}
}

void openhmd_control(struct dev_ent* ent, enum ctrl_cmd cmd)
{
	struct driver_state* state = ent->state;
	if (cmd == RESET_REFERENCE){
		pthread_mutex_lock(&state->lock);
		state->got_ref = true;
		state->ref_quat = inv_quat(state->last_quat);
		pthread_mutex_unlock(&state->lock);
	}
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
	debug_print(0, "%d devices found", nd);
	if (nd <= 0)
		return false;

	struct driver_state* state = malloc(sizeof(struct driver_state));
	if (!state){
		debug_print(0, "couldn't allocate state");
		return false;
	}

	*state = (struct driver_state){};
	ent->state = state;
	pthread_mutex_init(&state->lock, NULL);

/* should likely just sweep unless we explicitly get index set */
	long devind = 0;
	const char(* str);

	if (arg && arg_lookup(arg, "ohmd_index", 0, &str)){
		devind = strtol(str, NULL, 10) % INT_MAX;
	}

	if (devind == -1){
		debug_print(0, "device sweep requested");
		for (size_t i = 0; i < nd; i++){
			state->hmd = ohmd_list_open_device(ohmd, i);
			if (state->hmd){
				debug_print(0, "found device at index: %zu", i);
				break;
			}
		}
		if (!state->hmd){
			debug_print(0, "sweep over, no device worked");
			free(state);
			return false;
		}
	}
	else{
		state->hmd = ohmd_list_open_device(ohmd, devind);
		if (!state->hmd){
			debug_print(0, "failed to open device at index: %d/%d", devind, nd);
			free(state);
			return false;
		}
	}

	debug_print(0, "vendor:  %s", ohmd_list_gets(ohmd, 0, OHMD_VENDOR));
	debug_print(0, "product: %s", ohmd_list_gets(ohmd, 0, OHMD_PRODUCT));
	debug_print(0, "path:    %s", ohmd_list_gets(ohmd, 0, OHMD_PATH));

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
	getf(OHMD_LEFT_EYE_GL_PROJECTION_MATRIX, vr->meta.projection_left);
	getf(OHMD_RIGHT_EYE_GL_PROJECTION_MATRIX, vr->meta.projection_right);

/*
 * OHMD_BUTTON_COUNT,
 * we can _enqueue IO_EVENT for each button, the engine doesn't
 * really care about count
 */
	vrbridge_alloc_limb(ent, NECK, 0);

	return true;
}
