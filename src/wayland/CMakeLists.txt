# This is used by the main arcan build system to detect and add wayland

if (DISABLE_WAYLAND)
	amsg("${CL_YEL}wayland support\t${CL_RED}disabled${CL_RST}")
	return()
endif()

include(Wayland)
pkg_check_modules(WAYLAND_SERVER wayland-server)

if (NOT WAYLAND_SERVER_FOUND)
	amsg("${CL_YEL}wayland support\t${CL_RED}not found${CL_RST}")
	return()
else()
	amsg("${CL_YEL}wayland support\t${CL_GRN}enabled${CL_RST}")
endif()

find_package(WaylandProtocols)
find_package(Sanitizers REQUIRED)
pkg_check_modules(XKB REQUIRED xkbcommon)

# The required bits and xwm can be made optional if there ever comes a day
# that Wayland is mostly useful without Xwayland ..
pkg_check_modules(XCB REQUIRED xcb xcb-composite xcb-icccm xcb-xfixes xcb-util)

set(WAYBRIDGE_INCLUDES
	xwl
	${WAYLAND_SERVER_INCLUDE_DIRS}
	${CMAKE_CURRENT_BINARY_DIR}
	${XKB_INCLUDE_DIRS}
	${XCB_INCLUDE_DIRS}
	${CMAKE_CURRENT_SOURCE_DIR}/../engine
	${CMAKE_CURRENT_SOURCE_DIR}/../engine/external
)

set(WAYBRIDGE_SOURCES
	waybridge.c
	${CMAKE_CURRENT_SOURCE_DIR}/../platform/posix/mem.c
)

pkg_search_module(SECCOMP libseccomp)
if (SECCOMP_FOUND)
	message("secomp found, enabling syscall filtering")
	add_definitions(-DENABLE_SECCOMP)
	list(APPEND WAYLAND_SERVER_LINK_LIBRARIES seccomp)
else()
	message("No seccomp found, syscall filtering disabled")
endif()

# copied from Cloudef/wlc/protos
set(PROTOCOLS
	"${WAYLANDPROTOCOLS_PATH}/unstable/pointer-constraints/pointer-constraints-unstable-v1"
	"${WAYLANDPROTOCOLS_PATH}/unstable/relative-pointer/relative-pointer-unstable-v1"
	"${WAYLANDPROTOCOLS_PATH}/unstable/idle-inhibit/idle-inhibit-unstable-v1"
	"${WAYLANDPROTOCOLS_PATH}/stable/xdg-shell/xdg-shell"
	"${CMAKE_CURRENT_SOURCE_DIR}/wlimpl/dmabuf"
	"${CMAKE_CURRENT_SOURCE_DIR}/wlimpl/xdg-output"
	"${CMAKE_CURRENT_SOURCE_DIR}/wlimpl/wayland-drm"
	"${CMAKE_CURRENT_SOURCE_DIR}/wlimpl/server-decoration"
	"${CMAKE_CURRENT_SOURCE_DIR}/wlimpl/xdg-decoration"
)

list(APPEND SOURCES ${src})

foreach(proto ${PROTOCOLS})
   get_filename_component(base ${proto} NAME)
   wayland_add_protocol_server(src "${proto}.xml" ${base})
   list(APPEND sources ${src})
endforeach()

set_source_files_properties(${sources} PROPERTIES GENERATED ON)
add_library(wlprot STATIC ${sources})
target_include_directories(wlprot PRIVATE ${WAYLAND_SERVER_INCLUDE_DIRS})

SET(WAYBRIDGE_LIBRARIES
	${STDLIB}
	${EGL_LIBRARIES}
	arcan_shmif_int
	arcan_shmif_intext
	${WAYLAND_SERVER_LINK_LIBRARIES}
	${XKB_LINK_LIBRARIES}
	wlprot
)

SET(XWM_LIBRARIES
	${STDLIB}
	${XCB_LINK_LIBRARIES}
	arcan_shmif_int
)

add_executable(arcan-wayland ${WAYBRIDGE_SOURCES})
add_executable(arcan_xwm xwlwm/xwlwm.c)
target_link_libraries(arcan-wayland ${WAYBRIDGE_LIBRARIES})
target_link_libraries(arcan_xwm ${XWM_LIBRARIES})
target_include_directories(arcan-wayland PRIVATE ${WAYBRIDGE_INCLUDES})
target_include_directories(arcan_xwm PRIVATE ${WAYBRIDGE_INCLUDES})

add_sanitizers(arcan-wayland)
install(TARGETS arcan-wayland DESTINATION ${CMAKE_INSTALL_BINDIR})
install(TARGETS arcan_xwm DESTINATION ${CMAKE_INSTALL_BINDIR})

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/arcan-wayland.1 DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
