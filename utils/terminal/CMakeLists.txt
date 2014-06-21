# arcterm - Arcan based adaptation of uuterm
#

PROJECT( arcterm )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(MAJOR_VERSION 0)
set(MINOR_VERSION 1)
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION})

FIND_PACKAGE ( Freetype REQUIRED )

set (SHMIF_PATH 
	${CMAKE_CURRENT_SOURCE_DIR}/../../shmif
)
	
set (PLATFORM_PATH
	${SHMIF_PATH}/../platform/posix
)
add_definitions(
	-std=gnu11 
	-Wall 
	-DPLATFORM_HEADER=\"${PLATFORM_PATH}/../platform.h\" 
	-DENABLE_FSRV_AVFEED
	-DRENDERFUN_NOSUBIMAGE
	-DDEFAULT_FSRV_MODE=\"avfeed\"
)

set (
	SHMIF_SOURCES
	${SHMIF_PATH}/arcan_shmif_interop.h
	${SHMIF_PATH}/arcan_shmif_interop.c
	${SHMIF_PATH}/arcan_shmif_control.c
	${SHMIF_PATH}/arcan_shmif_control.h
	${SHMIF_PATH}/arcan_shmif_event.h
	${SHMIF_PATH}/arcan_shmif.h
	${PLATFORM_PATH}/sem.c
)

set (
	SUPPORT_SOURCES
	${SHMIF_PATH}/../engine/arcan_renderfun.c
	${SHMIF_PATH}/../engine/arcan_ttf.c
	${PLATFORM_PATH}/mem.c
	${PLATFORM_PATH}/resource_io.c
	${PLATFORM_PATH}/map_resource.c
	${PLATFORM_PATH}/paths.c
	${PLATFORM_PATH}/warning.c
	${PLATFORM_PATH}/strip_traverse.c
)

set (
	LIBC_DEPS
	m
	rt
	dl
)

include_directories(
	${CMAKE_CURRENT_SOURCE_DIR}/uuterm 
	${SHMIF_PATH}
	${FREETYPE_INCLUDE_DIRS}
	${SHMIF_PATH}/../engine
)

add_executable(arcterm 
	arcterm.c 
	${SHMIF_PATH}/../frameserver/frameserver.c 
	${SHMIF_SOURCES}
	${SUPPORT_SOURCES}
)

target_link_libraries(arcterm 
	pthread
	util
	${LIBC_DEPS} 
	${FREETYPE_LIBRARY}
)
