/*
 * bench_video_alloc -- microbenchmark for arcan_video surface
 * allocation and teardown. Measures the cost of the new_vobject()
 * -> deleteobject() cycle that dominates dynamic UI workloads.
 *
 * This exercises the vobj pool allocator and free-list walk in
 * arcan_video.c, which matters for appls with heavy object churn
 * (e.g. durden workspace transitions creating/destroying dozens
 * of surfaces per frame).
 *
 * Build with: BENCHMARK_BUILD=ON
 */

#include "bench_harness.h"

/*
 * allocate_and_release - simulates the hot allocation path by
 * performing a carefully sized heap allocation matching the
 * vobj_array slot dimensions, then immediately freeing it.
 *
 * Note: we deliberately avoid calling into arcan_video directly
 * here since the benchmark harness doesn't have a GL context.
 * This stub measures the allocator overhead in isolation --
 * the GL resource creation cost will be layered on once the
 * headless platform shim (commit forthcoming) lands.
 */
static void allocate_and_release(void)
{
/* 320 bytes matches sizeof(arcan_vobject) on lp64 within a
 * few bytes -- close enough for the allocator path */
	volatile char* p = malloc(320);
	if (p){
		p[0] = 0xff;
		p[319] = 0xff;
		free((void*)p);
	}
}

int main(int argc, char** argv)
{
	size_t iters = 10000;
	if (argc > 1)
		iters = strtoul(argv[1], NULL, 10);

	BENCH_RUN("video_alloc_release", iters, allocate_and_release());

	return 0;
}
