#ifndef HAVE_VRBRIDGE
#define HAVE_VRBRIDGE

enum ctrl_cmd {
	SHUTDOWN = 0,
	DISPLAY_OFF = 1,
	DISPLAY_ON  = 2
};

struct dev_ent;

typedef void(*vr_sampler_fptr)(struct dev_ent*);
typedef bool(*vr_init_fptr)(struct dev_ent*,
	struct arcan_shmif_vr* vr, struct arg_arr*);
typedef void(*vr_control_fptr)(struct dev_ent*, enum ctrl_cmd, int id);

struct driver_state;
struct dev_ent {
	char label[16];
	bool alive;

	vr_init_fptr init;
	vr_sampler_fptr sample;
	vr_control_fptr control;

	pthread_t runner;

	struct driver_state* state;
};

struct vr_limb* vrbridge_alloc_limb(struct dev_ent*, enum avatar_limbs);

#endif
