/*
 * Input-Event scheduler (stub still, nothing to see here)
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Currently just a nonsense- stub, nothing real to see here yet.
 */

#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

#include <arcan_shmif.h>
#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_event.h>

#include "ievsched.h"

struct ptsent {
	arcan_ioevent data;
	unsigned long pts;

	struct ptsent* next;
	struct ptsent* prev;
};

static struct {
	bool initalized;
	bool monotonic;
	unsigned long clock;

	struct ptsent* epoch;
	struct ptsent* current;
	struct ptsent* end;

} ievctx;

void ievsched_flush(bool log)
{
	struct ptsent* current = ievctx.epoch;

	while (current){
		struct ptsent* cur = current;
		current = current->next;
		free(cur);
	}

	memset(&ievctx, '\0', sizeof(ievctx));
}

void ievsched_step(int step)
{
	ievctx.clock = ievctx.clock + step;

	if (step < 0 && (-1 * step) > ievctx.clock)
		ievctx.clock = 0;
	else
		ievctx.clock += step;

/* slide current to point to the start of the current timestamp */
}

void ievsched_enqueue(arcan_ioevent* in)
{
	if (in->pts <= 0)
		return;
}

unsigned long ievsched_nextpts()
{
	return ievctx.clock;
}

bool ievsched_poll(arcan_ioevent** dst)
{
	*dst = NULL;
	return false;

	/* if log, then find point and enqueue, else step current clock
	 * until current == NULL or event clock != current time */
}

