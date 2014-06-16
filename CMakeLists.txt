# Arcan-fe, scriptable front-end engine
#
# Arcan-fe is the legal property of its developers, please refer
# to the COPYRIGHT file distributed with this source distribution.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
#
# --- Project metadata
PROJECT( arcan )
include(ExternalProject)
include(CheckIncludeFiles)

set(CMAKE_EXTERNAL_SRCDIR ${CMAKE_CURRENT_SOURCE_DIR}/external)
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(MAJOR_VERSION 0 )
set(MINOR_VERSION 5 )
set(PATCH_LEVEL 0 )
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})

set(SHARED_PERMISSIONS OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_READ)
set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE
		GROUP_READ WORLD_EXECUTE WORLD_READ)

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
option(ENABLE_NET "Build with networking support in frameserver" ON)
option(ENABLE_LIBRETRO "Build with libretro support in frameserver" ON)
option(ENABLE_LIBRETRO3D "Add 3D core support to libretro frameserver" ON)
option(ENABLE_VIDDEC "Build with libVLC video decoding support in frameserver" ON)
option(ENABLE_VIDENC "Build with FFMPEG video encoding support in frameserver" ON)
option(ENABLE_VIDENCVNC "Build video encoder with VNC server support" ON)
option(ENABLE_LED "Build with LED controller support in core" ON)
option(ENABLE_HMD "Build with Head-Mounted Display support in core" ON)
option(ENABLE_SIMD "Build with SIMD vector instruction set support" ON)
option(ENABLE_SIMD_ALIGNED "Assert that SIMD data sources are 16-byte aligned" OFF)
option(ENABLE_LWA "Build a lightweight arcan (arcan_lwa) with nested platform" OFF)
option(ENABLE_LUAJIT "Use the luajit-5.1 VM (if found)" ON)

if (NOT WIN32)
	option(SPLIT_FRAMESERVER "Split frameservers into separate binaries" OFF)
	option(EGL_VIDEO_PLATFORM "Build video subsystem using EGL (will disable SDL)" OFF)
	option(ENABLE_GLES2 "Use GLES2 rather than OpenGL 2.1 (requires EGL)" OFF)
	option(ENABLE_X11 "Use an XWindows Display for the GLES context (requires EGL)" OFF)
	option(MUSL_LIBC "Use the MUSL libc implementation (incomplete)" OFF)
endif()

option(SQLITE_AMALGAMATE "Use the SQLite Amalgamation" OFF)

message("")
message("Cmake options:")
message("   -DCMAKE_BUILD_TYPE=[Debug|Release|Profile|DebugTrace]")
message("   -DENABLE_ASAN=[Off|On] : Build with Address Sanitizer enabled")
message("   -DENABLE_SIMD=[On|Off] : Enable SIMD optimized instructions")
message("   -DENABLE_SIMD_ALIGNED=[Off|On] : |--> SIMD support assumes 16-byte aligned data")
message("")
message("   -DENABLE_NET=[On|Off] : Build networking frameserver (requires apache portable runtime libraries, APR)")
message("   -DENABLE_VIDDEC=[On|Off] : Build video decoding frameserver (requires libvlc libraries)")
message("   -DENABLE_VIDENC=[On|Off] : Build video encoding frameserver (requires ffmpeg libraries)")
message("   -DENABLE_VIDENCVNC=[On|Off] :       |-> Add VNC server support (if libvncserver is found)")
message("")
message("   -DENABLE_LIBRETRO=[On|Off] : Build libretro frameserver")
message("   -DENABLE_LIRETRO3D=[On|Off] : |--> Enable 3D support in libretro frameserver")
message("")
message("   -DENABLE_LED=[On|Off] : Build with LED controller support in core")
message("   -DENABLE_HMD=[On|Off] : Build with Head-Mounted Display support in core")
message("   -DENABLE_LWA=[Off|On] : Build lightweight additional arcan client (arcan-in-arcan)")
message("   -DENABLE_LUAJIT=[On|Off] : link with luajit51 (if found)")
message("   -DSQLITE_AMALGAMATE=[Off|On] : Build / Link with the SQLite Amalgamation")

