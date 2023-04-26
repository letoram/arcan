/*
 * Test case for performing handover-exec with embedding
 */
#define _GNU_SOURCE
#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <inttypes.h>
#include <stdarg.h>
#include <errno.h>
#include <stdio.h>

static char* media_arg;
static struct tui_context* ext_child;

#define TRACE_ENABLE
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

static void fill(struct tui_context* c)
{
	arcan_tui_erase_screen(c, NULL);
	arcan_tui_move_to(c, 0, 0);
}

static void on_key(struct tui_context* c, uint32_t xkeysym,
	uint8_t scancode, uint16_t mods, uint16_t subid, void* t)
{
	trace("unknown_key(%"PRIu32",%"PRIu8",%"PRIu16")", xkeysym, scancode, subid);
/* FIXME: move subwindow around */
}

static bool on_subwindow(struct tui_context* c,
	arcan_tui_conn* conn, uint32_t id, uint8_t type, void* tag)
{
/* hand over to afsrv_decode in a loop */
	trace("window(%"PRIu32", ok: %s)", id, conn ? "yes" : "no");
	if (!conn)
		return false;

	struct tui_cbcfg cbcfg = {};
	ext_child = arcan_tui_setup(NULL, c, &cbcfg, sizeof(cbcfg));

	if (type == TUI_WND_HANDOVER){
		char* env[2] = {NULL, NULL};
		asprintf(&env[0], "ARCAN_ARG=%s", media_arg);

		if (arcan_tui_handover(c, conn, NULL,
			"/usr/bin/afsrv_decode", NULL, env, 15) != -1){
			arcan_tui_wndhint(ext_child, c,
				(struct tui_constraints){
					.anch_row = 5,
					.anch_col = 5,
				});
			return true;
		}
	}
	return false;
}

int main(int argc, char** argv)
{
	arcan_tui_conn* conn = arcan_tui_open_display("tui-test", "");
	if (argc == 1){
		fprintf(stderr, "missing: afsrv_decode arg\n");
		return EXIT_FAILURE;
	}
	media_arg = argv[1];

/*
 * only the ones that are relevant needs to be filled
 */
	struct tui_cbcfg cbcfg = {
		.input_key = on_key,
		.subwindow = on_subwindow,
	};

	struct tui_context* tui = arcan_tui_setup(conn, NULL, &cbcfg, sizeof(cbcfg));
	arcan_tui_reset_flags(tui, TUI_ALTERNATE);

	if (!tui){
		fprintf(stderr, "failed to setup TUI connection\n");
		return EXIT_FAILURE;
	}

/* grab a handover video that we will pass to afsrv_decode */
	fill(tui);
	arcan_tui_request_subwnd_ext(
		tui, TUI_WND_HANDOVER, 0xa,
		(struct tui_subwnd_req){.hint = TUIWND_EMBED}, sizeof(struct tui_subwnd_req)
	);

	while (1){
		struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
				break;
		}
		else
			break;
	}

	arcan_tui_destroy(tui, NULL);

	return EXIT_SUCCESS;
}
