PROJECT( netproxy )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

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
	-Wno-unused-function
	-std=c++11
)

include(ExternalProject)

ExternalProject_Add(udt
	SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/udt"
	UPDATE_COMMAND ""
	GIT_REPOSITORY  "https://github.com/letoram/UDT"
	UPDATE_COMMAND ""
	PATCH_COMMAND ""
	INSTALL_COMMAND ""
	LOG_DOWNLOAD 1
	LOG_UPLOAD 1
	LOG_CONFIGURE 1
	LOG_BUILD 1
	LOG_TEST 1
	LOG_INSTALL 1
	-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
	-DMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
	-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
	-DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}
	-DLIBTYPE=STATIC
)

include_directories(
	${ARCAN_SHMIF_INCLUDE_DIR}
	${CMAKE_CURRENT_BINARY_DIR}/udt/src
)

SET(LIBRARIES
	pthread
	m
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_SHMIF_SERVER_LIBRARY}
	${CMAKE_CURRENT_BINARY_DIR}/udt-prefix/src/udt-build/libudt.a
)

set(SOURCES
	netproxy.cpp
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
install(TARGETS ${PROJECT_NAME} DESTINATION bin)
