/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: VR interfacing tool
 *
 * This tool implements the producer side of the shmif- extension for VR-
 * related data. Though it currently host the drivers itself, the hope is to be
 * able to outsource that work and plug-in whatever happens when/if Khronos
 * manages to clean up the VR framework mess.
 *
 * If possible, we provide not only sensor- data and metadata, but also related
 * devices like audio and video by requesting the relevant subsegments.
 *
 * The basic approach is to populate a structure of limbs, where a limb express
 * the object- space coordinates, position and relative to a single avatar.
 * There is a nasty many:many relation between the number of devices and the
 * number of limbs, with a possibility for overlap.
 *
 * Though wasteful, in the case of overlap or redundancies, it is probably
 * the safest to provide multiple implementations of the same limb, and have
 * the consumer discard or sensor-fuse.
 */
#include <stdbool.h>
#include "arcan_math.h"
#include <arcan_shmif.h>
#include <hidapi/hidapi.h>
#include <pthread.h>
#include <stdatomic.h>

#include "vrbridge.h"

#ifdef PSVR
#include "psvr.h"
#endif

volatile bool shutdown;
volatile _Atomic uint_least8_t active;

static void* limb_runner(void* arg)
{
	struct dev_ent* meta = arg;
	while (!shutdown){
/* 1. sample, and depending on device config, sleep or just spin */
/* 2. on device lost, flip our allocation bit and exit */
	}

	if (meta->control)
		meta->control(meta, SHUTDOWN, 0);

	return NULL;
}

static uint64_t ent_alloc_mask;
static struct dev_ent dev_tbl[] =
{
#ifdef PSVR
	{
		.init = psvr_init,
		.sample = psvr_sample,
		.control = psvr_control
	}
#endif
};

static bool init_device(struct dev_ent* ent)
{
/* run init function, if ok
 * create mutex and spawn limb_runner thread detached,
 * forward devent */
	return false;
}

static size_t device_rescan(
	struct arcan_shmif_cont* cont, struct arcan_shmif_vr* vr)
{
/*
 * Limb allocation -> own thread. Can update without any other synchronization
 * so the only thing we need to do here is poll the shmif- event-queue and
 * rescan/ realloc if needed.
 */
	size_t count = 0;

	for (size_t i = 0; i < sizeof(dev_tbl)/sizeof(dev_tbl[0]); i++){
		if (ent_alloc_mask & (1 << i))
			continue;

		if (init_device(&dev_tbl[i])){
			fprintf(stdout, "vrbridge:rescan() - found %s\n", dev_tbl[i].label);
			ent_alloc_mask |= 1 << i;
			count++;
		}
	}

	return count;
}

int main(int argc, char** argv)
{
	struct arg_arr* arg;
	struct arcan_shmif_cont con = arcan_shmif_open(SEGID_SENSOR, 0, &arg);
	if (!con.vidp){
		fprintf(stderr, "couldn't setup arcan connection\n");
		return EXIT_FAILURE;
	}

	struct arcan_shmif_vr* vr  = arcan_shmif_substruct(&con, SHMIF_META_VR).vr;
	if (!vr){
		fprintf(stderr, "couldn't retrieve VR substructure\n");
		return EXIT_FAILURE;
	}

	if (vr->version != VR_VERSION){
		fprintf(stderr, "header/shmif-vr version mismatch (in: %d, want: %d)\n",
			vr->version, VR_VERSION);
		return EXIT_FAILURE;
	}

/*
 * Now that we know that the other end is speaking our language, look for a
 * valid devices and enable. We don't actually do much display control other
 * than 'non-standard' stuff because server- side already does DPMS state
 * management and scanning / mapping to outputs.
 */

/*
 * allocate- a test-vr setup with nonsens parameters to be able to run
 * the entire chain from engine<->vrbridge<->avatar
 */
	if (arg_lookup(arg, "test", 0, NULL)){
		fprintf(stderr, "vrbridge:setup(test), not implemented\n");
		return EXIT_FAILURE;
	}
	else {
		while (device_rescan(&con, vr) == 0){
			fprintf(stderr, "vrbridge:setup() - "
				"no controllers found, sleep/rescan\n");
			sleep(5);
		}
	}

/*
 * Some VR devices found, since each device is ran in its own thread we simply
 * sleep and rescan on request from the server
 */
	arcan_event ev;
	bool running = true;
	while (running && arcan_shmif_wait(&con, &ev) > 0){
		if (ev.category == EVENT_TARGET)
		switch (ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			running = false;
		break;
		default:
		break;
		}
	}

	shutdown = true;
	while (atomic_load(&active) > 0){
		sleep(1);
	}
	return EXIT_SUCCESS;
}
