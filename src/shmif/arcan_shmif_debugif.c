#include "arcan_shmif.h"
#include "arcan_shmif_debugif.h"
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>
#include <ctype.h>
#include <sys/time.h>
#include <sys/resource.h>
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
	const char label[64];
	char shortcut;
	const char* menukey;
	uint64_t tag;
	void (*action)(struct debug_ctx*, struct menu_ent* self);
	bool (*eval)(struct debug_ctx*, struct menu_ent* self);
	struct tui_cbcfg handlers;
};

static bool fd_redirect(struct debug_ctx*, int fd);
static struct menu_ent* get_menu_tree(const char* key, size_t* count);

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
	struct tui_screen_attr attr_sel = attr;
	arcan_tui_get_color(c, TUI_COL_HIGHLIGHT, attr_sel.fc);
	arcan_tui_get_color(c, TUI_COL_BG, attr_sel.bc);
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

	size_t y = 0;
	for(; sofs + y < dst->n_entries && y < rows; y++){
		arcan_tui_move_to(c, 0, y);
		arcan_tui_writestr(c,
			dst->entries[sofs+y].label, dst->position == y ? &attr_sel : &attr);
	}

/* write each row (we're in nowrap, nocursor) and pick attr based on
 * highlight status */
}

static void menu_resized(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	menu_refresh(c, t);
}

static void menu_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* t)
{
	struct menu_ctx* dst = t;
	int last_pos = dst->position;

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
		if (dst->entries[dst->position].action){
			dst->entries[dst->position].action(
				dst->debugctx, &dst->entries[dst->position]);
		}
		else if (dst->entries[dst->position].menukey){
			size_t n_node;
			struct menu_ent* new_node = get_menu_tree(
				dst->entries[dst->position].menukey, &n_node);
			run_menu(dctx, new_node, n_node, NULL);
		}
	}
	else if (keysym == TUIK_ESCAPE){
/* deallocate and go back up menu stack */
		printf("give up\n");
	}
	else {
/* check character for match against shortcut or prefix, TUIK_
 * values if printable match ASCII so easy enough */
		if (!isprint(keysym))
			return;

		printf("move cursor based on pattern\n");
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
	struct menu_ent* menuflt = malloc(sizeof(struct menu_ent) * n_menu);
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
		.tag = menuctx,
		.input_key = menu_key,
		.resized = menu_resized
	};

	arcan_tui_update_handlers(ctx->tui, &menu_handlers, sizeof(menu_handlers));
	menu_refresh(ctx->tui, menuctx);
	return true;
}

static void* debug_thread(void* thr)
{
	struct debug_ctx* dctx = thr;
	size_t n_root;
	struct menu_ent* root = get_menu_tree("root", &n_root);

	if (!dctx->tui || !root){
		arcan_shmif_drop(&dctx->cont);
		free(thr);
		return NULL;
	}

	if (!run_menu(dctx, root, n_root, NULL)){
		arcan_shmif_drop(&dctx->cont);
		free(thr);
		return NULL;
	}

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

bool arcan_shmif_debugint_spawn(struct arcan_shmif_cont* c, void* tuitag)
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

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	struct tui_settings cfg = arcan_tui_defaults(c, tuitag);
	struct debug_ctx* hgs = malloc(sizeof(struct debug_ctx));
	if (!hgs)
		return false;

	*hgs = (struct debug_ctx){
		.infd = -1,
		.outfd = -1,
		.cont = *c,
		.tui = arcan_tui_setup(c,
			&cfg, &(struct tui_cbcfg){}, sizeof(struct tui_cbcfg))
	};

	if (!hgs->tui){
		free(hgs);
		return false;
	}

	arcan_tui_set_flags(hgs->tui, TUI_HIDE_CURSOR);

	if (-1 == pthread_create(&pth, &pthattr, debug_thread, hgs)){
		free(hgs);
		return false;
	}

	return true;
}

static bool fd_redirect(struct debug_ctx* dctx, int fd)
{
/* pipe-redirect -if that hasn't already happened- by first duping
 * stderr to somewhere, creating a pipe-pair, duping over and fwd
 * to the debug- thread */
	printf("request redirect on %d\n", fd);

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
	.label = "Intercept",
	.shortcut = 'f',
	.menukey = "fd_menu"
},
{
	.label = "Debugger",
	.shortcut = 'd',
	.menukey = "debug_menu"
}
/*
 * debugger
 *  -> OS specific prctls etc. to allow easy attach, then spawn process
 *     with the right attachment? (possible fork + sleep + signal + ...
 *
 *   - we'd also want to provide ourselves as a hand-over if that can be
 *     arranged, but more difficult
 *
 * memory (live / snapshot)
 * process (snapshot)
 */
};

static struct menu_ent* get_menu_tree(const char* key, size_t* count)
{
	printf("requested menu %s\n", key);

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
