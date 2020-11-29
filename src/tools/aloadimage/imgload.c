/*
 * Copyright 2017-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository
 * Reference: http://arcan-fe.com, README.MD
 * Description: fork()+sandbox asynch- image loading wrapper around stbi
 * Bad assumption with a 4 bpp fixed output format (needs revision for
 * float,...) and needs a wider range of sandbox- format supports. If/ when
 * good enough, this can be re-worked into main arcan to replace the _img
 * functions in the main pipeline (though split decode/setup further to
 * account for OSX-like anti-fork() bs).
 */
#include <arcan_shmif.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <signal.h>
#ifdef ENABLE_SECCOMP
#include <sys/prctl.h>
#endif
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <ctype.h>
#ifdef ENABLE_SECCOMP
	#include <seccomp.h>
#endif

#define NANOSVG_IMPLEMENTATION
#define NANOSVG_ALL_COLOR_KEYWORDS
#define NSVG_RGB(r,g,b)( SHMIF_RGBA(r, g, b, 0x00) )
#include "nanosvg.h"
#define NANOSVGRAST_IMPLEMENTATION
#include "nanosvgrast.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#include "imgload.h"

bool imgload_spawn(struct arcan_shmif_cont* con, struct img_state* tgt, int p)
{
/* pre-alloc the upper limit for the return- image, we'll munmap when
 * finished to look less memory hungry */
	if (tgt->out)
		munmap((void*)tgt->out, tgt->buf_lim);
	tgt->buf_lim = image_size_limit_mb * 1024 * 1024;
	tgt->out = mmap(NULL, tgt->buf_lim,
		PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	if (!tgt->out)
		return false;
	memset((void*)tgt->out, '\0', sizeof(struct img_data));

/* aliveness descriptor to multiplex with */
	int pair[2] = {-1, -1};
	pipe(pair);
	tgt->sigfd = pair[1];

/* spawn our worker process */
	tgt->proc = fork();
	if (-1 == tgt->proc){
		munmap((void*)tgt->out, tgt->buf_lim);
		tgt->out = NULL;
		return false;
	}
/* parent */
	else if (0 != tgt->proc)
		return true;

/* start with the most risk- prone, original fopen */
	FILE* inf;
	if (-1 != tgt->fd)
		inf = fdopen(tgt->fd, "r");
	else if (tgt->is_stdin)
		inf = stdin;
	else
		inf = fopen(tgt->fname, "r");

/* close the parent pipes in the safest way possible, if that fails, accept UB
 * and kill the streams (other option would be replacing with memstreams) */
	int nfd = open("/dev/null", O_RDWR);
	if (-1 != nfd){
		if (inf != stdin){
			dup2(nfd, STDIN_FILENO);
		}
		dup2(nfd, STDOUT_FILENO);
		dup2(nfd, STDERR_FILENO);
		close(nfd);
	}
	else{
		if (inf != stdin)
			fclose(stdin);
		fclose(stderr);
		fclose(stdout);
	}

	if (p)
		nice(p);

/* drop shm-con so that it's not around anymore - owning the parser won't grant
 * us direct access to the shm- connection and with the syscalls eliminated, it
 * can't be re-opened */
	if (con){
		munmap(con->addr, con->shmsize);
		close(con->epipe);
		close(con->shmh);
		memset(con, '\0', sizeof(struct arcan_shmif_cont));
	}

/* There is a possiblity of other descriptors being leaked here, e.g. fonts or
 * other playlist items that were retrieved from shmif as cloexec does not
 * apply to fork. The non-portable option would be to dup into 1 and then
 * closefrom(2).
 *
 * The 'correct' option would be to track and manually close.
 *
 * The more tedious approach would be to have a re-exec mode, re-exec ourselves,
 * mmap the buffer to decode into and go from there.
 *
 * Now, we accept the risk of the contents of other descriptors being
 * accessible from the sandbox, though the more serious configurations (seccmp)
 * should block out most means to do anything as long as a descriptor defined
 * playlist item doesn't come from a file.
 *
 * It is also possible to leak some information as a lot of the memory pages of
 * our parent, env, copy of stack etc. Hence why the sandbox should not have any
 * write channel (though cache- timing invalidation style side channel
 * communication is also a possibility).
 */

/* someone might've needed to be careless and run as root. Now we have the file
 * so that shouldn't matter. If these call fail, they fail - it's added safety,
 * not a guarantee. */
	if (-1 == setgid(65534)){}
	if (-1 == setuid(65534)){}

/* set some limits that will make things worse even if we don't have seccmp */
	setrlimit(RLIMIT_CORE, &(struct rlimit){});
	setrlimit(RLIMIT_FSIZE, &(struct rlimit){});
	setrlimit(RLIMIT_NOFILE, &(struct rlimit){});
	setrlimit(RLIMIT_NPROC, &(struct rlimit){});

#ifdef __OpenBSD__
	if(-1 == pledge("stdio", "")){
		_exit(EXIT_FAILURE);
	}

#endif

#ifdef ENABLE_SECCOMP
	if (!disable_syscall_flt){
		prctl(PR_SET_NO_NEW_PRIVS, 1);
		prctl(PR_SET_DUMPABLE, 0);
		scmp_filter_ctx flt = seccomp_init(SCMP_ACT_KILL);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(brk), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(exit), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(fstat), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(read), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(munmap), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(lseek), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(exit_group), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(close), 0);
		seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(write), 0);
//	seccomp_rule_add(flt, SCMP_ACT_ALLOW, SCMP_SYS(rt_sigreturn), 0);
		seccomp_load(flt);
	}
