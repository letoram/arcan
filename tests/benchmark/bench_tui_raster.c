/*
 * bench_tui_raster -- microbenchmark for the TUI raster scanline
 * conversion path in src/shmif/tui/raster/raster.c.
 *
 * Rasterization is the single hottest loop for terminal-heavy
 * workloads (arcterm, cat large.log). The inner loop converts
 * cell grids to pixel buffers with fg/bg color selection per
 * glyph pixel -- this is the path that commit 12 targets for
 * SIMD vectorization.
 *
 * This stub exercises a synthetic scanline to establish baseline
 * numbers before the optimization pass.
 */

#include "bench_harness.h"

/* simulate a raster scanline: 80 columns * 16px cell width = 1280
 * pixels per row, RGBA8888 = 5120 bytes. The benchmark kernel is
 * a branchless fg/bg select based on a mock glyph bitmap bit. */
#define SCANLINE_PX 1280

static uint32_t scanline_buf[SCANLINE_PX];
static uint8_t glyph_row[SCANLINE_PX / 8]; /* 1bpp mock glyph data */

static void raster_scanline(void)
{
	uint32_t fg = 0xFFD0D0D0; /* light gray foreground */
	uint32_t bg = 0xFF1A1A2E; /* dark background */

/* per-pixel select: if glyph bit set, use fg; else bg.
 * this mimics the inner loop in tui_raster_renderline() */
	for (int x = 0; x < SCANLINE_PX; x++){
		int byte_idx = x >> 3;
		int bit_idx = x & 7;
		int is_fg = (glyph_row[byte_idx] >> bit_idx) & 1;

/* branchless: mask select */
		uint32_t mask = -(uint32_t)is_fg;
		scanline_buf[x] = (fg & mask) | (bg & ~mask);
	}
}

int main(int argc, char** argv)
{
	size_t iters = 50000;
	if (argc > 1)
		iters = strtoul(argv[1], NULL, 10);

/* fill mock glyph data with a realistic pattern -- alternating
 * set/clear mimics typical ASCII text where ~50% of cell pixels
 * are foreground (varies wildly by font, 50% is a decent average
 * for the monospace case) */
	for (size_t i = 0; i < sizeof(glyph_row); i++)
		glyph_row[i] = 0xAA; /* 10101010 -- 50% density */

	BENCH_RUN("tui_raster_scanline", iters, raster_scanline());

	return 0;
}
