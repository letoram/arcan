PROJECT( arcan )
include(ExternalProject)
include(CheckIncludeFiles)
cmake_minimum_required(VERSION 2.8.8 FATAL_ERROR)

set(EXTERNAL_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake)

# static base version, manually mantained
set(MAJOR_VERSION 0 )
set(MINOR_VERSION 5 )
set(PATCH_LEVEL 0 )
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})

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
set( MAIN_LIBRARIES )

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
option(ENABLE_NET "Build with networking support in frameserver" ON)
option(ENABLE_LIBRETRO "Build with libretro support in frameserver" ON)
option(ENABLE_LIBRETRO3D "Add 3D core support to libretro frameserver" ON)
option(ENABLE_VIDDEC "Build with libVLC video decoding support in frameserver" ON)
option(ENABLE_VIDENC "Build with FFMPEG video encoding support in frameserver" ON)
option(ENABLE_VIDENCVNC "Build video encoder with VNC server support" ON)
option(ENABLE_REMOTING "Build remoting frameserver (vnc, ...)" ON)
if (NOT WIN32)
	option(ENABLE_TERMINAL "Build terminal frameserver" OFF)
	option(SPLIT_FRAMESERVER "Split frameservers into separate binaries" ON)
endif()

option(SQLITE_AMALGAMATE "Use the SQLite Amalgamation" OFF)

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
message("   -DMUSL_LIBC=[Off|On] build and link with MUSL Libc (incomplete)")
message("   -DSQLITE_AMALGAMATE=[Off|On] : Build / Link with the SQLite Amalgamation")
message("")
message("frameserver features:")
if (NOT WIN32)
message("   -DSPLIT_FRAMESERVER=[Off|On] : Build frameserver in split-chain loading")
message("                                  mode (each role gets a separate binary")
endif()
message("   -DENABLE_NET=[On|Off] : Build networking frameserver (using APR)")
message("   -DENABLE_VIDDEC=[On|Off] : Build video decoding frameserver (using LibVLC)")
message("   -DENABLE_REMOTING=[On|Off] : Build remoting frameserver (using vncserver)")
message("   -DENABLE_VIDENC=[On|Off] : Build video encoding frameserver (using ffmpeg)")
message("   -DENABLE_VIDENCVNC=[On|Off] :       |-> Add VNC server support")
message("   -DENABLE_LIBRETRO=[On|Off] : Build libretro frameserver")
message("   -DENABLE_LIBRETRO3D=[On|Off] : |--> Enable 3D support")
message(" or disable frameserver support, -DDISABLE_FRAMESERVERS=ON")
message("")

set (FRAMESERVER_MODESTRING "")

#
# These work as a sort of black-list that will be dropped when the VM is initialized
# For more fine-grained control, we should switch to a white-list approach where
# : is used as a table:member delimiter to keep certain functions.
#
if (NOT LUA_DROPSTR)
set (LUA_DROPSTR "io os package rawequal rawset rawget setfenv coroutine module require")
endif()

if (NOT GIT_MIRROR)
	SET(GIT_MIRROR "https://www.github.com/mirror")
endif()

#
# Hooks added here to later switch to -nostdlib -nodefaultlibs and
# get a decent libc for linux
#
set (STDLIB
	m
	pthread
)

#
# Incomplete, major workarounds need to be added for all external deps. etc.
# to build without linking in all the glibc filth
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

message("Using compiler: ${CMAKE_C_COMPILER_ID}")

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
# paths / locations
set(OPENCTM_LIBRARY openctm)
set(ARCAN_DEFINITIONS "")

FIND_PACKAGE ( Freetype REQUIRED )
FIND_PACKAGE ( PNG REQUIRED )

if (NOT AGP_PLATFORM)
	SET(AGP_PLATFORM "gl21")
endif()

SET (AGP_GL_SHARED
	platform/video_platform.h
	platform/agp/glshared.c
	platform/agp/glfun.h
	platform/agp/shdrmgmt.c
	platform/agp/glinit.c
)

if (AGP_PLATFORM STREQUAL "stub")
	set(AGP_SOURCES
		platform/agp/stub.c
	)

