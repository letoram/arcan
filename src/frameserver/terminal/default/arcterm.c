#include <arcan_shmif.h>
#include <stdio.h>
#include <arcan_tui.h>
#include <inttypes.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <pwd.h>
#include <ctype.h>
#include <signal.h>
#include <pthread.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

#include "cli.h"
#include "cli_builtin.h"

#include "tsm/libtsm.h"
#include "tsm/libtsm_int.h"
#include "tsm/shl-pty.h"
#include "b64dec.h"
#include "../../../shmif/tui/tui_int.h"

#ifdef SALLOW_ST
extern int st_tui_main(struct arcan_shmif_cont* con, struct arg_arr* args);
#endif

#define debug_log

struct t_line {
	size_t count;
	struct tui_cell* cells;
};

enum pipe_modes {
/* just forward from in-out and draw the visible characters into screen */
	PIPE_RAW = 0,

/* pipe-raw but respect line-feed characters */
	PIPE_PLAIN_LF = 1,

/* treat as utf8 with a sliding window on decode fail */
	PIPE_UTF8 = 2,

/* only show minimal information about the transfer itself */
	PIPE_STATS_BASIC = 3
};

static struct {
	struct tui_context* screen;

	struct tsm_vte* vte;
	struct shl_pty* pty;
	struct arg_arr* args;

	pthread_mutex_t synch;
	pthread_mutex_t hold;

	pid_t child;

	_Atomic volatile bool alive;
	_Atomic volatile int defer_resize;

/* track re-execute (reset) as well as working with stdin/stdout forwarding */
	bool die_on_term;
	bool complete_signal;
	bool pipe;
	int keep_stderr; /* 'saved' stderr descriptor if desired */
	size_t bytes_in;
	size_t bytes_out;
	uint8_t u8_buf[4];
	volatile uint8_t pipe_mode;

/* if the terminal has 'died' and 'fit' is set - we crop the stored
 * buffer to bounding box of 'real' (non-whitespace content) cells */
	bool fit_contents;
	struct {
		size_t rows;
		size_t cols;
	} initial_hint;

/* when the terminal has died and !die_on_term, we need to be able
 * to re-populate the contents on resize since the terminal state machine
 * itself won't be able to anymore - so save this here */
	struct t_line** volatile _Atomic restore;
	size_t restore_cxy[2];

/* if the client provides large b64 encoded data through OSC */
	volatile struct {
		uint8_t* buf;
		size_t buf_sz;
	} pending_bout;

/* sockets to communicate between terminal thread and render thread */
	int dirtyfd;
	int signalfd;

} term = {
	.die_on_term = true,
	.synch = PTHREAD_MUTEX_INITIALIZER,
	.hold = PTHREAD_MUTEX_INITIALIZER
};

static void reset_restore_buffer()
{
	struct t_line** cur = atomic_load(&term.restore);
	atomic_store(&term.restore, NULL);

	if (!cur)
		return;

	for(size_t i = 0; cur[i]; i++){
		if (cur[i]->count)
			free(cur[i]->cells);
		free(cur[i]);
	}

	free(cur);
}

extern void tuiint_flag_cursor(struct tui_context* tui);

static void apply_restore_buffer()
{
	arcan_tui_erase_screen(term.screen, false);
	struct t_line** cur = atomic_load(&term.restore);
	if (!cur)
		return;

	size_t rows, cols;
	arcan_tui_dimensions(term.screen, &rows, &cols);

	for (size_t row = 0; row < rows && cur[row]; row++){
		tsm_screen_move_to(term.screen->screen, 0, row);
		struct tui_cell* cells = cur[row]->cells;
		size_t n = cur[row]->count;

		for (size_t i = 0; i < n && i < cols; i++){
			struct tui_cell* c= &cells[i];
			uint32_t ch = c->draw_ch ? c->draw_ch : c->ch;
			tsm_screen_write(term.screen->screen, ch, &c->attr);
		}
	}

	tsm_screen_move_to(
		term.screen->screen, term.restore_cxy[0], term.restore_cxy[1]);
	tuiint_flag_cursor(term.screen);
}

static void create_restore_buffer(bool refit)
{
	reset_restore_buffer();
	size_t rows, cols;
	if (!term.screen)
		return;

	arcan_tui_dimensions(term.screen, &rows, &cols);
	size_t bufsz = sizeof(struct t_line*) * (rows + 1);
	struct t_line** buffer = malloc(bufsz);
	memset(buffer, '\0', bufsz);

	term.restore_cxy[0] = tsm_screen_get_cursor_x(term.screen->screen);
	term.restore_cxy[1] = tsm_screen_get_cursor_y(term.screen->screen);

	size_t max_row = 0;
	size_t max_col = 0;

	for (size_t row = 0; row < rows; row++){
		buffer[row] = malloc(sizeof(struct t_line));
		if (!buffer[row])
			goto fail;

		bufsz = sizeof(struct tui_cell) * cols;
		struct tui_cell* cells = malloc(bufsz);

		if (!cells)
			goto fail;

		buffer[row]->cells = cells;
		buffer[row]->count = cols;

		memset(cells, '\0', bufsz);
		bool row_dirty = false;

		for (size_t col = 0; col < cols; col++){
			struct tui_cell cell = arcan_tui_getxy(term.screen, col, row, true);

			uint32_t ch = cell.draw_ch ? cell.draw_ch : cell.ch;
			row_dirty |= ch && ch != ' ';

			if (ch && ch != ' ' && max_col < col+1)
					max_col = col+1;

			cells[col] = cell;
		}

		if (row_dirty)
			max_row = row+1;
	}

	if (refit){
		if (max_row && max_col){
/* so that we can 're-fit' on a reset when fit_contents has already been sent */
			if (!term.initial_hint.rows || !term.initial_hint.cols){
				term.initial_hint.rows = rows;
				term.initial_hint.cols = cols;
			}

			arcan_tui_wndhint(term.screen, NULL, (struct tui_constraints){
				.max_rows = max_row, .min_rows = max_row,
				.max_cols = max_col, .min_cols = max_col
			});
		}

/* should we mark that the buffer is empty? */
	}

	atomic_store(&term.restore, buffer);
	return;

fail:
	atomic_store(&term.restore, buffer);
	reset_restore_buffer();
	term.die_on_term = true;
}

