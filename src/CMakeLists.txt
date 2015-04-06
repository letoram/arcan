PROJECT( arcan )
include(ExternalProject)
include(CheckIncludeFiles)
cmake_minimum_required(VERSION 2.8.8 FATAL_ERROR)

set(EXTERNAL_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake)
if (GLOBAL_CFLAGS)
	add_definitions(${GLOBAL_CFLAGS})
endif()

# static base version, manually mantained
set(MAJOR_VERSION 0 )
set(MINOR_VERSION 5 )
set(PATCH_LEVEL 0 )
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})
set(PLATFORM_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/platform)

# blacklist some built-ins
if (NOT LUA_DROPSTR)
set (LUA_DROPSTR "io os package rawequal rawset rawget setfenv coroutine module require")
endif()

if (NOT GIT_MIRROR)
	SET(GIT_MIRROR "https://www.github.com/mirror")
endif()

# generate an identifiable buildtag for tracking purposes
if (NOT DEFINED ENGINE_BUILDTAG)
	find_package(Git)
	if (GIT_FOUND)
		execute_process(COMMAND ${GIT_EXECUTABLE} describe --always
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			RESULT_VARIABLE EXIT_CODE
			OUTPUT_VARIABLE GIT_VERSION
		)
		if (NOT ${EXIT_CODE} EQUAL 0)
			message(FATAL_ERROR "Extracting build tag using git failed, -DENGINE_BUILDTAG=mytag manually")
		endif()

		string(STRIP ${GIT_VERSION} GIT_VERSION)

		execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			RESULT_VARIABLE EXIT_CODE
			OUTPUT_VARIABLE GIT_BRANCH
		)
		if (NOT ${EXIT_CODE} EQUAL 0)
			message(FATAL_ERROR "Extracting build tag using git failed, -DENGINE_BUILDTAG=mytag manually")
		endif()

		string(STRIP ${GIT_BRANCH} GIT_BRANCH)

		set(ENGINE_BUILDTAG arcan-git-${GIT_BRANCH}-${GIT_VERSION})
	else()
		message(FATAL_ERROR "ENGINE_BUILDTAG not found and no git checkout detected, -DENGINE_BUILDTAG=mytag manually")
	endif()
endif()

if (NOT DEFINED ENGINE_BUILDTAG)
	include(GetGitRevisionDescription)
	git_describe(ENGINE_BUILDTAG)
	if (${ENGINE_BUILDTAG} MATCHES "NOTFOUND")
	endif()
endif()

set(SHARED_PERMISSIONS OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_READ)
set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE
		GROUP_READ WORLD_EXECUTE WORLD_READ)

if (WIN32)
	set(VPLATFORM_STR "sdl")
	set(VIDEO_PLATFORM "sdl")
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	set(VPLATFORM_STR "sdl")
	set(VIDEO_PLATFORM "sdl")
else()
	set(VPLATFORM_STR "x11|x11-headless|sdl|egl-gles|egl-dri|egl-nvidia")
endif()
set(AGPPLATFORM_STR "gl21|gles2|gles3|stub")

#
# for linux/BSD, we can build a 32-bit version of the hi-jack lib as well,
# and use it for 32-bit targets.
#
if( CMAKE_SIZEOF_VOID_P EQUAL 4 )
	set( HAVE_64_BIT 0 )
else()
	option(ENABLE_32BITHIJACK "Build both 64 and 32bit hijack libraries" OFF)
	set( HAVE_64_BIT 1 )
endif()

option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)
option(ENABLE_LUAJIT "Use the luajit-5.1 VM (if found)" ON)
option(ENABLE_SIMD "Build with SIMD vector instruction set support" ON)
option(ENABLE_LED "Build with LED controller support in core" OFF)
option(ENABLE_LTO "Build with Link-Time Optimization enabled" OFF)
if (NOT WIN32)
	option(MUSL_LIBC "Use the MUSL libc implementation (incomplete)" OFF)
	option(ENABLE_LWA "Build a lightweight arcan (arcan_lwa) with nested platform" OFF)
endif()
option(ENABLE_SIMD_ALIGNED "Assert that SIMD data sources are 16-byte aligned" OFF)

