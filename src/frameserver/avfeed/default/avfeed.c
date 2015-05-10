/*
 * No copyright claimed, Public Domain
 */
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <pthread.h>

#include <arcan_shmif.h>
#include "frameserver.h"

static void update_frame(struct arcan_shmif_cont* shms, shmif_pixel val)
{
	shmif_pixel* cptr = shms->vidp;

	int np = shms->addr->w * shms->addr->h;
	for (int i = 0; i < np; i++)
		*cptr++ = val;

	arcan_shmif_signal(shms, SHMIF_SIGVID);
}

static void dump_help()
{
	fprintf(stdout, "the avfeed- frameserver is primarily intended"
		" for testing and prototyping purposes and is not particularly"
		" useful on its own.\n");
}

/*
 * Quick skeleton to map up a audio/video/input
 * source to an arcan frameserver along with some helpers.
 */
int afsrv_avfeed(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	if (!con){
		dump_help();
		return EXIT_FAILURE;
	}
	struct arcan_shmif_cont shms = *con;

	if (!arcan_shmif_resize(&shms, 320, 200)){
		LOG("arcan_frameserver(decode) shmpage setup, resize failed\n");
		return EXIT_FAILURE;
	}

	update_frame(&shms, RGBA(0xff, 0xff, 0xff, 0xff));
	arcan_event ev;

	while(1)
		while(arcan_shmif_wait(&shms, &ev)){
			if (ev.category == EVENT_TARGET){
			if (ev.tgt.kind == TARGET_COMMAND_EXIT){
				fprintf(stdout, "parent requested termination, leaving.\n");
				return EXIT_SUCCESS;
			}
			else {
				static int red;
				update_frame(&shms, RGBA(red++, 0x00, 0x00, 0xff));
			}
			}
		}

	return EXIT_FAILURE;
}