static inline void trace(const char* msg, ...)
{
#ifdef TRACE_ENABLE
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
	fprintf(stderr, "\n");
#endif
}

extern int arcan_tuiint_dirty(struct tui_context* tui);

static ssize_t flush_buffer(int fd, char dst[static 4096])
{
	ssize_t nr = read(fd, dst, 4096);
	if (-1 == nr){
		if (errno == EAGAIN || errno == EINTR)
			return -1;

		atomic_store(&term.alive, false);
		arcan_tui_set_flags(term.screen, TUI_HIDE_CURSOR);

		return -1;
	}
	return nr;
}

static bool synch_quit(int fd)
{
	char buf[256];
	ssize_t nr = read(fd, buf, 256);
	for (ssize_t i = 0; i < nr; i++)
		if (buf[i] == 'q')
			return true;

	return false;
}

static void flush_ascii(uint8_t* buf, size_t nb, bool raw)
{
	size_t pos = 0;

	while (pos < nb){
		if (isascii(buf[pos])){
			if (!raw && buf[pos] == '\n')
				arcan_tui_newline(term.screen);
			else
				arcan_tui_write(term.screen, buf[pos], NULL);
		}
		pos++;
	}
}

static void write_number(size_t num)
{
	arcan_tui_printf(term.screen, NULL, "MISSING");
}

static void flush_stats()
{
	arcan_tui_erase_screen(term.screen, false);
	arcan_tui_move_to(term.screen, 0, 0);
	arcan_tui_printf(term.screen, NULL, "In: ");
	write_number(term.bytes_in);
	arcan_tui_move_to(term.screen, 0, 1);
	arcan_tui_printf(term.screen, NULL, "Out: ");
	write_number(term.bytes_out);
}

static void flush_utf8(uint8_t* buf, size_t nb)
{
	arcan_tui_move_to(term.screen, 0, 0);
	arcan_tui_printf(term.screen, NULL, "MISSING-U8");
}

static void flush_out(uint8_t* buf, size_t* left, size_t* ofs, int fdout, bool* die)
{
	struct pollfd set[] = {
		{.fd = fdout, .events = POLLOUT},
		{.fd = term.dirtyfd, .events = POLLIN}
	};

	if (!*left)
		return;

	if (-1 == poll(set, 2, *die ? 0 : -1))
		return;

	if (set[1].revents && synch_quit(term.dirtyfd)){
		*die = true;
		return;
	}

/* flushing out is allowed to be blocking unless >die< is already set */
	ssize_t nw = 0;
	if (set[0].revents)
		nw = write(fdout, &buf[*ofs], *left);

	if (nw < 0){
		if (errno != EAGAIN && errno != EINTR){
			*die = true;
		}
		return;
	}

	term.bytes_out += nw;
	if (term.pipe_mode == PIPE_STATS_BASIC)
		flush_stats();

	*left -= nw;
	*ofs += nw;

/* tail recurse until flushed or the >die< trigger gets set */
	return flush_out(buf, left, ofs, fdout, die);
}

static bool readout_pty(int fd)
{
	char buf[4096];
	bool got_hold = false;
	ssize_t nr = flush_buffer(fd, buf);

	if (nr < 0)
		return false;

	if (nr == 0)
		return true;

	if (0 != pthread_mutex_trylock(&term.synch)){
		pthread_mutex_lock(&term.hold);
		write(term.dirtyfd, &(char){'1'}, 1);
		pthread_mutex_lock(&term.synch);
		got_hold = true;
	}

	tsm_vte_input(term.vte, buf, nr);
	term.screen->dirty |= DIRTY_PARTIAL;

/* We could possibly also match against parser state, or specific total timeout
 * before breaking out and releasing the terminal - the reason for this
 * complicated scheme is to try and balance latency vs throughput vs tearing */
	size_t w, h;
	arcan_tui_dimensions(term.screen, &h, &w);
	ssize_t cap = w * h * 4;
	while (nr > 0 && cap > 0 && 1 == poll(
		(struct pollfd[]){ {.fd = fd, .events = POLLIN } }, 1, 0)){
		nr = flush_buffer(fd, buf);
		if (nr > 0){
			tsm_vte_input(term.vte, buf, nr);
			cap -= nr;
		}
	}

	if (got_hold){
		pthread_mutex_unlock(&term.hold);
	}
	pthread_mutex_unlock(&term.synch);

	return true;
}

/*
 * In 'pipe' mode we just buffer in from the fake-pty (exec) and from STDIN,
 * flush to STDOUT and update the 'view' with either statistics or some
 * filtered version of the data itself.
 */
