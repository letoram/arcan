PROJECT( a12loop )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../src/platform/cmake/modules)

find_package(arcan_shmif REQUIRED)

add_definitions(
	-Wall
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-Wno-unused-function
	-std=gnu11 # shmif-api requires this
)

include_directories(${ARCAN_SHMIF_INCLUDE_DIR})

SET(LIBRARIES
				#	rt
	pthread
	m
	arcan_a12
	${ARCAN_SHMIF_SERVER_LIBRARY}
)

SET(SOURCES
	${PROJECT_NAME}.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
