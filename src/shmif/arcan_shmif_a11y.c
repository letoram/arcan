#include "arcan_shmif.h"
#include "arcan_shmif_interop.h"
#include "shmif_defimpl.h"
#include "shmif_privint.h"
#include "arcan_shmif_server.h"
#include <dlfcn.h>

#define ARCAN_TUI_DYNAMIC
#include "arcan_tui.h"

struct a11y_meta {
	struct tui_context* tui;
	struct shmifsrv_client* oracle;
	size_t w, h;
	char* last_message;
	bool oracle_fail;
};

static void synch_oracle(struct a11y_meta* M, struct arcan_shmif_cont* P)
{
	if (M->oracle_fail)
		return;

	float density = P->priv->dh.tgt.ioevs[4].fv;
	arcan_event ev;
	int pv, rv;

/* if w/h differ, respawn the oracle.
 * The better option would be to send a subsegment and drop that while
 * retaining the connection, but that requires _encode to handle it which
 * it currently doesn't.
 */
/* MISSING: should attach LANG= to provide GEOHINT to direct language used */
	if (M->oracle && (M->w != P->w || M->h != P->h)){
		shmifsrv_free(M->oracle, 0);
		M->oracle = NULL;
	}

	if (!M->oracle){
		char envarg[1024] = "ARCAN_ARG=proto=ocr";
		char* envv[] = {envarg, NULL};

		struct shmifsrv_envp env = {
			.path = "/usr/bin/afsrv_encode",
			.envv = envv,
			.detach = 2 | 4 | 8,
			.init_w = P->w,
			.init_h = P->h,
			.type = SEGID_ENCODER
		};

		int clsock = -1;
		M->oracle = shmifsrv_spawn_client(env, &clsock, NULL, 0);
		if (!M->oracle){
			M->oracle_fail = true;
			return;
		}

/* ensure we send ACTIVATE or _encode will consume the STEPFRAME
 * event and the client will be dangling waiting for it */
		while ((pv = shmifsrv_poll(M->oracle) >= 0)){
			while (shmifsrv_dequeue_events(M->oracle, &ev, 1) == 1){
			}
			if (pv == 1)
				break;
		}

		M->w = P->w;
		M->h = P->h;
	}

	struct shmifsrv_vbuffer vb = {
		.w = P->w,
		.h = P->h,
		.pitch = P->pitch,
		.stride = P->stride,
		.buffer = P->vidp
	};

/* this goes away when we can have a futex to kqueue on */
	while ( (rv = shmifsrv_put_video(M->oracle, &vb) ) == 0 )
	{
		arcan_timesleep(1);
	}

/* this is OUTPUT so VFRAME ready doesn't really help,
 * we want STEPFRAME to know if the MESSAGE events are complete. */
	while ((pv = shmifsrv_poll(M->oracle) >= 0)){
		while (shmifsrv_dequeue_events(M->oracle, &ev, 1) == 1){
			if (ev.category == EVENT_EXTERNAL
				&& ev.ext.kind == EVENT_EXTERNAL_MESSAGE){
				bool bad;
				char* out;
				if (shmifsrv_merge_multipart_message(M->oracle, &ev, &out, &bad)){
					if (bad)
						continue;

					arcan_tui_move_to(M->tui, 0, 0);
					arcan_tui_printf(M->tui, NULL, "%s", out);
				}
			}
		}
		if (pv == 1)
			break;
	}

	if (pv == -1){
		shmifsrv_free(M->oracle, 0);
		M->oracle = NULL;
		M->oracle_fail = true;
	}
}

static void on_state(struct arcan_shmif_cont* p, int state)
{
	struct a11y_meta* M = p->priv->support_window_hook_data;

	if (state == SUPPORT_EVENT_VSIGNAL){
		if (p->hints & SHMIF_RHINT_TPACK)
			return;
/* this is where we'd forward the video buffer to an external oracle
 * and synch the output, do this as a mmap -> push_fd so that we don't
 * need to respawn as that can be really expensive.
 *
 * we can also ignore this entirely for TUI segments as those are
 * already covered through server side tunpacked buffers
 */
		synch_oracle(M, p);
	}
	else if (state == SUPPORT_EVENT_POLL){
		arcan_tui_process(&M->tui, 1, NULL, 0, 0);
	}
	else if (state == SUPPORT_EVENT_EXIT){
/* could forward last_words as well, but it's likely the outer-wm would
 * have this as part of a notification / window handling system that is
 * accessible already so we don't need to do that here */
		if (M->oracle){
			shmifsrv_free(M->oracle, SHMIFSRV_FREE_NO_DMS);
		}

		p->priv->support_window_hook = NULL;
		arcan_tui_destroy(M->tui, NULL);
		free(M);
	}
}

static void redraw(struct tui_context* T, struct a11y_meta* a11y)
{
	arcan_tui_move_to(T, 0, 0);

	if (a11y->oracle_fail){
		arcan_tui_printf(T, NULL, "image interpreter failed");
	}
	else
		arcan_tui_printf(T, NULL, "no accesibility information available");

	arcan_tui_refresh(T);
}

static void resized(struct tui_context* T,
		size_t neww, size_t newh, size_t cols, size_t rows, void* tag)
{
	struct arcan_shmif_cont* p = tag;
	struct a11y_meta* a11y = p->priv->support_window_hook_data;

	redraw(T, a11y);
}

static void execstate(struct tui_context* T, int state, void* tag)
{
	struct arcan_shmif_cont* p = tag;
	struct a11y_meta* a11y = p->priv->support_window_hook_data;

	if (state == 2){
		if (a11y->oracle){
			shmifsrv_free(a11y->oracle, 0);
			a11y->oracle = NULL;
			a11y->oracle_fail = true;
		}
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
	*a11y = (struct a11y_meta){0};
	p->priv->support_window_hook = on_state;
	p->priv->support_window_hook_data = a11y;

	a11y->tui = arcan_tui_setup(c,
			NULL, &(struct tui_cbcfg){
			.resized = resized,
			.exec_state = execstate,
			.tag = p
		}, sizeof(struct tui_cbcfg));

/* set some basic 'whatever' */
	arcan_tui_wndhint(a11y->tui, NULL,
		(struct tui_constraints){
			.min_rows = 2, .max_rows = 20,
			.min_cols = 64, .max_cols = 240}
	);
	return true;
}
