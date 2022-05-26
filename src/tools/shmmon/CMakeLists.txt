PROJECT( shmmon )
cmake_minimum_required(VERSION 3.1.0 FATAL_ERROR)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-D_DEBUG)
endif()

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../platform/cmake/modules)

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
	-std=gnu11 # shmif-api requires this
)

find_package(Math REQUIRED)
find_package(RT REQUIRED)
find_package(Threads REQUIRED)
find_package(DL REQUIRED)

include_directories(${ARCAN_SHMIF_INCLUDE_DIR})

SET(LIBRARIES
	Threads::Threads
	Math::Math
	RT::RT
	DL::DL
	${ARCAN_SHMIF_LIBRARY}
)

set(SOURCES
	shmmon.c
	parse-edid.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
install(TARGETS ${PROJECT_NAME} DESTINATION ${CMAKE_INSTALL_BINDIR})
