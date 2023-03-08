/*
 * Copyright 2016-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: VR interfacing tool
 */
#include <stdbool.h>
#include "arcan_math.h"
#include <arcan_shmif.h>
#include <hidapi.h>
#include <pthread.h>
#include <stdatomic.h>
#include <inttypes.h>
#include <stdarg.h>

#include "vrbridge.h"
#include "avr_test.h"
#include "avr_nreal.h"
#include "avr_openhmd.h"

static volatile bool in_init = true;
struct limb_runner {
	struct arcan_shmif_vr* vr;
	struct vr_limb* limb;
	struct dev_ent* dev;
	uint8_t limb_ind;
	unsigned limb_id;
};
unsigned long long epoch;

/*
 * normally, this is supposed to be started by arcan via the ext_vr config
 * mechanism - but for testing and debugging purposes it might make sense
 * to run from a console (stdin == tty). If that happens, 'fake' a working
 * vr context.
 */
static struct arcan_shmif_vr* vr_context;
static bool debug_offline;
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static int debug_level;

void debug_print_fn(int lvl, const char* fmt, ...)
{
	if (lvl >= debug_level)
		return;

	pthread_mutex_lock(&mutex);
	va_list ap;
	va_start(ap, fmt);
		vfprintf(stderr, fmt, ap);
	va_end(ap);
	pthread_mutex_unlock(&mutex);
}

static void* limb_runner(void* arg)
{
	struct limb_runner* meta = arg;

	while (in_init){}

	if (debug_offline){
		while (meta->dev->alive){
			meta->dev->sample(meta->dev, meta->limb, meta->limb_id);
		}
	}

	while (meta->dev->alive){
/* expected to block until limb has been updated, the timestamp is when
 * sampling was requested, not when the sample was retrieved */
		unsigned long long timestamp = arcan_timemillis() - epoch;
		meta->dev->sample(meta->dev, meta->limb, meta->limb_id);
		uint16_t checksum = subp_checksum(
			(uint8_t*)meta->limb, sizeof(struct vr_limb)-sizeof(uint16_t));
		atomic_store(&meta->limb->timestamp, timestamp);
		atomic_store(&meta->limb->data.checksum, checksum);
		atomic_fetch_or(&meta->vr->ready, 1 << meta->limb_ind);
	}

	return NULL;
}

static uint64_t ent_alloc_mask;
bool in_test_mode = false;
static struct dev_ent dev_tbl[] =
{
	{
		.init = test_init,
		.sample = test_sample,
		.control = test_control
	},
	{
		.init = nreal_init,
		.sample = nreal_sample,
		.control = nreal_control
	},
	{
		.init = openhmd_init,
		.sample = openhmd_sample,
		.control = openhmd_control
	}
};

static bool init_device(struct dev_ent* ent,
	struct arcan_shmif_vr* vr, struct arg_arr* arg)
{
	if (ent->init(ent, vr, arg)){
		ent->alive = true;
		return true;
	}
	return false;
}

static size_t device_rescan(struct arcan_shmif_vr* vr, struct arg_arr* arg)
{
/*
 * Limb allocation -> own thread. Can update without any other synchronization
 * rescan/ realloc if needed. Collisions or priority when it comes to limbs
 * should be solved with [arg] specifying the mapping and priority, but that
 * matters when we've gotten further.
 */
	size_t count = 0;

	for (size_t i = 0; i < sizeof(dev_tbl)/sizeof(dev_tbl[0]); i++){
		if (ent_alloc_mask & (1 << i))
			continue;

		if (init_device(&dev_tbl[i], vr, arg)){
			debug_print(0, "vrbridge:rescan() - found %s", dev_tbl[i].label);
			ent_alloc_mask |= 1 << i;
			count++;
		}
	}

	return count;
}

struct vr_limb* vrbridge_alloc_limb(
	struct dev_ent* dev, enum avatar_limbs limb, unsigned id)
{
	uint64_t lv = (uint64_t)1 << (uint64_t)limb;
	uint64_t map = atomic_load(&vr_context->limb_mask);
	if (map & (1 << lv)){
		debug_print(0,
			"device tried to allocate existing limb %d (id: %d)", limb, id);
		return NULL;
	}

	struct limb_runner* thctx = malloc(sizeof(struct limb_runner));
	if (!thctx)
		return NULL;

	atomic_fetch_or(&vr_context->limb_mask, lv);
	map = atomic_load(&vr_context->limb_mask);
	debug_print(0,
		"allocated limb slot %d, id: %d (mask: %"PRIu64")", limb, id, map);
	*thctx = (struct limb_runner){
		.vr = vr_context,
		.limb = &vr_context->limbs[limb],
		.dev = dev,
		.limb_ind = limb,
		.limb_id = id
	};

	pthread_attr_t nanny_attr;
	pthread_attr_init(&nanny_attr);
	pthread_attr_setdetachstate(&nanny_attr, PTHREAD_CREATE_DETACHED);

	pthread_t nanny;
	if (0 != pthread_create(&nanny, &nanny_attr, limb_runner, thctx)){
		free(thctx);
		atomic_fetch_and(&vr_context->limb_mask, ~lv);
		return NULL;
	}

