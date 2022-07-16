PROJECT( aloadimage )
cmake_minimum_required(VERSION 3.1.0 FATAL_ERROR)
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

find_package(Math REQUIRED)
find_package(RT REQUIRED)
find_package(DL REQUIRED)
find_package(Threads REQUIRED)
find_package(Sanitizers REQUIRED)

include(GNUInstallDirs) # CMAKE_INSTALL_MANDIR

SET(LIBRARIES
	Math::Math
	RT::RT
	DL::DL
	Threads::Threads
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

include_directories(${ARCAN_SHMIF_INCLUDE_DIR} ${ARCAN_TUI_INCLUDE_DIR})

SET(SOURCES
	${PROJECT_NAME}.c
	imgload.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
install(TARGETS ${PROJECT_NAME} DESTINATION ${CMAKE_INSTALL_BINDIR})
add_sanitizers(${PROJECT_NAME})

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/aloadimage.1 DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
