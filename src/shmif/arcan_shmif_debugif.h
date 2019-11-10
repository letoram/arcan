#ifndef HAVE_SHMIF_DEBUGIF
/*
 * Try to spawn / derive a debugging interface pivoting bootstrapped that is
 * bootstrapped / built using the specified context. Return true if the callee
 * adopts the context.
 */
struct debugint_ext_resolver {
	void (*handler)(void* tui_context, void* tag);
	char* label;
	void* tag;
};

bool arcan_shmif_debugint_spawn(
	struct arcan_shmif_cont* c, void* tuitag, struct debugint_ext_resolver* res);
int arcan_shmif_debugint_alive();

#endif
