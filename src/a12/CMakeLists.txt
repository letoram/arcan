pkg_check_modules(FFMPEG QUIET libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

set(LIBRARIES
	pthread
	arcan_shmif
	arcan_shmif_server
)

# should be probed based on architecture, and then dynamically, need to dive
# into how that is done - but might as well take it for when we also add
# optimized chacha
set(DEFS
	BLAKE3_NO_AVX2
	BLAKE3_NO_AVX512
	BLAKE3_NO_SSE41
	ZSTD_MULTITHREAD
# this would need architecture probing and enable for certain rounds of amd64
	ZSTD_DISABLE_ASM
)

set(A12_VERSION_MAJOR 0)
set(A12_VERSION_MINOR 1)

if (FFMPEG_FOUND)
	amsg("(a12) ${CL_GRN} ffmpeg support found, H264 enc/dec enabled ${CL_RST}")
	add_definitions(-DWANT_H264_DEC)
	add_definitions(-DWANT_H264_ENC)

	list(APPEND LIBRARIES ${FFMPEG_LINK_LIBRARIES})
	include_directories(${FFMPEG_INCLUDE_DIRS})
else()
	amsg("(a12) ${CL_YEL} ffmpeg support NOT found, video enc/dec DISABLED ${CL_RST}")
endif()

if (ENABLE_TRACY)
	option(TRACY_ENABLE "" ON)
	option(TRACY_ON_DEMAND "" ON)
	if (NOT TARGET TracyClient)
		add_subdirectory(
			${EXTERNAL_SRC_DIR}/git/tracy
			${CMAKE_CURRENT_BINARY_DIR}/tracy
		)
	endif()
	set_target_properties(TracyClient PROPERTIES
		COMPILE_FLAGS -fPIC)
	list(APPEND DEFS WITH_TRACY)
	list(APPEND LIBRARIES TracyClient)
	amsg("(a12) ${CL_YEL}tracy support\t${CL_GRN}enabled${CL_RST}")
else()
	amsg("(a12) ${CL_YEL}tracy support\t${CL_RED}disabled${CL_RST}")
endif()

set(A12_SOURCES
	a12.c
	a12_decode.c
	a12_encode.c
	${PLATFORM_ROOT}/posix/mem.c
	${PLATFORM_ROOT}/posix/base64.c
	${PLATFORM_ROOT}/posix/random.c
)

set (ZSTD_SOURCES
	external/zstd/common/pool.c
	external/zstd/common/debug.c
	external/zstd/common/entropy_common.c
	external/zstd/common/error_private.c
	external/zstd/common/fse_decompress.c
	external/zstd/common/pool.c
	external/zstd/common/threading.c
	external/zstd/common/xxhash.c
	external/zstd/common/zstd_common.c
	external/zstd/compress/fse_compress.c
	external/zstd/compress/hist.c
	external/zstd/compress/huf_compress.c
	external/zstd/compress/zstd_compress.c
	external/zstd/compress/zstd_compress_literals.c
	external/zstd/compress/zstd_compress_sequences.c
	external/zstd/compress/zstd_compress_superblock.c
	external/zstd/compress/zstd_double_fast.c
	external/zstd/compress/zstd_fast.c
	external/zstd/compress/zstd_lazy.c
	external/zstd/compress/zstd_ldm.c
	external/zstd/compress/zstd_opt.c
	external/zstd/compress/zstdmt_compress.c
	external/zstd/decompress/huf_decompress.c
	external/zstd/decompress/zstd_ddict.c
	external/zstd/decompress/zstd_decompress.c
	external/zstd/decompress/zstd_decompress_block.c
)

set(EXTERNAL_SOURCES
	external/blake3/blake3.c
	external/blake3/blake3_dispatch.c
	external/blake3/blake3_portable.c
	external/x25519.c
	${ZSTD_SOURCES}
)

add_library(arcan_a12 SHARED ${A12_SOURCES} ${EXTERNAL_SOURCES})
target_compile_definitions(arcan_a12 PRIVATE ${DEFS})

set_target_properties(arcan_a12 PROPERTIES
	COMPILE_FLAGS -fPIC
	VERSION ${A12_VERSION_MAJOR}.${A12_VERSION_MINOR}
)

target_include_directories(arcan_a12 PRIVATE
	external/blake3
	external/zstd
	external/zstd/common
	external
	${PLATFORM_ROOT}/../engine
	${PLATFORM_ROOT}/../shmif
)

target_link_libraries(arcan_a12 ${LIBRARIES})

set(A12_LIBRARIES arcan_a12 PARENT_SCOPE)
install(TARGETS arcan_a12
	LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
	ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(FILES a12.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/arcan)
add_subdirectory("net")
