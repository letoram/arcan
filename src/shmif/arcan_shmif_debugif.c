#include "arcan_shmif.h"
#include "arcan_shmif_interop.h"
#include "arcan_shmif_debugif.h"
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>
#include <ctype.h>
#include <unistd.h>
#include <stdatomic.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/mman.h>
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

enum debug_cmd_id {
	TAG_CMD_DEBUGGER = 0,
	TAG_CMD_ENVIRONMENT = 1,
	TAG_CMD_DESCRIPTOR = 2,
	TAG_CMD_PROCESS = 3,
/* other interesting:
 * - browse namespace / filesystem and allow load/store
 *    |-> would practically require some filtering / extra input handling
 *        for the listview (interesting in itself..)
 */
};

static _Atomic int beancounter;

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

static int run_listwnd(
	struct debug_ctx* dctx, struct tui_list_entry* list, size_t n_elem);

static const char* stat_to_str(struct stat* s)
{
	const char* ret = "unknown";
	switch(s->st_mode & S_IFMT){
	case S_IFIFO:
		ret = "fifo";
	break;
	case S_IFCHR:
		ret = "char";
	break;
	case S_IFDIR:
		ret = "dir";
	break;
	case S_IFREG:
		ret = "file";
	break;
	case S_IFBLK:
		ret = "block";
	break;
	case S_IFSOCK:
		ret = "socket";
	break;
	default:
	break;
	}
	return ret;
}

enum intercept_type {
	INTERCEPT_MITM_PIPE,
	INTERCEPT_MITM_SOCKET,
	INTERCEPT_MAP
};

static int can_intercept(struct stat* s)
{
	int mode = s->st_mode & S_IFMT;
	if (mode & S_IFIFO)
		return INTERCEPT_MITM_PIPE;
	else if (mode & S_IFREG)
		return INTERCEPT_MAP;
	else if (mode & S_IFSOCK)
		return INTERCEPT_MITM_SOCKET;
	return -1;
}

static void fd_to_flags(char buf[static 8], int fd)
{
	buf[7] = '\0';

/* first, cloexec */
	buf[0] = ' ';
	int rv = fcntl(fd, F_GETFD);
	if (-1 == rv){
		buf[0] = '?';
	}
	else if (rv & O_CLOEXEC){
		buf[0] = 'x';
	}

/* now flags */
	buf[1] = ' ';
	rv = fcntl(fd, F_GETFL);
	if (-1 == rv){
		buf[1] = '?';
	}
	else if ((rv & O_NONBLOCK))
	;
	else
		buf[1] = 'b';

	if (rv & O_RDWR){
		buf[2] = 'r';
		buf[3] = 'w';
	}
	else if (rv & O_WRONLY){
		buf[2] = ' ';
		buf[3] = 'w';
	}
	else {
		buf[2] = 'r';
	buf[3] = ' ';
	}
}

static void run_descriptor(struct debug_ctx* dctx, int fdin, int type)
{
/*
 * intermediate menu for possible descriptor actions, i.e. copy, edit, view, mim,
 */

	struct tui_list_entry lents[6];
	size_t nents = 0;

	if (type == INTERCEPT_MAP){
		lents[0] = (struct tui_list_entry){
			.label = "Copy",
			.tag = 1
		};
		lents[1] = (struct tui_list_entry){
			.label = "View",
			.tag = 2
		};
		nents = 2;
	}
	else if (type == INTERCEPT_MITM_PIPE){
		lents[0] = (struct tui_list_entry){
			.label = "Intercept (Stream)",
			.tag = 3
		};
		nents = 1;
	}
	else if (type == INTERCEPT_MITM_SOCKET){
		lents[0] = (struct tui_list_entry){
			.label = "Intercept (BiDi)",
			.tag = 4
		};
		lents[0] = (struct tui_list_entry){
			.label = "Intercept (Read)",
			.tag = 5
		};
		lents[2] = (struct tui_list_entry){
			.label = "Intercept (Write)",
			.tag = 6
		};
/* other tasty options:
 * - fdswap
 */
		nents = 3;
	}

	int rv = run_listwnd(dctx, lents, nents);
	if (-1 == rv){
		return;
	}

	switch(lents[rv].tag){
	case 1:
	break;
	case 2:
/* check permissions on descriptor to determine read- write, doesn't really matter */
	break;
	case 3:
	break;
	case 4:
/* BiDi is the worst as we need a window for read and another for write */
	break;
	case 5:
	break;
	case 6:
	break;
	}

/*
 * intercept or send/copy?
 * set as current bchunk- handler and re-run menu
 */


/*	if (lents[rv].tag == 1){
		arcan_tui_announce_io(dctx, true, NULL, "*");
		return run_descriptor(dctx, fdin, fdout, type);
	}
*/

/* should present some other options here,
 * read-only,
 * buffer-sizes, commit sizes
 * right now just go with streaming into bufferwindow and invalidate/ flush
 */

/*
 * Other thing is that we should possibly have a shared structure where we
 * track the descriptors that we are already tampering with so that those
 * doesn't appear in menu
 */
	arcan_tui_update_handlers(dctx->tui,
		&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));

	bool ro = true;
	uint8_t* buf = NULL;
	size_t buf_sz = 0;

	switch(type){
	case INTERCEPT_MITM_PIPE:
/* pipe identification can be done with F_GETFL, then check if WRONLY or
 * if neither O_RDWR or WRONLY is set - streaming controls are needed */
		buf_sz = 4096;
		buf = malloc(buf_sz);
		memset(buf, '\0', buf_sz);
	break;
	case INTERCEPT_MITM_SOCKET:
/* socket is just awful, read and write on the same and need to handle
 * OOB / etc. todo */
		return;
	break;
	case INTERCEPT_MAP:
/* quick browsing to see what it is about */
		break;
	}

