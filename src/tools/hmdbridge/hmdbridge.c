/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: HMD interfacing tool
 *
 * This tool implements the producer side of the shmif- extension for
 * HMD- related data. The intent is to use it as a prototyping tool for
 * refining the data model, and upon completion, plugin-in whatever
 * VR toolkit is actually usable.
 *
 * If possible, we provide not only sensor- data and metadata, but
 * also related devices like audio and video by requesting the relevant
 * subsegments.
 *
 * The basic approach is to populate a structure of limbs, where a limb
 * express the object- space coordinates, position and relative to a
 * single avatar.
 */
#include <arcan_shmif.h>
#include "arcan_math.h"
#include <arcan_shmif_sub.h>
#include <hidapi/hidapi.h>
#include <pthread.h>

struct runner_meta {
	struct arcan_shmif_cont* con;
};

static void* limb_runner(void* arg)
{
/*	struct runner_meta* meta = arg; */
	while (1){
/* 1. wait for device to update data, update checksum and timestamp */
/* 2. on device lost, flip our allocation bit and exit */
	}
	return NULL;
}

static void psvr_sampler(struct runner_meta* meta, hid_device* dev)
{

}

static void device_rescan(
	struct arcan_shmif_cont* cont, struct arcan_shmif_hmd* hmd)
{
/*
 * Limb allocation -> own thread. Can update without any other synchronization
 * so the only thing we need to do here is poll the shmif- event-queue and
 * rescan/ realloc if needed.
 */
}

typedef void(*vr_sampler_fptr)(struct runner_meta*, hid_device* dev);
typedef void(*vr_init_fptr)(struct runner_meta*, hid_device* dev);

/*
 * The data we're looking for when scanning for new HMD related devices
 * in the USB network. Note that not all set valid meta (hres = 0 is
 * enough to be invalid) because it doesn't match the context or the
 * values cannot be statically defined.
 */
struct usb_ent {
	uint16_t vid, pid;
	char label[16];
	int limbs;
	struct hmd_meta meta;
	vr_init_fptr init;
	vr_sampler_fptr sampler;
};

static const struct usb_ent usb_tbl[] =
{
	{
	.vid = 0x54c, .pid = 0x09af, .label = "morpheus",
	.sampler = psvr_sampler, .limbs = 1,
	.meta = {
	}
	}
};

int main(int argc, char** argv)
{
	struct arg_arr* arg;
	struct arcan_shmif_cont con = arcan_shmif_open(SEGID_SENSOR, 0, &arg);
	if (!con.vidp){
		fprintf(stderr, "couldn't setup arcan connection\n");
		return EXIT_FAILURE;
	}

	struct arcan_shmif_hmd* hmd = arcan_shmif_substruct(&con, SHMIF_META_HMD).hmd;
	if (!hmd){
		fprintf(stderr, "couldn't retrieve HMD substructure\n");
		return EXIT_FAILURE;
	}

	if (hmd->version != HMD_VERSION){
		fprintf(stderr, "header/shmif-hmd version mismatch (in: %d, want: %d)\n",
			hmd->version, HMD_VERSION);
		return EXIT_FAILURE;
	}

/*
 * Now that we know that the other end is speaking our language, look for a
 * valid devices and enable. We don't actually do much display control other
 * than 'non-standard' stuff because server- side already does DPMS state
 * management and scanning / mapping to outputs.
 */

/*
 * allocate- a test-hmd setup with nonsens parameters to be able to run
 * the entire chain from engine<->hmdbridge<->avatar
 */
	if (arg_lookup(arg, "test", 0, NULL)){

	}
	else {
		device_rescan(&con, hmd);
	}

	arcan_event ev;
	while (1){
		while (arcan_shmif_poll(&con, &ev) > 0){
		}
	}
}
