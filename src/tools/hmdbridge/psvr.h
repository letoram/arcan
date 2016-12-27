#ifndef HAVE_PSVR
#define HAVE_PSVR

void psvr_sample(struct dev_ent*);
bool psvr_init(struct dev_ent*);
void psvr_control(struct dev_ent*, enum ctrl_cmd, int id);

#endif
