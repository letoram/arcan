#include "arcan_shmif.h"
#include "arcan_shmif_debugif.h"
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>
#include <ctype.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <limits.h>
#include <poll.h>

/*
 * ideally all this would be fork/asynch-signal safe
 */

#define ARCAN_TUI_DYNAMIC
#include "arcan_tui.h"
#include "arcan_tuisym.h"
#include "arcan_tui_listwnd.h"
#include "arcan_tui_bufferwnd.h"

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
	bool dead;
};

static const char* stat_to_str(struct stat* s)
{
	if (S_IFIFO & s->st_mode){
		return "fifo";
	}
	else if (S_IFCHR & s->st_mode){
		return "char";
	}
	else if (S_IFDIR & s->st_mode){
		return "dir";
	}
	else if (S_IFBLK & s->st_mode){
		return "block";
	}
	else if (S_IFSOCK & s->st_mode){
		return "socket";
	}
	else if (S_IFREG & s->st_mode){
		return "false";
	}
	else
		return "unknown";
}

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

static void run_descriptor(struct debug_ctx* dctx, int fd)
{
/* dup- dance, convert to bufferwnd, select- intercept */
}

static void gen_descriptor_menu(struct debug_ctx* dctx)
{
/* build a large pollset, fire it once and see which ones were valid */
	struct rlimit rlim;
	int lim = 512;
	if (0 == getrlimit(RLIMIT_NOFILE, &rlim))
		lim = rlim.rlim_cur;

/* this is anything but atomic, we run inside an unwitting process, so either
 * we do something nasty like fork+stop-resume parent on collect or just accept
 * the race for now - there seem to be no portable solution for this so go with
 * what we can */
	struct pollfd* set = malloc(sizeof(struct pollfd) * lim);
	for (size_t i = 0; i < lim; i++)
		set[i].fd = i;

	poll(set, lim, 0);

	size_t count = 0;
	for (size_t i = 0; i < lim; i++){
		if (!(set[i].revents & POLLNVAL))
			count++;
	}

	if (count == 0){
		free(set);
		return;
	}
	printf("count resolved to %zu\n", count);

/* convert / stat-test the valid descriptors, and build the final menu list */
	struct tui_list_entry* lents = malloc(sizeof(struct tui_list_entry) * count);
	if (!lents){
		free(set);
		return;
	}

	struct dent {
		struct stat stat;
		int fd;
	}* dents = malloc(sizeof(struct dent) * count);
	if (!dents){
		free(lents);
		free(set);
		return;
	}

	count = 0;
	for (size_t i = 0; i < lim; i++){
		if (set[i].revents & POLLNVAL)
			continue;
		struct tui_list_entry* lent = &lents[count];
		lents[count] = (struct tui_list_entry){
			.tag = count,
/*		.label = "set later" */
/*		.attributes =
 *        CHECKED : already used?
 *        PASSIVE : couldn't be stat:ed
 */
		};

		size_t lbl_len = 256;
		char* lbl_prefix = malloc(lbl_len);
		if (!lbl_prefix)
			continue;

		dents[count].fd = set[i].fd;
		if (-1 == fstat(dents[count].fd, &dents[count].stat)){
			lents[count].attributes |= LIST_PASSIVE;
			snprintf(lbl_prefix, lbl_len, "%d(stat-fail) : %s",
				set[i].fd, strerror(errno));
		}
		else {
			snprintf(lbl_prefix, lbl_len,	"%d(%s) : can't resolve",
				set[i].fd, stat_to_str(&dents[count].stat));
		}
		lents[count].label = lbl_prefix;

/* resolve to pathname if possible */
#ifdef F_GETPATH
#endif
		count++;
	}

/* switch to new menu */
	arcan_tui_listwnd_setup(dctx->tui, lents, count);
	for(;;){
		struct tui_process_res res = arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL)
				break;
		}

		struct tui_list_entry* ent;
		if (arcan_tui_listwnd_status(dctx->tui, &ent)){
			if (ent){
/* run descriptor, with ent tag as index */
				run_descriptor(dctx, dents[ent->tag].fd);
			}
			break;
		}
	}

	for (size_t i = 0; i < count; i++){
		free(lents[i].label);
	}

	free(set);
	free(lents);
}

static void root_menu(struct debug_ctx* dctx)
{
	struct tui_list_entry menu_root[] = {
		{
			.label = "File Descriptors",
			.attributes = LIST_HAS_SUB,
			.tag = 0
		},
		{
			.label = "Debugger",
			.attributes = LIST_HAS_SUB,
			.tag = 1
		}
	};

	while(!dctx->dead){
		arcan_tui_listwnd_setup(dctx->tui, menu_root, COUNT_OF(menu_root));

		for(;;){
			struct tui_process_res res =
				arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);

			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL)
				return;

			struct tui_list_entry* ent;
			if (arcan_tui_listwnd_status(dctx->tui, &ent)){

/* this will just chain into a new listwnd setup, and if they cancel
 * we can just repeat the setup - until the dead state has been set */
				if (ent){
					if (ent->tag == 0)
						gen_descriptor_menu(dctx);
				}
				break;
			}

		}
	}
}

static void* debug_thread(void* thr)
{
	struct debug_ctx* dctx = thr;

	if (!dctx->tui){
		arcan_shmif_drop(&dctx->cont);
		free(thr);
		return NULL;
	}

	root_menu(dctx);

	arcan_tui_destroy(dctx->tui, NULL);
	free(thr);
	return NULL;
}

bool arcan_shmif_debugint_spawn(struct arcan_shmif_cont* c, void* tuitag)
{
/* make sure we have the TUI functions for the debug thread along with
 * the respective widgets, dynamically load the symbols */
	if (!arcan_tui_setup ||
			!arcan_tui_listwnd_setup ||
			!arcan_tui_bufferwnd_setup
	){
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

		if (!arcan_tui_listwnd_dynload(dlsym, openh))
			return false;

		if (!arcan_tui_bufferwnd_dynload(dlsym, openh))
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
