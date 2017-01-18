#ifndef HAVE_VRBRIDGE
#define HAVE_VRBRIDGE

enum ctrl_cmd {
	SHUTDOWN = 0,
	DISPLAY_OFF = 1,
	DISPLAY_ON  = 2
};

struct dev_ent;
typedef void(*vr_sampler_fptr)(struct dev_ent*);
typedef bool(*vr_init_fptr)(struct dev_ent*);
typedef void(*vr_control_fptr)(struct dev_ent*, enum ctrl_cmd, int id);

struct dev_ent {
/* refers to the control device, the backend is reponsible
 * for more (if applicable) */
	char label[16];
	uint64_t limb_map;

/* 0: blocking, implementation controlled timeout */
	uint16_t samplerate;

	vr_init_fptr init;
	vr_sampler_fptr sample;
	vr_control_fptr control;

	void* tag;
	pthread_t runner;
};

struct vr_limb* vrbridge_alloc_limb(struct dev_ent*, enum avatar_limbs);

#endif
