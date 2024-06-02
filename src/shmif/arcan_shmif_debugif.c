/*
 * Runtime in-process Debug Interface
 * Copyright 2018-2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: This provides a collection of useful user-initiated
 * debug control and process exploration tools.
 * Notes:
 *  - simple:
 *    - mim window controls (buffer size, streaming mode, view mode)
 *    -                      inject latency
 *    - non-visual MiM
 *    - hash-table based FD tracking and tagging debugif FDs in FD view
 *
 *  - interesting / unexplored venues:
 *    - seccomp- renderer
 *    - sanitizer
 *    - statistic profiler
 *    - detach intercept / redirect window
 *    - dynamic descriptor list refresh
 *    - runtime symbol hijack
 *    - memory pages to sense_mem deployment
 *      - use llvm-symbolizer to resolve addresses to memory
 *        and show as labels/overlays on the bytes themselves
 *    - short-write commit (randomize commit-sizes)
 *    - enumerate modules and their symbols? i.e. dl_iterate_phdr
 *      and trampoline?
 *    - 'special' tactics, e.g. malloc- intercept + backtrace on write
 *      to pair buffers and transformations, fetch from trap page pool
 *      and mprotect- juggle to find crypto and compression functions
 *    - detach-thread and detach- process for FD intercept
 *    - browse- filesystem based on cwd
 *    - message path for the debugif to have a separate log queue
 *    - ksy loading
 *    - special syscall triggers (though this requires a tracer process)
 *      - descriptor modifications
 *      - mmap
 * 	MIM_MODE_
 *    - key structure interpretation:
 *      - malloc stats
 *      - shmif-mempage inspection
 *
 * Likely that some of these and other venues should be written as separate
 * tools that jack into the menu (see src/tools/adbginject) rather than make
 * the code here too extensive.
 *
 * Many of these moves are quite risky without other good primitives
 * first though, the most pressing one is probably 'suspend all other
 * threads'.
 *
 * Interesting source of problems, when debugif is active no real output
 * can be allowed from this one, tui or shmif as any file might be
 * redirected and cause locking
 */
#include "arcan_shmif.h"
#include "arcan_shmif_interop.h"
#include "shmif_defimpl.h"
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
#include <sys/wait.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>

#ifdef __LINUX
#include <sys/prctl.h>
#endif

/*
 * ideally all this would be fork/asynch-signal safe
 * but it is a tall order to fill, need much more work and control to
 * pool and prealloc heap memory etc.
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
	TAG_CMD_SPAWN = 0,
	TAG_CMD_ENVIRONMENT = 1,
	TAG_CMD_DESCRIPTOR = 2,
	TAG_CMD_PROCESS = 3,
	TAG_CMD_EXTERNAL = 4
};

static volatile _Atomic int beancounter;

/*
 * menu code here is really generic enough that it should be move elsewhere,
 * frameserver/util or a single-header TUI suppl file possibly
 */
struct debug_ctx {
	struct arcan_shmif_cont cont;
	struct tui_context* tui;
/* tract if we are in store/restore mode */
	int last_fd;

/* track if we are in interception state or not */
	int infd;
	int outfd;

/* when the UI thread has been shut down */
	bool dead;

/* hook for custom menu entries */
	struct debugint_ext_resolver resolver;
};

enum mim_buffer_mode {
	MIM_MODE_CHUNK,
	MIM_MODE_STREAM,
};

struct mim_buffer_opts {
	size_t size;
	enum mim_buffer_mode mode;
};

/* basic TUI convenience loop / setups */
static struct tui_list_entry* run_listwnd(struct debug_ctx* dctx,
	struct tui_list_entry* list, size_t n_elem, const char* ident,
	size_t* pos);

static int run_buffer(struct tui_context* tui, uint8_t* buffer,
	size_t buf_sz, struct tui_bufferwnd_opts opts, const char* ident);

static void run_mitm(struct tui_context* tui, struct mim_buffer_opts opts,
	int fd, bool thdwnd, bool mitm, bool mask, const char* label);

static void show_error_message(struct tui_context* tui, const char* msg)
{
	if (!msg)
		return;

	run_buffer(tui,
		(uint8_t*) msg, strlen(msg), (struct tui_bufferwnd_opts){
		.read_only = true,
		.view_mode = BUFFERWND_VIEW_ASCII
	}, "error");
}

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
		ret = " dir";
	break;
	case S_IFREG:
		ret = "file";
	break;
	case S_IFBLK:
		ret = "block";
	break;
	case S_IFSOCK:
		ret = "sock";
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
	buf[0] = '_';
	int rv = fcntl(fd, F_GETFD);
	if (-1 == rv){
		buf[0] = '?';
	}
	else if (!(rv & FD_CLOEXEC)){
		buf[0] = 'x';
	}

/* now flags */
	buf[1] = '_';
	rv = fcntl(fd, F_GETFL);
	if (-1 == rv){
		buf[1] = '?';
	}
	else if ((rv & O_NONBLOCK))
		;
	else
		buf[1] = 'B';

	if (rv & O_RDWR){
		buf[2] = 'r';
		buf[3] = 'w';
	}
	else if (rv & O_WRONLY){
		buf[2] = '_';
		buf[3] = 'w';
	}
	else {
		buf[2] = 'r';
		buf[3] = '_';
	}

