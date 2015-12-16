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
#include <pwd.h>
#include <signal.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/signal.h>
#include <sys/wait.h>

#include "tsm/libtsm.h"
#include "tsm/shl-pty.h"

struct {
	struct tsm_screen* screen;
	struct tsm_vte* vte;
	struct shl_pty* pty;

	pid_t child;
	int child_fd;

	tsm_age_t age;
} term = {
};

static void tsm_log(void* data, const char* file, int line,
	const char* func, const char* subs, unsigned int sev,
	const char* fmt, va_list arg)
{
	fprintf(stderr, "[%d] %s:%d - %s, %s()\n", sev, file, line, subs, func);
	vfprintf(stderr, fmt, arg);
}

static void read_callback(struct shl_pty* pty,
	void* data, char* u8, size_t len)
{
	tsm_vte_input(term.vte, u8, len);
}

static void write_callback(struct tsm_vte* vte,
	const char* u8, size_t len, void* data)
{
	shl_pty_write(term.pty, u8, len);
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
		shell = pass->pw_shell;
	}

	static const char* unset[] = {
		"COLUMNS", "LINES", "TERMCAP",
	};

	int ind = 0;
	const char* val;

	for (int i=0; i < sizeof(unset)/sizeof(unset[0]); i++)
		unsetenv(unset[i]);

/* might get overridden with putenv below */
	setenv("TERM", "xterm-256color", 1);

	int sigs[] = {
		SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM
	};

	for (int i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
		signal(sigs[i], SIG_DFL);

	char* args[] = {shell, "-i", NULL};

	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

static int draw_cb(struct tsm_screen* screen, uint32_t id,
	const uint32_t* ch, size_t len, unsigned w, unsigned x, unsigned y,
	const struct tsm_screen_attr* attr, tsm_age_t age, void* data)
{
	printf("@%d,%d: %d %c\n", x, y, *ch, isalnum(*ch) ? *ch : ' ');
	return 0;
}

int main(int argc, char** argv)
{
	const char* val;

	if (tsm_screen_new(&term.screen, tsm_log, 0) < 0){
		printf("fatal, couldn't setup tsm screen\n");
		return EXIT_FAILURE;
	}

	if (tsm_vte_new(&term.vte, term.screen, write_callback,
		NULL /* write_cb_data */, tsm_log, NULL /* tsm_log_data */) < 0){
		printf("fatal, couldn't setup vte\n");
		return EXIT_FAILURE;
	}

	tsm_screen_set_max_sb(term.screen, 1000);

	setlocale(LC_CTYPE, "C");
	signal(SIGHUP, SIG_IGN);

	if ( (term.child = shl_pty_open(&term.pty,
		read_callback, NULL, 10, 5)) == 0){
		setup_shell();
		exit(EXIT_FAILURE);
	}

	if (term.child < 0){
		printf("couldn't spawn child terminal.\n");
		return EXIT_FAILURE;
	}

	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;
	int ptyfd = shl_pty_get_fd(term.pty);
	int age = 0;

	tsm_screen_resize(term.screen, 10, 5);
	shl_pty_resize(term.pty, 10, 5);

	while(1){
		int pc = 2;
		struct pollfd fds[3] = {
			{ .fd = ptyfd, .events = pollev},
			{ .fd = STDIN_FILENO, .events = pollev}
		};
		int sv = poll(fds, 2, -1);
		if (fds[0].revents & POLLIN){
			printf("pty - data\n");
			int rc = shl_pty_dispatch(term.pty);
			printf("dispatch: %d\n", rc);
			age = tsm_screen_draw(term.screen, draw_cb, NULL);
			printf("age: %d\n", age);
		} else if (fds[0].revents & POLLHUP){
			printf("pty - hangup\n");
		} else if (fds[0].revents & POLLERR){
			printf("pty - error\n");
		} else if (fds[0].revents & POLLNVAL){
			printf("pty - invalid\n");
		}

		if (fds[1].revents & POLLIN){
			char buf[64];
			ssize_t in = read(STDIN_FILENO, buf, 64);
			if (in > 0){
				shl_pty_write(term.pty, buf, 64);
			}
			int rc = shl_pty_dispatch(term.pty);
		}
	}

	return EXIT_SUCCESS;
}
