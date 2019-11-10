#define _POSIX_C_SOURCE 200812L

#include <arcan_shmif.h>
#include <stdlib.h>
#include "../../shmif/arcan_shmif_debugif.h"

volatile struct arcan_shmif_cont cont;
static volatile bool hold_constructor = true;
static char* label;

/*
 * running from the constructor state there are more options we can add to the
 * menu here, one would be to interactively do PLT hooking or setup syscall
 * filter, libbacktrace + seccomp handler, trigger,
 * for the PLT hooking, have a list of known crypto- lib symbols to provide
 * a pipe- filter into would be nice and neat
 */
static void process_handler(void* C, void* tag)
{
	if (!hold_constructor)
		return;

	label[0] = '\0';
	hold_constructor = false;
}

void __attribute__((constructor)) adbinject_setup()
{
	struct arg_arr* args;
	unsetenv("LD_PRELOAD");

/* can use the args[] here to retrieve a list of PLT hooks to install */

/* handover / detach to debugif */
	struct arcan_shmif_cont ct = arcan_shmif_open(SEGID_TUI, 0, &args);
	label = strdup("Continue");

/* custom menu entry for process control so we can release */
	arcan_shmif_debugint_spawn(&ct, NULL,
		&(struct debugint_ext_resolver){
		.handler = process_handler,
		.label = label,
		.tag = NULL
	});

	while (arcan_shmif_debugint_alive() && hold_constructor){
		sleep(1);
	}
	cont = ct;
}

void __attribute__((destructor)) adbinject_teardown()
{
/* something less crude than this would be nice */
	while (arcan_shmif_debugint_alive()){
		sleep(1);
	}
	free(label);
}