#endif

/* now we're in the dangerous part, stbi_load_from_file - though the source is
 * just a filestream, we need to return the decoded buffer somehow. STBI may
 * need intermediate allocations and we can't really tell, so unfortunately we
 * waste an extra memcpy.
 *
 * Decent optimizations needed here and not in place now:
 * 1. custom 'upper limit' malloc so we can drop the mmap/brk/munmap syscalls
 * 2. patch stbi- to use a separate allocator for our output buffer so
 *    that the decode writes directly to tgt->out->buf, saving us a
 *    memcpy.
 * 3. pre-mmaping file and using stbi-load-from-memory could drop the
 *    fstat/read/lseek syscalls as well.
 *
 * The custom allocator will likely also be needed for this to work in a
 * multithreaded setting.
 *
 * the repacking is done to make sure that the channel-order matches the shmif
 * format as we don't have controls for specifying that in stbi- right now
 */

/* peek on the first characters and see if we have xml/svg */
	char hdr[8];
	if (1 != fread(hdr, 8, 1, inf))
		exit(EXIT_FAILURE);
	if (strncmp(hdr, "<?xml", 5) == 0 || strncmp(hdr, "<svg", 4) == 0){
		fseek(inf, 0, SEEK_SET);
		NSVGimage* image = nsvgParseFromFile(inf, "px", tgt->density);
		if (image){
			size_t w = image->width;
			size_t h = image->height;
			struct NSVGrasterizer* rast = nsvgCreateRasterizer();
			nsvgRasterize(rast, image,
				0, 0, 1, (unsigned char*)tgt->out->buf, w, h, w * sizeof(shmif_pixel));
			tgt->out->w = w;
			tgt->out->h = h;
			tgt->out->buf_sz = w * h * 4;
			tgt->out->vector = true;
			tgt->out->ready = true;
			tgt->out->msg[0] = '\0';
			exit(EXIT_SUCCESS);
		}
	}

/* else just assume stbi- can handle it */
	fseek(inf, 0, SEEK_SET);

	int dw, dh;
	shmif_pixel* buf = (shmif_pixel*)
		stbi_load_from_file(inf, &dw, &dh, NULL, sizeof(shmif_pixel));
	shmif_pixel* out = (shmif_pixel*) tgt->out->buf;
	tgt->out->w = dw;
	tgt->out->h = dh;
	tgt->out->buf_sz = dw * dh * 4;
	tgt->out->msg[0] = '\0';

	if (buf){
		for (size_t i = dw * dh; i > 0; i--){
			uint8_t r = ((*buf) & 0x000000ff);
			uint8_t g = ((*buf) & 0x0000ff00) >> 8;
			uint8_t b = ((*buf) & 0x00ff0000) >> 16;
			uint8_t a = ((*buf) & 0xff000000) >> 24;
			buf++;
			*out++ = SHMIF_RGBA(r, g, b, a);
		}
		tgt->out->ready = true;
		exit(EXIT_SUCCESS);
	}
	else{
		size_t i = 0;
		for (; i < sizeof(tgt->out->msg) && stbi__g_failure_reason[i]; i++)
			tgt->out->msg[i] = stbi__g_failure_reason[i];
	}
	exit(EXIT_FAILURE);
}

