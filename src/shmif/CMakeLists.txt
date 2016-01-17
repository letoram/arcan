#
# This is used by the main arcan build system to define the shmif platform
# and install targets, but also for some external projects that need to
# do an in-source build of shmif- and its platform (automated build/
# test systems etc) without a full installation.
#
# Defines:
# ARCAN_SHMIF_INCLUDE_DIR
# ARCAN_SHMIF_LIBRARY (set to arcan_shmif_int)
#
# Targets:
# arcan_shmif
# arcan_shmif_int
#
# Installs: (if ARCAN_SOURCE_DIR is not set)
#
set(ASHMIF_MAJOR 0)
set(ASHMIF_MINOR 7)

if (ARCAN_SOURCE_DIR)
	set(ASD ${ARCAN_SOURCE_DIR})
else()
	set(ASD ${CMAKE_CURRENT_SOURCE_DIR}/../)
endif()

if (STDLIB)
	set(ASHMIF_STDLIB ${STDLIB})
else()
	set(ASHMIF_STDLIB -lrt)
endif()

set(ASHMIF_INSTPATH lib/arcan)

set (SHMIF_HEADERS
	${ASD}/shmif/arcan_shmif_control.h
	${ASD}/shmif/arcan_shmif_interop.h
	${ASD}/shmif/arcan_shmif_event.h
	${ASD}/shmif/arcan_shmif.h
)

set (SHMIF_SOURCES
	${SHMIF_HEADERS}
	${ASD}/shmif/arcan_shmif_control.c
)

if (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
	set(SHMIF_PLATFORM
		${ASD}/platform/posix/warning.c
		${ASD}/platform/posix/time.c
		${ASD}/platform/posix/sem.c
		${ASD}/platform/posix/fdpassing.c
	)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	set(SHMIF_PLATFORM
		${ASD}/platform/posix/warning.c
		${ASD}/platform/posix/time.c
		${ASD}/platform/posix/sem.c
		${ASD}/platform/posix/fdpassing.c
	)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	set(SHMIF_PLATFORM
		${ASD}/platform/posix/warning.c
		${ASD}/platform/darwin/time.c
		${ASD}/platform/darwin/sem.c
		${ASD}/platform/posix/fdpassing.c
	)
	set(ASHMIF_INSTPATH lib)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
# missing at the moment
else()
	message(FATAL_ERROR "attempted to build arcan-shmif on an unsupported OS/platform")
endif()

set_property(SOURCE ${ASD}/platform/posix/fdpassing.c
	APPEND PROPERTY COMPILE_FLAGS -w)
set_property(SOURCE ${ASD}/platform/posix/fdpassing.c
	APPEND PROPERTY COMPILE_DEFINITIONS NONBLOCK_RECV)

add_library(arcan_shmif_int STATIC ${SHMIF_SOURCES} ${SHMIF_PLATFORM})
add_library(arcan_shmif SHARED ${SHMIF_SOURCES} ${SHMIF_PLATFORM})
target_link_libraries(arcan_shmif PRIVATE ${STDLIB})
target_link_libraries(arcan_shmif_int PRIVATE ${STDLIB})

# note that we enable fpic for the static here as some
# subdirectores need to pull it in as part of building a shared library
set_target_properties(arcan_shmif_int PROPERTIES
	COMPILE_FLAGS -fPIC
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
	SOVERSION ${ASHMIF_MAJOR}
)
set(ARCAN_SHMIF_INCLUDE_DIR ${ASD}/shmif PARENT_SCOPE)
set(ARCAN_SHMIF_LIBRARY arcan_shmif_int ${ASHMIF_STDLIB} PARENT_SCOPE)

target_include_directories(arcan_shmif_int PRIVATE ${ASD}/shmif)
target_include_directories(arcan_shmif PRIVATE ${ASD}/shmif)

if (NOT ARCAN_SOURCE_DIR)
	install(TARGETS arcan_shmif arcan_shmif_int
		LIBRARY DESTINATION ${ASHMIF_INSTPATH}
		ARCHIVE DESTINATION ${ASHMIF_INSTPATH}
	)
	install(FILES ${SHMIF_HEADERS} DESTINATION include/arcan/shmif)

# The config file is more similar to a regular find module,
# the procedure for doing something this trivial ("install library,
# provide means for other projects to find library") seems excessively
# verbose and 'cmake:y'.
	install(FILES ${PLATFORM_ROOT}/cmake/arcan_shmif-config.cmake
		DESTINATION CMake COMPONENT dev)
endif()