/* query_label and input_label will be forwarded, we add our stuff there,
 * then set commit_write_fn (commit) to get write-back callbacks for edit
 * on memory - then we can call synch when the data is updated, use prefix
 * offs as byte counter*/

	struct tui_bufferwnd_opts opts = {
		.read_only = ro,
		.view_mode = BUFFERWND_VIEW_HEX_DETAIL,
		.allow_exit = true
	};

/* switch to bufferwnd, the streaming mode needs to add some more controls
 * for flushing etc. */
	arcan_tui_bufferwnd_setup(dctx->tui,
		buf, buf_sz, &opts, sizeof(struct tui_bufferwnd_opts));

	while(1){
		struct tui_process_res res = arcan_tui_process(&dctx->tui, 1, &fdin, 1, -1);
		arcan_tui_refresh(dctx->tui);
	}

/* for MITM we need to dup-dance back */
	switch(type){
	case INTERCEPT_MITM_PIPE:
		free(buf);
	break;
	case INTERCEPT_MITM_SOCKET:
/* todo */
	break;
	case INTERCEPT_MAP:
		munmap(buf, buf_sz);
	break;
	}
}

static int run_listwnd(
	struct debug_ctx* dctx, struct tui_list_entry* list, size_t n_elem)
{
	arcan_tui_update_handlers(dctx->tui,
		&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));
	arcan_tui_listwnd_setup(dctx->tui, list, n_elem);

	int rv = -1;
	for(;;){
		struct tui_process_res res = arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL){
				break;
			}
		}

		struct tui_list_entry* ent;
		if (arcan_tui_listwnd_status(dctx->tui, &ent)){
			if (ent){
				rv = ent->tag;
			}
			break;
		}
	}

	arcan_tui_listwnd_release(dctx->tui);
	return rv;
}

