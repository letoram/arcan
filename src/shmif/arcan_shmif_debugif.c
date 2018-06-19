#include "arcan_shmif.h"
#include "arcan_shmif_debugif.h"
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>
#include <ctype.h>
#include <limits.h>
#include <poll.h>

/*
 * ideally all this would be fork/asynch-signal safe
 */

#define ARCAN_TUI_DYNAMIC
#include "arcan_tui.h"

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

/*
 * menu code here is really generic enough that it should be move elsewhere,
 * frameserver/util or a single-header TUI suppl file possibly
 */
struct debug_ctx {
	struct arcan_shmif_cont cont;
	struct tui_context* tui;
	int infd;
	int outfd;
};

struct menu_ctx {
	struct debug_ctx* debugctx;
	struct menu_ent* entries;
	size_t n_entries;
	size_t position;
	void (*destroy)(struct menu_ctx*);
};

struct menu_ent;
struct menu_ent {
	const char* label;
	char shortcut;
	const char* menukey;
	uint64_t tag;
	void (*action)(struct debug_ctx*, struct menu_ent* self);
	bool (*eval)(struct debug_ctx*, struct menu_ent* self);
	struct tui_cbcfg handlers;
};

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

/* pretty much run whenever, the front/back buffers will make sure
 * that only cells that are truly different will be synched */
static void menu_refresh(struct tui_context* c, struct menu_ctx* dst)
{
	struct tui_screen_attr attr = arcan_tui_defattr(c, NULL);
	arcan_tui_get_color(c, TUI_COL_HIGHLIGHT, attr.fc);
	arcan_tui_get_color(c, TUI_COL_BG, attr.bc);
	arcan_tui_erase_screen(c, false);

	size_t rows, cols;
	arcan_tui_dimensions(c, &rows, &cols);

/* fixme, dynamic content refresh? */

/* clamp cursor to current set- size */

/* simple path: no paging. */
	size_t sofs = 0;
	if (dst->n_entries < rows){
	}
	else{
/* otherwise, find which page the current position puts us at */
	}

/* write each row (we're in nowrap, nocursor) and pick attr based on
 * highlight status */
}

static void menu_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	struct menu_ctx* dst = t;
	int last_pos = dst->position;
	printf("input: %d\n", keysym);

	if (keysym == TUIK_J || keysym == TUIK_DOWN){
		dst->position = (dst->position + 1) % dst->n_entries;
	}
	else if (keysym == TUIK_K || keysym == TUIK_UP){
		if (dst->position > 0)
			dst->position--;
		else
			dst->position = dst->n_entries - 1;
	}
	else if (keysym == TUIK_KP_ENTER || keysym == TUIK_RETURN){
/* deallocate and activate menu entry */
	}
	else if (keysym == TUIK_ESCAPE){
/* deallocate and go back up menu stack */
	}
	else {
/* check character for match against shortcut, TUIK_ values
 * if printable match ASCII so easy enough */
		if (!isprint(keysym))
			return;

		for (size_t i = 0; i < dst->n_entries; i++){
		}
	}

/* update the cursor and paging */
	if (dst->position != last_pos)
		menu_refresh(c, dst);
}

static bool run_menu(struct debug_ctx* ctx,
	struct menu_ent menu[], size_t n_menu, void (*cancel)(struct menu_ctx*))
{
	struct menu_ctx* menuctx = malloc(sizeof(struct menu_ctx));
	if (!menuctx)
		return false;

	size_t n_flt = 0;
	struct menu_ent* menuflt = malloc(sizeof(struct menu_ent));
	if (!menuflt){
		free(menuctx);
		return false;
	}

	for (size_t i = 0; i < n_menu; i++){
		if (!menu[i].eval || menu[i].eval(ctx, &menu[i])){
			menuflt[n_flt++] = menu[i];
		}
	}

	if (!n_flt){
		free(menuctx);
		free(menuflt);
		return false;
	}

	*menuctx = (struct menu_ctx){
		.debugctx = ctx,
		.entries = menuflt,
		.n_entries = n_flt,
		.position = 0,
		.destroy = cancel
	};

	struct tui_cbcfg menu_handlers = {
		.tag = ctx,
		.input_key = menu_key,
	};

	arcan_tui_update_handlers(ctx->tui, &menu_handlers, sizeof(menu_handlers));
	menu_refresh(ctx->tui, menuctx);
	return true;
}

