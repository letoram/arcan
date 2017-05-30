#ifndef HAVE_PSVR
#define HAVE_PSVR

void test_sample(struct dev_ent* dev, struct vr_limb* limb, unsigned id);
bool test_init(struct dev_ent*, struct arcan_shmif_vr*, struct arg_arr*);
void test_control(struct dev_ent*, enum ctrl_cmd);

#endif
