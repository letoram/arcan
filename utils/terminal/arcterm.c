#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <locale.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/signal.h>

#include <arcan_shmif.h>

#include "uuterm/uuterm.h"
#include "uuterm/ucf.h"
#include "uuterm/dblbuf.h"

extern const unsigned char vga_ascii_ucf[];
extern const size_t vga_ascii_ucf_size;

struct {
	struct arcan_shmif_cont shmcont;
	struct dblbuf dbuf;
} termctx;

/*
 * this is built and run as a regular avfeed frameserver
 * but using the arcan_frameserver_avfeed namespace.
 */
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
{
	struct ucf font = {0};
	setlocale(LC_CTYPE, "");
	if (ucf_load(&font, getenv("ARCTERM_FONT")) < 0
		&& ucf_init(&font, vga_ascii_ucf, vga_ascii_ucf_size) < 0){
		LOG("fatal, couldn't load any font.\n");
		return;
	}

	termctx.shmcont = arcan_shmif_acquire(keyfile, SHMIF_OUTPUT, true, false);
	if (!termctx.shmcont.addr){
		LOG("fatal, couldn't map shared memory from (%s)\n", keyfile);
	}

	struct uuterm term = {0};
	struct uudisp disp = {
		.w = 8,
		.h = 16
	};

	int tty, len;

	fd_set fds, wfds;
	struct timeval tv;
	char buf[256];
	
	if ( (tty = uutty_open(NULL, disp.w, disp.h)) < 0){
		LOG("fatal, couldn't open tty.\n");
		return;
	}

	signal(SIGHUP, SIG_IGN);
	unsigned char* dispbuf = malloc(UU_BUF_SIZE(disp.w, disp.h) * 4);
	uuterm_replace_buffer(&term, disp.w, disp.h, dispbuf);

	termctx.dbuf.slices = dblbuf_setup_buf(80, 25, 
		4 * disp.w, disp.h, dispbuf); 

	arcan_shmif_resize(&termctx.shmcont, disp.w * 80, disp.h * 25);

	while(true){
		FD_ZERO(&fds);
		FD_ZERO(&wfds);
		FD_SET(tty, &fds);

/* add the regular incoming event queue to the FD set */
		tv.tv_sec = 0;
		tv.tv_usec = 250000;

/* use select timer as an extra for updating cursor blink as well */
		if (select(1, &fds, &wfds, NULL, &tv) <= 0){
			disp.blink++;
			FD_ZERO(&fds);
		}

/* got some data on terminal, forward it one byte at a time, and if
 * we know that something relevant has changed, redraw and signal display */	
		if (FD_ISSET(tty, &fds)){
			if ((len = read(tty, buf, sizeof(buf))) <= 0)
				break;

			for (int i = 0; i < len; i++){
				uuterm_stuff_byte(&term, buf[i]);
				if (term.reslen)
					write(tty, term.res, term.reslen);
			}
		}

/* check arcan event loop;
 *
 * use to get additional characters to push to terminal.
 * use message to inject multiple (paste)
 * use transfer-FD to inject file into terminal context,
 * use transfer-FD to get file from terminal context
 */
		uudisp_refresh(&disp, &term);
		memcpy(termctx.shmcont.vidp, dispbuf, UU_BUF_SIZE(disp.w, disp.h) * 4);
		arcan_shmif_signal(&termctx.shmcont, SHMIF_SIGVID);
	}	
}

