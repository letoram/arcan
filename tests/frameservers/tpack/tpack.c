#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <errno.h>

#include <arcan_shmif.h>
#include <arcan_tui.h>

static uint8_t* tpack_buf;
static size_t tpack_buf_sz;

struct __attribute__((packed)) tui_raster_header {
	uint32_t data_sz;
	uint16_t lines;
	uint16_t cells;
	uint8_t direction;
	uint16_t flags;
	uint8_t bgc[4];
};

static void on_resized(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	arcan_tui_tunpack(c, tpack_buf, tpack_buf_sz, 0, 0, col, row);
}

int main(int argc, char** argv)
{
	if (argc <= 1){
		fprintf(stderr, "use:\n\ttpack full.tpack [delta or full.tpack]*\n\n");
		return EXIT_FAILURE;
	}

	FILE* fin = fopen(argv[1], "r");
	if (!fin){
		fprintf(stderr, "couldn't open %s\n", argv[1]);
		return EXIT_FAILURE;
	}

	fseek(fin, 0, SEEK_END);
/* assumes the first package sets the right size */
	tpack_buf_sz = ftell(fin);
	tpack_buf = malloc(tpack_buf_sz);
	rewind(fin);
	if (1 != fread(tpack_buf, tpack_buf_sz, 1, fin)){
		fprintf(stdout, "error reading from %s\n", argv[1]);
		fclose(fin);
		return EXIT_FAILURE;
	}

	arcan_tui_conn* C = arcan_tui_open_display("tpack test", argv[1]);
	if (!C){
		fprintf(stderr, "couldn't connect to arcan\n");
		return EXIT_FAILURE;
	}

	struct tui_cbcfg cb = {.resized = on_resized};
	struct tui_context* T = arcan_tui_setup(C, NULL, &cb, sizeof(cb));

	while (1){
		arcan_tui_process(&T, 1, NULL, 0, -1);
		if (-1 == arcan_tui_refresh(T) && errno == EINVAL)
			break;
	}

	return EXIT_SUCCESS;
}
