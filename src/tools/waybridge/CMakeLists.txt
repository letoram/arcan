PROJECT( arcan-wayland )
cmake_minimum_required(VERSION 3.1.0 FATAL_ERROR)
set(ARCAN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../")
set(CMAKE_MODULE_PATH ${ARCAN_ROOT}platform/cmake/modules)

include(Wayland)
find_package(Wayland)

set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
set(THREADS_PREFER_PTHREAD_FLAG TRUE)
find_package(Threads REQUIRED)
find_package(Math REQUIRED)
find_package(RT REQUIRED)
find_package(DL REQUIRED)
find_package(WaylandProtocols REQUIRED)
find_package(Sanitizers REQUIRED)
find_package(XKB REQUIRED)

set(STDLIB Threads::Threads RT::RT DL::DL Math::Math)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-D_DEBUG)
endif()

if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED WITH_EXT)
endif()

include_directories(
	xwl
	${ARCAN_SHMIF_INCLUDE_DIR}
	${WAYLAND_SERVER_INCLUDE_DIRS}
	${CMAKE_CURRENT_BINARY_DIR}
	${XKB_INCLUDE_DIRS}
	${ARCAN_ROOT}
)

add_definitions(
	-Wall
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
  -Wno-unused-but-set-variable
	-Wno-unused-function
	-Wno-unused-const-variable
	-Wno-unknown-warning-option
	${CMAKE_THREAD_LIBS_INIT}
	-std=gnu11 # shmif-api requires this
)

if (PKG_CONFIG_FOUND)
	pkg_search_module(SECCOMP libseccomp)
	if (SECCOMP_FOUND)
		message("secomp found, enabling syscall filtering")
		add_definitions(-DENABLE_SECCOMP)
		list(APPEND WAYLAND_SERVER_LIBRARIES seccomp)
	else()
		message("No seccomp found, syscall filtering disabled")
	endif()
else()
	message("No pkg-config found, disabling seccomp")
endif()

# copied from Cloudef/wlc/protos
set(PROTOCOLS
	"${WAYLANDPROTOCOLS_PATH}/unstable/xdg-shell/xdg-shell-unstable-v6"
	"${WAYLANDPROTOCOLS_PATH}/unstable/linux-dmabuf/linux-dmabuf-unstable-v1"
	"${WAYLANDPROTOCOLS_PATH}/unstable/pointer-constraints/pointer-constraints-unstable-v1"
	"${WAYLANDPROTOCOLS_PATH}/unstable/relative-pointer/relative-pointer-unstable-v1"
	"${WAYLANDPROTOCOLS_PATH}/unstable/idle-inhibit/idle-inhibit-unstable-v1"
	"${WAYLANDPROTOCOLS_PATH}/stable/xdg-shell/xdg-shell"
	"${CMAKE_CURRENT_SOURCE_DIR}/wlimpl/wayland-drm"
)

list(APPEND sources ${src})

foreach(proto ${PROTOCOLS})
   get_filename_component(base ${proto} NAME)
   wayland_add_protocol_server(src "${proto}.xml" ${base})
   list(APPEND sources ${src})
endforeach()

set_source_files_properties(${sources} PROPERTIES GENERATED ON)
add_library(wlprot STATIC ${sources})

SET(LIBRARIES
	EGL
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_SHMIF_EXT_LIBRARY}
	${WAYLAND_SERVER_LIBRARIES}
	${XKB_LIBRARIES}
	${STDLIB}
	wlprot
)

SET(XWM_LIBRARIES
	xcb
	xcb-composite
	xcb-icccm
	${STDLIB}
	${ARCAN_SHMIF_LIBRARY}
)

SET(SOURCES
	waybridge.c
)

add_executable(arcan-wayland ${SOURCES})
add_executable(arcan_xwm xwlwm/xwlwm.c)
target_link_libraries(arcan-wayland ${LIBRARIES})
target_link_libraries(arcan_xwm ${XWM_LIBRARIES})

add_sanitizers(${PROJECT_NAME})
install(TARGETS ${PROJECT_NAME} DESTINATION bin)
install(TARGETS arcan_xwm DESTINATION bin)

if (CMAKE_SYSTEM_NAME MATCHES "(FreeBSD|NetBSD|OpenBSD)")
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/arcan-wayland.1 DESTINATION man/man1)
else()
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/arcan-wayland.1 DESTINATION share/man/man1)
endif()#install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/arcan-wayland.1 DESTINATION man)
