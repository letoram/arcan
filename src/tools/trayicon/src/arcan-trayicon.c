#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <assert.h>
#include <spawn.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include "../../../frameserver/util/utf8.c"

#define NANOSVG_IMPLEMENTATION
#define NANOSVGRAST_IMPLEMENTATION
#define NANOSVG_ALL_COLOR_KEYWORDS
#define NSVG_RGB(r, g, b)(SHMIF_RGBA(r, g, b, 0x00))
#include "nanosvg.h"
#include "nanosvgrast.h"

struct trayicon_state {
/* icon sources */
	const char* icon_normal;
	const char* icon_pressed;

/* render controls */
	float density;
	bool dirty;
	bool pressed;

/* child process control */
	char* bin;
	char** argv;
	char** envv;
	pid_t client_pid;
};

/* if the icon state is missing or broken, use a solid color to indicate that */
static void draw_fallback(
	struct arcan_shmif_cont* C, struct trayicon_state* trayicon)
{
	shmif_pixel col = trayicon->pressed ?
		SHMIF_RGBA(0xff, 0x00, 0x00, 0xff) : SHMIF_RGBA(0x00, 0xff, 0x00, 0xff);
	for (size_t i = 0; i < C->pitch * C->h; i++)
		C->vidp[i] = col;
	trayicon->dirty = true;
}

static void render_to(
	struct arcan_shmif_cont* C, struct trayicon_state* trayicon)
{
	FILE* src = fopen(trayicon->pressed ?
		trayicon->icon_pressed : trayicon->icon_normal, "r");

	if (!src)
		return draw_fallback(C, trayicon);

/* happens rarely enough that in-memory caching is just a hazzle, might
 * as well support icon changing at runtime-, nsvgParseFromFile will fclose() */
	NSVGimage* image = nsvgParseFromFile(src, "px", trayicon->density);
	if (!image)
		return draw_fallback(C, trayicon);

	NSVGrasterizer* rast = nsvgCreateRasterizer();
	if (!rast){
		nsvgDelete(image);
		return draw_fallback(C, trayicon);
	}

	float scalew = C->w / image->width;
	float scaleh = C->h / image->height;
	float scale = scalew < scaleh ? scalew : scaleh;

	nsvgRasterize(rast, image, 0, 0, scale, C->vidb, C->w, C->h, C->stride);
	nsvgDelete(image);
	nsvgDeleteRasterizer(rast);
	trayicon->dirty = true;
}

static void force_kill(pid_t pid)
{
	kill(pid, SIGKILL);
	int wstatus;
	while (pid != waitpid(pid, &wstatus, 0) && errno != EINVAL){}
}

struct killarg {
	pid_t pid;
	int timeout;
};

static void* kill_thread(void* T)
{
	struct killarg* karg = T;

	free(karg);
	return NULL;
}

static void toggle_client(
	struct arcan_shmif_cont* C, struct trayicon_state* trayicon)
{
/* If we don't have a client, spawn it, if we have one, first killing it softly
 * with this song - it is a bit naive dealing with pthread creation failures as
 * it just switches to SIGKILL and wait */
	if (trayicon->client_pid != -1){
		pthread_t pth;
		pthread_attr_t attr;
		pthread_attr_init(&attr);
		pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
		struct killarg* karg = malloc(sizeof(struct killarg));
		if (!karg)
			force_kill(trayicon->client_pid);
		else {
			*karg = (struct killarg){
				.pid = trayicon->client_pid
			};
			if (-1 == pthread_create(&pth, &attr, kill_thread, karg)){
				free(karg);
				force_kill(trayicon->client_pid);
			}
		}
		trayicon->client_pid = -1;
		trayicon->pressed = false;
	}
	else {
		arcan_shmif_enqueue(C, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_HANDOVER
		});
		trayicon->pressed = true;
	}

	trayicon->dirty = true;
}

