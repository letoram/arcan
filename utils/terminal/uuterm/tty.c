/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#define _XOPEN_SOURCE 500

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/ioctl.h>

void uutty_resize(int fd, int w, int h)
{
#ifdef TIOCSWINSZ
	struct winsize ws = { };
	ws.ws_col = w;
	ws.ws_row = h;
	ioctl(fd, TIOCSWINSZ, &ws);
#endif
}

/* #define posix_openpt(x) open("/dev/ptmx", x) */

int uutty_open(char **cmd, int w, int h)
{
	int ptm, pts;
	struct stat st;

	if (!cmd || !cmd[0] || stat(cmd[0], &st) < 0
	 || !S_ISCHR(st.st_mode)
	 || (ptm = open(cmd[0], O_RDWR|O_NOCTTY)) < 0
	 || (isatty(ptm) ? 0 : (close(ptm),1)) ) {

		if ((ptm = posix_openpt(O_RDWR|O_NOCTTY)) < 0)
			return -1;
		if (grantpt(ptm) < 0 || unlockpt(ptm) < 0) {
			close(ptm);
			return -1;
		}

		switch(fork()) {
		case -1:
			close(ptm);
			return -1;
		case 0:
			setsid();
			pts = open(ptsname(ptm), O_RDWR);
			close(ptm);
			dup2(pts, 0);
			dup2(pts, 1);
			dup2(pts, 2);
			if (pts > 2) close(pts);
			// FIXME............................
			if (cmd) execvp(cmd[0], cmd);
			else {
				char *s = getenv("SHELL");
				if (!s) s = "/bin/sh";
				execl(s, s, (char *)0);
			}
			_Exit(1);
		}
	
		uutty_resize(ptm, w, h);
	}

	fcntl(ptm, F_SETFL, fcntl(ptm, F_GETFL)|O_NONBLOCK);

	return ptm;
}
