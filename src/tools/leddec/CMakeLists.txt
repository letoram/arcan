PROJECT( leddec )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
find_package(PkgConfig)

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../platform/cmake/modules)
if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED)
endif()

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-DDEBUG)
endif()

SET(LIBRARIES
	m
	${ARCAN_SHMIF_LIBRARY}
)

if (PKG_CONFIG_FOUND)
	pkg_search_module(SECCOMP libseccomp)
	if (SECCOMP_FOUND)
		message("secomp found, enabling syscall filtering")
		add_definitions(-DENABLE_SECCOMP)
		list(APPEND LIBRARIES seccomp)
	else()
		message("No seccomp found, syscall filtering disabled")
	endif()
else()
	message("No pkg-config found, disabling seccomp")
endif()

if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	add_definitions(-D__APPLE__)
endif()

add_definitions(
	-Wall
  -Wno-unused-function
  -Wno-unused-variable
	-fpic
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-std=gnu11 # shmif-api requires this
)

include_directories(${ARCAN_SHMIF_INCLUDE_DIR})

SET(SOURCES
	${PROJECT_NAME}.c
	leddec.c
)

add_executable(${PROJECT_NAME} ${SOURCES} ${SHMIF_SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})

install(TARGETS ${PROJECT_NAME} DESTINATION bin)