static void do_event(struct arcan_shmif_cont* C,
	struct arcan_event* ev, struct trayicon_state* trayicon)
{
	if (ev->category != EVENT_IO && ev->category != EVENT_TARGET)
		return;

/* only care about the initial press */
	if (ev->category == EVENT_IO){
		if (ev->io.kind != EVENT_IO_BUTTON || !ev->io.input.digital.active)
			return;

		if (strcmp(ev->io.label, "ACTIVATE") == 0 ||
			ev->io.devkind == EVENT_IDEVKIND_MOUSE){
			toggle_client(C, trayicon);
		}

		return;
	}

/* category == EVENT_TARGET */
	switch (ev->tgt.kind){
	case TARGET_COMMAND_DISPLAYHINT:{
		size_t w = ev->tgt.ioevs[0].uiv;
		size_t h = ev->tgt.ioevs[1].uiv;
		if (w && h && (w != C->w || h != C->h)){
			arcan_shmif_resize(C, w, h);
			render_to(C, trayicon);
		}
	}
	break;
/* got the reply to our pending request, time to handover */
	case TARGET_COMMAND_NEWSEGMENT:{
		trayicon->client_pid = arcan_shmif_handover_exec(C, *ev,
			trayicon->bin, trayicon->argv, trayicon->envv, false);
		if (-1 != trayicon->client_pid){
			render_to(C, trayicon);
		}
	}
	break;
/* server-side state somehow lost, kill the client if we
 * have one, submit a frame update regardless */
	case TARGET_COMMAND_RESET:
		if (-1 != trayicon->client_pid){
			toggle_client(C, trayicon);
		}
		trayicon->dirty = true;
	break;

/* our CLOCKREQ timer will trigger this. */
	case TARGET_COMMAND_STEPFRAME:
/* did the client exit without us trying to get rid of it? */
		if (-1 != trayicon->client_pid){
			if (trayicon->client_pid == waitpid(
				trayicon->client_pid, NULL, WNOHANG)){
				trayicon->client_pid = -1;
				trayicon->pressed = false;
				trayicon->dirty = true;
				render_to(C, trayicon);
			}
		}
	break;
	default:
	break;
	}
}

static void event_loop(
	struct arcan_shmif_cont* C, struct trayicon_state* trayicon)
{
	struct arcan_event ev;

	while(arcan_shmif_wait(C, &ev)){

/* got one event, might be more in store so flush them out */
		do_event(C, &ev, trayicon);
		while (arcan_shmif_poll(C, &ev) > 0)
			do_event(C, &ev, trayicon);

/* and update if something actually changed */
		if (trayicon->dirty){
			arcan_shmif_signal(C, SHMIF_SIGVID);
		}
	}
}

static int show_args(const char* args, int rv)
{
	fprintf(stderr, "Usage:\n"
	"\t icon-launch mode: icon.svg icon-active.svg exec-file [args]\n"
	"\t stdin-tray item mode: --stdin [-w, --width n_cells]\n");
	return rv;
}

extern char** environ;

/* Alternate tray icon mode where we simply read from stdin and render as much
 * as we can into a tui context. Intended to be used with some input script
 * that monitors some source and expose as updates into a button. */
struct stdin_data {
	struct tui_cell* buffer;
	size_t buffer_count;
};

static void render_buffer(
	struct tui_context* tui, struct tui_cell* cells, size_t n)
{
/* option to align right? */
	arcan_tui_move_to(tui, 0, 0);
	for (size_t i = 0; i < n; i++){
		arcan_tui_write(tui, cells[i].ch, &cells[i].attr);
	}
}

static void update_buffer(
	struct tui_context* tui, struct stdin_data* dst, char* inbuf)
{
/* fill with a base attribute, the input format can override it locally */
	struct tui_cell cell = {};
	arcan_tui_get_color(tui, TUI_COL_TEXT, cell.attr.fc);
	arcan_tui_get_bgcolor(tui, TUI_COL_BG, cell.attr.bc);

/* reset to base attribute */
	for (size_t i = 0; i < dst->buffer_count; i++){
		dst->buffer[i] = cell;
	}

/* process input string and apply to buffer, this is where we can add more
 * formatting / decoding, e.g. the lemonbar protocol and just match to cells */
	size_t in = 0, out = 0;
	uint32_t cp = 0;
	uint32_t state = 0;

/* need to go utf8 to ucs4 */
	while(inbuf[in] && (utf8_decode(&state, &cp, inbuf[in++]) != UTF8_REJECT)){
		if (state == UTF8_ACCEPT){
			dst->buffer[out++].ch = cp;
		}
	}

	render_buffer(tui, dst->buffer, out);
}