static struct menu_ent* get_menu_tree(const char* key, size_t* count);

static void* debug_thread(void* thr)
{
	struct debug_ctx* dctx = thr;
	struct tui_cbcfg cbcfg = {};
	size_t n_root;
	struct menu_ent* root = get_menu_tree("root", &n_root);

	arcan_tui_conn* c = (arcan_tui_conn*) &dctx->cont;
	struct tui_settings cfg = arcan_tui_defaults(c, NULL);
	dctx->tui = arcan_tui_setup(c, &cfg, &cbcfg, sizeof(cbcfg));

	if (!dctx->tui || !root){
		arcan_shmif_drop(&dctx->cont);
		free(thr);
		return NULL;
	}

	run_menu(dctx, root, n_root, NULL);

/* normal event->cb dispatch loop, menu navigation is used to
 * mutate the meaning of the debug window and the set of applicable
 * handlers */
	while (dctx->tui){
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

	arcan_tui_destroy(dctx->tui, NULL);
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
 * magic, we broke the fd - sorry */
		return false;
	}

	return true;

}

static void intercept_fdent(struct debug_ctx* ctx, struct menu_ent* self)
{

}

static void build_fd_menu(struct debug_ctx* ctx, struct menu_ent* self)
{
/* to avoid relying on proc and so on for probing file descriptors,
 * we go with just building a big pollset, and just check which ones
 * are nval */
	struct rlimit rlim;
	int lim = 512;
	if (0 == getrlimit(RLIMIT_NOFILE, &rlim))
		lim = rlim.rlim_cur;
	size_t fds_sz = sizeof(struct pollfd) * lim;
	struct pollfd* fds = malloc(fds_sz);
	if (!fds)
		return;

	memset(fds, '\0', fds_sz);

	for (size_t i = 0; i < lim; i++)
		fds[i].fd = i;

	size_t nfd = 0;
	poll(fds, lim, 0);
	for (size_t i = 0; i <lim; i++)
		if (!(fds[i].revents & POLLNVAL))
			nfd++;

/* more hazzle here since it is a dynamic menu that calls for dynamic
 * deallocation, so we don't go through run_menu but rather just mimic */
	size_t nent = nfd + 1;
	struct menu_ent* new_menu = malloc(sizeof(struct menu_ent) * nent);
	nent = 0;
	if (!new_menu){
		free(fds);
		return;
	}

	for (size_t i = 0; i < lim; i++){
		if (fds[i].revents & POLLNVAL)
			continue;

		new_menu[nent++] = (struct menu_ent){
		};
	}

	struct menu_ctx* menuctx = malloc(sizeof(struct menu_ctx));
	if (!menuctx)
		return;

	*menuctx = (struct menu_ctx){
		.debugctx = ctx,
		.entries = new_menu,
	};

	free(fds);
}

static bool eval_senseye(struct debug_ctx* ctx, struct menu_ent* self)
{
/* check for the senseye-rwstat support library and use that to add
 * support for sense-mem and sense-file like behavior */
	return false;
}

/* ---------------- MENU DEFINITIONS BELOW --------------------- */

static struct menu_ent fd_menu[] = {
{
	.label = "Active",
	.shortcut = 'a',
	.tag = 1,
	.action = build_fd_menu
},
{
	.label = "Passive",
	.shortcut = 'p',
	.tag = 0,
	.action = build_fd_menu
},
{
	.label = "Senseye",
	.shortcut = 's',
	.tag = 2,
	.action = build_fd_menu,
	.eval = eval_senseye
}
};

static struct menu_ent root_menu[] = {
{
	.label = "File Descriptors",
	.shortcut = 'f',
	.menukey = "fd_menu"
}
/*
 * debugger
 *  -> OS specific prctls etc. to allow easy attach, then spawn process
 *     with the right attachment? (possible fork + sleep + signal + ...
 *
 * memory (live / snapshot)
 * process (snapshot)
 */
};

static struct menu_ent* get_menu_tree(const char* key, size_t* count)
{
	if (strcmp(key, "root") == 0){
		*count = COUNT_OF(root_menu);
		return root_menu;
	}

	if (strcmp(key, "fd_menu") == 0){
		*count = COUNT_OF(fd_menu);
		return fd_menu;
	}

	*count = 0;
	return NULL;
}