static void* pump_pipe()
{
	uint8_t buffer[4096];
	size_t left = 0;
	size_t ofs = 0;
	bool die = false;
	int out_dst = STDOUT_FILENO;

	struct pollfd set[] = {
		{.fd = shl_pty_get_fd(term.pty, false), .events = POLLIN | POLLERR | POLLNVAL | POLLHUP},
		{.fd = STDIN_FILENO, .events = POLLIN},
		{.fd = term.dirtyfd, .events = POLLIN},
	};

/* The reason for having the signaling socket alive here still is also to allow
 * for a future 'detach' mode where an input label allows us to let the stdio
 * mapping remain and drop the ability to inspect - i.e. just fork / splice */
	while (atomic_load(&term.alive) && !die){
		if (left){
/* we can get here if the incoming pipe or pty dies, then we should still flush */
			flush_out(buffer, &left, &ofs, out_dst, &die);
			continue;
		}

		if (-1 == poll(set, sizeof(set) / sizeof(set[0]), -1))
			continue;

/* Signal to quit takes priority as it might mean reset and then the data is
 * considered outdated and the pty will be closed */
		if (set[2].revents && synch_quit(term.dirtyfd)){
			die = true;
			break;
		}

		ssize_t nr = 0;

/* Then flushing pty takes priority so that we don't block on backpressure,
 * and we show the output of the pty routing */
		if (set[0].revents & POLLIN){
			nr = read(set[0].fd, buffer, 4096);

			if (nr > 0){
				term.bytes_in += nr;

/* different pipe modes have different agendas here, and we might want to
 * be able to toggle representation (RAW, UTF8/whitespace, statistics) */
				switch(term.pipe_mode){
					case PIPE_RAW:
						flush_ascii(buffer, nr, true);
					break;
					case PIPE_PLAIN_LF:
						flush_ascii(buffer, nr, false);
					break;
					case PIPE_STATS_BASIC:
						flush_stats();
					break;
					case PIPE_UTF8:
						flush_utf8(buffer, nr);
					break;
				}
				left = nr;
				ofs = 0;
				out_dst = STDOUT_FILENO;
				continue;
			}
		}

/* If the data >COMES< from STDIN we have to route to the PTY, which may bounce
 * back or it may perform some kind of processing - this could've safely been a
 * separate thread, but then would face problems with 'reset' state synch in the
 * same way we use the signalling socket now */
		if (nr <= 0 && (set[1].revents & POLLIN)){
			nr = read(set[1].fd, buffer, 4096);
			if (nr > 0){
				left = nr;
				ofs = 0;
				out_dst = shl_pty_get_fd(term.pty, true);
				continue;
			}
		}

/* Then if the dies we should give up, not if STDIN does as the pty can
 * still emit data as a function of previous input (decompression for instance).
 * STDOUT is checked in the flush out routine below */
		if (nr <= 0){
			if (set[1].revents & (POLLERR | POLLNVAL | POLLHUP)){
				die = true;
				break;
			}
			continue;
		}
	}

/* allow flush out unless we have received a 'quit now' */
	flush_out(buffer, &left, &ofs, out_dst, &die);

/* could possibly check what is mapped on stdin, proc-scrape the backing store
 * and figure out if it is possible to grok the size - but hardly worth it */
	arcan_tui_progress(term.screen, TUI_PROGRESS_INTERNAL, 1.0);

	write(term.dirtyfd, &(char){'Q'}, 1);
	atomic_store(&term.alive, false);

	return NULL;
}

static void* pump_pty()
{
	int fd = shl_pty_get_fd(term.pty, false);
	short pollev = POLLIN | POLLERR | POLLNVAL | POLLHUP;

	struct pollfd set[2] = {
		{.fd = fd, .events = pollev},
		{.fd = term.dirtyfd, pollev},
	};

	while (atomic_load(&term.alive)){
/* dispatch might just flush whatever is queued for writing, which can come from
 * the callbacks in the UI thread */
		if (atomic_load(&term.defer_resize)){
			size_t rows, cols;
			atomic_fetch_add(&term.defer_resize, -1);
			arcan_tui_dimensions(term.screen, &rows, &cols);
			shl_pty_resize(term.pty, cols, rows);
		}

		shl_pty_dispatch(term.pty);

		if (-1 == poll(set, 2, 30))
			continue;

/* tty determines lifecycle */
		if (set[0].revents){
			if (!readout_pty(fd) || (set[0].revents & POLLHUP))
				break;
		}

/* flush signal / wakeup, quit if we got that value as we might need to reset */
		if (set[1].revents && synch_quit(set[1].fd))
			break;
	}

	write(term.dirtyfd, &(char){'Q'}, 1);
	return NULL;
}

static void dump_help()
{
	fprintf(stdout, "Environment variables: \nARCAN_CONNPATH=path_to_server\n"
		"ARCAN_TERMINAL_EXEC=value : run value through /bin/sh -c instead of shell\n"
		"ARCAN_TERMINAL_ARGV : exec will route through execv instead of execvp\n"
		"ARCAN_TERMINAL_PIDFD_OUT : writes exec pid into pidfd\n"
		"ARCAN_TERMINAL_PIDFD_IN  : exec continues on incoming data\n\n"
	  "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n"
		"Accepted packed_args:\n"
		"    key      \t   value   \t   description\n"
		"-------------\t-----------\t-----------------\n"
		" env         \t key=val   \t override default environment (repeatable)\n"
		" chdir       \t dir       \t change working dir before spawning shell\n"
		" bgalpha     \t rv(0..255)\t opacity (default: 255, opaque) - deprecated\n"
		" ci          \t ind,r,g,b \t override palette at index\n"
		" blink       \t ticks     \t set blink period, 0 to disable (default: 12)\n"
		" login       \t [user]    \t login (optional: user, only works for root)\n"
#ifndef FSRV_TERMINAL_NOEXEC
		" exec        \t cmd       \t allows arcan scripts to run shell commands\n"
#endif
		" keep_alive  \t           \t don't exit if the terminal or shell terminates\n"
		" keep_stderr \t           \t forward whatever [stderr] is into the child\n"
		"             \t           \t and disable logging for afsrv_terminal\n"
		" autofit     \t           \t (with exec, keep_alive) shrink window to fit\n"
		" record      \t fname     \t record everything in main window in tpackani fmt\n"
		" pipe        \t [mode]    \t map stdin-stdout (mode: raw, lf)\n"
		" palette     \t name      \t use built-in palette (below)\n"
		" cli         \t [lua]     \t switch to non-vt cli/builtin shell mode\n"
		" cursor      \t [style]   \t set default cursor: block, bar, underline, hollow\n"
#ifdef SALLOW_ST
		" interp      \t [tsm,st]  \t specify emulator state machine\n"
#endif
		"Built-in palettes:\n"
		"default, solarized, solarized-black, solarized-white, srcery\n"
		"-------------\t-----------\t----------------\n\n"
		"Cli mode (pty-less) specific args:\n"
		"    key      \t   value   \t   description\n"
		"-------------\t-----------\t-----------------\n"
		" env         \t key=val   \t override default environment (repeatable)\n"
		" mode        \t exec_mode \t arcan, wayland, x11, vt100 (default: vt100)\n"
#ifndef FSRV_TERMINAL_NOEXEC
		" oneshot     \t           \t use with exec, shut down after evaluating command\n"
		"-------------\t-----------\t----------------\n"
#endif
	);
}

