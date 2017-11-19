PROJECT( arcan-net )
cmake_minimum_required(VERSION 3.0.4 FATAL_ERROR)

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
	m
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_SHMIF_SERVER_LIBRARY}
)

set(SOURCES
	blake2bp-ref.c
	blake2b-ref.c
	a12.c
)

add_executable( arcan-netpipe ${SOURCES} netpipe.c)
add_executable( arcan-net ${SOURCES} netproxy.cpp)

set_property(TARGET arcan-net PROPERTY CXX_STANDARD 11)
set_property(TARGET arcan-netpipe PROPERTY C_STANDARD 11)

target_link_libraries(arcan-net ${LIBRARIES}
	pthread
	${CMAKE_CURRENT_BINARY_DIR}/udt-prefix/src/udt-build/libudt.a
)
target_link_libraries(arcan-netpipe ${LIBRARIES})

install(TARGETS arcan-net arcan-netpipe DESTINATION bin)