static void mark_finished(struct img_state* tgt, bool broken)
{
	tgt->broken = broken;
	if (-1 != tgt->sigfd){
		close(tgt->sigfd);
		tgt->sigfd = -1;
	}
}

bool imgload_poll(struct img_state* tgt)
{
	if (!tgt->proc || !tgt->out)
		return true;

	int sc = 0;
	int rc;
	while ((rc = waitpid(tgt->proc, &sc, WNOHANG)) == -1 && errno == EINTR){}
/* failed */
	if (rc == -1){
		snprintf((char*)tgt->msg, sizeof(tgt->msg), "(%s)", strerror(errno));
		mark_finished(tgt, true);
		return true;
	}

/* nothing new */
	if (rc == 0)
		return false;

/* client tries to exceed buffer, signs of a troublemaker */
	size_t out_sz = tgt->out->buf_sz;
	if (out_sz > tgt->buf_lim){
		munmap((void*)tgt->out, tgt->buf_lim);
		tgt->proc = 0;
		tgt->out = NULL;
		snprintf((char*)tgt->msg, sizeof(tgt->msg),
			"(%zuMiB>%zuMiB)",
			(out_sz+1) / (1024 * 1024),
			(tgt->buf_lim+1) / (1024 * 1024)
		);
		mark_finished(tgt, true);
		return true;
	}

/* copy+filter error message on failure */
	if (sc != EXIT_SUCCESS){
		size_t i = 0, j = 0;
		uint8_t ch;
		while (j < sizeof(tgt->msg)-1 &&
			i < sizeof(tgt->out->msg) && (ch = tgt->out->msg[i])){
			if (isprint(ch))
				tgt->msg[j++] = ch;
			i++;
		}
		debug_message("%s failed, (reason: %s)\n", tgt->fname, tgt->msg);
		munmap((void*)tgt->out, tgt->buf_lim);
		tgt->out = NULL;
		tgt->buf_lim = 0;
		mark_finished(tgt, true);
		return true;
	}
	tgt->proc = 0;
	tgt->out->x = tgt->out->y = 0;

/* unmap extra data, align with page size */
	uintptr_t system_page_size = sysconf(_SC_PAGE_SIZE);
	uintptr_t base = (uintptr_t) tgt->out;
	uintptr_t end = base + sizeof(struct img_data) + out_sz;
	if (end % system_page_size != 0)
		end += system_page_size - end % system_page_size;

/* if fork/exec/... are not closed off, there's the sigbus possiblity left,
 * though DOS isn't much of a threat model here, our real worry is code-exec */
	size_t ntr = tgt->buf_lim - (end - base);
/* Odd case where we we couldn't poke hole in the mapping, simply skip the
 * truncate step. This affects accounting in playlists slightly */
	if (0 == munmap((void*) end, ntr))
		tgt->buf_lim -= ntr;

	debug_message("%s loaded (total: %zu, max: %zu, remove: %zu\n",
		tgt->fname, out_sz, tgt->buf_lim, ntr);

	mark_finished(tgt, false);
	return true;
}
/*
 * reset the contents of imgload so that it can be used for a new imgload_spawn
 * only run after imgload_poll has returned true once.
 */
void imgload_reset(struct img_state* tgt)
{
	if (tgt->proc){
		debug_message("reset on living source, killing: %s\n", tgt->fname);
		kill(tgt->proc, SIGKILL);
		while (-1 == waitpid(tgt->proc, NULL, 0) && errno == EINTR){}
		tgt->proc = 0;
	}

	tgt->broken = false;
	if (tgt->out){
		munmap((void*)tgt->out, tgt->buf_lim);
		tgt->out = NULL;
		tgt->buf_lim = 0;
	}
}
