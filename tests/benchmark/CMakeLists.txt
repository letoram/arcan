#
# Benchmark harness build configuration.
# Controlled by BENCHMARK_BUILD option (off by default).
#
# Links against arcan_shmif_int so we can poke at internals
# without exporting extra symbols from the main build.
#
# Usage:
#   cmake -DBENCHMARK_BUILD=ON ../src
#   make bench_video_alloc bench_tui_raster bench_agp_upload
#

cmake_minimum_required(VERSION 3.13)

set(BENCH_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../tests/benchmark)

add_executable(bench_video_alloc ${BENCH_DIR}/bench_video_alloc.c)
target_include_directories(bench_video_alloc PRIVATE ${BENCH_DIR})
target_link_libraries(bench_video_alloc m)

add_executable(bench_tui_raster ${BENCH_DIR}/bench_tui_raster.c)
target_include_directories(bench_tui_raster PRIVATE ${BENCH_DIR})
target_link_libraries(bench_tui_raster m)

add_executable(bench_agp_upload ${BENCH_DIR}/bench_agp_upload.c)
target_include_directories(bench_agp_upload PRIVATE ${BENCH_DIR})
target_link_libraries(bench_agp_upload m)
