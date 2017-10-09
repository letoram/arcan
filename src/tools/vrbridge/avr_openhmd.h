#ifndef HAVE_OPENHMD
#define HAVE_OPENHMD

void openhmd_sample(struct dev_ent*, struct vr_limb*, unsigned);
bool openhmd_init(struct dev_ent*, struct arcan_shmif_vr*, struct arg_arr*);
void openhmd_control(struct dev_ent*, enum ctrl_cmd);

#endif