static void sighuph(int num)
{
	if (term.pty)
		term.pty = (shl_pty_close(term.pty), NULL);
}

static void on_mouse_motion(struct tui_context* c,
	bool relative, int x, int y, int modifiers, void* t)
{
	trace("mouse motion(%d:%d, mods:%d, rel: %d",
		x, y, modifiers, (int) relative);

	if (!relative){
		tsm_vte_mouse_motion(term.vte, x, y, modifiers);
	}
}

static void on_mouse_button(struct tui_context* c,
	int last_x, int last_y, int button, bool active, int modifiers, void* t)
{
	trace("mouse button(%d:%d - @%d,%d (mods: %d)\n",
		button, (int)active, last_x, last_y, modifiers);
	tsm_vte_mouse_button(term.vte, button, active, modifiers);
}

static void on_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint16_t mods, uint16_t subid, void* t)
{
	trace("on_key(%"PRIu32",%"PRIu8",%"PRIu16")", keysym, scancode, subid);
	if (term.pipe)
		return;

	tsm_vte_handle_keyboard(term.vte,
		keysym, isascii(keysym) ? keysym : 0, mods, subid);
}

static bool on_u8(struct tui_context* c, const char* u8, size_t len, void* t)
{
/* special little nuance here is that this goes straight to the descriptor,
 * so there might be some conflict with queueing if we paste a large block */
	if (write(shl_pty_get_fd(term.pty, true), u8, len) < 0
		&& errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
		atomic_store(&term.alive, false);
	}

	return true;
}

static void on_utf8_paste(struct tui_context* c,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	trace("utf8-paste(%s):%d", str, (int) cont);
	tsm_vte_paste(term.vte, (char*)str, len);
}

static unsigned long long last_frame;

static void on_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	create_restore_buffer(false);
}

static void on_resized(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	trace("resize(%zu(%zu),%zu(%zu))", neww, col, newh, row);

	if (atomic_load(&term.restore) && !term.alive){
		apply_restore_buffer();
	}

	atomic_fetch_add(&term.defer_resize, 1);
	last_frame = 0;
}

static void write_callback(struct tsm_vte* vte,
	const char* u8, size_t len, void* data)
{
	shl_pty_write(term.pty, u8, len);
}

static void str_callback(struct tsm_vte* vte, enum tsm_vte_group group,
	const char* msg, size_t len, bool crop, void* data)
{
/* parse and see if we should set title */
	if (!msg || len < 3 || crop){
		debug_log(vte,
			"bad OSC sequence, len = %zu (%s)\n", len, msg ? msg : "");
		return;
	}

/* 0, 1, 2 : set title */
	if ((msg[0] == '0' || msg[0] == '1' || msg[0] == '2') && msg[1] == ';'){
		arcan_tui_ident(term.screen, &msg[2]);
		return;
	}

/* Clipboard controls
 *
 * Ps = 5 2
 *
 * param 1 : (zero or more of cpqs0..7), ignore and default to c
 * param 2 : ? (paste) or base64encoded content, otherwise 'reset'
 *
 * this (should) come base64 */
	if (len > 5 && msg[0] == '5' && msg[1] == '2' && msg[2] == ';'){
		size_t i = 3;

/* skip to second argument */
		for (; i < len-1 && msg[i] != ';'; i++){}
		i++;

		if (i >= len){
			debug_log(vte, "OSC 5 2 sequence overflow\n");
			return;
		}

/* won't be shared with other clients so it is rather pointless to have paste,
 * we could practically announce any bin-io as capable input, keep it around
 * and on paste- request deal with it - but serial transfer this way is pain */
		if (msg[i] == '?'){
			debug_log(vte, "OSC 5 2 paste unsupported\n");
			return;
		}

		size_t outlen;
		uint8_t* outb = from_base64((const uint8_t*)&msg[i], &outlen);
		if (!outb){
			debug_log(vte, "OSC 5 2 bad base64 encoding\n");
			return;
		}

/* there are multiple paths we might need to take dependent on the contents,
 * if it is not a proper string or too long we can only really announce it as
 * a bchunk */
		size_t pos = 0;
		for (;outb[pos] && pos < outlen; pos++){}
		bool is_terminated = pos < outlen && !outb[pos];

/* if it actually behaves and looks like short utf8- go with that */
		if (is_terminated && outlen < 8192){
			if (arcan_tui_copy(term.screen, (const char*) outb)){
				free(outb);
				return;
			}
		}

/* from_base64 always adds null-termination here, even when we might not want it */
		outlen--;

/* otherwise send as an immediate file transfer request rather than clipboard */
		if (term.pending_bout.buf)
			free(term.pending_bout.buf);
		term.pending_bout.buf = outb;
		term.pending_bout.buf_sz = outlen;

		arcan_tui_announce_io(term.screen, true, NULL, "bin");
		return;
	}

	debug_log(vte,
		"%d:unhandled OSC command (PS: %d), len: %zu\n",
		vte->log_ctr++, (int)msg[0], len
	);
}

static char* get_shellenv()
{
	char* shell = getenv("SHELL");

	if (!getenv("PATH"))
		setenv("PATH", "/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin", 1);

	const struct passwd* pass = getpwuid( getuid() );
	if (pass){
		setenv("LOGNAME", pass->pw_name, 1);
		setenv("USER", pass->pw_name, 1);
		setenv("SHELL", pass->pw_shell, 0);
		setenv("HOME", pass->pw_dir, 0);
		shell = pass->pw_shell;
	}

	/* some safe default should it be needed */
	if (!shell)
		shell = "/bin/sh";

/* will be exec:ed so don't worry to much about leak or mgmt */
	return shell;
}

