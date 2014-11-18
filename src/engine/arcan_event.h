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

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_EPRIV
#define _HAVE_ARCAN_EPRIV

struct arcan_evctx;

/* check timers, poll IO events and timing calculations
 * out : (NOT NULL) storage- container for number of ticks that has passed
 *                   since the last call to arcan_process
 * ret : range [0 > n < 1] how much time has passed towards the next tick */
typedef void (*arcan_tick_cb)(int count);
float arcan_event_process(struct arcan_evctx*, arcan_tick_cb);

struct arcan_evctx* arcan_event_defaultctx();

/*
 * Pushes as many events from srcqueue to dstqueue as possible
 * without over-saturating. allowed defines which kind of category
 * that will be transferred, other events will be ignored.
 * The saturation cap is defined in 0..1 range as % of full capacity
 * specifying a source ID (can be ARCAN_EID) will be used for rewrites
 * if the category has a source identifier
 */
void arcan_event_queuetransfer(
	struct arcan_evctx* dstqueue, struct arcan_evctx* srcqueue,
	enum ARCAN_EVENT_CATEGORY allowed, float saturation, arcan_vobj_id source);

/* ignore-all on enqueue */
void arcan_event_maskall(struct arcan_evctx*);

/* drop any mask, including maskall */
void arcan_event_clearmask(struct arcan_evctx*);

/* set a specific mask, somewhat limited */
void arcan_event_setmask(struct arcan_evctx*, unsigned mask);

int64_t arcan_frametime();

/*
 * special case, due to the event driven approach of LUA invocation,
 * we can get situations where we have a queue of events related to
 * a certain vid/aid, after the user has explicitly asked for it to be deleted.
 *
 * This means the user either has to check for this condition by tracking
 * the object (possibly dangling references etc.)
 * or that we sweep the queue and erase the tracks of the object in question.
 *
 * the default behaviour is to not erase unprocessed events that are made
 * irrelevant due to a deleted object.
 */
void arcan_event_erase_vobj(struct arcan_evctx* ctx,
	enum ARCAN_EVENT_CATEGORY category, arcan_vobj_id source);

/*
 * used as part of trying to salvage external connections while
 * resetting audio/video/scripting contexts. This sweeps the "to be processed"
 * event-queue and removes all events that doesn't strictly come from
 * external sources.
 */
void arcan_event_purge();

void arcan_event_init(struct arcan_evctx* dstcontext);
void arcan_event_deinit(struct arcan_evctx*);

#endif