message("")
message("Cmake options:")
message("   -DCMAKE_BUILD_TYPE=[Debug|Release|Profile|DebugTrace]")
message("   -DENABLE_ASAN=[Off|On] : Build with Address Sanitizer enabled")
message("   -DENABLE_SIMD=[On|Off] : Enable SIMD optimized instructions")
message("   -DENABLE_LTO=[Off|On] : Build with Link-Time Optimizations")
# message("    -DENABLE_PBO=[Appl-path] : Profile-based Optimization prepass with appl")
# message("                               as optimization profile.")
message("   -DENABLE_SIMD_ALIGNED=[Off|On] : |--> SIMD support assumes 16-byte alignment")
message("")
message("audio/video/input support:")
message("   -DVIDEO_PLATFORM=${VPLATFORM_STR} : Set video/display platform")
message("   -DAGP_PLATFORM=${AGPPLATFORM_STR} : Set video/rendering platform")
message("")
message("optimization / core features:")
message("   -DENABLE_LED=[On|Off] : Build with LED controller support in core")
message("   -DENABLE_LWA=[Off|On] : Build lightweight additional arcan client")
message("   -DENABLE_LUAJIT=[On|Off] : link with luajit51 (if found)")
message("")

# Hooks added here to later switch to -nostdlib -nodefaultlibs and get a decent libc for linux
set (STDLIB
	m
	pthread
)

# no other audio platforms supported currently
set(AUDIO_PLATFORM "openal")

#
# Incomplete still, will probably be extended / fixed when testing/building on Alpine Linux
# (openrc, grsec and free from systemd and glibc? interesting - can we just drop pulse
# and d-bus as well, or switch to the reasonably clean nobus implementation)
#
if (MUSL_LIBC)
	set(MUSL ${CMAKE_CURRENT_SOURCE_DIR}/external/musl)
	ExternalProject_Add(
	libmusl
	SOURCE_DIR ${MUSL}
	CONFIGURE_COMMAND ${MUSL}/configure --prefix=${MUSL}/.libs --disable-shared
	PREFIX ${MUSL}
	BUILD_COMMAND make
	BUILD_IN_SOURCE 1
	)
	set(STDLIB ${MUSL}/.libs/lib/libc.a)
endif()

message(STATUS "Using compiler: ${CMAKE_C_COMPILER_ID}")

if ("${CMAKE_C_COMPILER_ID}" MATCHES "GNU")
	execute_process(
		COMMAND ${CMAKE_C_COMPILER} -dumpversion OUTPUT_VARIABLE GCC_VERSION)

	if (NOT (GCC_VERSION VERSION_GREATER 4.7 OR GCC_VERSION VERSION_EQUAL 4.7))
		message(FATAL_ERROR "Ancient GCC Version detected, Arcan needs to be compiled with Clang-3.3+ or 4.7+")
	endif()

elseif ("${CMAKE_C_COMPILER_ID}" MATCHES "Clang")
else()
	message(FATAL_ERROR "Arcan requires an ISO C 9899:2011 capable compiler (Clang-3.3+ or gcc 4.7+)")
endif()

if (CMAKE_BUILD_TYPE STREQUAL "Profile")
	message("------------------*Profile Build*------------------")
	add_definitions(-pg)
	set(CMAKE_EXE_LINKER_FLAGS "-pg")
endif(CMAKE_BUILD_TYPE STREQUAL "Profile")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	message("------------------*Debug Build*--------------------")
	add_definitions(-g -D_DEBUG -O0 -fno-omit-frame-pointer)
endif (CMAKE_BUILD_TYPE STREQUAL "Debug")

if (CMAKE_BUILD_TYPE STREQUAL "DebugTrace")
	message("-------------- *Debug Tracing Build* --------------")
	add_definitions(-g -D_DEBUG -DTRACE_ENABLE)
endif (CMAKE_BUILD_TYPE STREQUAL "DebugTrace")

if (ENABLE_ASAN)
	if (ASAN_TYPE)
		set(CMAKE_C_FLAGS "-fsanitize=${ASAN_TYPE} ${CMAKE_C_FLAGS}")
	else()
		set(CMAKE_C_FLAGS "-fsanitize=address ${CMAKE_C_FLAGS}")
	endif()
endif (ENABLE_ASAN)

if (ENABLE_LTO)
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -flto")
endif()