/* Other options:
 * seals
 * locked */
}

static bool mim_flush(
	struct tui_context* tui, uint8_t* buf, size_t buf_sz, int fdout)
{
	if (-1 == fdout)
		return true;

	struct tui_bufferwnd_opts opts = {
		.read_only = true,
		.view_mode = BUFFERWND_VIEW_ASCII,
		.allow_exit = false
	};

	char msg[32];
	size_t buf_pos = 0;
	snprintf(msg, 32, "Flushing, %zu / %zu bytes", buf_pos, buf_sz);

/* it's not that we really can do anything in the context of errors here */
	int rfl = fcntl(fdout, F_GETFL);
	fcntl(fdout, F_SETFL, rfl | O_NONBLOCK);

	struct pollfd pfd[2] = {
		{
			.fd = fdout,
			.events = POLLOUT | POLLERR | POLLNVAL | POLLHUP
		},
		{
			.events = POLLIN | POLLERR | POLLNVAL | POLLHUP
		}
	};

/* keep going until the buffer is sent or something happens */
	int status;
	while(buf_pos < buf_sz &&
		1 == (status = arcan_tui_bufferwnd_status(tui))){
		arcan_tui_get_handles(&tui, 1, &pfd[1].fd, 1);
		int status = poll(pfd, 2, -1);
		if (pfd[0].revents){
/* error */
			if (!(pfd[0].revents & POLLOUT)){
				break;
			}

/* write and update output window */
			ssize_t nw = write(fdout, &buf[buf_pos], buf_sz - buf_pos);
			if (nw > 0){
				buf_pos += nw;
				snprintf(msg, 32, "Flushing, %zu / %zu bytes", buf_pos, buf_sz);
				arcan_tui_bufferwnd_synch(tui, (uint8_t*)msg, strlen(msg), 0);
			}
		}

/* and always update the window */
		arcan_tui_process(&tui, 1, NULL, 0, 0);
		arcan_tui_refresh(tui);
	}

/* if the context has died and we have data left to flush, try one final big
 * write before calling it a day or we may leave the client in a bad state */
	if (buf_pos < buf_sz){
		fcntl(fdout, F_SETFL, rfl & (~O_NONBLOCK));
		while (buf_pos < buf_sz){
			ssize_t nw = write(fdout, &buf[buf_pos], buf_sz - buf_pos);
			if (-1 == nw){
				if (errno == EAGAIN || errno == EINTR)
					continue;
				break;
			}
			buf_pos += nw;
		}
	}

/* restore initial flag state */
	fcntl(fdout, F_SETFL, rfl);

/* there is no real recovery should this be terminated prematurely */
	return buf_pos == buf_sz;
}

static void mim_window(
	struct tui_context* tui, int fdin, int fdout, struct mim_buffer_opts bopts)
{
/*
 * other options:
 * streaming or windowed,
 * window size,
 * read/write
 */
	struct tui_bufferwnd_opts opts = {
		.read_only = false,
		.view_mode = BUFFERWND_VIEW_HEX_DETAIL,
		.allow_exit = true
	};

/* switch window, wait for buffer */
	size_t buf_sz = bopts.size;
	size_t buf_pos = 0;
	uint8_t* buf = malloc(buf_sz);
	if (!buf)
		return;

	memset(buf, '\0', buf_sz);

/* would be convenient with a message area that gets added, there's also the
 * titlebar and buffer control - ideally this would even be a re-usable helper
 * with bufferwnd rather than here */
refill:
	arcan_tui_bufferwnd_setup(tui,
		buf, 0, &opts, sizeof(struct tui_bufferwnd_opts));

	bool read_data = true;
	int status;

	while(1 == (status = arcan_tui_bufferwnd_status(tui))){
		struct tui_process_res res;
		if (read_data){
			res = arcan_tui_process(&tui, 1, &fdin, 1, -1);
		}
		else
			res = arcan_tui_process(&tui, 1, NULL, 0, -1);

/* fill buffer if needed */
		if (res.ok){
			if (buf_sz - buf_pos > 0){
				ssize_t nr = read(fdin, &buf[buf_pos], buf_sz - buf_pos);
				if (nr > 0){
					buf_pos += nr;
					arcan_tui_bufferwnd_synch(tui,
						buf, buf_pos, arcan_tui_bufferwnd_tell(tui, NULL));

					if (buf_sz == buf_pos)
						read_data = false;
				}
			}
		}

/* buffer updated? grow it */
		if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
			break;
	}

/* commit- flush and reset, if the connection is dead there is no real recourse
 * until we implement a global 'lock-all-threads' then continue this one as
 * write may continue to come in on our fdin at a higher rate than drain to
 * fdout, which in turn would block the dup2 swapback */
	if (mim_flush(tui, buf, buf_pos, fdout) && status == 0){
		buf_pos = 0;
		arcan_tui_bufferwnd_tell(tui, &opts);
		read_data = true;
		arcan_tui_bufferwnd_release(tui);
		goto refill;
	}

/* caller will clean up descriptors */
	arcan_tui_bufferwnd_release(tui);
	arcan_tui_update_handlers(tui,
		&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));
	free(buf);
}

