/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
/
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,MA 02110-1301,USA.
 *
 */
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_event.h>

#include "ievsched.h"

/* just insertion sorted doubly linked list */
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