static char* group_expand(struct group_ent* group, const char* in)
{
	return strdup(in);
}

static char** build_argv(char* appname, char* instr)
{
	struct group_ent groups[] = {
		{.enter = '"', .leave = '"', .expand = group_expand},
		{.enter = '\0', .leave = '\0', .expand = NULL}
	};

	struct argv_parse_opt opts = {
		.prepad = 1,
		.groups = groups,
		.sep = ' '
	};

	ssize_t err_ofs = -1;
	char** res = extract_argv(instr, opts, &err_ofs);
	if (res)
		res[0] = appname;

	return res;
}

static void setup_shell(struct arg_arr* argarr, char* const args[])
{
	static const char* unset[] = {
		"COLUMNS", "LINES", "TERMCAP",
		"ARCAN_ARG", "ARCAN_APPLPATH", "ARCAN_APPLTEMPPATH",
		"ARCAN_FRAMESERVER_LOGDIR", "ARCAN_RESOURCEPATH",
		"ARCAN_SHMKEY", "ARCAN_SOCKIN_FD"
	};

	int ind = 0;
	const char* val;

	for (int i=0; i < sizeof(unset)/sizeof(unset[0]); i++)
		unsetenv(unset[i]);

/* set some of the common UTF-8 default envs, shell overrides if needed */
	setenv("LANG", "en_GB.UTF-8", 0);
	setenv("LC_CTYPE", "en_GB.UTF-8", 0);

/* FIXME: check what we should do with PWD, SHELL, TMPDIR, TERM, TZ,
 * DATEMSK, LINES, LOGNAME(portable set), MSGVERB, PATH */

/* might get overridden with putenv below, or if we are exec:ing /bin/login */
#ifdef __OpenBSD__
	setenv("TERM", "wsvt25", 1);
#else
	setenv("TERM", "xterm-256color", 1);
#endif

	while (arg_lookup(argarr, "env", ind++, &val))
		putenv(strdup(val));

	if (arg_lookup(argarr, "chdir", 0, &val)){
		chdir(val);
	}

#ifndef NSIG
#define NSIG 32
#endif

/* so many different contexts and handover methods needed here and not really a
 * clean 'ok we can get away with only doing this', the arcan-launch setups
 * need argument passing in env, the afsrv_cli need re-exec with argv in argv,
 * and some specialized features like debug handover may need both */
	char* exec_arg = getenv("ARCAN_TERMINAL_EXEC");

#ifdef FSRV_TERMINAL_NOEXEC
	if (arg_lookup(argarr, "exec", 0, &val)){
		LOG("permission denied, noexec compiled in");
	}
#else
	if (arg_lookup(argarr, "exec", 0, &val)){
		exec_arg = strdup(val);
		arcan_tui_ident(term.screen, exec_arg);
	}
#endif

	sigset_t sigset;
	sigemptyset(&sigset);
	pthread_sigmask(SIG_SETMASK, &sigset, NULL);

	for (size_t i = 1; i < NSIG; i++)
		signal(i, SIG_DFL);

/* special case, ARCAN_TERMINAL_EXEC skips the normal shell setup */
	if (exec_arg){
		char* inarg = getenv("ARCAN_TERMINAL_ARGV");
		char* args[] = {"/bin/sh", "-c" , exec_arg, NULL};

		const char* pidfd_in = getenv("ARCAN_TERMINAL_PIDFD_IN");
		const char* pidfd_out = getenv("ARCAN_TERMINAL_PIDFD_OUT");

/* forward our new child pid to the _out fd, and then blockread garbage */
		if (pidfd_in && pidfd_out){
			int infd = strtol(pidfd_in, NULL, 10);
			int outfd = strtol(pidfd_out, NULL, 10);
			pid_t pid = getpid();
			write(outfd, &pid, sizeof(pid));
			read(infd, &pid, 1);
			close(infd);
			close(outfd);
		}

/* inherit some environment, filter the things we used */
		unsetenv("ARCAN_TERMINAL_EXEC");
		unsetenv("ARCAN_TERMINAL_PIDFD_IN");
		unsetenv("ARCAN_TERMINAL_PIDFD_OUT");
		unsetenv("ARCAN_TERMINAL_ARGV");

/* two different forms of this, one uses the /bin/sh -c route with all the
 * arguments in the packed exec string, the other splits into a binary and
 * an argument, the latter matters */
		if (inarg)
			execvp(exec_arg, build_argv(exec_arg, inarg));
		else
			execv("/bin/sh", args);

		exit(EXIT_FAILURE);
	}

	execvp(args[0], args);
	exit(EXIT_FAILURE);
}

/*
static bool on_subst(struct tui_context* tui,
	struct tui_cell* cells, size_t n_cells, size_t row, void* t)
{
	bool res = false;
	for (size_t i = 0; i < n_cells-1; i++){
 */
/* far from an optimal shaping rule, but check for special forms of continuity,
 * 3+ of (+_-) like shapes horizontal or vertical, n- runs of whitespace or
 * vertical similarities in terms of whitespace+character
 */
/*
		if ( (isspace(cells[i].ch) && isspace(cells[i+1].ch)) ){
			cells[i].attr.aflags |= TUI_ATTR_SHAPE_BREAK;
			res = true;
		}
	}

	return res;
}
*/

static void on_exec_state(struct tui_context* tui, int state, void* tag)
{
	if (state == 0)
		shl_pty_signal(term.pty, SIGCONT);
	else if (state == 1)
		shl_pty_signal(term.pty, SIGSTOP);
	else if (state == 2)
		shl_pty_signal(term.pty, SIGHUP);
}