static void buf_window(struct tui_context* tui, int source, const char* lbl)
{
/* just read-only / mmap for now */
	struct stat fs;
	if (-1 == fstat(source, &fs) || !fs.st_size)
		return;

	void* buf = mmap(NULL, fs.st_size, PROT_READ, MAP_PRIVATE, source, 0);
	if (buf == MAP_FAILED)
		return;

	struct tui_bufferwnd_opts opts = {
		.read_only = true,
		.view_mode = BUFFERWND_VIEW_HEX_DETAIL,
		.allow_exit = true
	};

	run_buffer(tui, buf, fs.st_size, opts, lbl);
	munmap(buf, fs.st_size);
}

static void setup_mitm(
	struct tui_context* tui, int source, bool mask, struct mim_buffer_opts opts)
{
	int fdin = source;
	int fdout = -1;

/* need a cloexec pair of pipes */
	int pair[2];
	if (-1 == pipe(pair))
		return;

/* set numbers and behavior based on direction */
	int orig = dup(source);
	int fd_in, fd_out, scratch;

	int fl = fcntl(source, F_GETFL);
	if ((fl & O_WRONLY) || source == STDOUT_FILENO){
		char ident[32];
		snprintf(ident, 32, "outgoing: %d", source);
		arcan_tui_ident(tui, ident);
		dup2(pair[1], source);
		close(pair[1]);
		fd_in = pair[0];
		scratch = fd_in;
		fd_out = mask ? -1 : orig;
	}
	else {
		char ident[32];
		snprintf(ident, 32, "incoming: %d", source);
		arcan_tui_ident(tui, ident);
		dup2(pair[0], source);
		close(pair[0]);
		fd_in = orig;
		fd_out = mask ? -1 : pair[1];
		scratch = pair[1];
	}

/* blocking / non-blocking is not handled correctly */
	mim_window(tui, fd_in, fd_out, opts);
	dup2(orig, source);
	close(orig);
	close(scratch);
}

/*
 * intermediate menu for possible descriptor actions
 */
enum {
	DESC_COPY = 0,
	DESC_VIEW,
	DESC_MITM_PIPE,
	DESC_MITM_REDIR,
	DESC_MITM_BIDI,
	DESC_MITM_RO,
	DESC_MITM_WO,
	WINDOW_METHOD
};
static void run_descriptor(
	struct debug_ctx* dctx, int fdin, int type, const char* label)
{
	if (fdin <= 2){
		type = INTERCEPT_MITM_PIPE;
	}

	const int buffer_sizes[] = {512, 1024, 2048, 4096, 8192, 16384};
	struct mim_buffer_opts bopts = {
		.size = 4096,
	};
	struct tui_list_entry lents[6];
	char* strpool[6] = {NULL};
	size_t nents = 0;
	bool spawn_new = false;
	struct tui_list_entry* ent;
	size_t pos = 0;

/* mappables are typically files or shared memory */
	if (type == INTERCEPT_MAP){
		lents[nents++] = (struct tui_list_entry){
			.label = "Copy",
			.tag = DESC_COPY
		};
		lents[nents++] = (struct tui_list_entry){
			.label = "View",
			.tag = DESC_VIEW
		};
	}
/* on solaris/some BSDs we have these as bidirectional / go with socket */
	else if (type == INTERCEPT_MITM_PIPE){
		lents[nents++] = (struct tui_list_entry){
			.label = "Intercept",
			.tag = DESC_MITM_PIPE
		};
		lents[nents++] = (struct tui_list_entry){
			.label = "Redirect",
			.tag = DESC_MITM_REDIR
		};

	/* display more metadata:
 * possibly: F_GETPIPE_SZ */
	}
	else if (type == INTERCEPT_MITM_SOCKET){
		lents[nents++] = (struct tui_list_entry){
			.label = "Intercept (BiDi)",
			.tag = DESC_MITM_BIDI
		};
		lents[nents++] = (struct tui_list_entry){
			.label = "Intercept (Read)",
			.tag = DESC_MITM_RO
		};
		lents[nents++] = (struct tui_list_entry){
			.label = "Intercept (Write)",
			.tag = DESC_MITM_WO
		};
/* other tasty options:
 * - fdswap (on pending descriptor for OOB)
 */
	}
/* F_GETLEASE, F_GET_SEALS */
	lents[nents++] = (struct tui_list_entry){
		.label = "Window: Current",
		.tag = WINDOW_METHOD
	};

rerun:
	ent = run_listwnd(dctx, lents, nents, label, &pos);
	if (!ent){
		return;
	}

