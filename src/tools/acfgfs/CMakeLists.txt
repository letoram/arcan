PROJECT( acfgfs )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../platform/cmake/modules)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-D_DEBUG)
endif()

find_package(arcan_shmif REQUIRED)
find_package(fuse3 REQUIRED)

add_definitions(
	-Wall
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-Wno-unused-function
	-std=gnu11 # shmif-api requires this
)

SET(LIBRARIES
	pthread
	m
	${ARCAN_SHMIF_LIBRARY}
	${FUSE3_LIBRARIES}
)

set(SOURCES
	acfgfs.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
install(TARGETS ${PROJECT_NAME} DESTINATION bin)
target_include_directories(${PROJECT_NAME} PUBLIC ${ARCAN_SHMIF_INCLUDE_DIR} ${FUSE3_INCLUDE_DIRS})
