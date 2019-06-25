PROJECT( arcan-net )
cmake_minimum_required(VERSION 3.0.4 FATAL_ERROR)
include(FindPkgConfig)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-D_DEBUG)
endif()

if (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	add_definitions(-D__LINUX)
endif()

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../platform/cmake/modules)
if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED WITH_EXT)
endif()

add_definitions(
	-Wall
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-Wno-unused-function
	-pthread
	-fPIC
)

SET(LIBRARIES
	m
	pthread
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_SHMIF_SERVER_LIBRARY}
)

find_package(Sanitizers REQUIRED)
find_package(FFMPEG REQUIRED QUIET)

if (FFMPEG_FOUND)
	message("ffmpeg support found, H264 enc/dec enabled")
	add_definitions(-DWANT_H264_DEC)
	add_definitions(-DWANT_H264_ENC)
	list(APPEND LIBRARIES ${FFMPEG_LIBRARIES})
	include_directories(${FFMPEG_INCLUDE_DIRS})
else()
	message("ffmpeg support NOT found, disabled")
endif()

include(ExternalProject)

# ExternalProject_Add(udt
# UDT as carrier is something we'll avoid for now.
#
#	SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/udt"
#	UPDATE_COMMAND ""
#	GIT_REPOSITORY  "https://github.com/letoram/UDT"
#	UPDATE_COMMAND ""
#	PATCH_COMMAND ""
#	INSTALL_COMMAND ""
#	LOG_DOWNLOAD 1
#	LOG_UPLOAD 1
#	LOG_CONFIGURE 1
#	LOG_BUILD 1
#	LOG_TEST 1
#	LOG_INSTALL 1
#	-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
#	-DMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
#	-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
#	-DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}
#	-DLIBTYPE=STATIC
#)

include_directories(
	${ARCAN_SHMIF_INCLUDE_DIR}
	../../engine
	../../platform/posix
	external/blake2
	external/25519
	external
	#	${CMAKE_CURRENT_BINARY_DIR}/udt/src
)

set(EXTERNAL_SOURCES
	external/blake2/blake2bp-ref.c
	external/blake2/blake2b-ref.c
	external/miniz/miniz.c
)

set(SOURCES
	a12.c
	a12_decode.c
	a12_encode.c
	a12_helper_srv.c
	a12_helper_cl.c
	../../platform/posix/mem.c
	../../platform/posix/base64.c
	${EXTERNAL_SOURCES}
)

add_executable( arcan-net ${SOURCES} netproxy.c)
add_sanitizers( arcan-net )

set_property(TARGET arcan-net PROPERTY C_STANDARD 11)

target_link_libraries(arcan-net ${LIBRARIES})

install(TARGETS
	arcan-net
	DESTINATION bin)
