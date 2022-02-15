PROJECT( glcube )
cmake_minimum_required(VERSION 3.1.0)

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../src/platform/cmake/modules)
if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED arcan_shmif arcan_shmif_ext)
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
	pthread
	m
	${ARCAN_SHMIF_LIBRARY}
	${ARCAN_SHMIF_EXT_LIBRARY}
)

SET(SOURCES
	esTransform.c
	${PROJECT_NAME}.c
)

FIND_PACKAGE(OpenGL REQUIRED)

add_executable(${PROJECT_NAME} ${SOURCES} ${SHMIF_SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES} ${OPENGL_gl_LIBRARY})