	switch(ent->tag){
	case DESC_COPY:{
		arcan_tui_announce_io(dctx->tui, true, NULL, "*");
		return run_descriptor(dctx, fdin, type, label);
	}
	break;
	case WINDOW_METHOD:
		spawn_new = !spawn_new;
		ent->label = spawn_new ? "Window: New" : "Window: Current";
		goto rerun;
	break;
	case DESC_VIEW:
		run_mitm(dctx->tui, bopts, fdin, spawn_new, false, true, label);
	break;
	case DESC_MITM_PIPE:
		run_mitm(dctx->tui, bopts, fdin, spawn_new, true, false, label);
	break;
	case DESC_MITM_REDIR:
		run_mitm(dctx->tui, bopts, fdin, spawn_new, true, true, label);
	break;
	case DESC_MITM_BIDI:
/*
 * we need another window for this one to work or a toggle to
 * swap in/out (perhaps better actually)
 */
	break;
	case DESC_MITM_RO:
/*
 * the nastyness here is that we need to proxy oob stuff,
 * socket API is such a pile of garbage.
 */
	break;
	case DESC_MITM_WO:
	break;
	}
}

static void bchunk(struct tui_context* T,
	bool input, uint64_t size, int fd, const char* type, void* tag)
{
	struct debug_ctx* dctx = tag;

	if (dctx->last_fd == -1)
		return;

	struct arcan_shmif_cont* c = arcan_tui_acon(T);

	int copy_last = arcan_shmif_dupfd(dctx->last_fd, -1, true);
	if (-1 == copy_last){
		return;
	}

	int copy_new = arcan_shmif_dupfd(fd, -1, true);
	if (-1 == copy_new){
		close(copy_last);
		return;
	}

/* bgcopy takes care of closing */
	if (input){
		arcan_shmif_bgcopy(c, copy_new, copy_last, -1, 0);
	}
	else {
		arcan_shmif_bgcopy(c, copy_last, copy_new, -1, 0);
	}
}

static struct tui_list_entry* run_listwnd(struct debug_ctx* dctx,
	struct tui_list_entry* list, size_t n_elem, const char* ident, size_t* pos)
{
	struct tui_list_entry* ent = NULL;
	arcan_tui_update_handlers(dctx->tui,
		&(struct tui_cbcfg){
			.bchunk = bchunk,
			.tag = dctx
		}, NULL, sizeof(struct tui_cbcfg));
	arcan_tui_listwnd_setup(dctx->tui, list, n_elem);
	arcan_tui_ident(dctx->tui, ident);
	if (pos)
		arcan_tui_listwnd_setpos(dctx->tui, *pos);

	for(;;){
		struct tui_process_res res = arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL){
				break;
			}
		}

		if (arcan_tui_listwnd_status(dctx->tui, &ent)){
			break;
		}
	}

	if (pos)
		*pos = arcan_tui_listwnd_tell(dctx->tui);
	arcan_tui_listwnd_release(dctx->tui);
	return ent;
}

struct wnd_mitm_opts {
	struct tui_context* tui;
	struct mim_buffer_opts mim_opts;
	int fd;
	bool mitm;
	bool mask;
	bool shutdown;
	char* label;
};

/* using this pattern/wrapper to work both as a new thread and current, for
 * thread it is slightly racy (though this applies in general, as we don't have
 * control over what other threads are doing when the descriptor menu is
 * generated) */
static void* wnd_runner(void* opt)
{
	struct wnd_mitm_opts* mitm = opt;

	if (mitm->mitm){
		setup_mitm(mitm->tui, mitm->fd, mitm->mask, mitm->mim_opts);
	}
	else {
		buf_window(mitm->tui, mitm->fd, mitm->label);
	}

	free(mitm->label);
	if (mitm->shutdown){
		arcan_tui_destroy(mitm->tui, NULL);
	}
	free(mitm);
	return NULL;
}

static void run_mitm(struct tui_context* tui, struct mim_buffer_opts bopts,
	int fd, bool thdwnd, bool mitm, bool mask, const char* label)
{
/* package in a dynamic 'wnd runner' struct */
	struct wnd_mitm_opts* opts = malloc(sizeof(struct wnd_mitm_opts));
	struct tui_context* dtui = tui;

	if (!opts)
		return;

/* enter a request-loop for a new tui wnd, just sidestep the normal tui
 * processing though as we want to be able to switch into a error message
 * buffer window */
	if (thdwnd){
		struct arcan_shmif_cont* c = arcan_tui_acon(tui);
		arcan_shmif_enqueue(c, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_TUI
		});
		struct arcan_event ev;
		while(arcan_shmif_wait(c, &ev)){
			if (ev.category != EVENT_TARGET)
				continue;
/* could be slightly more careful and pair this to a request token, but
 * since we don't use clipboard etc. this is fine */
			if (ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT){
				struct arcan_shmif_cont new =
					arcan_shmif_acquire(c, NULL, SEGID_TUI, 0);

/* note that tui setup copies, it doesn't alias directly so stack here is ok */
				dtui = arcan_tui_setup(&new,
					tui, &(struct tui_cbcfg){}, sizeof(struct tui_cbcfg));

				if (!dtui){
					show_error_message(tui, "Couldn't bind text window");
					return;
				}
				break;
			}
			else if (ev.tgt.kind == TARGET_COMMAND_REQFAIL){
				show_error_message(tui, "Server rejected window request");
				return;
			}
		}
	}

	*opts = (struct wnd_mitm_opts){
		.tui = dtui,
		.fd = fd,
		.mitm = mitm,
		.mask = mask,
		.shutdown = thdwnd,
		.label = strdup(label)
	};

	if (thdwnd){
		pthread_t pth;
		pthread_attr_t pthattr;
		pthread_attr_init(&pthattr);
		pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

		if (-1 == pthread_create(&pth, &pthattr, wnd_runner, opts)){
			arcan_tui_destroy(opts->tui, NULL);
			free(opts->label);
			free(opts);
			show_error_message(tui, "Couldn't spawn new thread for window");
		}
	}
	else
		wnd_runner((void*)opts);
}