# --- Step 1, Dependencies / find package flags
find_package(Freetype REQUIRED)
find_package(PNG REQUIRED)
find_package(OpenAL REQUIRED)
find_package(SQLITE3 REQUIRED)
find_package(SSE)

include(${PLATFORM_ROOT}/CMakeLists.AGP)
include(${PLATFORM_ROOT}/CMakeLists.Video)

message("\n---- Stage 1: library dependencies and configuration ----")
if (NOT SQLITE_AMALGAMATE)
endif(NOT SQLITE_AMALGAMATE)

message(STATUS "Lua")
if (ENABLE_LUAJIT)
	message(STATUS "Looking for JIT enabled LUA VM")
	FIND_PACKAGE ( Lua51JIT )
endif()

if (NOT LUA_LIBRARY)
	FIND_PACKAGE ( Lua51 )
endif (NOT LUA_LIBRARY)

if (NOT LUA_LIBRARIES)
	message("--> Lua Library not found, building from external/lua")
	add_subdirectory( external/lua )
	set (LUA_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external/lua)
	set (LUA_LIBRARIES lua51 )
endif (NOT LUA_LIBRARIES)

#
# We split MAIN_LIBRARIES into ARCANMAIN_LIBRARIES and MAIN_LIBRARIES
# as some customisations would conflict with building the LWA version.
#
LIST (APPEND
	ARCANMAIN_LIBRARIES
	${OPENAL_LIBRARY}
)

LIST (APPEND
	MAIN_LIBRARIES
	openctm
	${FREETYPE_LIBRARY}
	${LUA_LIBRARIES}
	${SQLITE3_LIBRARIES}
	${PNG_LIBRARIES}
)