if (NOT WIN32) 
message("   -DSPLIT_FRAMESERVER=[Off|On] : Build frameserver in split-chain loading mode (each role gets a separate binary")
message("")
message("   -DEGL_VIDEO_PLATFORM=[Off|On] : Build with EGL video platform (replaces SDL)")
message("   -DENABLE_GLES2=[Off|On] :       |--> EGL platform uses GLES2 API)")
message("   -DENABLE_X11=[Off|On] :         |--> EGL platform uses X11 Windowing")
message("")
message("   -DMUSL_LIBC=[Off|On] build and link with MUSL Libc (incomplete)") 
endif()
message("")

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
	add_definitions(-g -D_DEBUG -fno-omit-frame-pointer)
endif (CMAKE_BUILD_TYPE STREQUAL "Debug")

if (CMAKE_BUILD_TYPE STREQUAL "DebugTrace")
	message("-------------- *Debug Tracing Build* --------------")
	add_definitions(-g -D_DEBUG -DTRACE_ENABLE)
endif (CMAKE_BUILD_TYPE STREQUAL "DebugTrace")

if (ENABLE_ASAN)
	set(CMAKE_C_FLAGS "-fsanitize=address ${CMAKE_C_FLAGS}")
endif (ENABLE_ASAN)

# --- Step 1, Dependencies / find package flags
# paths / locations
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake)
set(OPENCTM_LIBRARY openctm)

# OS Specific libraries / dependencies first
if(WIN32)
	set(WINLIB ${CMAKE_CURRENT_SOURCE_DIR}/platform/win32/lib)
	set(WININC ${CMAKE_CURRENT_SOURCE_DIR}/platform/win32/include)
	set(WINDISTR ${CMAKE_CURRENT_SOURCE_DIR}/distr)
	set(CMAKE_INCLUDE_PATH ${WININC} /usr/local/include)
	set(CMAKE_LIBRARY_PATH ${WINLIB} /usr/local/lib)

	set(SDL_INCLUDE_DIR ${WININC}\\SDL)

	set(ZLIB_INCLUDE_DIR ${WININC})
	set(BZIP2_INCLUDE_DIR ${WININC})
	set(OPENAL_LIBRARY ${WINLIB}\\OpenAL32.lib)
	set(OPENAL_INCLUDE_DIR ${WININC}\\AL)
	set(PNG_PNG_INCLUDE_DIR ${WININC})

	set(FREETYPE_LIBRARY ${WINDISTR}\\win32libs\\freetype6.dll)
	set(PNG_LIBRARY ${WINLIB}\\libpng16.a)
	set(ZLIB_LIBRARY ${WINDISTR}\\win32libs\\zlib1.dll)

	set(APR_LIBRARY ${WINLIB}\\libapr-1.a)
	set(APR_INCLUDE_DIR ${WININC}\\apr)
	set(SQLITE3_INCLUDE_DIR ${WININC})
	set(SQLITE3_LIBRARY_RELEASE ${WINDISTR}\\win32libs\\sqlite3.dll)
	set(SDLIMAGE_INCLUDE_DIR ${WININC}\\SDL)
	set(GLEW_INCLUDE_DIR ${WININC})
	set(GLEW_LIBRARY ${WINLIB}\\glew32s.lib)
	set(ENABLE_LWA OFF)
	set(OS_PLATFORM_NAME "Win32")
endif()

if (EGL_VIDEO_PLATFORM)
    set(VIDEO_PLATFORM "egl")
		FIND_PACKAGE(EGL REQUIRED)
	
		if (ENABLE_GLES2)
			FIND_PACKAGE(GLES2 REQUIRED)
		else()
			FIND_PACKAGE(OpenGL REQUIRED)	
		endif()

	if (NOT ENABLE_X11)
		set(INPUT_PLATFORM "linux")
	endif()
	
	if (ENABLE_X11)
		FIND_PACKAGE(X11 REQUIRED)
		LIST(APPEND MAIN_LIBRARIES ${X11_LIBRARIES})
		LIST(APPEND MAIN_INCLUDE_DIRS ${X11_INCLUDE_DIR})
		set(INPUT_PLATFORM "x11")

	elseif(${CMAKE_SYSTEM_NAME} MATCHES "Linux")
		FIND_PACKAGE( GBMKMS REQUIRED )
		LIST(APPEND MAIN_LIBRARIES ${GBMKMS_LIBRARIES})
		LIST(APPEND INCLUDE_DIRS ${GBMKMS_INCLUDE_DIRS})
	endif()

