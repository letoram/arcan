#ifndef HAVE_NREAL
#define HAVE_NREAL

void nreal_sample(struct dev_ent*, struct vr_limb*, unsigned);
bool nreal_init(struct dev_ent*, struct arcan_shmif_vr*, struct arg_arr*);
void nreal_control(struct dev_ent*, enum ctrl_cmd);

#endif
