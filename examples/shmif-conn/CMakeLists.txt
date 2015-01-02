PROJECT( example )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

#
# Platform functions. When that API is more stable, we'll
# simply wrap it in a library but for now, we require
# compiler and layout compliance.
#
# The cheap way is to just recurse until recursion fail
# (i.e. we reach /) and look for the first src tree.
#
if (NOT ARCAN_SOURCE_DIR)
	get_filename_component(ASD_SEARCH ${CMAKE_CURRENT_SOURCE_DIR} ABSOLUTE)
	set(ASD_LAST "/")

	while(NOT ${ASD_LAST} STREQUAL ${ASD_SEARCH} AND NOT ARCAN_SOURCE_DIR)
		set(ASD_LAST ${ASD_SEARCH})
		get_filename_component(ASD_SEARCH ${ASD_SEARCH} DIRECTORY)
		if (IS_DIRECTORY ${ASD_SEARCH}/src)
			set(ARCAN_SOURCE_DIR ${ASD_SEARCH}/src)
		endif()
	endwhile()

	if (NOT ARCAN_SOURCE_DIR)
		message(FATAL_ERROR "ARCAN_SOURCE_DIR is not set, use -DARCAN_SOURCE_DIR=")
	endif()
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

add_executable(example ${SOURCES} ${SHMIF_SOURCES})
target_link_libraries(example ${LIBRARIES})
