/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <locale.h>
#include <sys/select.h>
#include <sys/time.h> /* for broken systems */

#include "uuterm.h"
#include "ucf.h"

int ucf_load(struct ucf *, const char *);
extern const unsigned char vga_ascii_ucf[];
extern const size_t vga_ascii_ucf_size;

int main(int argc, char *argv[])
{
	struct uuterm t = { };
	struct uudisp d = { };
	struct ucf f = { };
	int tty, max;
	int i, l;
	unsigned char b[256];
	fd_set fds, wfds;
	struct timeval tv;
	void *buf;

	setlocale(LC_CTYPE, "");

	if (ucf_load(&f, getenv("UUTERM_FONT")) < 0
	 && ucf_init(&f, vga_ascii_ucf, vga_ascii_ucf_size) < 0)
		return 1;

	d.cell_w = 8;
	d.cell_h = 16;
	d.font = &f;

	if (uudisp_open(&d) < 0)
		return 1;

	for (i=1; i<argc; i++)
		argv[i-1] = argv[i];
	argv[i-1] = NULL;

	if ((tty = uutty_open(argc > 1 ? argv : NULL, d.w, d.h)) < 0)
		return 1;

	signal(SIGHUP, SIG_IGN);

	if (!(buf = uuterm_buf_alloc(d.w, d.h))) {
		uudisp_close(&d);
		return 1;
	}
	uuterm_replace_buffer(&t, d.w, d.h, buf);
	uuterm_reset(&t);

	for (;;) {
		/* Setup fd_set containing fd's used by display and our tty */
		FD_ZERO(&fds);
		FD_ZERO(&wfds);
		FD_SET(tty, &fds);
		max = uudisp_fd_set(&d, tty, &fds);
		if (d.inlen) FD_SET(tty, &wfds);
		tv.tv_sec = 0;
		tv.tv_usec = 250000;
		if (select(max, &fds, &wfds, NULL, &tv) <= 0) {
			d.blink++;
			FD_ZERO(&fds);
		}

		/* Process input from the tty, up to buffer size */
		if (FD_ISSET(tty, &fds)) {
			if ((l = read(tty, b, sizeof b)) <= 0)
				break;
			for (i=0; i<l; i++) {
				uuterm_stuff_byte(&t, b[i]);
				if (t.reslen) write(tty, t.res, t.reslen);
			}
		}

		/* Write input from previous event */
		if (d.inlen) {
			int l = write(tty, d.intext, d.inlen);
			if (l < 0) l = 0;
			d.intext += l;
			d.inlen -= l;
			d.blink = 1;
		}

		/* Look for events from the display */
		uudisp_next_event(&d, &fds);

		if (d.w != t.w || d.h != t.h) {
			void *newbuf = uuterm_buf_alloc(d.w, d.h);
			if (newbuf) {
				uuterm_replace_buffer(&t, d.w, d.h, newbuf);
				uuterm_free(buf);
				buf = newbuf;
				uutty_resize(tty, d.w, d.h);
			}
		}

		/* If no more input is pending, refresh display */
		FD_ZERO(&fds);
		FD_SET(tty, &fds);
		tv.tv_sec = tv.tv_usec = 0;
		select(max, &fds, NULL, NULL, &tv);
		if (!FD_ISSET(tty, &fds))
			uudisp_refresh(&d, &t);
	}

	uudisp_close(&d);

	return 0;
}