static void get_fd_fn(char* buf, size_t lim, int fd)
{
#ifdef __LINUX
	snprintf(buf, 256, "/proc/self/fd/%d", fd);
/* using buf on both arguments should be safe here due to the whole 'need the
 * full path before able to generate output' criteria, but explicitly terminate
 * on truncation */
	char buf2[256];
	int rv = readlink(buf, buf2, 255);
	if (rv <= 0){
		snprintf(buf, 256, "error: %s", strerror(errno));
	}
	else{
		buf2[rv] = '\0';
		snprintf(buf, 256, "%s", buf2);
	}
#else
	snprintf(buf, 256, "Couldn't Resolve");
/* BSD: resolve to pathname if possible F_GETPATH */
#endif
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
	char buf[256];

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

		if (-1 == fstat(fds[i], &dents[used].stat)){
/* mark the stat as failed but remember the descriptor and write down */
			if (fds[i] > 2){
				lents[used].attributes |= LIST_PASSIVE;
				snprintf(lbl_prefix, lbl_len,
					"%4d[](fail): %s", fds[i], strerror(errno));
			}
			else {
				snprintf(lbl_prefix, lbl_len, "[    ](fail): %s", strerror(errno));
			}
		}
/* resolve more data */
		else {
			char scratch[8] = {0, 0, 0, 0, 0, 0, 0, 0};
			fd_to_flags(scratch, fds[i]);
			if (-1 == can_intercept(&dents[used].stat) && fds[i] > 2)
				lents[used].attributes |= LIST_PASSIVE;
			get_fd_fn(buf, 256, fds[i]);
			if (fds[i] > 2){
				snprintf(lbl_prefix, lbl_len, "%4d[%s](%s)\t: %s",
					fds[i], scratch, stat_to_str(&dents[used].stat), buf);
			}
			else
				snprintf(lbl_prefix, lbl_len, "[%s](%s)\t: %s",
					scratch, stat_to_str(&dents[used].stat), buf);
		}

/* prefix STDIO */
		if (fds[i] <= 2){
			char buf2[256];
			snprintf(buf2, 256, "%s", lbl_prefix);
			switch(fds[i]){
			case STDIN_FILENO:
				snprintf(lbl_prefix, lbl_len, "<DIN%s", buf2);
			break;
			case STDOUT_FILENO:
				snprintf(lbl_prefix, lbl_len, "OUT>%s", buf2);
			break;
			case STDERR_FILENO:
				snprintf(lbl_prefix, lbl_len, "ERR>%s", buf2);
			break;
			}
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
	struct tui_list_entry* ent =
		run_listwnd(dctx, lents, count, "open descriptors", NULL);

	if (ent){
		int icept = can_intercept(&dents[ent->tag].stat);
		dctx->last_fd = dents[ent->tag].fd;
		get_fd_fn(buf, 256, dents[ent->tag].fd);
		run_descriptor(dctx, dents[ent->tag].fd, icept, buf);
		dctx->last_fd = -1;
	}

	for (size_t i = 0; i < count; i++){
		free(lents[i].label);
	}

	free(fds);
	free(lents);

/* finished with the buffer window, rebuild the list */
	if (ent){
		gen_descriptor_menu(dctx);
	}
}

/* we don't want full execvpe kind of behavior here as path might be
 * messed with, so just use a primitive list */
static char* find_exec(const char* fname)
{
	static const char* const prefix[] = {"/usr/local/bin", "/usr/bin", ".", NULL};
	size_t ind = 0;

	while(prefix[ind]){
		char* buf	= NULL;
		if (-1 == asprintf(&buf, "%s/%s", prefix[ind++], fname))
			continue;

		struct stat fs;
		if (-1 == stat(buf, &fs)){
			free(buf);
			continue;
		}

		return buf;
	}

	return NULL;
}

enum spawn_action {
	SPAWN_SHELL = 0,
	SPAWN_DEBUG_GDB = 1,
	SPAWN_DEBUG_LLDB = 2
};

static const char* spawn_action(struct debug_ctx* dctx,
	char* action, struct arcan_shmif_cont* c, struct arcan_event ev)
{
	static const char* err_not_found = "Couldn't find executable";
	static const char* err_couldnt_spawn = "Couldn't spawn child process";
	static const char* err_read_pid = "Child didn't return a pid";
	static const char* err_build_env = "Out of memory on building child env";
	static const char* err_build_pipe = "Couldn't allocate control pipes";
	const char* err = NULL;

/* attach foreplay here requires that:
 *
 * 1. pipes gets inherited (both read and write)
 * 2. afsrv_terminal does the tty foreplay (until the day we have gdb/lldb FEs
 *    that just uses tui entirely, in those cases the handshake can be done
 *    here, writes the child pid into its 'PIDFD_OUT'.
 * 3. we run prctl and set this child as the tracer.
 *
 * The idea of racing the pid to get the tracer role after the debugger has
 * detached shouldn't be possible (see LSM_HOOK on task_free which runs
 * yama_ptracer_del in the kernel source).
 *
 * The other tactic that is a bit more precise and not require the terminal as
 * a middle man by ptracing() through each new process. stop on-enter into
 * ptrace and do the same read/write dance.
 */
	char* exec_path = find_exec("afsrv_terminal");
	char* argv[] = {"afsrv_terminal", NULL};
	if (!exec_path)
		return err_not_found;

	if (!action){
/* spawn detached that'll ensure a double-fork like condition,
 * meaning that the pid should be safe to block-wait on */

		struct sigaction oldsig;
		sigaction(SIGCHLD, &(struct sigaction){}, &oldsig);

		pid_t pid =
			arcan_shmif_handover_exec(c, ev, exec_path, argv, NULL, true);

		while(pid != -1 && -1 == waitpid(pid, NULL, 0)){
			if (errno != EINTR)
				break;
		}
		sigaction(SIGCHLD, &oldsig, NULL);

		free(exec_path);
		if (-1 == pid)
			return err_couldnt_spawn;

		return NULL;
	}

/* remove any existing tracer */
#ifdef __LINUX
#ifdef PR_SET_PTRACER
	prctl(PR_SET_PTRACER, 0, 0, 0, 0);
#endif
#endif

/* rest are much more involved, start with some communication pipes
 * and handover environment - normal signalling etc. doesn't work for
 * error detection and the fork detach from handover_exec */
	int fdarg_out[2];
	int fdarg_in[2];

/* grab the pipe pairs that will be inherited into the child */
	if (-1 == pipe(fdarg_out)){
		return err_build_pipe;
	}

	if (-1 == pipe(fdarg_in)){
		close(fdarg_out[0]);
		close(fdarg_out[1]);
		return err_build_pipe;
	}

/* cloexec- off our end of the descriptors */
	int flags = fcntl(fdarg_out[1], F_GETFD);
	if (-1 != flags)
		fcntl(fdarg_out[1], F_SETFD, flags | FD_CLOEXEC);
	flags = fcntl(fdarg_in[0], F_GETFD);
	if (-1 != flags)
		fcntl(fdarg_in[0], F_SETFD, flags | FD_CLOEXEC);

/* could've done this less messier on the stack .. */
	char* envv[5] = {0};
	err = err_build_env;
	if (-1 == asprintf(&envv[0], "ARCAN_TERMINAL_EXEC=%s", action)){
		envv[0] = NULL;
		goto out;
	}

	if (-1 == asprintf(&envv[1], "ARCAN_TERMINAL_ARGV=-p %d", (int)getpid())){
		envv[1] = NULL;
		goto out;
	}

	if (-1 == asprintf(&envv[2], "ARCAN_TERMINAL_PIDFD_OUT=%d", fdarg_in[1])){
		envv[2] = NULL;
		goto out;
	}

	if (-1 == asprintf(&envv[3], "ARCAN_TERMINAL_PIDFD_IN=%d", fdarg_out[0])){
		envv[3] = NULL;
		goto out;
	}

/* handover-execute the terminal */
	struct sigaction oldsig;
	sigaction(SIGCHLD, &(struct sigaction){}, &oldsig);

	pid_t pid = arcan_shmif_handover_exec(c, ev, exec_path, argv, envv, true);
	while(pid != -1 && -1 == waitpid(pid, NULL, 0)){
		if (errno != EINTR)
			break;
	}
	sigaction(SIGCHLD, &oldsig, NULL);
	free(exec_path);

	close(fdarg_out[0]);
	close(fdarg_in[1]);

/* wait for the pid argument */
	pid_t inpid = -1;
	char inbuf[8] = {0};
	ssize_t nr;
	while (-1 == (nr = read(fdarg_in[0], &inpid, sizeof(pid_t)))){
		if (errno != EAGAIN && errno != EINTR)
			break;
	}

	if (-1 == nr){
		err = err_read_pid;
		goto out;
	}

/* enable the tracer, doesn't look like we can do this for the BSDs atm.
 * but use the same setup / synch path anyhow - for testing purposes,
 * disable the protection right now */

#ifdef __LINUX
#ifdef PR_SET_PTRACER
	prctl(PR_SET_PTRACER, inpid, 0, 0, 0);
#endif
#endif

/* send the continue trigger */
	uint8_t outc = '\n';
	write(fdarg_out[1], &outc, 1);
	err = NULL;

/* other option here is to have a monitor thread for the descriptor, waiting
 * for that one to fail and use to release a singleton 'being traced' or have
 * an oracle for 'isDebuggerPresent' like behavior */
out:
	for (size_t i = 0; i < 5; i++){
		free(envv[i]);
	}
	close(fdarg_in[0]);
	close(fdarg_out[1]);

	return err;
}

static int run_buffer(struct tui_context* tui, uint8_t* buffer,
	size_t buf_sz, struct tui_bufferwnd_opts opts, const char* title)
{
	int status = 1;
	opts.allow_exit = true;
	arcan_tui_ident(tui, title);
	arcan_tui_bufferwnd_setup(tui, buffer, buf_sz, &opts, sizeof(opts));

	while(1 == (status = arcan_tui_bufferwnd_status(tui))){
		struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL){
				break;
			}
		}
	}

