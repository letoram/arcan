#include <stdint.h>
#include <stdbool.h>
#include "arcan_math.h"
#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <hidapi.h>
#include <pthread.h>
#include "vrbridge.h"
#include "avr_test.h"
#include "ahrs.h"

#define ID_NECK 0
#define ID_LTOOL 1
#define ID_RTOOL 2

struct driver_state {
	int axis_ind;
	float axis[3];
};

void test_sample(struct dev_ent* dev, struct vr_limb* limb, unsigned id)
{
	struct driver_state* state = dev->state;

	switch(id){
/* just spin around each axis in sequence */
	case ID_NECK:
		arcan_timesleep(400);
		state->axis[state->axis_ind] += 10;
		if (state->axis[state->axis_ind] > 360.0){
			state->axis[state->axis_ind] = 0;
			state->axis_ind = (state->axis_ind + 1) % 3;
		}
		limb->data.orientation = build_quat_taitbryan(
			state->axis[0], state->axis[1], state->axis[2]);
	break;

	case ID_LTOOL:
		arcan_timesleep(240);
	break;

	case ID_RTOOL:
		arcan_timesleep(240);
	break;
	default:
		printf("vrbridge: unknown id (%d) in test_sample\n", id);
	break;
	}
}

void test_control(struct dev_ent* ent, enum ctrl_cmd cmd)
{
}

extern bool in_test_mode;
bool test_init(struct dev_ent* ent,
	struct arcan_shmif_vr* vr, struct arg_arr* arg)
{
	if (!in_test_mode || vr->meta.hres)
		return false;

	struct driver_state* state = malloc(sizeof(struct driver_state));
	if (!state)
		return false;

	vr->meta.hres = 1280;
	vr->meta.vres = 720;

/*
 * no haptics or aything else right now, just a head and two
 * tools being held (so basically what vive gives you)
 */
	vrbridge_alloc_limb(ent, NECK, ID_NECK);

	if (arg){
		if (arg_lookup(arg, "l_tool", 0, NULL))
			vrbridge_alloc_limb(ent, L_TOOL, ID_LTOOL);
		if (arg_lookup(arg, "r_tool", 0, NULL))
			vrbridge_alloc_limb(ent, R_TOOL, ID_RTOOL);
	}
	state->axis[0] = state->axis[1] = state->axis[2];
	state->axis_ind = 0;
	ent->state = state;

	return true;
}
