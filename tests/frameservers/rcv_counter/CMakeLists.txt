PROJECT( rcv_counter )
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
	pthread
	m
)

SET(SHMIF_SOURCES
	${ARCAN_SOURCE_DIR}/platform/posix/warning.c
	${ARCAN_SOURCE_DIR}/platform/posix/sem.c
	${ARCAN_SOURCE_DIR}/platform/posix/shm.c
	${ARCAN_SOURCE_DIR}/platform/posix/fdpassing.c
	${ARCAN_SOURCE_DIR}/shmif/arcan_shmif_control.c
	${ARCAN_SOURCE_DIR}/shmif/arcan_shmif_interop.c
)

if (${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
LIST(APPEND SHMIF_SOURCES
	${ARCAN_SOURCE_DIR}/platform/darwin/time.c)
else()
LIST(APPEND SHMIF_SOURCES
	${ARCAN_SOURCE_DIR}/platform/posix/time.c)
LIST(APPEND LIBRARIES rt)
endif()

SET(SOURCES
	src/${CMAKE_PROJECT_NAME}.c
)

add_executable(${CMAKE_PROJECT_NAME} ${SOURCES} ${SHMIF_SOURCES})
target_link_libraries(${CMAKE_PROJECT_NAME} ${LIBRARIES})
