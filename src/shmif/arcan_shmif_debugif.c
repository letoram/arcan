#include "arcan_shmif.h"
#include "arcan_shmif_debugif.h"
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>

#define ARCAN_TUI_DYNAMIC
#include "arcan_tui.h"

struct debug_ctx {
	struct arcan_shmif_cont cont;
	struct tui_context* tui;
	int infd;
	int outfd;
};

struct menu_ent {
	const char* label;
	void (*fptr)(struct debug_ctx*);
};

/*
 *
 */

static bool fd_redirect(struct debug_ctx*, int fd);

static void flush_io(struct debug_ctx* ctx)
{
	char buf[4096];
	char* cur = buf;

	if (-1 == ctx->infd)
		return;

	ssize_t nr = read(ctx->infd, buf, 4096);
	while (nr > 0){
		ssize_t nw = write(ctx->outfd, cur, nr);
		if (-1 == nw)
			break;
		nr -= nw;
		cur += nw;
	}
}

static void* debug_thread(void* thr)
{
	struct debug_ctx* dctx = thr;
	struct tui_cbcfg cbcfg = {
		.tag = thr
	};

/* we already have a 'display' in the sense of the shmif connection, since
 * tui is designed to not explicitly rely on shmif */
	arcan_tui_conn* c = (arcan_tui_conn*) &dctx->cont;
	struct tui_settings cfg = arcan_tui_defaults(c, NULL);
	dctx->tui = arcan_tui_setup(c, &cfg, &cbcfg, sizeof(cbcfg));

	if (!dctx->tui){
		arcan_shmif_drop(&dctx->cont);
		free(thr);
		return NULL;
	}

/* normal event->cb dispatch loop, menu navigation is used to
 * mutate the meaning of the debug window and the set of applicable
 * handlers */
	while (1){
		struct tui_process_res res =
			arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);

		if (res.ok)
			flush_io(dctx);

		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL){
				break;
			}
		}
	}

	free(thr);
	return NULL;
}

static bool spawn_debugint(struct arcan_shmif_cont* c, int in, int out)
{
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

	struct debug_ctx* hgs = malloc(sizeof(struct debug_ctx));
	*hgs = (struct debug_ctx){
		.infd = in,
		.outfd = out,
		.cont = *c
	};

	if (-1 == pthread_create(&pth, &pthattr, debug_thread, hgs)){
		free(hgs);
		return false;
	}

	return true;
}

bool arcan_shmif_debugint_spawn(struct arcan_shmif_cont* c)
{
/* make sure we have the TUI functions for the debug thread */
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

	return spawn_debugint(c, -1, -1);
}

static bool fd_redirect(struct debug_ctx* dctx, int fd)
{
/* pipe-redirect -if that hasn't already happened- by first duping
 * stderr to somewhere, creating a pipe-pair, duping over and fwd
 * to the debug- thread */

	int fd_copy = dup(fd);
	if (-1 == fd_copy)
		return false;

	int dpipe[2];
	if (-1 == pipe(dpipe)){
		close(fd_copy);
		return false;
	}

	if (-1 == dup2(fd, dpipe[1])){
		close(dpipe[0]);
		close(dpipe[1]);
		close(fd_copy);
		return false;
	}

	if (-1 == dup2(fd, fd_copy)){
/* really not much of an escape from this without maybe some fork
 * magic, we broke stderr - sorry */
		return false;
	}

	return true;
}
