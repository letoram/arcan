PROJECT( proxycon )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../src/platform/cmake/modules)

if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED)
endif()

add_definitions(
	-Wall
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-std=gnu11 # shmif-api requires this
)

include_directories(${ARCAN_SHMIF_INCLUDE_DIR})

SET(LIBRARIES
				#	rt
	pthread
	m
	${ARCAN_SHMIF_SERVER_LIBRARY}
)

SET(SOURCES
	${PROJECT_NAME}.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