extern int arcan_fdscan(int** listout);
static void gen_descriptor_menu(struct debug_ctx* dctx)
{
/* grab a list of current descriptors */
	int* fds;
	ssize_t count = arcan_fdscan(&fds);
	if (-1 == count)
		return;

/* convert this set to list entry values */
	struct tui_list_entry* lents = malloc(sizeof(struct tui_list_entry) * count);
	if (!lents){
		free(fds);
		return;
	}

/* stat it and continue */
	struct dent {
		struct stat stat;
		int fd;
	}* dents = malloc(sizeof(struct dent) * count);
	if (!dents){
		free(lents);
		free(fds);
		return;
	}

/* generate an entry even if the stat failed, as the info is indicative
 * of a FD being detected and then inaccessible or gone */
	size_t used = 0;
	for (size_t i = 0; i < count; i++){
		struct tui_list_entry* lent = &lents[count];
		lents[used] = (struct tui_list_entry){
			.tag = i
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

/* mark the stat as failed but remember the descriptor and write down */
		if (-1 == fstat(fds[i], &dents[used].stat)){
			lents[used].attributes |= LIST_PASSIVE;
			snprintf(lbl_prefix, lbl_len,
				"%d(stat-fail) : %s", fds[i], strerror(errno));
		}
/* resolve more data */
		else {
			char scratch[8];
			fd_to_flags(scratch, fds[i]);
			if (-1 == can_intercept(&dents[used].stat))
				lents[used].attributes |= LIST_PASSIVE;
#ifdef __LINUX
			char buf[256];
			snprintf(buf, 256, "/proc/self/fd/%d", fds[i]);
/* using buf on both arguments should be safe here due to the whole 'need the
 * full path before able to generate output' criteria, but explicitly terminate
 * on truncation */
			int rv = readlink(buf, buf, 255);
			if (-1 == rv){
				snprintf(buf, 256, "error: %s", strerror(errno));
			}
			else
				buf[rv] = '\0';

			snprintf(lbl_prefix, lbl_len, "%4d[%s](%s)\t: %s",
				fds[i], scratch, stat_to_str(&dents[used].stat), buf);
#else
			snprintf(lbl_prefix, lbl_len,	"%4d[%s](%s)\t: can't resolve",
				fds[i], scratch, stat_to_str(&dents[used].stat));
#endif
/* BSD: resolve to pathname if possible */
#ifdef F_GETPATH
#endif
		}

/* stat:able, good start, extract flags and state */
		dents[used].fd = fds[i];
		lents[used].label = lbl_prefix;
		used++;
	}

/* switch to new menu */

/* special treatment for STDIN, STDOUT, STDERR as well as those can go to a
 * tty/pty, meaning that our normal 'check if pipe' won't just work by default */

/* Pipes are 'easy', we can check if the end is read or write and setup the
 * interception accordingly. Sockets have types and are bidirectional, so
 * either we request a new window and use one for the read and one for the
 * write end - as well as getsockopt on type etc. to figure out if the socket
 * can actually be intercepted or not. */
	int rv = run_listwnd(dctx, lents, count);

	if (-1 != rv){
		struct tui_list_entry* ent = &lents[rv];
		int icept = can_intercept(&dents[ent->tag].stat);
		run_descriptor(dctx, dents[ent->tag].fd, icept);
	}

	for (size_t i = 0; i < count; i++){
		free(lents[i].label);
	}

	free(fds);
	free(lents);

/* finished with the buffer window, rebuild the list */
	if (-1 != rv)
		return gen_descriptor_menu(dctx);
}

/*
 * debugger and the others are more difficult as we currently need to handover
 * exec into afsrv_terminal in a two phase method where we need to stall the
 * child a little bit while we see prctl(PR_SET_PTRACE, pid, ...).
 */
static void gen_debugger_menu(struct debug_ctx* dctx)
{
/* check for presence of lldb and gdb, use special chainloaders for them,
 * possibly through afsrv_terminal to get the pty */
}

/*
 * For this feature we would like to provide an editable view of the process
 * environment. This is anything but trivial as basically all other threads
 * would need to be suspended while we are doing this.
 *
 * Normally this could be done with some convoluted ptrace+fork dance, and
 * implement for each platform. At the moment we settle for unsafe probing,
 * and revisit later when other features are in place.
 *
 * Another option is the linux proc/env dance.
 *
 * Things to look out for:
 *  client setting keys to a corrupted value (modify environ and add extra)
 */
extern char** environ;
static struct tui_list_entry* build_env_list(size_t* outc)
{
	size_t nelem = 0;
	while(environ[nelem++]){}
	if (!nelem)
		return NULL;

	*outc = 0;
	struct tui_list_entry* nents = malloc(sizeof(struct tui_list_entry) * nelem);
	if (!nents)
		return NULL;

	for (size_t i = 0; i < nelem; i++){
		size_t len = 0;
		for (; environ[i] && environ[i][len] && environ[i][len] != '='; len++){}
		if (len == 0)
			continue;

		char* label = malloc(len+1);
		if (!label)
			continue;

		memcpy(label, environ[i], len);
		label[len] = '\0';

		nents[*outc] = (struct tui_list_entry){
			.attributes = LIST_HAS_SUB,
			.tag = i,
			.label = label
		};
		(*outc)++;
	}

	return nents;
}

static void free_list(struct tui_list_entry* list, size_t nc)
{
	for (size_t i = 0; i < nc; i++)
		free(list[i].label);
	free(list);
}

static void gen_environment_menu(struct debug_ctx* dctx)
{
	size_t nelem = 0;

	struct tui_list_entry* list = build_env_list(&nelem);
	if (!list)
		return;

	if (!nelem){
		free(list);
		return;
	}

	int ind = run_listwnd(dctx, list, nelem);
	if (-1 == ind){
		free_list(list, nelem);
		return;
	}

	char* env = getenv(list[ind].label);
	if (!env || !(env = strdup(env)))
		return gen_environment_menu(dctx);

	struct tui_bufferwnd_opts opts = {
		.read_only = false,
		.view_mode = BUFFERWND_VIEW_ASCII,
		.allow_exit = true
	};

/* bufferwnd is used here intermediately as it has the problem of not
 * being able to really handle insertion, so either that gets fixed or
 * the libreadline replacement finally gets written */
	arcan_tui_bufferwnd_setup(dctx->tui, (uint8_t*) env,
		strlen(env), &opts, sizeof(struct tui_bufferwnd_opts));

	while(arcan_tui_bufferwnd_status(dctx->tui) == 1){
		struct tui_process_res res = arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL){
				dctx->dead = true;
				break;
			}
		}
	}

	return gen_environment_menu(dctx);
}

