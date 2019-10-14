#define _POSIX_C_SOURCE 200812L

#include <arcan_shmif.h>
#include <stdlib.h>

volatile struct arcan_shmif_cont cont;
extern bool arcan_shmif_debugint_spawn(struct arcan_shmif_cont* c, void*);
extern int arcan_shmif_debugint_alive();

void __attribute__((constructor)) adbinject_setup()
{
	struct arg_arr* args;
	unsetenv("LD_PRELOAD");

/* can use the args[] here to retrieve a list of PLT hooks to install */

/* handover / detach to debugif */
	struct arcan_shmif_cont ct = arcan_shmif_open(SEGID_TUI, 0, &args);
	arcan_shmif_debugint_spawn(&ct, NULL);

	cont = ct;
}

void __attribute__((destructor)) adbinject_teardown()
{
/* something less crude than this would be nice */
	while (arcan_shmif_debugint_alive()){
		sleep(1);
	}
}
