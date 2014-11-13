PROJECT( counter )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

#
# For finding the shared memory interface and corresponding
# Platform functions. When that API is more stable, we'll
# simply wrap it in a library but for now, we require
# compiler and layout compliance.
#
if (NOT ARCAN_SOURCE_DIR)
				message(FATAL_ERROR "ARCAN_SOURCE_DIR is not set, use -DARCAN_SOURCE_DIR=")
endif()

add_definitions(
	-Wall
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-std=gnu11 # shmif-api requires this
	-DPLATFORM_HEADER=\"${ARCAN_SOURCE_DIR}/platform/platform.h\" # platform files may need this
)

include_directories(${ARCAN_SOURCE_DIR}/shmif)

SET(LIBRARIES
	rt
	pthread
	m
)

SET(SHMIF_SOURCES
	${ARCAN_SOURCE_DIR}/platform/posix/warning.c
	${ARCAN_SOURCE_DIR}/platform/posix/time.c
	${ARCAN_SOURCE_DIR}/platform/posix/sem.c
	${ARCAN_SOURCE_DIR}/platform/posix/shm.c
	${ARCAN_SOURCE_DIR}/platform/posix/fdpassing.c
	${ARCAN_SOURCE_DIR}/shmif/arcan_shmif_control.c
	${ARCAN_SOURCE_DIR}/shmif/arcan_shmif_interop.c
)

SET(SOURCES
	src/main.c
)

add_executable(counter ${SOURCES} ${SHMIF_SOURCES})
target_link_libraries(counter ${LIBRARIES})