int arcan_shmif_debugint_alive()
{
	return atomic_load(&beancounter);
}

static void build_process_str(char* dst, size_t dst_sz)
{
/* bufferwnd currently 'misses' a way of taking some in-line formatted string
 * and resolving, the intention was to add that as a tack-on layer and use the
 * offset- lookup coloring to perform that resolution, simple strings for now */
	pid_t cpid = getpid();
	pid_t ppid = getppid();
#ifdef LINUX
	snprintf(dst, dst_sz, "PID: %zd Parent: %zd", (ssize_t) cpid, (ssize_t) ppid);
/* information sources from proc / pid:
 * cmdline [\0 sep]
 * mountinfo?
 * /proc/sys/kernel/yama/ptrace_scope
 * hmm, map_files can be used now without the fseek hell
 * oom_score
 * -- not all are cheap enough for synch
 * from status, signal mask, uid/gid, fdsizes(?), seccomp, voluntary / forced
 * limits
 * tracer-pid
 * IP sampling mode?
 */
#else
	snprintf(dst, dst_sz, "PID: %zd Parent: %zd", (ssize_t) cpid, (ssize_t) ppid);
#endif
/* hardening analysis,
 * aslr, nxstack, canaries (also extract canary)
 */
}

static void set_process_window(struct debug_ctx* dctx)
{
/* build a process description string that we periodically update */
	char outbuf[2048];
	build_process_str(outbuf, sizeof(outbuf));
	struct tui_bufferwnd_opts opts = {
		.read_only = true,
		.view_mode = BUFFERWND_VIEW_ASCII,
		.allow_exit = true
	};

	arcan_tui_bufferwnd_setup(dctx->tui,
		(uint8_t*) outbuf, strlen(outbuf)+1, &opts, sizeof(struct tui_bufferwnd_opts));

/* normal event-loop, but with ESCAPE as a 'return' behavior */
	while(arcan_tui_bufferwnd_status(dctx->tui) == 1){
		struct tui_process_res res = arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL){
				dctx->dead = true;
				break;
			}
		}
		else{
			dctx->dead = true;
			break;
		}
/* check last- refresh and build process str and call bufferwnd_synch */
	}

/* return the context to normal, dead-flag will propagate and free if set */
	arcan_tui_bufferwnd_release(dctx->tui);
	arcan_tui_update_handlers(dctx->tui,
		&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));
}

static void root_menu(struct debug_ctx* dctx)
{
	struct tui_list_entry menu_root[] = {
		{
			.label = "File Descriptors",
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_DESCRIPTOR
		},
		{
			.label = "Debugger",
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_DEBUGGER
		},
		{
			.label = "Environment",
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_ENVIRONMENT
		},
		{
			.label = "Process Information",
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_PROCESS
		}
	};

	while(!dctx->dead){
/* update the handlers so there's no dangling handlertbl+cfg */
		arcan_tui_update_handlers(dctx->tui,
			&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));
		arcan_tui_listwnd_setup(dctx->tui, menu_root, COUNT_OF(menu_root));

		for(;;){
			struct tui_process_res res =
				arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);

			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL)
				return;

			struct tui_list_entry* ent;
			if (arcan_tui_listwnd_status(dctx->tui, &ent)){
				arcan_tui_listwnd_release(dctx->tui);
				arcan_tui_update_handlers(dctx->tui,
					&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));

/* this will just chain into a new listwnd setup, and if they cancel
 * we can just repeat the setup - until the dead state has been set */
				if (ent){
					switch(ent->tag){
						case TAG_CMD_DESCRIPTOR :
							gen_descriptor_menu(dctx);
						break;
						case TAG_CMD_DEBUGGER :
							gen_debugger_menu(dctx);
						break;
						case TAG_CMD_ENVIRONMENT :
							gen_environment_menu(dctx);
						break;
						case TAG_CMD_PROCESS :
							set_process_window(dctx);
						break;
					}
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
		atomic_fetch_add(&beancounter, -1);
		free(thr);
		return NULL;
	}

	root_menu(dctx);

	arcan_tui_destroy(dctx->tui, NULL);
	atomic_fetch_add(&beancounter, -1);
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

	atomic_fetch_add(&beancounter, 1);

	return true;
}
