/* Input Event scheduling,
 *
 * A simple growing buffer for arcan input events that
 * has a pts set to a local monotonic clock with epoc
 * relative to the first reset. These are typically
 * aligned to the number of retro_run() invocations
 *
 * These allow for collisions, meaning that multiple events
 * can be applied in the same logical pulse, even though
 * they may technically override eachother. Order is
 * first-come-first-serve.
 *
 * If this is setup with rewind / replay support,
 * these will accumulate until out of memory or until
 * explicitly flushed.
 */

/* drop all currently stored input events, resets the
 * internal pts counter. If log is set, new configuration
 * will either hold all new inputs or drop them as they're dequeued */
void ievsched_flush(bool log);

/* Increment or decrement the current stepcounter.
 * the end result will be clamped to 0 <= n < ULINT_MAX */
void ievsched_step(int step);

/* add ioevent to ptsqueue */
void ievsched_enqueue(arcan_ioevent* ioev);

/* check if anything is entered for the current timeslot,
 * dst will be populated with a reference to the next useful IOevent
 * or null+false if there's nothing scheduled */
bool ievsched_poll(arcan_ioevent** dst);

/* return the current clock time, useful to tag an event before
 * enqueue if it doesn't have a evslot set. */
unsigned long ievsched_nextpts();

