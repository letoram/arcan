PROJECT( arcan_vr )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

find_package(PkgConfig)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-D_DEBUG)
endif()

if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED)
endif()

add_definitions(
	-Wall
	-D__UNIX
	-DPSVR
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
  -Wno-unused-but-set-variable
	-Wno-unused-function
	-std=gnu11 # shmif-api requires this
)

set(ARCAN_ROOT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${ARCAN_ROOT_DIR}/src/platform/cmake/modules)

include_directories(
	${ARCAN_SHMIF_INCLUDE_DIR}
	${ARCAN_ROOT_DIR}/src/engine
	${ARCAN_ROOT_DIR}/src/shmif
	${ARCAN_ROOT_DIR}/external
)

SET(LIBRARIES
	pthread
	m
	${ARCAN_SHMIF_LIBRARY}
)

if (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	find_package(libusb-1.0 REQUIRED)
	set(PLATFORM_SOURCES
		${ARCAN_ROOT_DIR}/external/hidapi/hid.c
		${ARCAN_ROOT_DIR}/src/platform/posix/time.c
	)
	set(LIBRARIES ${LIBRARIES} ${LIBUSB_1_LIBRARIES})
	include_directories(${LIBUSB_1_INCLUDE_DIR})

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	find_library(IOKIT NAMES IOKit)
	find_library(COREFOUNDATION NAMES CoreFoundation)
	set(PLATFORM_SOURCES
		${ARCAN_ROOT_DIR}/external/hidapi/hid_darwin.c
		${ARCAN_ROOT_DIR}/src/platform/darwin/time.c
	)
	set(LIBRARIES ${LIBRARIES} ${IOKIT} ${COREFOUNDATION})

elseif (${CMAKE_SYSTEM_NAME} MATCHES "BSD" OR ${CMAKE_SYSTEM_NAME}} MATCHES "DragonFly")
	add_definitions(-DLIBUSB_BSD)
	set(LIBRARIES ${LIBRARIES} usb usbhid)
	set(PLATFORM_SOURCES
		${ARCAN_ROOT_DIR}/src/platform/posix/time.c
		${ARCAN_ROOT_DIR}/external/hidapi/hid.c
	)
else()
	set(PLATFORM_SOURCES
		${ARCAN_ROOT_DIR}/external/hidapi/hid.c
		${ARCAN_ROOT_DIR}/src/platform/posix/time.c
	)
endif()

set(SOURCES
	vrbridge.c
	ahrs.c
	psvr.c
	test.c
	${ARCAN_ROOT_DIR}/src/engine/arcan_math.c
	${PLATFORM_SOURCES}
)

add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${LIBRARIES})
