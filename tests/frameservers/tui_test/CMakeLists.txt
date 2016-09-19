PROJECT( tui_test )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED arcan_shmif arcan_shmif_tui)
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
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_SHMIF_TUI_LIBRARY}
)

SET(SOURCES
	${PROJECT_NAME}.c
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
