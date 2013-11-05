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

set(CMAKE_EXTERNAL_SRCDIR ${CMAKE_CURRENT_SOURCE_DIR}/external)
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(MAJOR_VERSION 0 )
set(MINOR_VERSION 3 )
set(PATCH_LEVEL 1beta )
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})

set(SHARED_PERMISSIONS OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_READ)
set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE
		GROUP_READ WORLD_EXCECUTE WORLD_READ)

set( MAIN_LIBRARIES )
set( FSRV_BUILD_FLAGS "-Wno-deprecated-declarations")

#
# for linux/BSD, we can build a 32-bit version of the hi-jack lib as well,
# and use it for 32-bit targets.
#
if( CMAKE_SIZEOF_VOID_P EQUAL 4 )
	set( HAVE_64_BIT 0 )
else( CMAKE_SIZEOF_VOID_P EQUAL 4 )
	option(ENABLE_32BITHIJACK "Build both 64 and 32bit hijack libraries" OFF)
	set( HAVE_64_BIT 1 )
	set( HAVE_SIMD TRUE )
endif( CMAKE_SIZEOF_VOID_P EQUAL 4 )

option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)
option(ENABLE_NET "Build with networking support in frameserver" ON)
option(ENABLE_LIBRETRO "Build with libretro support in frameserver" ON)
option(ENABLE_VIDDECENC "Build with video decoding/encoding support in frameserver" ON)
option(LUA51_JIT "Use the luajit-5.1 VM (if found)" ON)
option(SQLITE_AMALGAMATE "Use the SQLite Amalgamation" OFF)

# Collective sigh for stupid standard breaking features (nested functions, seriously..).
# Two GNU extensions are used, anonymous inner unions (accepted in C11)
# and variable size structure member not at end of struct (for Linux/CMSG)
add_definitions(-std=gnu99 
-DGL_HEADERS="platform/sdl/glheaders.h")

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

