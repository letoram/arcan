/*
 * bench_agp_upload -- microbenchmark for the AGP texture upload
 * path through src/platform/agp/glshared.c.
 *
 * The texture upload (agp_update_vstore) is a critical bottleneck
 * for wayland bridge performance -- every client surface commit
 * flows through this codepath. We measure memcpy overhead since
 * GL context isn't available in the benchmark harness; the actual
 * glTexSubImage2D cost will be profiled separately with the
 * headless platform shim.
 *
 * Test pattern: 1920x1080 RGBA8888 surface (~8MB), simulating
 * a single full-frame upload from a wayland client.
 */

#include "bench_harness.h"

/* 1080p RGBA8888 -- the common case for wayland/x11 client buffers */
#define TEX_W 1920
#define TEX_H 1080
#define TEX_BPP 4
#define TEX_SIZE (TEX_W * TEX_H * TEX_BPP)

static uint8_t* src_buf;
static uint8_t* dst_buf;

static void texture_upload_memcpy(void)
{
/* simulate the staging buffer copy that precedes the GL upload.
 * in the real path this is arcan_shmif -> agp backing store,
 * which is a straight memcpy for the non-DMA-BUF case */
	memcpy(dst_buf, src_buf, TEX_SIZE);
}

int main(int argc, char** argv)
{
	size_t iters = 500;
	if (argc > 1)
		iters = strtoul(argv[1], NULL, 10);

/* posix_memalign for cache-line alignment -- gives us a fair
 * comparison baseline against SIMD-optimized paths that require
 * 16-byte alignment (SSE) or 32-byte (AVX2) */
	posix_memalign((void**)&src_buf, 64, TEX_SIZE);
	posix_memalign((void**)&dst_buf, 64, TEX_SIZE);

	if (!src_buf || !dst_buf){
		fprintf(stderr, "bench_agp_upload: allocation failed (%d bytes)\n", TEX_SIZE);
		return 1;
	}

/* fill source with non-zero pattern to prevent copy-on-write
 * page deduplication from skewing results on Linux */
	for (size_t i = 0; i < TEX_SIZE; i++)
		src_buf[i] = (uint8_t)(i & 0xFF);

	BENCH_RUN("agp_upload_1080p", iters, texture_upload_memcpy());

	free(src_buf);
	free(dst_buf);

	return 0;
}
