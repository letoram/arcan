#ifndef HAVE_REMOTING
#define HAVE_REMOTING

/* remoting.c just extracts protocol argument and forwards to one
 * of these functions, so to add support for more remoting protocols,
 * extend the check there, add to this list and update the CMakeLists */

int run_vnc(struct arcan_shmif_cont* cont, struct arg_arr* args);
int run_a12(struct arcan_shmif_cont* cont, struct arg_arr* args);

#endif
