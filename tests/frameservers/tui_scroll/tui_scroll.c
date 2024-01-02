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

static unsigned long linecap = 65536;
static unsigned position = 0;
static bool redraw;

static void draw(struct tui_context* c)
{
	size_t rows, cols;
	arcan_tui_dimensions(c, &rows, &cols);
	arcan_tui_erase_screen(c, NULL);
	arcan_tui_move_to(c, 0, 0);
	struct tui_screen_attr attr = arcan_tui_defcattr(c, TUI_COL_TEXT);

	for (size_t i = 0; (i + position < linecap) && i <= rows; i++){
		arcan_tui_printf(c, &attr, "%zu", i + position);
		arcan_tui_move_to(c, 0, i);
	}

	arcan_tui_content_size(c, position, linecap, 0, 0);
}

void seek_absolute(struct tui_context* c, float pct, void* tag)
{
	position = (float)linecap * pct;
	redraw = true;
}

void seek_relative(struct tui_context* c, ssize_t rows, ssize_t cols, void* tag)
{
	if (rows < 0){
		if (-rows < position)
			position = 0;
		else
			position += rows;
	}

	redraw = true;
}

void resized(struct tui_context* c,
	size_t neww, size_t newh, size_t cols, size_t rows, void* tag)
{
	redraw = true;
}

int main(int argc, char** argv)
{
	arcan_tui_conn* conn = arcan_tui_open_display("tui-test", "");
	if (argc > 1){
		linecap = strtoul(argv[1], NULL, 10);
	}
/*
 * only the ones that are relevant needs to be filled
 */
	struct tui_cbcfg cbcfg = {
		.seek_absolute = seek_absolute,
		.seek_relative = seek_relative,
		.resized = resized
	};

	struct tui_context* tui = arcan_tui_setup(conn, NULL, &cbcfg, sizeof(cbcfg));
	if (!tui){
		fprintf(stderr, "failed to setup TUI connection\n");
		return EXIT_FAILURE;
	}

	draw(tui);

	while (1){
		struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (redraw)
				redraw = (draw(tui), 0);

			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
				break;
		}
		else
			break;
	}

	arcan_tui_destroy(tui, NULL);

	return EXIT_SUCCESS;
}