static int stdin_tui(const char* name, size_t w)
{
	arcan_tui_conn* conn = arcan_tui_open_display(name, "");
	if (!conn){
		fprintf(stderr, "Couldn't connect to arcan, check ARCAN_CONNPATH\n");
		return EXIT_FAILURE;
	}

/* shmif will give us a non-blocking descriptor this way */
	int src = arcan_shmif_dupfd(STDIN_FILENO, -1, false);
	if (-1 == src){
		fprintf(stderr, "Couldn't create unblocking descriptor\n");
		return EXIT_FAILURE;
	}

	struct tui_cell buffer[256];

	struct stdin_data tag = {
		.buffer = buffer,
		.buffer_count = 256,
	};

	struct tui_cbcfg cbcfg = {
/*		.input_label = on_label,
		.resized = on_resize,*/
		.tag = &tag
	};

	struct tui_context* tui = arcan_tui_setup(conn, NULL, &cbcfg, (sizeof(cbcfg)));
	arcan_tui_set_flags(tui, TUI_HIDE_CURSOR);

/* this will forward our desired constraints and attempt a resize once */
	if (w){
		arcan_tui_wndhint(tui, NULL, (struct tui_constraints){
			.min_rows = 1, .max_rows = 1,
			.min_cols = 1, .max_cols = w
		});
	}

	char inbuf[256];
	uint8_t inbuf_ofs = 0;

	while (1){
		struct tui_process_res res = arcan_tui_process(&tui, 1, &src, 1, -1);
		if (res.errc != TUI_ERRC_OK)
			break;

		if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
			break;

/* not the most throughput friendly approach but not exactly performance heavy,
 * place to add some additional parsing in order to set more of the cell
 * attributes */
 		if (res.bad)
			break;

/* 256 character crop- limited non-blocking fgets */
		ssize_t nr;
		while ((nr = read(src, &inbuf[inbuf_ofs], 1)) > 0){
			if (inbuf[inbuf_ofs] == '\n' || inbuf_ofs == 255){
				inbuf[inbuf_ofs] = '\0';
				update_buffer(tui, &tag, inbuf);
				inbuf_ofs = 0;
			}
			else
				inbuf_ofs++;
		}
	}

	arcan_tui_destroy(tui, NULL);
	return EXIT_SUCCESS;
}

int main(int argc, char** argv)
{
	if (argc <= 1)
		return show_args("", EXIT_FAILURE);

	if (strcmp(argv[1], "-") == 0 || strcmp(argv[1], "--stdin") == 0){
		size_t w = 0;

		if (argc == 4 && (strcmp(argv[2], "-w") == 0 || strcmp(argv[2], "--width") == 0)){
			w = strtoul(argv[3], NULL, 10);
		}
		return stdin_tui("button", w);
	}

	if (argc <= 2)
		return show_args("", EXIT_FAILURE);

/* open the connection */
	struct arg_arr* args;
	struct arcan_shmif_cont conn =
		arcan_shmif_open(SEGID_ICON, SHMIF_ACQUIRE_FATALFAIL, &args);

/* get the display configuration */
	struct arcan_shmif_initial* cfg;
	size_t icfg = arcan_shmif_initial(&conn, &cfg);
	assert(icfg == sizeof(struct arcan_shmif_initial));

/* rendering- options, convert ppcm to dpi */
	struct trayicon_state state = {
		.density = cfg->density * 0.393700787f,
		.bin = argv[3],
		.argv = &argv[4],
		.client_pid = -1,
		.envv = environ,
		.icon_normal = argv[1],
		.icon_pressed = argv[2]
	};

/* register our keybinding */
	arcan_shmif_enqueue(&conn, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(LABELHINT),
		.ext.labelhint = {
			.idatatype = EVENT_IDATATYPE_DIGITAL,
			.label = "ACTIVATE",
			.descr = "tooltip description goes here"
/* we can suggest a hotkey like mapping here as well with the
 * modifiers and initial fields and data from arcan_tuisym.h */
		}
	});

/* request a wakeup timer */
	arcan_shmif_enqueue(&conn, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(CLOCKREQ),
		.ext.clock.rate = 5
	});

/* update immediately so we become visible */
	render_to(&conn, &state);
	arcan_shmif_signal(&conn, SHMIF_SIGVID);
	event_loop(&conn, &state);

	return EXIT_SUCCESS;
}
