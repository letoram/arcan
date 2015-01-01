/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>
#include <pthread.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/param.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <signal.h>
#include <errno.h>
#include <setjmp.h>

#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_shmif.h>
#include <arcan_event.h>
#include <arcan_video.h>
#include <arcan_audio.h>
#include <arcan_frameserver.h>

static struct arcan_frameserver* tag;
static sigjmp_buf recover;

static void bus_handler(int signo)
{
	if (!tag)
		abort();

	siglongjmp(recover, 1);
}

int arcan_frameserver_enter(struct arcan_frameserver* m)
{
	static bool initialized;

	if (!initialized){
		initialized = true;
		if (signal(SIGBUS, bus_handler) == SIG_ERR)
			arcan_warning("(posix/fsrv_guard) can't install sigbus handler.\n");
		}

	if (sigsetjmp(recover, 1)){
		arcan_warning("(posix/fsrv_guard) DoS attempt from client.\n");
		arcan_frameserver_dropshared(tag);
		tag = NULL;
		return 0;
	}

	tag = m;
	return 1;
}

void arcan_frameserver_leave()
{
	tag = NULL;
}
