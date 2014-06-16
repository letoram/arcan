# arcterm - Arcan based adaptation of uuterm
#

PROJECT( arcterm )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(MAJOR_VERSION 0)
set(MINOR_VERSION 1)
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION})

set (
	UUTERM_SOURCES
	uuterm/ascii.c
	uuterm/cell.c
	uuterm/dblbuf.c
	uuterm/decomp.c
	uuterm/refresh.c
	uuterm/term.c
	uuterm/tty.c
	uuterm/ucf.c
	uuterm/font_load.c
)

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

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/uuterm ${SHMIF_PATH}) 
# include_directories
add_executable(arcterm arcterm.c ${SHMIF_PATH}/../frameserver/frameserver.c ${UUTERM_SOURCES} ${SHMIF_SOURCES})
target_link_libraries(arcterm pthread rt dl)

