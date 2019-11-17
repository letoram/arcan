find_package(FFMPEG QUIET)

set(LIBRARIES
	pthread
	arcan_shmif
	arcan_shmif_server
)

if (FFMPEG_FOUND)
	message("(a12) ffmpeg support found, H264 enc/dec enabled")
	add_definitions(-DWANT_H264_DEC)
	add_definitions(-DWANT_H264_ENC)
	list(APPEND LIBRARIES ${FFMPEG_LIBRARIES})
	include_directories(${FFMPEG_INCLUDE_DIRS})
else()
	message("(a12) ffmpeg support NOT found, video encoding")
endif()

set(A12_SOURCES
	a12.c
	a12_decode.c
	a12_encode.c
	${PLATFORM_ROOT}/posix/mem.c
	${PLATFORM_ROOT}/posix/base64.c
)

set(EXTERNAL_SOURCES
	external/blake2/blake2bp-ref.c
	external/blake2/blake2b-ref.c
	external/miniz/miniz.c
	external/x25519.c
	${PLATFORM_ROOT}/posix/chacha20.c
)

add_library(arcan_a12 SHARED ${A12_SOURCES} ${EXTERNAL_SOURCES})
target_include_directories(arcan_a12 PRIVATE
	external/blake2
	external
	${PLATFORM_ROOT}/../engine
	${PLATFORM_ROOT}/../shmif
)
target_link_libraries(arcan_a12 ${LIBRARIES})
set(A12_LIBRARIES arcan_a12 PARENT_SCOPE)
install(TARGETS arcan_a12
	LIBRARY DESTINATION lib
	ARCHIVE DESTINATION lib
)
install(FILES a12.h DESTINATION include/arcan)
add_subdirectory("net")
