PROJECT( keystore )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(BASEDIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../src)
set(CMAKE_MODULE_PATH ${BASEDIR}/platform/cmake/modules)

find_package(arcan_shmif REQUIRED)

add_definitions(
	-Wall
	-D__UNIX
	-DPOSIX_C_SOURCE
	-D_GNU_SOURCE
	-Wno-unused-function
	-std=gnu11 # shmif-api requires this
)

include_directories(
	${ARCAN_SHMIF_INCLUDE_DIR}
	${BASEDIR}/frameserver/util
	${BASEDIR}/a12
)

SET(LIBRARIES
				#	rt
	pthread
	m
	arcan_a12
	${ARCAN_SHMIF_SERVER_LIBRARY}
)

SET(SOURCES
	${PROJECT_NAME}.c
	${BASEDIR}/frameserver/util/anet_keystore_naive.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
