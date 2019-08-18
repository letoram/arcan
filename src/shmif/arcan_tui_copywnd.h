#ifndef HAVE_TUI_COPYWND
#define HAVE_TUI_COPYWND

/*
 * Using [src] as a template (directly or via the internal pending_
 * copy_window structure) and build a copy-window using [con].
 *
 * Assumes ownership and control over the segment that [con] is
 * referencing to.
 */
void arcan_tui_copywnd(
	struct tui_context* src, struct arcan_shmif_cont con);

#endif