if (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
set(BSD_BUILD ON)
endif (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")

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
endif()

FIND_PACKAGE ( SDL REQUIRED )
FIND_PACKAGE ( SDL_image )
FIND_PACKAGE ( Freetype REQUIRED )
FIND_PACKAGE ( OpenGL REQUIRED )
FIND_PACKAGE ( OpenAL REQUIRED )
FIND_PACKAGE ( PNG REQUIRED )

# modified version of the 51 package that checks for the lua51_jit option 
if (LUA51_JIT)
	FIND_PACKAGE ( Lua51JIT )
endif (LUA51_JIT)

if (NOT LUA_LIBRARY)
	FIND_PACKAGE ( Lua51 )
endif (NOT LUA_LIBRARY)

if (NOT LUA_LIBRARIES)
	message("--> LUA Library not found, building from external/lua")
	add_subdirectory( external/lua )
	set (LUA_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external/lua)
	set (LUA_LIBRARIES lua51 )
endif (NOT LUA_LIBRARIES)

FIND_PACKAGE ( BZip2 REQUIRED )
FIND_PACKAGE ( ZLIB REQUIRED )

if (NOT SQLITE_AMALGAMATE) 
FIND_PACKAGE ( SQLITE3 REQUIRED )
endif(NOT SQLITE_AMALGAMATE) 

FIND_PACKAGE ( GLEW REQUIRED )

FIND_PACKAGE ( APR ) # Adds support for frameserver_net
FIND_PACKAGE ( FFMPEG ) # Adds support for frameserver_encode, frameserver_decode

LIST (APPEND
	MAIN_LIBRARIES
	${OPENCTM_LIBRARY}
	${SDL_LIBRARY}
	${FREETYPE_LIBRARY}
	${LUA_LIBRARIES}
	${OPENGL_gl_LIBRARY}
	${OPENAL_LIBRARY}
	${BZIP2_LIBRARIES}
	${ZLIB_LIBRARY}
	${ASSERT_LIBRARY}
	${SQLITE3_LIBRARIES}
	${GLEW_LIBRARIES}
	${PNG_LIBRARIES}
)

set (
FSRV_LIBRARIES
	${SDL_LIBRARY}
	${BZIP2_LIBRARIES}
	${ZLIB_LIBRARY}
)

set (
INCLUDE_DIRS
	${APR_INCLUDE_DIR}
	${LUA_INCLUDE_DIR}
	${OPENAL_INCLUDE_DIR}
	${SDL_INCLUDE_DIR}
	${PNG_INCLUDE_DIR}
	${FREETYPE_INCLUDE_DIRS}
	${SQLITE3_INCLUDE_DIR}
	${FFMPEG_INCLUDE_DIRS}
	${FFMPEG_LIBAVCODEC_INCLUDE_DIR}
	${GLEW_INCLUDE_DIRS}
	"frameserver/ntsc"
	"external"
)

if (${SDLIMAGE_FOUND})
	message("--> SDL_Image found, enabling (use -DCMAKE_DISABLE_FIND_PACKAGE_SDL_image to force off).")
	list(APPEND MAIN_LIBRARIES ${SDLIMAGE_LIBRARY})
	list(APPEND INCLUDE_DIRS ${SDLIMAGE_INCLUDE_DIR})
	add_definitions(-DSDLIMAGE)
endif(${SDLIMAGE_FOUND}) 

add_subdirectory( external/openctm )

# --- Step 2, source files
set (
 SOURCES
 arcan_event.c
 arcan_lua.c
 arcan_framequeue.c
 arcan_frameserver_backend.c
 arcan_main.c
 arcan_db.c
 arcan_video.c
 arcan_renderfun.c
 arcan_shdrmgmt.c
 arcan_3dbase.c
 arcan_math.c
 arcan_audio.c
 arcan_ttf.c
 arcan_img.c
 arcan_audioint.h
 arcan_framequeue.h
 arcan_event.h
 arcan_lua.h
 arcan_frameserver_backend.h
 arcan_math.h
 arcan_3dbase.h
 arcan_video.h
 arcan_util.h
 arcan_audio.h
 arcan_target_launcher.h
 arcan_led.c
 arcan_hmd.c
 arcan_hmd.h
 arcan_led.h
 arcan_general.h
 arcan_db.h
 arcan_shdrmgmt.h
 arcan_frameserver_shmpage.h
 arcan_frameserver_shmpage.c
)

set (
 FSRV_SOURCES
 frameserver/graphing/font_8x8.h
 frameserver/graphing/net_graph.h
 frameserver/graphing/net_graph.c
 frameserver/resampler/resample.c
 frameserver/resampler/speex_resampler.h
 arcan_frameserver_shmpage.h
 arcan_frameserver_shmpage.c
 arcan_event.c
 external/fft/kiss_fft.c
 external/fft/kiss_fftr.c
)

if (${HAVE_SIMD})
	message("-- Enabling SIMD")
	add_definitions(-DARCAN_MATH_SIMD)
	list(APPEND SOURCES arcan_math_simd.c)
endif (${HAVE_SIMD})

# Enable / Disable individual frameserver features
if (${ENABLE_LIBRETRO})
	message("--> Including libretro support.")
	list(APPEND FSRV_SOURCES
	 frameserver/libretro.h
	 frameserver/libretro.c
	 frameserver/ntsc/snes_ntsc.h
	 frameserver/ntsc/snes_ntsc.c
 	)
	add_definitions(-DENABLE_FSRV_LIBRETRO) 
endif(${ENABLE_LIBRETRO})

if (${APR_FOUND} AND ${ENABLE_NET})
	message("--> Including networking support.") 
	list(APPEND FSRV_LIBRARIES ${APR_LIBRARIES} )
	list(APPEND FSRV_SOURCES
   frameserver/net.h
	 frameserver/net.c
	)
	add_definitions(-DENABLE_FSRV_NET)
else (${APR_FOUND} AND ${ENABLE_NET})
	message("--> Disabling networking support.")
endif (${APR_FOUND} AND ${ENABLE_NET})

if (${FFMPEG_FOUND} AND ${ENABLE_VIDDECENC})
	message("--> Enabling video encoding/decoding support.") 
	list(APPEND FSRV_LIBRARIES ${FFMPEG_LIBRARIES})
	list(APPEND FSRV_SOURCES 
		frameserver/decode.h
		frameserver/decode.c
		frameserver/encode.h
		frameserver/encode.c
		frameserver/encode_presets.c
		frameserver/encode_presets.h
	)
	add_definitions(-DENABLE_FSRV_ENCODE -DENABLE_FSRV_DECODE)
else (${FFMPEG_FOUND} AND ${ENABLE_VIDDECENC})
	message("--> Disabling video de-/encoding.")
endif(${FFMPEG_FOUND} AND ${ENABLE_VIDDECENC})

if (SQLITE_AMALGAMATE)
	message("--> Embedding the SQLite Amalgamation.")
	list(APPEND SOURCES external/sqlite3/sqlite3.c)
	list(APPEND MAIN_LIBRARIES dl)
endif (SQLITE_AMALGAMATE)

if (LUA51_JIT)
	message("--> Enabling JIT- mode for LUA.")
	set_property(SOURCE arcan_lua.c PROPERTY 
				COMPILE_DEFINITIONS LUA51_JIT)
endif (LUA51_JIT)

include_directories(${INCLUDE_DIRS})

#
# OS and more compiler specific files, packaging etc.
#
if (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.FreeBSD)

elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.linux)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/CMakeLists.Windows)
endif()

