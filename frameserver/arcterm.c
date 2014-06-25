/*
 * Arcan Terminal
 * Heavily derived from ST (suckless.org) X/MIT License.
 * UTF8 conversion code, escape encoding / decoding etc. refactored from st
 * Rendering etc. written to use arcan font format strings
 */

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <locale.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>

#if defined(__linux) 
#include <pty.h>
#elif defined(__OpenBSD__) || defined(__APPLE__)
	#include <util.h>
#else
	#include <libutil.h>
#endif

#include <pwd.h>

#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/signal.h>
#include <sys/wait.h>

#include <arcan_shmif.h>

static struct arcan_shmif_cont shmcont;

static struct {
	pid_t pid;
	int child;
} term = {0};

static unsigned char utflut[5] = {
	0x80, 0x00, 0xC0, 0xE0, 0xF0
};

static unsigned char utfmask[5] = {
	0xc0, 0x80, 0xe0, 0xf0, 0xf8
};

static size_t utf8dec(char* ch, long* u, size_t chlen)
{
	return 0;
}

static size_t valid_utf8(long* u, size_t i)
{
	return 0;
}

static size_t utf8enc(long u, char* ch, size_t chlen)
{
	size_t len;

	len = valid_utf8(&u, 0);
	if (chlen < len)
		return 0;

	for(int i = len - 1; i != 0; --i){
		ch[i] = utflut[i] | (u & ~utfmask[0]);
		u >>= 6;
	}

	ch[0] = utflut[len] | (u & ~utfmask[len]);
	return len;
}

static void child_sigh(int a)
{
	int status = 0;
	if (waitpid(term.pid, &status, 0) < 0){
		LOG("Waiting for child %d failed, reason: %s\n",
			term.pid, strerror(errno));
	}
}

static void setup_shell()
{
	char* shell = getenv("SHELL");
	const struct passwd* pass = getpwuid( getuid() );
	if (pass){
		setenv("LOGNAME", pass->pw_name, 1);
		setenv("USER", pass->pw_name, 1);
		setenv("SHELL", pass->pw_shell, 0);
		setenv("HOME", pass->pw_dir, 0);
	}

	unsetenv("COLUMNS");
	unsetenv("LINES");
	unsetenv("TERMCAP");

	int sigs[] = {
		SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM
	};

	setenv("TERM", shell, 1);
	for (int i = 0; i < sizeof(sigs); i++)
		signal(sigs[i], SIG_DFL);

	char* args[] = {shell, "-i", NULL};

	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

static void launchtty()
{
	int master, slave;
	struct winsize w_sz = {80, 25, 0, 0};

	if (openpty(&master, &slave, NULL, NULL, &w_sz) < 0){
		LOG("open_pty failed: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

	term.pid = fork();
	if (term.pid == -1){
		LOG("fork() subshell failed: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

	if (term.pid == 0){
		setsid();
		dup2(slave, STDIN_FILENO);
		dup2(slave, STDOUT_FILENO);
		dup2(slave, STDERR_FILENO);
		close(slave);
		close(master);

		setup_shell();
		exit(EXIT_FAILURE);
	}

	close(slave);
	term.child = master;
	signal(SIGCHLD, child_sigh);
/* opt_io?! term-mode |= MODE_PRINT, opt_io == "-", open etc. */
}

/*
static void disable_shell()
{
	kill(term.pid, SIGHUP);
	exit(EXIT_SUCCESS);
}
*/

static void pop_inbuf(int fd)
{
	static char inbuf[4096];
	static int inbuf_len = 0;

	char* tail = inbuf;
	char s[5] = {0};
	size_t s_sz;
	long ucodep;
	int rc;

/*
 * populate incoming buffer with enough data,
 * sweep the buffer and consume complete utf8 sequences,
 * emit to interpreter one character at a time
 */
	size_t ntr = sizeof(inbuf) / sizeof(inbuf[0]) - inbuf_len;
retry:
	if ( (rc = read(fd, inbuf + inbuf_len, ntr) < 0) ){
		if (errno == EINTR)
			goto retry;
		LOG("couldn't read from shell, reason: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

	inbuf_len += rc;
	while((s_sz = utf8dec(tail, &ucodep, inbuf_len))){
		utf8enc(ucodep, s, 4);
		printf("got %s\n", s);
		tail += s_sz;
		inbuf_len -= s_sz;
	}

/* slide static buffer */
	memmove(inbuf, tail, inbuf_len);
}

void arcan_frameserver_terminal_run(const char* resource, const char* keyfile)
{
	shmcont = arcan_shmif_acquire(keyfile, SHMIF_OUTPUT, true, false);
	if (!shmcont.addr){
		LOG("fatal, couldn't map shared memory from (%s)\n", keyfile);
	}

	int font_w = 16;
	int font_h = 8;

	setlocale(LC_CTYPE, "");
	signal(SIGHUP, SIG_IGN);
	arcan_shmif_resize(&shmcont, 80 * font_w, 25 * font_h);

	launchtty();

	fd_set fds;

	while(true){
		FD_ZERO(&fds);
		FD_SET(term.child, &fds);

		struct timeval tv = {
			.tv_sec = 0,
			.tv_usec = 250000
		};

		if (select(1, &fds, NULL, NULL, &tv) <= 0){
/* timeout, blink */
			if (errno == EINTR)
				continue;
		}

		if (FD_ISSET(term.child, &fds)){
/* read, interpret, update rows */
			pop_inbuf(term.child);
		}

		arcan_event ev;
		while (arcan_event_poll(&shmcont.inev, &ev) == 1){
		}

		uint32_t* vidp = (uint32_t*) shmcont.vidp;

		for (int row = 0; row < shmcont.addr->h; row++)
			for (int col = 0; col < shmcont.addr->w; col++){
				*vidp++ = RGBA(12, 24, 48, 0xff);
			}

		arcan_shmif_signal(&shmcont, SHMIF_SIGVID);
	}
}