endif()

if (NOT VIDEO_PLATFORM OR VIDEO_PLATFORM STREQUAL "sdl")
	set(VIDEO_PLATFORM "sdl")
	FIND_PACKAGE( SDL REQUIRED )
	FIND_PACKAGE ( OpenGL REQUIRED )
	FIND_PACKAGE ( GLEW REQUIRED )
	FIND_PACKAGE ( SDL_image )
	LIST(APPEND MAIN_LIBRARIES ${GLEW_LIBRARY} ${OPENGL_gl_LIBRARY} ${SDL_LIBRARY})
	LIST(APPEND INCLUDE_DIRS ${SDL_INCLUDE_DIR} ${GLEW_INCLUDE_DIRS})

	if (${SDLIMAGE_FOUND})
		message("--> SDL_Image found, adding") 
		list(APPEND MAIN_LIBRARIES ${SDLIMAGE_LIBRARY})
		list(APPEND INCLUDE_DIRS ${SDLIMAGE_INCLUDE_DIR})
		add_definitions(-DSDLIMAGE)
	endif(${SDLIMAGE_FOUND}) 
endif()

if (NOT INPUT_PLATFORM OR INPUT_PLATFORM STREQUAL "sdl")
	set(INPUT_PLATFORM "sdl")
	FIND_PACKAGE( SDL REQUIRED )
endif()

if (NOT AUDIO_PLATFORM)
	set(AUDIO_PLATFORM "openal")
	FIND_PACKAGE( OpenAL REQUIRED )
endif()

FIND_PACKAGE ( Freetype REQUIRED )
FIND_PACKAGE ( PNG REQUIRED )

message("video output (VIDEO_PLATFORM) set to : ${VIDEO_PLATFORM}")
message("audio output (AUDIO_PLATFORM) set to : ${AUDIO_PLATFORM}")
message("device input (INPUT_PLATFORM) set to : ${INPUT_PLATFORM}")
message("\n---- Stage 1: library dependencies and configuration ----")
# modified version of the 51 package that checks for the lua51_jit option 
FIND_PACKAGE ( BZip2 REQUIRED )
FIND_PACKAGE ( ZLIB REQUIRED )

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

LIST (APPEND
	MAIN_LIBRARIES
	${OPENCTM_LIBRARY}
	${FREETYPE_LIBRARY}
	${LUA_LIBRARIES}
	${OPENAL_LIBRARY}
	${BZIP2_LIBRARIES}
	${ZLIB_LIBRARY}
	${ASSERT_LIBRARY}
	${SQLITE3_LIBRARIES}
	${GLEW_LIBRARIES}
	${PNG_LIBRARIES}
)

LIST (APPEND 
	INCLUDE_DIRS
	${LUA_INCLUDE_DIR}
	${OPENAL_INCLUDE_DIR}
	${PNG_INCLUDE_DIR}
	${FREETYPE_INCLUDE_DIRS}
	${SQLITE3_INCLUDE_DIR}
	"frameserver"
	"frameserver/ntsc"
	"external"
	"shmif"
	"engine"
)

add_subdirectory( external/openctm )

# --- Step 2, source files
set (
 SOURCES
 engine/arcan_event.c
 engine/arcan_lua.c
 engine/arcan_main.c
 engine/arcan_db.c
 engine/arcan_video.c
 engine/arcan_renderfun.c
 engine/arcan_shdrmgmt.c
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
 engine/arcan_target_launcher.h
 engine/arcan_led.c
 engine/arcan_hmd.c
 engine/arcan_hmd.h
 engine/arcan_led.h
 engine/arcan_general.h
 engine/arcan_db.h
 engine/arcan_shdrmgmt.h
 engine/arcan_frameserver_backend.h
 engine/arcan_frameserver_backend.c
 shmif/arcan_shmif_interop.h
 shmif/arcan_shmif_control.c
 shmif/arcan_shmif_event.h
 shmif/arcan_shmif.h
)

