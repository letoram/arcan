#ifndef HAVE_VRBRIDGE
#define HAVE_VRBRIDGE

enum ctrl_cmd {
	SHUTDOWN = 0,
	DISPLAY_OFF = 1,
	DISPLAY_ON  = 2,

/* set reference orientation / position to the current state */
	RESET_REFERENCE = 3,
};

void debug_print_fn(int lvl, const char* fmt, ...);
#define debug_print(lvl, fmt, ...) \
		do { debug_print_fn(lvl, "%s:%d:%s(): " fmt "\n",\
			"", __LINE__, __func__,##__VA_ARGS__); } while (0)

struct dev_ent;

/*
 * used by the different drivers during the init stage, request allocation and
 * binding of a limb to the specific device. Returns a pointer to the limb
 * structure that the driver is allowed to populate, or NULL if the limb has
 * already been reserved by another driver.
 */
struct vr_limb* vrbridge_alloc_limb(
	struct dev_ent*, enum avatar_limbs, unsigned id);

/*
 * import/pluck from the platform- source tree
 */
long long int arcan_timemillis();
void arcan_timesleep(unsigned long);

/*
 * The different driver callbacks:
 *  sample -> Block until the driver has retreived a sample for the
 *            referenced limb, each limb can run in its own thread.
 */
typedef void(*vr_sampler_fptr)(struct dev_ent*, struct vr_limb*, unsigned id);

/*
 * Return true if the device was successfully initalized and should
 * be treated as active. This is the opportunity for a driver to call
 * vrbridge_alloc_limb
 */
typedef bool(*vr_init_fptr)(struct dev_ent*,
	struct arcan_shmif_vr* vr, struct arg_arr*);

/*
 * Control commands, like suspend/resume or enable/disable display
 * (if the driver support such features, meaning that other paths like
 * DKMS/dri doesn't work for this device)
 */
typedef void(*vr_control_fptr)(struct dev_ent*, enum ctrl_cmd);

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

#endif