/* return the context to normal, dead-flag will propagate and free if set */
	arcan_tui_bufferwnd_release(tui);
	arcan_tui_update_handlers(tui,
		&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));

	return status;
}

static void gen_spawn_menu(struct debug_ctx* dctx)
{
	struct tui_list_entry lents[] = {
		{
			.label = "Shell",
			.tag = 0,
/*			.attributes = LIST_PASSIVE, */
		},
		{
			.label = "GNU Debugger (gdb)",
			.attributes = LIST_PASSIVE,
			.tag = 1
		},
		{
			.label = "LLVM Debugger (lldb)",
			.attributes = LIST_PASSIVE,
			.tag = 2
		}
	};

/* need to do a sanity check if the binaries are available, if we can actually
 * fork(), exec() etc. based on current sandbox settings and unmask the items
 * that can be used */
	char* gdb = find_exec("gdb");
	if (gdb){
		lents[1].attributes = 0;
		free(gdb);
	}

	char* lldb = find_exec("lldb");
	if (lldb){
		lents[2].attributes = 0;
		free(lldb);
	}

	struct tui_list_entry* ent =
		run_listwnd(dctx, lents, COUNT_OF(lents), "debuggers", NULL);

/* for all of these we need a handover segment as we can't just give the tui
 * context away like this, even though when the debugger connection is setup,
 * we can't really 'survive' anymore as we will just get locked */
	if (!ent)
		return;

/* this will leave us hanging until we get a response from the server side,
 * and other events will be dropped, so this is a very special edge case */
	struct arcan_shmif_cont* c = arcan_tui_acon(dctx->tui);
	arcan_shmif_enqueue(c, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = SEGID_HANDOVER
	});

	struct arcan_event ev;
	pid_t child;
	const char* err = NULL;

	while(arcan_shmif_wait(c, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT){
			char* fn = NULL;
			if (ent->tag == SPAWN_DEBUG_GDB){
				fn = find_exec("gdb");
				if (!fn)
					break;
			}
			else if (ent->tag == SPAWN_DEBUG_LLDB){
				fn = find_exec("lldb");
				if (!fn)
					break;
			}
			err = spawn_action(dctx, fn, c, ev);
			break;
		}
/* notify that the bash request failed revert */
		else if (ev.tgt.kind == TARGET_COMMAND_REQFAIL){
			err = "Server rejected window request";
			break;
		}
	}

	show_error_message(dctx->tui, err);
	gen_spawn_menu(dctx);
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

	struct tui_list_entry* ent =
		run_listwnd(dctx, list, nelem, "environment", NULL);
	if (!ent){
		free_list(list, nelem);
		return;
	}

	char* env = getenv(ent->label);
	if (!env || !(env = strdup(env)))
		return gen_environment_menu(dctx);

	run_buffer(dctx->tui, (uint8_t*) env, strlen(env), (struct tui_bufferwnd_opts){
		.read_only = false,
		.view_mode = BUFFERWND_VIEW_ASCII
	}, ent->label);

	return gen_environment_menu(dctx);
}

