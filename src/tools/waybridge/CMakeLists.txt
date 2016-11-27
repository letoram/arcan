PROJECT( arcan-wayland )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

find_package(PkgConfig)
pkg_check_modules(PKG_WAYLAND_SERVER REQUIRED wayland-server)
find_path(WAYLAND_SERVER_INCLUDE_DIR wayland-server.h ${PKG_WAYLAND_SERVER_INCLUDE_DIRS})
find_library(WAYLAND_SERVER_LIBRARIES wayland-server PATHS ${PKG_WAYLAND_SERVER_LIBRARY_DIRS})

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-D_DEBUG)
endif()

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
  -Wno-unused-but-set-variable
	-Wno-unused-function
	-std=gnu11 # shmif-api requires this
)

include_directories(${ARCAN_SHMIF_INCLUDE_DIR} ${WAYLAND_SERVER_INCLUDE_DIR})

SET(LIBRARIES
	pthread
	m
	EGL
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_SHMIF_EXT_LIBRARY}
	${WAYLAND_SERVER_LIBRARIES}
)

SET(SOURCES
	waybridge.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
