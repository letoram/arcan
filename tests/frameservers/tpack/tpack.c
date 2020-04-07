#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

struct __attribute__((packed)) tui_raster_header {
	uint32_t data_sz;
	uint16_t lines;
	uint16_t cells;
	uint8_t direction;
	uint16_t flags;
	uint8_t bgc[4];
};

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

/* grab header and dimensions for the resize call */
	struct tui_raster_header hdr;
	if (1 != fread(&hdr, sizeof(hdr), 1, fin)){
		fprintf(stderr, "couldn't grab header from input\n");
		return EXIT_FAILURE;
	}
	fclose(fin);

	struct arcan_shmif_cont conn =
		arcan_shmif_open(SEGID_TUI, SHMIF_ACQUIRE_FATALFAIL, NULL);
	conn.hints = SHMIF_RHINT_TPACK;
	arcan_shmif_resize_ext(&conn, conn.w, conn.h,
		(struct shmif_resize_ext){
		.vbuf_cnt = -1, .abuf_cnt = -1,
		.rows = hdr.lines, hdr.cells
	});

	while(1){
		for (size_t i = 1; i < argc; i++){
			fin = fopen(argv[i], "r");
			fseek(fin, 0, SEEK_END);
/* assumes the first package sets the right size */
			size_t nb = ftell(fin);
			rewind(fin);
			if (1 != fread(conn.vidb, nb, 1, fin))
				return EXIT_FAILURE;
			fclose(fin);
		}
		arcan_shmif_signal(&conn, SHMIF_SIGVID);
	}
	/* grab the dimensions from the main file */
/* iterate the list of inputs and send them along */
/* possibly add a raster mode where we do the rasterization ourselves for fuzzing */

	return EXIT_SUCCESS;
}
