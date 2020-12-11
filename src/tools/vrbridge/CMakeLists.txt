PROJECT( arcan_vr )
cmake_minimum_required(VERSION 3.1.0 FATAL_ERROR)
find_package(PkgConfig REQUIRED)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-D_DEBUG)
endif()

set(ARCAN_ROOT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${ARCAN_ROOT_DIR}/src/platform/cmake/modules)

include(FindPkgConfig)
if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED)
endif()

add_definitions(
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-Wall
	-Wno-unused-const-variable
	-Wno-unused-function
	${CMAKE_THREADS_LIBS_INIT}
)

include_directories(
	${ARCAN_SHMIF_INCLUDE_DIR}
	${ARCAN_ROOT_DIR}/src/engine
	${ARCAN_ROOT_DIR}/external/hidapi
)

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Math REQUIRED)
find_package(RT REQUIRED)
find_package(Threads REQUIRED)
find_package(DL REQUIRED)

SET(LIBRARIES
	Threads::Threads
	Math::Math
	RT::RT
	DL::DL
	${ARCAN_SHMIF_LIBRARY}
)

if (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	pkg_check_modules(LIBUSB_1 REQUIRED libusb-1.0)
	set(PLATFORM_SOURCES
		${ARCAN_ROOT_DIR}/external/hidapi/hid.c
		${ARCAN_ROOT_DIR}/src/platform/posix/time.c
	)
	set(LIBRARIES ${LIBRARIES} ${LIBUSB_1_LINK_LIBRARIES})
	include_directories(${LIBUSB_1_INCLUDE_DIRS})

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	find_library(IOKIT NAMES IOKit)
	find_library(COREFOUNDATION NAMES CoreFoundation)
	set(PLATFORM_SOURCES
		${ARCAN_ROOT_DIR}/external/hidapi/hid_darwin.c
		${ARCAN_ROOT_DIR}/src/platform/darwin/time.c
	)
	set(LIBRARIES ${LIBRARIES} ${IOKIT} ${COREFOUNDATION})

elseif (${CMAKE_SYSTEM_NAME} MATCHES "BSD|DragonFly")
	pkg_check_modules(LIBUSB_1 REQUIRED libusb-1.0)
	add_definitions(-DLIBUSB_BSD)
	set(LIBRARIES ${LIBRARIES} iconv ${LIBUSB_1_LINK_LIBRARIES})
	include_directories(${LIBUSB_1_INCLUDE_DIRS})
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
	openhmd.c
	test.c
	${ARCAN_ROOT_DIR}/src/engine/arcan_math.c
	${PLATFORM_SOURCES}
)

add_executable(${PROJECT_NAME} ${SOURCES})

if (DEFINED NO_BUILTIN_OPENHMD)
	pkg_check_modules(OPENHMD REQUIRED openhmd)
	if (OPENHMD_FOUND)
		include_directories(${OPENHMD_INCLUDE_DIRS})
		list(APPEND LIBRARIES ${OPENHMD_LINK_LIBRARIES})
		list(APPEND SOURCES openhmd.c)
		add_definitions(-DOPENHMD)
	endif()
else()
	add_subdirectory("OpenHMD")
	include_directories(${CMAKE_CURRENT_SOURCE_DIR}/OpenHMD)
	list(APPEND LIBRARIES openhmd)
endif()

target_link_libraries(${PROJECT_NAME} ${LIBRARIES})

install(TARGETS ${PROJECT_NAME} DESTINATION bin)
