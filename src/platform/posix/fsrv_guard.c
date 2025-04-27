/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

// #include "arcan_shmif.h"
// #include PLATFORM_HEADER

// #include "platform/shmif_platform.h"
// #include "arcan_shmif_server.h"

#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>
#include <stdatomic.h>
#include <math.h>
#include <sys/wait.h>
#include <pthread.h>
#include <signal.h>
#include <setjmp.h>

#include "../os_platform.h"
#include "../fsrv_platform.h"

static struct arcan_frameserver* tag;
static sigjmp_buf recover;
static size_t counter;

static void bus_handler(int signo)
{
	if (!tag)
		abort();

	siglongjmp(recover, 0);
}

void platform_fsrv_enter(struct arcan_frameserver* m, jmp_buf out)
{
	static bool initialized;
	counter++;

	if (!initialized){
		initialized = true;
		if (signal(SIGBUS, bus_handler) == SIG_ERR)
			arcan_warning("(posix/fsrv_guard) can't install sigbus handler.\n");
		}

	if (sigsetjmp(recover, 0)){
		arcan_warning("(posix/fsrv_guard) DoS attempt from client.\n");
		platform_fsrv_dropshared(tag);
		tag = NULL;
		longjmp(out, -1);
	}

	tag = m;
}

size_t platform_fsrv_clock()
{
	return counter;
}

void platform_fsrv_leave()
{
	tag = NULL;
}