elseif (AGP_PLATFORM STREQUAL "gl21")
	FIND_PACKAGE(OpenGL REQUIRED)
	SET (AGP_LIBRARIES
		${OPENGL_gl_LIBRARY}
	)

	SET (AGP_SOURCES
		${AGP_GL_SHARED}
		platform/agp/gl21.c
	)

elseif (AGP_PLATFORM STREQUAL "gles2")
	FIND_PACKAGE(GLES2 REQUIRED)
	add_definitions(-DGLES2)
	SET(AGP_LIBRARIES
		${GLES2_LIBRARIES}
	)
		SET (AGP_SOURCES
		${AGP_GL_SHARED}
		platform/agp/gles.c
	)

elseif (AGP_PLATFORM STREQUAL "gles3")
	FIND_PACKAGE(GLES3 REQUIRED)
	add_definitions(-DGLES3)
	SET(AGP_LIBRARIES
		${GLES3_LIBRARIES}
	)
	SET (AGP_SOURCES
		${AGP_GL_SHARED}
		platform/agp/gles.c
	)
	set_property(SOURCE platform/agp/gles.c
		APPEND PROPERTY COMPILE_DEFINITIONS GLES3)

else()
	message(FATAL_ERROR "Unknown AGP platform specified, #{AGP_PLATFORM}")
endif()

set(PLATFORM_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/platform)

if (GLOBAL_CFLAGS)
	add_definitions(${GLOBAL_CFLAGS})
endif()

if (VIDEO_PLATFORM STREQUAL "x11" OR VIDEO_PLATFORM STREQUAL "x11-headless")
	if (NOT INPUT_PLATFORM)
		set(INPUT_PLATFORM "x11")
	endif()

	add_definitions(-DWITH_X11)

	if (VIDEO_PLATFORM STREQUAL "x11-headless")
		set(VIDEO_PLATFORM "x11")
		add_definitions(-DWITH_HEADLESS_MAIN)
	endif()

	FIND_PACKAGE(X11 REQUIRED)

	LIST(APPEND INCLUDE_DIRS ${X11_INCLUDE_DIRS})
	LIST(APPEND MAIN_LIBRARIES ${AGP_LIBRARIES} ${X11_LIBRARIES})
	LIST(APPEND LWA_LIBRARIES ${AGP_LIBRARIES} ${X11_LIBRARIES})

	if (ENABLE_LWA)
		message("Enabling LWA (Arcan-in-Arcan) build using X11 HEADLESS")
		SET(LWA_HEADLESS ${PLATFORM_ROOT}/x11/video.c)
	endif()

# legacy platform for weaker platforms RPI etc.
elseif(VIDEO_PLATFORM STREQUAL "egl-gles")
	if (NOT INPUT_PLATFORM)
		set(INPUT_PLATFORM "linux")
	endif()

	FIND_PACKAGE(EGL REQUIRED)

	if (ENABLE_LWA)
		message("Enabling LWA (Arcan-in-Arcan) build using X11 HEADLESS")
		SET(LWA_HEADLESS ${PLATFORM_ROOT}/egl-gles/video.c)
		LIST(APPEND LWA_LIBRARIES ${AGP_LIBRARIES} ${EGL_LIBRARIES})
	endif()

	if (GLES2_BCM_IMPLEMENTATION)
		message("broadcom (BCM) GLES implementation found, set BCM_ROOT to bad dir to disable")
		LIST(APPEND ARCAN_DEFINITIONS WITH_BCM)
		set_property(SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/platform/egl-gles/video.c
			APPEND PROPERTY COMPILE_FLAGS -fgnu89-inline)
	endif()

	LIST(APPEND INCLUDE_DIRS
		${GLES2_INCLUDE_DIRS}
		${EGL_INCLUDE_DIRS}
	)

	LIST(APPEND MAIN_LIBRARIES
		${AGP_LIBRARIES}
		${EGL_LIBRARIES}
	)

elseif(VIDEO_PLATFORM STREQUAL "egl-nvidia")
	if (NOT INPUT_PLATFORM)
		set(INPUT_PLATFORM "linux")
	endif()

	FIND_PACKAGE(EGL REQUIRED)