int arcan_shmif_debugint_alive()
{
	return atomic_load(&beancounter);
}

#ifdef __LINUX
static int get_yama()
{
	FILE* pf = fopen("/proc/sys/kernel/yama/ptrace_scope", "r");
	int rc = -1;

	if (!pf)
		return -1;

	char inbuf[8];
	if (fgets(inbuf, sizeof(inbuf), pf)){
		rc = strtoul(inbuf, NULL, 10);
	}

	fclose(pf);
	return rc;
}
#endif

static void build_process_str(FILE* fout)
{
/* bufferwnd currently 'misses' a way of taking some in-line formatted string
 * and resolving, the intention was to add that as a tack-on layer and use the
 * offset- lookup coloring to perform that resolution, simple strings for now */
	pid_t cpid = getpid();
	pid_t ppid = getppid();
	if (!fout)
		return;

#ifdef __LINUX
	fprintf(fout, "PID: %zd Parent: %zd\n", (ssize_t) cpid, (ssize_t) ppid);

/* digging around in memory for command-line will hurt too much,
 * fgets also doesn't work due to the many 0 terminated strings */
	char inbuf[4096];
	fprintf(fout, "Cmdline:\n");
	FILE* pf = fopen("/proc/self/cmdline", "r");
	int ind = 0, ofs = 0;
	if (pf){
		while (!feof(pf)){
			int ch = fgetc(pf);
			if (ch == 0){
				inbuf[ofs] = '\0';
				fprintf(fout, "\t%d : %s\n", ind++, inbuf);
				ofs = 0;
			}
			else if (ch > 0){
				if (ofs < sizeof(inbuf)-1){
					inbuf[ofs] = ch;
					ofs++;
				}
			}
		}
		fclose(pf);
	}

/* ptrace status is nice to help figuring out debug status, even if
 * it isn't really a per process attribute as much as systemwide */
	int yn = get_yama();
	switch(yn){
	case -1:
		fprintf(fout, "Ptrace: Couldn't Read\n");
	break;
	case 0:
		fprintf(fout, "Ptrace: Unrestricted\n");
	break;
	case 1:
		fprintf(fout, "Ptrace: Restricted\n");
	break;
	case 2:
		fprintf(fout, "Ptrace: Admin-Only\n");
	break;
	case 3:
		fprintf(fout, "Ptrace: None\n");
	break;
	}

/* PR_GET_CHILD_SUBREAPER
 * PR_GET_DUMPABLE
 * PR_GET_SECCOM
 * mountinfo?
 * oom_score
 * -- not all are cheap enough for synch
 * Status File:
 *  - TracerPid
 *  - Seccomp
 * limits
 */
#else
	fprintf(fout, "PID: %zd Parent: %zd", (ssize_t) cpid, (ssize_t) ppid);
#endif
/* hardening analysis,
 * aslr, nxstack, canaries (also extract canary)
 */
}