	pthread_attr_destroy(&nanny_attr);

	return &vr_context->limbs[limb];
}

static void control_cmd(int cmd)
{
	for (size_t i = 0; i < sizeof(dev_tbl)/sizeof(dev_tbl[0]); i++){
		if (!(ent_alloc_mask & (1 << i)))
			continue;

		dev_tbl[i].control(&dev_tbl[i], RESET_REFERENCE);
	}
}

static int console_main()
{
	struct arg_arr* aarg =
		arg_unpack(getenv("ARCAN_ARG"));
	debug_offline = true;
	printf("console detected, switching to arcan-less mode\n");
	vr_context = malloc(sizeof(struct arcan_shmif_vr));
	*vr_context = (struct arcan_shmif_vr){};
	debug_level = 10;

	if (arg_lookup(aarg, "test", 0, NULL))
		in_test_mode = true;

	while(device_rescan(vr_context, aarg) == 0){
		printf("vrbridge:setup() - ""no controllers found, sleep/rescan");
		sleep(5);
	}

	printf("vr bridge running in offline mode\n");
	in_init = false;
	epoch = arcan_timemillis();
	vr_context->ready = true;
	while (1){
		sleep(1);
	}

	return EXIT_SUCCESS;
}

int main(int argc, char** argv)
{
	struct arg_arr* arg;

	if (isatty(STDIN_FILENO)){
		return console_main();
	}

	struct arcan_shmif_cont con = arcan_shmif_open(
		SEGID_SENSOR, SHMIF_ACQUIRE_FATALFAIL | SHMIF_NOAUTO_RECONNECT, &arg);
	if (!con.vidp){
		debug_print(0, "couldn't setup arcan connection");
		return EXIT_FAILURE;
	}
	arcan_shmif_setprimary(SHMIF_INPUT, &con);

/*
 * Need these shenanigans to get time enough to attach. since this is typically
 * spawned from the arcan process which makes it annoying and often gdb-broken
 * to follow (set follow-fork-mode, set follow-exec-mode etc.)
 */
	if (getenv("ARCAN_VR_DEBUGATTACH") || arg_lookup(arg, "debug", 0, NULL)){
		debug_print(0, "entering debug-attach loop (pid: %d)", getpid());
		volatile bool flag = 0;
		while (!flag){};
	}

/* still need to explicitly say that we want this protocol */
	arcan_shmif_resize_ext(&con, con.w, con.h, (struct shmif_resize_ext){
		.meta = SHMIF_META_VR
	});

	vr_context = arcan_shmif_substruct(&con, SHMIF_META_VR).vr;
	if (!vr_context){
		debug_print(0, "couldn't retrieve VR substructure");
		return EXIT_FAILURE;
	}

	if (vr_context->version != VR_VERSION){
		debug_print(0, "header/shmif-vr version mismatch "
			"(in: %d, want: %d)", vr_context->version, VR_VERSION);
		return EXIT_FAILURE;
	}

/*
 * Now that we know that the other end is speaking our language, look for a
 * valid devices and enable. We don't actually do much display control other
 * than 'non-standard' stuff because server- side already does DPMS state
 * management and scanning / mapping to outputs.
 */
	const char* argm;
	if (arg_lookup(arg, "debug", 0, &argm)){
		debug_level = strtoul(argm, NULL, 10);
	}

/*
 * will get test.c driver to return true, and since it's at the top of the
 * table, it will grab most limbs, fill out metadata etc.
 */
	if (arg_lookup(arg, "test", 0, NULL)){
		debug_print(0, "test mode requested");
		in_test_mode = true;
	}

/*
 * Allocate- a test-vr setup with nonsens parameters to be able to run
 * the entire chain from engine<->vrbridge<->avatar.
 */
	while(device_rescan(vr_context, arg) == 0){
		debug_print(0, "vrbridge:setup() - "
				"no controllers found, sleep/rescan");
		sleep(5);
		if (!con.addr->dms){
			debug_print(0, "vrbridge:setup() - server died while waiting for device");
			arcan_shmif_drop(&con);
			return EXIT_FAILURE;
		}
	}

/*
 * Some VR devices found, since each device is ran in its own thread we simply
 * sleep and rescan on request from the server
 */
	arcan_event ev;
	in_init = false;
	epoch = arcan_timemillis();
	vr_context->ready = true;
	debug_print(0, "vrbridge:setup completed, entering loop\n");

	while (arcan_shmif_wait(&con, &ev) > 0){
		if (ev.category == EVENT_TARGET)
		switch (ev.tgt.kind){
/* soft-reset defines new reference orientations */
		case TARGET_COMMAND_RESET:
			control_cmd(RESET_REFERENCE);
		break;
		case TARGET_COMMAND_EXIT:
			control_cmd(SHUTDOWN);
			arcan_shmif_drop(&con);
/* FIXME: sweep driver list and send shutdown command */
		break;
		default:
		break;
		}
	}

	return EXIT_SUCCESS;
}