# need a way to check nvidia driver version so that we maintain that
# dependency statically
	LIST(APPEND MAIN_LIBRARIES
		${EGL_LIBRARIES}
		${AGP_LIBRARIES}
	)
	if (ENABLE_LWA)
		message("Enabling LWA (Arcan-in-Arcan build) using NVIDIA Linux headless")
		SET(LWA_HEADLESS ${PLATFORM_ROOT}/egl-nvidia/video.c)
		LIST(APPEND LWA_LIBRARIES ${AGP_LIBRARIES} ${EGL_LIBRARIES})
	endif()
elseif(VIDEO_PLATFORM STREQUAL "egl-dri")
	if (NOT INPUT_PLATFORM)
		set(INPUT_PLATFORM "linux")
	endif()

	FIND_PACKAGE(EGL REQUIRED)
	FIND_PACKAGE(GBMKMS REQUIRED)

	LIST(APPEND MAIN_LIBRARIES
		${EGL_LIBRARIES}
		${AGP_LIBRARIES}
		${GBMKMS_LIBRARIES}
	)
	LIST(APPEND INCLUDE_DIRS
		${GBMKMS_INCLUDE_DIRS}
	)

	if (ENABLE_LWA)
		message("Enabling LWA (Arcan-in-Arcan build) using EGL-DRI HEADLESS")
		SET(LWA_HEADLESS ${PLATFORM_ROOT}/egl-dri/video_rnode.c)
		LIST(APPEND LWA_LIBRARIES ${AGP_LIBRARIES}
			${EGL_LIBRARIES} ${GBMKMS_LIBRARIES})
	endif()

elseif (VIDEO_PLATFORM STREQUAL "sdl")
	if (NOT INPUT_PLATFORM)
		set(INPUT_PLATFORM "sdl")
	endif()


	FIND_PACKAGE(SDL REQUIRED)
	FIND_PACKAGE(SDL_image)

	LIST(APPEND INCLUDE_DIRS ${SDL_INCLUDE_DIR})
	LIST(APPEND ARCANMAIN_LIBRARIES ${SDL_LIBRARY} ${AGP_LIBRARIES})

	if (${SDLIMAGE_FOUND})
		message("--> SDL_Image found, adding")
		list(APPEND ARCANMAIN_LIBRARIES ${SDLIMAGE_LIBRARY})
		list(APPEND LWA_LIBRARIES ${SDLIMAGE_LIBRARY} ${SDL_LIBRARY})
		list(APPEND INCLUDE_DIRS ${SDLIMAGE_INCLUDE_DIR})
		set_property(SOURCE engine/arcan_img.c
			APPEND PROPERTY COMPILE_DEFINITIONS SDLIMAGE)
	endif(${SDLIMAGE_FOUND})

	if (ENABLE_LWA)
		message("Enabling LWA (Arcan-in-Arcan build) using X11 HEADLESS")
		FIND_PACKAGE(X11 REQUIRED)
		LIST(APPEND INCLUDE_DIRS ${X11_INCLUDE_DIRS})
		LIST(APPEND LWA_LIBRARIES ${X11_LIBRARIES} ${AGP_LIBRARIES})
		if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
			message("Enabling LWA (Arcan-in-Arcan) build using Darwin HEADLESS")
			SET(LWA_HEADLESS ${PLATFORM_ROOT}/darwin/video.c)
			set_property(SOURCE ${PLATFORM_ROOT}/arcan/video.c APPEND PROPERTY
				OBJECT_DEPENDS ${PLATFORM_ROOT}/darwin/video.c)
			set_property(SOURCE frameserver/libretro.c APPEND PROPERTY
				OBJECT_DEPENDS ${PLATFORM_ROOT}/darwin/video.c)
		else()
			message("Enabling LWA (Arcan-in-Arcan) build using X11 HEADLESS")
			SET(LWA_HEADLESS ${PLATFORM_ROOT}/x11/video.c)
		endif()
	endif()

else()
	message(FATAL_ERROR "No video platform specified, use -DVIDEO_PLATFORM=${VPLATFORM_STR} e.g. -DVIDEO_PLATFORM=sdl")
endif()