# in split-mode, these will bundle with the platform
# frameserver.c and then each subgroup by its own into
# a separate binary, in (default) join mode, the final
# FSRV_SOURCES will be composed of the subgroups
set (
 FSRV_SOURCES
 shmif/arcan_shmif_interop.h
 shmif/arcan_shmif_interop.c
 shmif/arcan_shmif_control.c
 shmif/arcan_shmif_control.h
 shmif/arcan_shmif_event.h
 shmif/arcan_shmif.h
)

if (ENABLE_SIMD)
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

if (ENABLE_HMD)
	message("--> Adding HMD device support.")
	list(APPEND ${SOURCES}
		arcan_hmd.c
		arcan_hmd.h
	)
	add_definitions(-DARCAN_HMD)
endif(ENABLE_HMD)

# Enable / Disable individual frameserver features
if (ENABLE_LIBRETRO)
	message("--> Adding libretro support.")
	set(FSRV_LIBRETRO_SOURCES
	 frameserver/libretro.h
	 frameserver/libretro.c
	 frameserver/stateman.h
	 frameserver/stateman.c
	 frameserver/ievsched.c
	 frameserver/ievsched.h
#	 frameserver/retexture.h
#	 frameserver/retexture.c
	 frameserver/resampler/resample.c
	 frameserver/resampler/speex_resampler.h
	 frameserver/ntsc/snes_ntsc.h
	 frameserver/ntsc/snes_ntsc.c
	 frameserver/graphing/net_graph.c
	 frameserver/graphing/net_graph.h
	 frameserver/graphing/font_8x8.h
	)

	if (ENABLE_LIBRETRO3D)
		message("    |-> Enabling experimental 3D support.")
		set_property( SOURCE frameserver/libretro.c
			APPEND PROPERTY COMPILE_DEFINITIONS
				FRAMESERVER_LIBRETRO_3D
		)	
	endif()
endif()

if (ENABLE_NET)
	message("--> Adding networking support.") 
	FIND_PACKAGE(APR REQUIRED) 

	list(APPEND INCLUDE_DIRS ${APR_INCLUDE_DIR})
	list(APPEND FSRV_NET_LIBRARIES ${APR_LIBRARIES} )
	set(FSRV_NET_SOURCES
		frameserver/graphing/net_graph.c
		frameserver/graphing/net_graph.h
		frameserver/graphing/font_8x8.h
		frameserver/net.h
		frameserver/net.c
		frameserver/net_cl.c
		frameserver/net_shared.h
		frameserver/net_shared.c
	)
endif()

#
# AVfeed is a convenience- mapped input skeleton frameserver
# for hooking up custom input sources
#
if (AVFEED_SOURCES)
	list(APPEND FSRV_AVFEED_SOURCES ${AVFEED_SOURCES})
	list(APPEND FSRV_AVFEED_LIBRARIES ${AVFEED_LIBS})
endif()

if (${ENABLE_VIDDEC})
	FIND_PACKAGE( VLC REQUIRED )
	set(FSRV_DECODE_SOURCES 
		frameserver/decode_vlc.c
		external/fft/kiss_fft.c
		external/fft/kiss_fftr.c
	)
	set(FSRV_DECODE_LIBRARIES
		${LIBVLC_LIBRARY}
	)
	
	list(APPEND INCLUDE_DIRS
		${LIBVLC_INCLUDE_DIR}
	)
endif()

if (${ENABLE_VIDENC})
	FIND_PACKAGE ( FFMPEG REQUIRED)

	message("--> Adding video encoding (ffmpeg) support.") 
	set(FSRV_ENCODE_LIBRARIES 
		${FFMPEG_LIBRARIES}
		pthread
		${BZIP2_LIBRARIES}
		${ZLIB_LIBRARY}
	)

	set(FSRV_ENCODE_SOURCES
		frameserver/encode.c
		frameserver/encode_presets.c
		frameserver/encode_presets.h
	)

	if (${ENABLE_VIDENCVNC})
		FIND_PACKAGE(VNC)
		if (${LIBVNC_FOUND}) 
			message("   |--> VNC Server libraries found, enabling vnc support in encoder.")
			list(APPEND INCLUDE_DIRS ${LIBVNC_INCLUDE_DIRS})
			set_property(SOURCE frameserver/encode.c PROPERTY COMPILE_DEFINITIONS HAVE_VNCSERVER)
		 	list(APPEND FSRV_ENCODE_LIBRARIES ${LIBVNC_LIBRARIES})
		else()
			message("   |--> VNC Server libraries not found, disabling vnc support.")
		endif()	
	endif()

	list(APPEND INCLUDE_DIRS
		${FFMPEG_INCLUDE_DIRS}
		${FFMPEG_LIBAVCODEC_INCLUDE_DIR}
	)
