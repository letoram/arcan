#ifndef HAVE_TEST
#define HAVE_TEST

void psvr_sample(struct dev_ent*);
bool psvr_init(struct dev_ent*, struct arcan_shmif_vr*, struct arg_arr*);
void psvr_control(struct dev_ent*, enum ctrl_cmd, int id);

#endif