static bool setup_build_term()
{
	size_t rows = 0, cols = 0;
	arcan_tui_reset(term.screen);
	tsm_vte_hard_reset(term.vte);
	arcan_tui_dimensions(term.screen, &rows, &cols);
	term.complete_signal = false;

/* just to re-use the same interfaces in the case where we want exec and
 * just control stdin/stdout versus a full posix_openpt */
	if (term.pipe)
		term.child = shl_pipe_open(&term.pty, true);
	else
		term.child = shl_pty_open(&term.pty, NULL, NULL, cols, rows, term.keep_stderr);

	if (term.child < 0){
		arcan_tui_destroy(term.screen, "Shell process died unexpectedly");
		return false;
	}

/*
 * and lastly, spawn the pseudo-terminal
 */
/* we're inside child */
	if (term.child == 0){
		const char* val;
		char* argv[] = {get_shellenv(), "-i", NULL, NULL};

		if (arg_lookup(term.args, "cmd", 0, &val) && val){
			argv[2] = strdup(val);
		}

/* special case handling for "login", this requires root */
		if (arg_lookup(term.args, "login", 0, &val)){
			struct stat buf;
			argv[1] = "-p";
			if (stat("/bin/login", &buf) == 0 && S_ISREG(buf.st_mode))
				argv[0] = "/bin/login";
			else if (stat("/usr/bin/login", &buf) == 0 && S_ISREG(buf.st_mode))
				argv[0] = "/usr/bin/login";
			else{
				LOG("login prompt requested but none was found\n");
				return EXIT_FAILURE;
			}
		}

		setup_shell(term.args, argv);
		return EXIT_FAILURE;
	}

/* spawn a thread that deals with feeding the tsm specifically, then we run
 * our normal event look constantly in the normal process / refresh style. */
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	atomic_store(&term.alive, true);

/* with pipe- mode, we want stdout to be non-blocking */
	if (term.pipe){
		if (-1 == pthread_create(&pth, &pthattr, pump_pipe, NULL)){
			int flags = fcntl(STDOUT_FILENO, F_GETFL);
			fcntl(STDOUT_FILENO, flags | O_NONBLOCK);
			atomic_store(&term.alive, false);
			return EXIT_FAILURE;
		}
	}
	else {
		if (-1 == pthread_create(&pth, &pthattr, pump_pty, NULL)){
			atomic_store(&term.alive, false);
			return EXIT_FAILURE;
		}
	}

	return true;
}

static void on_reset(struct tui_context* tui, int state, void* tag)
{
/* this state needs to be verified against pledge etc. as well since some
 * of the foreplay might become impossible after privsep */

	switch (state){
/* soft, just state machine + tui */
	case 0:
		arcan_tui_reset(tui);
		tsm_vte_hard_reset(term.vte);
	break;

/* hard, try to re-execute command, send HUP if still alive then mark as dead */
	case 1:
		reset_restore_buffer();
		tsm_vte_hard_reset(term.vte);

/* hang-up any existing terminal, tell the current process thread to give up
 * and wait for that to be acknowledged. */
		if (atomic_load(&term.alive)){
			on_exec_state(tui, 2, tag);
			char q = 'q';
			write(term.dirtyfd, &q, 1);
			while (q != 'Q'){
				read(term.dirtyfd, &q, 1);
			}
			atomic_store(&term.alive, false);
		}

		if (!term.die_on_term){
			arcan_tui_progress(term.screen, TUI_PROGRESS_INTERNAL, 0.0);
		}

		if (term.initial_hint.rows && term.initial_hint.cols){
			arcan_tui_wndhint(term.screen, NULL, (struct tui_constraints){
				.max_rows = term.initial_hint.rows, .min_rows = term.initial_hint.rows,
				.max_cols = term.initial_hint.cols, .min_cols = term.initial_hint.cols
			});
		}

		shl_pty_close(term.pty);
		setup_build_term();
	break;

/* crash, ... ? do nothing */
	default:
	break;
	}

/* reset vte state */
}

struct labelent;
struct labelent {
	void (* handler)(struct labelent* self);
	bool disabled;
	int tag;
	struct tui_labelent ent;
};

static void force_autofit(struct labelent* S)
{
	bool old_fit = term.fit_contents;
	term.fit_contents = true;
	create_restore_buffer(term.fit_contents);
	term.fit_contents = old_fit;
}

static void set_pipe(struct labelent* S)
{
	arcan_tui_erase_screen(term.screen, false);
	term.pipe_mode = S->tag;
}

static struct labelent labels[] =
{
	{
		.handler = force_autofit,
		.ent =
		{
			.label = "AUTOFIT",
			.descr = "Resize window to buffer contents",
			.initial = TUIK_F1,
			.modifiers = TUIM_LSHIFT
		}
	},
	{
		.handler = set_pipe,
		.disabled = true,
		.tag = PIPE_RAW,
		.ent =
		{
			.label = "VIEW_RAW",
			.descr = "Show pipe output in window as unfiltered",
			.initial = TUIK_F1
		},
	},
	{
		.handler = set_pipe,
		.disabled = true,
		.tag = PIPE_RAW,
		.ent =
		{
			.label = "VIEW_RAW_LF",
			.descr = "Show pipe output in window as unfiltered, respect linefeed",
			.initial = TUIK_F1
		},
	},
	{
		.handler = set_pipe,
		.disabled = true,
		.tag = PIPE_PLAIN_LF,
		.ent =
		{
			.label = "VIEW_UTF8",
			.descr = "Convert input to UTF8, mark invalid values",
			.initial = TUIK_F2
		}
	},
	{
		.handler = set_pipe,
		.disabled = true,
		.tag = PIPE_STATS_BASIC,
		.ent =
		{
			.label = "VIEW_STATS",
			.descr = "Only show read/written/pending",
			.initial = TUIK_F3
		}
	},
};