target_link_libraries( arcan ${MAIN_LIBRARIES} )
set_target_properties( arcan_frameserver PROPERTIES COMPILE_FLAGS "${FSRV_BUILD_FLAGS}" )
target_link_libraries( arcan_frameserver ${FSRV_LIBRARIES} )

install(TARGETS arcan_frameserver DESTINATION ${BIN_DST})
install(TARGETS arcan DESTINATION ${BIN_DST})
install(DIRECTORY ${CMAKE_SOURCE_DIR}/themes/ 
	DESTINATION ${THEME_DST} 
	DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR} 
	FILE_PERMISSIONS ${SHARED_PERMISSIONS} 
	PATTERN ".svn" EXCLUDE)

if (TEST_DST) 
	install(DIRECTORY ${CMAKE_SOURCE_DIR}/tests/
		DESTINATION ${TEST_DST}
		DIRECTORY_PERMISSIONS ${SHARED_PERMISSIONS_DIR}
		FILE_PERMISSIONS ${SHARED_PERMISSIONS}
		PATTERN ".svn" EXCLUDE)
endif (TEST_DST)

install(DIRECTORY ${CMAKE_SOURCE_DIR}/resources/ 
				DESTINATION ${RESOURCES_DST} 
				DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR} 
				FILE_PERMISSIONS ${SHARED_PERMISSIONS} 
				PATTERN ".svn" EXCLUDE)

INCLUDE(InstallRequiredSystemLibraries)
set(CPACK_SOURCE_IGNORE_FILES "/\\\\..*$;~$;${CPACK_SOURCE_IGNORE_FILES}")
set(CPACK_PACKAGE_NAME "Arcan")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Scriptable frontend for games and emulators")
set(CPACK_PACKAGE_DESCRIPTION "ARCAN is a fully scriptable front-end for launching and managing emulators, games and other full-screen applications in a visually appealing and embeddable way.")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/distr/LICENSE.txt")

set(CPACK_PACKAGE_VERSION_MAJOR ${MAJOR_VERSION} )
set(CPACK_PACKAGE_VERSION_MINOR ${MINOR_VERSION} )
set(CPACK_PACKAGE_VERSION_PATCH ${PATCH_LEVEL} )
set(CPACK_PACKAGE_CONTACT "arcan-fe@b-stahl.se")
INCLUDE( CPack )