endif()

if (SQLITE_AMALGAMATE)
	message("--> Embedding the SQLite Amalgamation.")
	list(APPEND SOURCES external/sqlite3/sqlite3.c)
	list(APPEND MAIN_LIBRARIES dl)
endif (SQLITE_AMALGAMATE)

if (LUA51_JIT)
	message("--> Enabling JIT- mode for Lua.")
	set_property(SOURCE engine/arcan_lua.c PROPERTY 
				COMPILE_DEFINITIONS LUA51_JIT)
endif (LUA51_JIT)

include_directories(${INCLUDE_DIRS})

#
# OS and more compiler specific files, packaging etc.
# Expected to 
#
if (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
	message("\n---- Stage 2, FreeBSD specific configuration ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.FreeBSD)

elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	message("\n---- Stage 2, Linux specific configuration ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.linux)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	message("\n---- Stage 2, Windows specific configuration ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.Windows)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	message("\n---- Stage 2, OS X specific configuration ----")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.Darwin)

else()
	message(FATAL_ERROR "Unsupported OS detected, abandon ship!.")
endif()

message("\n---- Stage 3, Linking / Packaging ----")
target_link_libraries( arcan ${STDLIB} ${MAIN_LIBRARIES} )
target_link_libraries( arcan_frameserver ${STDLIB} ${FSRV_LIBRARIES} )
if (ENABLE_LWA)
	target_link_libraries( arcan_lwa ${STDLIB} ${MAIN_LIBRARIES} )
endif()

#
# Collective sigh for stupid standard breaking features (nested functions, seriously..).
# one GNU extension is forcibly used here, variable size structure member 
# not at end of struct (for Linux/CMSG) else we'd be c11. 
# C11 requirement is for _Alignas and _Atomic
#
install(TARGETS arcan_frameserver ${FSRV_TARGETS} DESTINATION ${BIN_DST})
install(TARGETS arcan DESTINATION ${BIN_DST})
install(DIRECTORY ${CMAKE_SOURCE_DIR}/themes/ 
	DESTINATION ${THEME_DST} 
	DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR} 
	FILE_PERMISSIONS ${SHARED_PERMISSIONS} 
	PATTERN ".gitignore" EXCLUDE)

if (TEST_DST) 
	install(DIRECTORY ${CMAKE_SOURCE_DIR}/tests/
		DESTINATION ${TEST_DST}
		DIRECTORY_PERMISSIONS ${SHARED_PERMISSIONS_DIR}
		FILE_PERMISSIONS ${SHARED_PERMISSIONS}
		PATTERN ".gitignore" EXCLUDE)
endif (TEST_DST)

install(DIRECTORY ${CMAKE_SOURCE_DIR}/resources/ 
				DESTINATION ${RESOURCES_DST} 
				DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR} 
				FILE_PERMISSIONS ${SHARED_PERMISSIONS} 
				PATTERN ".gitignore" EXCLUDE)

INCLUDE(InstallRequiredSystemLibraries)
set(CPACK_SOURCE_IGNORE_FILES "/\\\\..*$;~$;${CPACK_SOURCE_IGNORE_FILES}")
set(CPACK_PACKAGE_NAME "Arcan")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Scriptable frontend for games and emulators")
set(CPACK_PACKAGE_DESCRIPTION "ARCAN is a fully scriptable front-end for launching and managing emulators, games and other full-screen applications in a visually appealing and embeddable way.")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/distr/LICENSE.txt")

set(CPACK_PACKAGE_VERSION_MAJOR ${MAJOR_VERSION} )
set(CPACK_PACKAGE_VERSION_MINOR ${MINOR_VERSION} )
set(CPACK_PACKAGE_VERSION_PATCH ${PATCH_LEVEL} )
set(CPACK_PACKAGE_CONTACT "contact@arcan-fe.com")
INCLUDE( CPack )