static bool on_label_query(
	struct tui_context* T,
	size_t index, const char* country, const char* lang,
	struct tui_labelent* dstlbl, void* t)
{
	size_t current = 0;
	size_t ti = index;

/* poor complexity in this search but few entries */
	for (size_t i = 0; i < COUNT_OF(labels); i++){
		if (labels[i].disabled)
			continue;

		if (index - current)
			current++;
		else{
			*dstlbl = labels[i].ent;
			return true;
		}
	}

	return legacy_query_label(T, index-current, dstlbl);
}

static bool on_label_input(
	struct tui_context* T, const char* label, bool active, void* tag)
{
	if (!active)
		return true;

	for (size_t i = 0; i < COUNT_OF(labels); i++){
		if (strcmp(label, labels[i].ent.label) == 0 && !labels[i].disabled){
			labels[i].handler(&labels[i]);
			return true;
		}
	}

	return legacy_consume_label(T, label);

	return false;
}

static void on_bchunk(struct tui_context* c,
	bool input, uint64_t size, int fd, const char* tag, void* t)
{
	if (input || !term.pending_bout.buf)
		return;

/* blocking rather dumb, but it is really just for OSC 5 2 */
	FILE* fpek = fdopen(fd, "w+");
	fwrite(term.pending_bout.buf, term.pending_bout.buf_sz, 1, fpek);
	fclose(fpek);
	free(term.pending_bout.buf);
	term.pending_bout.buf = NULL;
}

static int parse_color(const char* inv, uint8_t outv[4])
{
	return sscanf(inv, "%"SCNu8",%"SCNu8",%"SCNu8",%"SCNu8,
		&outv[0], &outv[1], &outv[2], &outv[3]);
}

static void on_relative(struct tui_context* c, ssize_t dy, ssize_t dx, void* tag)
{
	if (dx < 0)
		arcan_tui_scroll_up(c, -1 * dy);
	else
		arcan_tui_scroll_down(c, dy);
}

static bool copy_palette(struct tui_context* tc, uint8_t* out)
{
	uint8_t ref[3] = {0, 0, 0};
	for (size_t i = TUI_COL_TBASE; i < TUI_COL_LIMIT; i++){
		size_t ofs = (i - TUI_COL_TBASE) * 3;
		arcan_tui_get_color(tc, i, &out[ofs]);
	}

/* special hack, the bg color for the reserved-1 slot will be set if we
 * have received an upstream palette */
	arcan_tui_get_bgcolor(tc, 1, ref);
	return ref[0] == 255;
}

static void on_tick(struct tui_context* c, void* tag)
{
	if (c->in_select && c->scrollback != 0){
		if (c->scrollback < 0){
			if (c->scrollback < -1)
				c->scrollback++;
			else{
				arcan_tui_scroll_up(c, abs(c->scrollback));
				c->dirty |= DIRTY_FULL;
			}
		}
		else
			if (c->scrollback > 1)
				c->scrollback--;
			else{
				arcan_tui_scroll_down(c, c->scrollback);
				c->dirty |= DIRTY_FULL;
			}
	}
}

int cursor_style_arg(struct arg_arr* args)
{
	const char* val;
/* more possible modes needed here, UTF8, stats */
	if (!arg_lookup(args, "cursor", 0, &val) || !val)
		return CURSOR_BLOCK;

	if (strcmp(val, "underline") == 0)
		return CURSOR_UNDER;
	else if (strcmp(val, "hollow") == 0)
		return CURSOR_HOLLOW;
	else if (strcmp(val, "bar") == 0)
		return CURSOR_BAR;

	return CURSOR_BLOCK;
}

int afsrv_terminal(struct arcan_shmif_cont* con, struct arg_arr* args)
{
	if (!con)
		return EXIT_FAILURE;

	const char* val;
/* more possible modes needed here, UTF8, stats */
	if (arg_lookup(args, "pipe", 0, &val)){
		term.pipe = true;
		if (val && strcmp(val, "lf") == 0)
			term.pipe_mode = PIPE_PLAIN_LF;
	}

/* save stderr to a specific descriptor that gets inherited into the new
 * subprocess (and survives resets), remove our ability to write into it */
	if (arg_lookup(args, "keep_stderr", 0, &val)){
		term.keep_stderr = dup(STDERR_FILENO);
		fcntl(term.keep_stderr, F_SETFD, FD_CLOEXEC);

		int ndev = open("/dev/null", O_WRONLY);
		dup2(ndev, STDERR_FILENO);
		close(ndev);
	}

/*
 * this is the first migration part we have out of the normal vt- legacy,
 * see cli.c
 */
	if (arg_lookup(args, "cli", 0, &val)){
		if (val && strcmp(val, "lua") == 0)
			return arcterm_luacli_run(con, args);
		else
			return arcterm_cli_run(con, args);
	}

#ifdef SALLOW_ST
	if (arg_lookup(args, "interp", 0, &val)){
		if (val && strcmp(val, "st") == 0){
			return st_tui_main(con, args);
		}
	}
#endif

	if (arg_lookup(args, "help", 0, &val)){
		dump_help();
		return EXIT_SUCCESS;
	}
/*
 * this table act as both callback- entry points and a list of features that we
 * actually use. So binary chunk transfers, video/audio paste, geohint etc.
 * are all ignored and disabled
 */
	struct tui_cbcfg cbcfg = {
		.input_mouse_motion = on_mouse_motion,
		.input_mouse_button = on_mouse_button,
		.query_label = on_label_query,
		.input_label = on_label_input,
		.input_utf8 = on_u8,
		.input_key = on_key,
		.bchunk = on_bchunk,
		.utf8 = on_utf8_paste,
		.resize = on_resize,
		.resized = on_resized,
		.exec_state = on_exec_state,
		.reset = on_reset,
		.seek_relative = on_relative,
		.tick = on_tick
/*
 * for advanced rendering, but not that interesting
 * .substitute = on_subst
 */
	};

	term.screen = arcan_tui_setup(con, NULL, &cbcfg, sizeof(cbcfg));

	if (!term.screen){
		fprintf(stderr, "failed to setup TUI connection\n");
		return EXIT_FAILURE;
	}
	arcan_tui_allow_deprecated(term.screen);
	arcan_tui_cursor_style(term.screen, cursor_style_arg(args), NULL);

/* make a preroll- state copy of legacy-palette range */
	uint8_t palette_copy[TUI_COL_LIMIT * 3];
	bool custom_palette = copy_palette(term.screen, palette_copy);

	term.args = args;

/*
 * Now we have the display server connection and the abstract screen,
 * configure the terminal state machine. This will override the palette
 * that might be inside tui, so rebuild from our copy.
 */
	if (tsm_vte_new(&term.vte, term.screen, write_callback, NULL) < 0){
		arcan_tui_destroy(term.screen, "Couldn't setup terminal emulator");
		return EXIT_FAILURE;
	}

/*
 * allow the window state to survive, terminal won't be updated but
 * other tui behaviors are still valid
 */
	if (arg_lookup(args, "keep_alive", 0, NULL)){
		term.die_on_term = false;
		arcan_tui_progress(term.screen, TUI_PROGRESS_INTERNAL, 0.0);
	}

/*
 * inject the event before anything is actually up and running, this
 * uses symbols internal to our tui implementation - for other settings
 * it is better to simply send the event during preroll as normal
 */
	if (arg_lookup(args, "record", 0, &val) && val){
		int fd = open(val, O_WRONLY | O_CREAT, 0600);
		if (-1 != fd){
			tui_event_inject(term.screen, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_BCHUNK_OUT,
				.tgt.ioevs[0] = fd,
				.tgt.message = "tuiani"
			});
			close(fd);
		}
		else{
			LOG("record=%s : couldn't create file for tuiani out\n", val);
		}
	}

