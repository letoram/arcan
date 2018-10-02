PROJECT( ltui )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
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

set(ARCAN_SOURCE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../)

include_directories(${ARCAN_SHMIF_INCLUDE_DIR} ${ARCAN_TUI_INCLUDE_DIR}
	${ARCAN_SOURCE_ROOT}/../external/lua ${ARCAN_SOURCE_ROOT}/shmif/tui)
add_subdirectory(${ARCAN_SOURCE_ROOT}/../external/lua ${CMAKE_CURRENT_BINARY_DIR}/lua)

SET(LIBRARIES
	pthread
	m
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_TUI_LIBRARY}
	lua51
)

SET(SOURCES
	ltui.c
	${ARCAN_SOURCE_ROOT}/shmif/tui/tui_lua.c
)

install(TARGETS ${PROJECT_NAME} DESTINATION bin)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