LIST (APPEND
	INCLUDE_DIRS
	${LUA_INCLUDE_DIR}
	${OPENAL_INCLUDE_DIR}
	${PNG_INCLUDE_DIR}
	${FREETYPE_INCLUDE_DIRS}
	${SQLITE3_INCLUDE_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/platform
	${EXTERNAL_SRC_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/shmif
	${CMAKE_CURRENT_SOURCE_DIR}/engine
)

add_subdirectory( ${EXTERNAL_SRC_DIR}/openctm )

#
# engine source files + graphics platform
#
list (APPEND
 SOURCES
 engine/arcan_event.c
 engine/arcan_lua.c
 engine/arcan_main.c
 engine/arcan_db.c
 engine/arcan_video.c
 engine/arcan_renderfun.c
 engine/arcan_3dbase.c
 engine/arcan_math.c
 engine/arcan_audio.c
 engine/arcan_ttf.c
 engine/arcan_img.c
 engine/arcan_audioint.h
 engine/arcan_event.h
 engine/arcan_lua.h
 engine/arcan_math.h
 engine/arcan_3dbase.h
 engine/arcan_video.h
 engine/arcan_audio.h
 engine/arcan_general.h
 engine/arcan_db.h
 engine/arcan_frameserver.h
 engine/arcan_frameserver.c
 shmif/arcan_shmif.h
 shmif/arcan_shmif_interop.h
 shmif/arcan_shmif_control.c
 shmif/arcan_shmif_control.h
 shmif/arcan_shmif_event.h
)

# database tool is sqlite3 + libc so less need to work
# around with platform layers etc.
set (ARCANDB_SOURCES
	engine/arcan_dbtool.c
	engine/arcan_db.c
	platform/posix/warning.c
	platform/stub/mem.c
)

if (ENABLE_SIMD AND SSE_FOUND)
	message("--> Enabling SIMD")

	if (ENABLE_SIMD_ALIGNED)
		message("      |--> Asserting SIMD operands are aligned")
		message("           These can *crash* at odd intervals on ")
		message("           poor _Alignas implementations")
		set_property(SOURCE engine/arcan_math_simd.c
			APPEND PROPERTY COMPILE_DEFINITIONS ARCAN_MATH_ALIGNED_SIMD)
	endif()

	set_property(SOURCE engine/arcan_math.c
		APPEND PROPERTY COMPILE_DEFINITIONS ARCAN_MATH_SIMD)
	list(APPEND SOURCES engine/arcan_math_simd.c)

	set_property(SOURCE engine/arcan_math_simd.c
		APPEND PROPERTY COMPILE_FLAGS -msse3)
endif()

if (ENABLE_LED)
	message("--> Adding LED controller support.")
	list(APPEND ${SOURCES}
		arcan_led.c
		arcan_led.h
	)
	add_definitions(-DARCAN_LED)
endif()

if (LUA51_JIT)
	message("--> Enabling JIT- mode for Lua.")
	set_property(SOURCE engine/arcan_lua.c APPEND PROPERTY
		COMPILE_DEFINITIONS LUA51_JIT)
	set(LUA_TAG "luajit51")
else()
	set(LUA_TAG "lua51")
endif()

set(ENGINE_BUILDTAG ${ENGINE_BUILDTAG}-${VIDEO_PLATFORM}-${AGP_PLATFORM}-${AUDIO_PLATFORM}-${INPUT_PLATFORM}-${LUA_TAG})

set (SHMIF_SOURCES
  shmif/arcan_shmif.h
	shmif/arcan_shmif_interop.h
	shmif/arcan_shmif_control.c
	shmif/arcan_shmif_control.h
	shmif/arcan_shmif_interop.c
	shmif/arcan_shmif_event.h
)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/shmif)

message("\n---- Stage 1 configuration ----")
message("video output (VIDEO_PLATFORM) set to : ${VIDEO_PLATFORM}")
message("audio output (AUDIO_PLATFORM) set to : ${AUDIO_PLATFORM}")
message("device input (INPUT_PLATFORM) set to : ${INPUT_PLATFORM}")

#
# Expand with more platforms as needed, all are expected to define
# PLATFORM_[ ,fsrv, shmif]_SOURCES, add a global definition
# for PLATFORM_HEADER add any OS- specific definitions to
# MAIN_LIBRARIES, set OS_DYLIB_EXTENSION
#
if (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
	message("\n---- Stage 2, FreeBSD specific ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.FreeBSD)

elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	message("\n---- Stage 2, Linux specific ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.Linux)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	message("\n---- Stage 2, Windows specific ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.Windows)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	message("\n---- Stage 2, OSX/Darwin specific ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.Darwin)

else()
	message(FATAL_ERROR "Unsupported OS detected, abandon ship!.")
endif()

message("\n---- Stage 3, SHMIF Library ----")
add_library(arcan_shmif STATIC
	${SHMIF_SOURCES}
	${SHMIF_PLATFORM}
)
target_link_libraries(arcan_shmif PRIVATE ${STDLIB})

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
add_subdirectory(frameserver)

set_property(SOURCE engine/arcan_lua.c engine/arcan_main.c APPEND PROPERTY
	COMPILE_DEFINITIONS FRAMESERVER_MODESTRING=\"${FRAMESERVER_MODESTRING}\"
	LUA_DROPSTR=\"${LUA_DROPSTR}\" ARCAN_BUILDVERSION=\"${ENGINE_BUILDTAG}\")

message("\n---- Stage 4, Linking / Packaging ----")

if (HEADLESS_PLATFORM)
	message("\n---- Stage 4, LWA Build ----")
	include(platform/CMakeLists.LWA)
else()
	message("\n---- Stage 4, LWA Build (omitted) ----")
endif()

add_executable(arcan_db ${ARCANDB_SOURCES})
target_link_libraries(arcan_db ${STDLIB} ${SQLITE3_LIBRARIES})
target_include_directories(arcan_db PRIVATE ${INCLUDE_DIRS})

# GCC *** requiring dl to be the last argument to avoid dlclose in some
# edge-cases? just take them out behind the shed and pull the trigger.

add_executable(arcan
	${SOURCES}
	${ARCAN_PLATFORM}
	${AGP_SOURCES}
 	${PLATFORM_SOURCES}
)

target_include_directories(arcan PRIVATE ${INCLUDE_DIRS})
target_compile_definitions(arcan PRIVATE ${ARCAN_DEFINITIONS})
target_link_libraries( arcan
	${STDLIB}
	${MAIN_LIBRARIES}
	${AGP_LIBRARIES}
	${ARCANMAIN_LIBRARIES}
)

#
# The database tool is a CLI for the engine/arcan_db with additional
# code not part of the main arcan binaries (to make it somewhat harder
# for a misbehaving script to add / introduce new configs / targets
# and execute them.
#

set_property(TARGET arcan_db APPEND PROPERTY
				COMPILE_DEFINITIONS ARCAN_DB_STANDALONE )