/*
 * when the keep_alive state is entered, try and shrink the window
 * to the bounding box of the contents itself
 */
	if (arg_lookup(args, "autofit", 0, NULL)){
		term.fit_contents = true;
	}

/* if a command-line palette override is set, apply that - BUT if there was
 * custom color overrides defined during preroll (tui_setup) those take
 * precedence */
	if (arg_lookup(args, "palette", 0, &val)){
		tsm_vte_set_palette(term.vte, val);
	}

/* synch back custom colors */
	if (custom_palette){
		for (size_t i = 0; i < VTE_COLOR_NUM; i++){
			tsm_vte_set_color(term.vte, i, &palette_copy[i * 3]);
		}
	}

/* DEPRECATED - custom command-line color overrides */
	int ind = 0;
	uint8_t ccol[4];
	while(arg_lookup(args, "ci", ind++, &val)){
		if (4 == parse_color(val, ccol))
			tsm_vte_set_color(term.vte, ccol[0], &ccol[1]);
	}

/* Immediately reset / draw so that we get a window before the shell wakes */
	arcan_tui_erase_screen(term.screen, NULL);
	arcan_tui_refresh(term.screen);

	tsm_set_strhandler(term.vte, str_callback, 256, NULL);

	signal(SIGHUP, sighuph);

/* socket pair used to signal between the threads, this will be kept
 * alive even between reset/re-execute on a terminated terminal */
	int pair[2];
	if (-1 == socketpair(AF_UNIX, SOCK_STREAM, 0, pair))
		return EXIT_FAILURE;

	int flags;
	if (-1 != (flags = fcntl(pair[0], F_GETFD)))
		fcntl(pair[0], F_SETFD, flags | FD_CLOEXEC);

	if (-1 != (flags = fcntl(pair[1], F_GETFD)))
		fcntl(pair[1], F_SETFD, flags | FD_CLOEXEC);

	term.dirtyfd = pair[0];
	term.signalfd = pair[1];

	if (!setup_build_term())
		return EXIT_FAILURE;

#ifdef __OpenBSD__
	pledge(SHMIF_PLEDGE_PREFIX " tty", NULL);
#endif

/* re-fetch fg/bg from the vte so the palette can be considered, slated
 * to be removed when the builtin/ scripts cover the color definition bits */
	uint8_t fgc[3], bgc[3];
	tsm_vte_get_color(term.vte, VTE_COLOR_BACKGROUND, bgc);
	tsm_vte_get_color(term.vte, VTE_COLOR_FOREGROUND, fgc);
	arcan_tui_set_color(term.screen, TUI_COL_BG, bgc);
	arcan_tui_set_color(term.screen, TUI_COL_TEXT, fgc);
	arcan_tui_reset_labels(term.screen);

	bool alive;
	while((alive = atomic_load(&term.alive)) || !term.die_on_term){
		pthread_mutex_lock(&term.synch);

		struct tui_process_res res =
			arcan_tui_process(&term.screen, 1, &term.signalfd, 1, -1);

		if (res.errc < TUI_ERRC_OK){
			break;
		}

/* indicate that we are finished so the user has the option to reset rather
 * than terminate, make sure this is done only once per running cycle */
		if (!term.alive && !term.die_on_term && !term.complete_signal){
			arcan_tui_progress(term.screen, TUI_PROGRESS_INTERNAL, 1.0);
			term.complete_signal = true;
		}

		arcan_tui_refresh(term.screen);

/* screen contents have been synched and updated, but we don't have a
 * restore spot for dealing with resize or contents boundary */
		if (!alive && !atomic_load(&term.restore)){
			create_restore_buffer(term.fit_contents);
		}

	/* flush out the signal pipe, don't care about contents, assume
	 * it is about unlocking for now */
		pthread_mutex_unlock(&term.synch);
		if (res.ok){
			char buf[256];
			read(term.signalfd, buf, 256);
			pthread_mutex_lock(&term.hold);
			pthread_mutex_unlock(&term.hold);
		}
	}

	if (term.keep_stderr)
		close(term.keep_stderr);

	arcan_tui_destroy(term.screen, NULL);
	return EXIT_SUCCESS;
}
