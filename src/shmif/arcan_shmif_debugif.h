#ifndef HAVE_SHMIF_DEBUGIF
/*
 * Try to spawn / derive a debugging interface pivoting bootstrapped that is
 * bootstrapped / built using the specified context. Return true if the callee
 * adopts the context.
 */
bool arcan_shmif_debugint_spawn(struct arcan_shmif_cont*, void* tuitag);
int arcan_shmif_debugint_alive();

#endif