static void set_process_window(struct debug_ctx* dctx)
{
/* build a process description string that we periodically update */
	char* buf = NULL;
	size_t buf_sz = 0;
	FILE* outf = open_memstream(&buf, &buf_sz);
	if (!outf)
		return;

/* some options, like nice-level etc. should perhaps also be exposed
 * here in an editable way */

	build_process_str(outf);
	fflush(outf);
	struct tui_bufferwnd_opts opts = {
		.read_only = true,
		.view_mode = BUFFERWND_VIEW_ASCII,
		.wrap_mode = BUFFERWND_WRAP_ACCEPT_LF,
		.allow_exit = true
	};

	run_buffer(dctx->tui, (uint8_t*) buf, buf_sz, opts, "process");
/* check return code and update if commit */

	if (outf)
		fclose(outf);
	free(buf);
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
			.label = "Spawn",
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_SPAWN
		},
/*
 * browse based on current-dir, openat(".") and navigate like that
 *  {
 *  	.label = "Browse",
 *  	.attributes = LIST_HAS_SUB,
 *  	.tag = TAG_CMD_BROWSEFS
 *  },
 */
		{
			.label = "Environment",
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_ENVIRONMENT
		},
		{
			.label = "Process Information",
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_PROCESS
		},
/*
 * this little thing is to allow other tools to attach more entries
 * here, see, for instance, src/tools/adbginject.so that keeps the
 * process locked before continuing.
 */
		{
			.attributes = LIST_HAS_SUB,
			.tag = TAG_CMD_EXTERNAL
		}
	};

	size_t nent = 4;
	struct tui_list_entry* cent = &menu_root[COUNT_OF(menu_root)-1];
	if (dctx->resolver.label){
		cent->label = dctx->resolver.label;
		nent++;
	}

	while(!dctx->dead){
/* update the handlers so there's no dangling handlertbl+cfg */
		if (cent->label){
			cent->attributes = cent->label[0] ? LIST_HAS_SUB : LIST_PASSIVE;
		}

		arcan_tui_update_handlers(dctx->tui,
			&(struct tui_cbcfg){}, NULL, sizeof(struct tui_cbcfg));

		arcan_tui_listwnd_setup(dctx->tui, menu_root, nent);
		arcan_tui_ident(dctx->tui, "root");

		while(!dctx->dead){
			struct tui_process_res res =
				arcan_tui_process(&dctx->tui, 1, NULL, 0, -1);

			if (-1 == arcan_tui_refresh(dctx->tui) && errno == EINVAL){
				dctx->dead = true;
				return;
			}

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
						case TAG_CMD_SPAWN :
							gen_spawn_menu(dctx);
						break;
						case TAG_CMD_ENVIRONMENT :
							gen_environment_menu(dctx);
						break;
						case TAG_CMD_PROCESS :
							set_process_window(dctx);
						break;
						case TAG_CMD_EXTERNAL :
							dctx->resolver.handler(dctx->tui, dctx->resolver.tag);
						break;
					}
				}
/* switch to out-loop that resets the menu */
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

	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(REGISTER),
		.ext.registr = {
			.kind = SEGID_DEBUG
		}
	};

	snprintf(ev.ext.registr.title, 32, "debugif(%d)", (int)getpid());

	arcan_shmif_enqueue(arcan_tui_acon(dctx->tui), &ev);
	root_menu(dctx);

	arcan_tui_destroy(dctx->tui, NULL);
	atomic_fetch_add(&beancounter, -1);
	free(thr);
	return NULL;
}

bool arcan_shmif_debugint_spawn(
	struct arcan_shmif_cont* c, void* tuitag, struct debugint_ext_resolver* res)
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
	struct debug_ctx* hgs = malloc(sizeof(struct debug_ctx));
	if (!hgs)
		return false;

	*hgs = (struct debug_ctx){
		.infd = -1,
		.outfd = -1,
		.cont = *c,
		.tui = arcan_tui_setup(c,
			tuitag, &(struct tui_cbcfg){}, sizeof(struct tui_cbcfg))
	};

	if (res)
		hgs->resolver = *res;

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