# no other audio platforms supported currently
set(AUDIO_PLATFORM "openal")
FIND_PACKAGE( OpenAL REQUIRED )

message("\n---- Stage 1: library dependencies and configuration ----")
if (NOT SQLITE_AMALGAMATE)
FIND_PACKAGE ( SQLITE3 REQUIRED )
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
	${OPENCTM_LIBRARY}
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
 ${AGP_SOURCES}
)

# database tool is sqlite3 + libc so less need to work
# around with platform layers etc.
set (ARCANDB_SOURCES
	engine/arcan_dbtool.c
	engine/arcan_db.c
	platform/posix/warning.c
	platform/stub/mem.c
)

set (SHMIF_SOURCES
  shmif/arcan_shmif.h
	shmif/arcan_shmif_interop.h
	shmif/arcan_shmif_control.c
	shmif/arcan_shmif_control.h
	shmif/arcan_shmif_interop.c
	shmif/arcan_shmif_event.h
)

# since these are used on multiple targets, force the define here.
set_property(SOURCE platform/posix/fdpassing.c
	APPEND PROPERTY COMPILE_FLAGS -w)
set_property(SOURCE platform/posix/fdpassing.c
	APPEND PROPERTY COMPILE_DEFINITIONS NONBLOCK_RECV)

FIND_PACKAGE(SSE)
if (ENABLE_SIMD AND SSE_FOUND)
	message("--> Enabling SIMD")

	set_property(SOURCE engine/arcan_math.c
		APPEND PROPERTY COMPILE_DEFINITIONS ARCAN_MATH_SIMD)
	list(APPEND SOURCES engine/arcan_math_simd.c)

	if (ENABLE_SIMD_ALIGNED)
		message("      |--> Asserting SIMD operands are aligned")
		message("           These can *crash* at odd intervals on ")
		message("           poor _Alignas implementations")
		set_property(SOURCE engine/arcan_math_simd.c
			APPEND PROPERTY COMPILE_DEFINITIONS ARCAN_MATH_ALIGNED_SIMD)
	endif()

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

if (SQLITE_AMALGAMATE)
	message("--> Embedding the SQLite Amalgamation.")
	list(APPEND SOURCES external/sqlite3/sqlite3.c)
endif (SQLITE_AMALGAMATE)

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

include_directories(${INCLUDE_DIRS})

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
add_library(arcan_shmif STATIC ${SHMIF_SOURCES} ${PLATFORM_SHMIF_SOURCES})

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
add_subdirectory(frameserver)

set_property(SOURCE engine/arcan_lua.c engine/arcan_main.c APPEND PROPERTY
	COMPILE_DEFINITIONS FRAMESERVER_MODESTRING=\"${FRAMESERVER_MODESTRING}\"
	LUA_DROPSTR=\"${LUA_DROPSTR}\" ARCAN_BUILDVERSION=\"${ENGINE_BUILDTAG}\")

message("\n---- Stage 4, Linking / Packaging ----")

if (ENABLE_LWA)
	message("\n---- Stage 4, LWA Build ----")
	include(platform/CMakeLists.LWA)
else()
	message("\n---- Stage 4, LWA Build (omitted) ----")
endif()

add_executable( arcan_db ${ARCANDB_SOURCES} )
target_link_libraries( arcan_db ${STDLIB} ${SQLITE3_LIBRARIES})

# GCC *** requiring dl to be the last argument to avoid dlclose in some
# edge-cases? just take them out behind the shed and pull the trigger.

add_executable( arcan ${SOURCES} ${PLATFORM_SOURCES} )
set_property(TARGET arcan APPEND PROPERTY COMPILE_DEFINITIONS ${ARCAN_DEFINITIONS})
target_link_libraries( arcan ${STDLIB} ${MAIN_LIBRARIES} ${ARCANMAIN_LIBRARIES})

#
# The database tool is a CLI for the engine/arcan_db with additional
# code not part of the main arcan binaries (to make it somewhat harder
# for a misbehaving script to add / introduce new configs / targets
# and execute them.
#

set_property(TARGET arcan_db APPEND PROPERTY
				COMPILE_DEFINITIONS ARCAN_DB_STANDALONE )
