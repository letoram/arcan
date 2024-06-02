#include "arcan_shmif.h"
#include "arcan_shmif_interop.h"
#include "shmif_defimpl.h"
#include "shmif_privint.h"
#include <dlfcn.h>

#define ARCAN_TUI_DYNAMIC
#include "arcan_tui.h"

struct a11y_meta {
	struct tui_context* tui;
};

static void on_state(struct arcan_shmif_cont* p, int state)
{
	struct a11y_meta* M = p->priv->support_window_hook_data;
	if (state == SUPPORT_EVENT_VSIGNAL){
/* this is where we'd forward the video buffer to an external oracle
 * and synch the output */
	}
	else if (state == SUPPORT_EVENT_POLL){
		arcan_tui_process(&M->tui, 1, NULL, 0, 0);
	}
	else if (state == SUPPORT_EVENT_EXIT){
/* could forward last_words as well, but it's likely the outer-wm would
 * have this as part of a notification / window handling system that is
 * accessible already so we don't need to do that here */
		p->priv->support_window_hook = NULL;
		arcan_tui_destroy(M->tui, NULL);
		free(M);
	}
}

bool arcan_shmif_a11yint_spawn(
	struct arcan_shmif_cont* c, struct arcan_shmif_cont* p)
{
/*
 * only one active per parent
 */
	if (p->priv->support_window_hook)
		return false;

/* regular thing to handle dynamic injection / loading */
	if (!arcan_tui_setup){
		void* openh = dlopen(
"libarcan_tui."
#ifndef __APPLE__
	"so"
#else
	"dylib"
#endif
		, RTLD_LAZY);
		if (!arcan_tui_dynload(dlsym, openh))
			return false;
	}

/*
 * there are a few possible options here.
 *
 * Most important is to mark that the client doesn't have an accessibility
 * implemetation. This can be done as a simple message on the subject.
 *
 * The other is to hand over to a receiving oracle. With whisper support
 * in afsrv_encode, we can latch the [c] segment and provide frame-hooks
 * that routes the image data onwards to afsrv_encode, convert and attach
 * the output into either tesseract or whisper or both.
 *
 * Yet another is to look for the symbols used by at-spi or accesskit and
 * hook ourselves there, retrieve the tree and navigate it through this
 * segment.
 */

	struct a11y_meta* a11y = malloc(sizeof(struct a11y_meta));
	*a11y = (struct a11y_meta){
		.tui = arcan_tui_setup(c,
			NULL, &(struct tui_cbcfg){.tag = p}, sizeof(struct tui_cbcfg))
	};

/* set some basic 'whatever' */
	arcan_tui_wndhint(a11y->tui, NULL,
		(struct tui_constraints){
			.min_rows = 2, .max_rows = 20,
			.min_cols = 64, .max_cols = 240}
	);
	arcan_tui_printf(a11y->tui, NULL, "no accesibility information available");
	arcan_tui_refresh(a11y->tui);

	p->priv->support_window_hook = on_state;
	p->priv->support_window_hook_data = a11y;

	return true;
}
