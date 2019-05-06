#include <arcan_shmif.h>
#include <assert.h>
#include <spawn.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>

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
	fprintf(stderr, "Usage: icon.svg icon-active.svg exec-file [args]\n");
	return rv;
}

extern char** environ;

int main(int argc, char** argv)
{
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
