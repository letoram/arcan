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
#ExternalProject_Add(
# nacl
# SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/nacl
# STAMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/nacl/stamp
# TMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/nacl/tmp
# DOWNLOAD_DIR ${CMAKE_CURRENT_BINARY_DIR}/nacl
# INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/nacl

# BUILD_IN_SOURCE 1
# INSTALL_COMMAND ""
#)

#ExternalProject_Add(
#	libjpeg-turbo
#	SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo
#	STAMP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo/stamp
#	TMP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo/tmp
#	DOWNLOAD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo
#	SVN_REPOSITORY svn://svn.code.sf.net/p/libjpeg-turbo/code/tags/1.3.0
#	UPDATE_COMMAND ""
#	INSTALL_COMMAND ""
#	BUILD_IN_SOURCE 1
#)

cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)
set(MAJOR_VERSION 0 )
set(MINOR_VERSION 3 )
set(PATCH_LEVEL 1alpha )
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
	set( HAVE_64_BIT 1 )
	set( HAVE_SIMD TRUE )
endif( CMAKE_SIZEOF_VOID_P EQUAL 4 )

option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)
option(ENABLE_NET "Build with networking support in frameserver" ON)
option(ENABLE_LIBRETRO "Build with libretro support in frameserver" ON)
option(ENABLE_VIDDECENC "Build with video decoding/encoding support in frameserver" ON)
option(LUA51_JIT "Use the luajit-5.1 VM" ON)
option(SQLITE_AMALGAMATE "Use the SQLite Amalgamation" OFF)

# Collective sigh for stupid standard breaking features (nested functions, seriously..).
# Two GNU extensions are used, anonymous inner unions (accepted in C11)
# and variable size structure member not at end of struct (for Linux/CMSG)
add_definitions(-std=iso9899:1999 -DBSD_SOURCE -Wno-gnu 
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

# --- Step 1, Dependencies
# paths / locations
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake_modules)
set(OPENCTM_LIBRARY openctm)

# os specific lib/dep lookup hacks
if(APPLE)
	set(CMAKE_FIND_FRAMEWORK "FIRST")
# everytime I have to do something like this, I die a little on the inside. :'(
elseif(WIN32)
	set(WINLIB ${CMAKE_CURRENT_SOURCE_DIR}/win32/lib)
	set(WININC ${CMAKE_CURRENT_SOURCE_DIR}/win32/inc)
	set(CMAKE_INCLUDE_PATH ${WININC} /usr/local/include)
	set(CMAKE_LIBRARY_PATH ${WINLIB} /usr/local/lib)

	set(SDL_INCLUDE_DIR ${WININC}\\SDL)

	set(ZLIB_INCLUDE_DIR ${WININC})
	set(BZIP2_INCLUDE_DIR ${WININC})
	set(OPENAL_LIBRARY ${WINLIB}\\OpenAL32.lib)
	set(OPENAL_INCLUDE_DIR ${WININC}\\AL)
	set(PNG_PNG_INCLUDE_DIR ${WININC})

	set(FREETYPE_LIBRARY ${WINLIB}\\distr\\libfreetype-6.dll)
	set(PNG_LIBRARY ${WINLIB}\\distr\\libpng15-15.dll)
	set(ZLIB_LIBRARY ${WINLIB}\\distr\\zlib1.dll)
	set(LUA_LIBRARY ${WINLIB}\\..\\lua\\liblua.a)

	set(APR_LIBRARY ${WINLIB}\\libapr-1.a)
	set(APR_INCLUDE_DIR ${WININC}\\apr)
	set(LUA_INCLUDE_DIR ${WININC}\\..\\lua)
	set(SQLITE3_INCLUDE_DIR ${WININC})
	set(SQLITE3_LIBRARY_RELEASE ${WINLIB}\\distr\\sqlite3.dll)
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
FIND_PACKAGE ( Lua51 REQUIRED )
FIND_PACKAGE ( BZip2 REQUIRED )
FIND_PACKAGE ( ZLIB REQUIRED )

if (NOT SQLITE_AMALGAMATE) 
FIND_PACKAGE ( SQLITE3 REQUIRED )
endif(NOT SQLITE_AMALGAMATE) 

FIND_PACKAGE ( GLEW REQUIRED )

# -- without APR, no frameserver_net (and no need for NaCL)
FIND_PACKAGE ( APR )

# -- without FFMPEG, no frameserver_encode, frameserver_decode
FIND_PACKAGE ( FFMPEG )

LIST (APPEND
	MAIN_LIBRARIES
	${OPENCTM_LIBRARY}
	${SDL_LIBRARY}
	${FREETYPE_LIBRARY}
	${LUA_LIBRARY}
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
#	${CMAKE_CURRENT_BINARY_DIR}/nacl/libnacl.a
#	${CMAKE_CURRENT_BINARY_DIR}/nacl/randombytes/librandombytes.a
#	${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo/include
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
	${FFMPEG_INCLUDE_DIR}
	${FFMPEG_LIBAVCODEC_INCLUDE_DIR}
	${GLEW_INCLUDE_DIRS}
	"frameserver/ntsc"
#	"nacl/include"
#	"libjpeg-turbo/include"
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
	 frameserver/arcan_frameserver_libretro.h
	 frameserver/arcan_frameserver_libretro.c
	 frameserver/ntsc/snes_ntsc.h
	 frameserver/ntsc/snes_ntsc.c
 	)
	add_definitions(-DENABLE_FSRV_LIBRETRO) 
endif(${ENABLE_LIBRETRO})

if (${APR_FOUND} AND ${ENABLE_NET})
	message("--> Including networking support.") 
	list(APPEND FSRV_LIBRARIES ${APR_LIBRARIES} )
	list(APPEND FSRV_SOURCES
   frameserver/arcan_frameserver_net.h
	 frameserver/arcan_frameserver_net.c
	)
	add_definitions(-DENABLE_FSRV_NET)
else (${APR_FOUND} AND ${ENABLE_NET})
	message("--> Disabling networking support.")
endif (${APR_FOUND} AND ${ENABLE_NET})

if (${FFMPEG_FOUND} AND ${ENABLE_VIDDECENC})
	message("--> Enabling video encoding/decoding support.") 
	list(APPEND FSRV_LIBRARIES ${FFMPEG_LIBRARIES})
	list(APPEND FSRV_SOURCES 
		frameserver/arcan_frameserver_decode.h
		frameserver/arcan_frameserver_decode.c
		frameserver/arcan_frameserver_encode.h
		frameserver/arcan_frameserver_encode.c
		frameserver/arcan_frameserver_encode_presets.c
		frameserver/arcan_frameserver_encode_presets.h
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

# OS Specific modifications
#
# This is mostly out of date, although it should be possible to get 
# up to speed without much effort, it still requires someone taking on
# that job for OSX
#
if (${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
#
# the default paths / filenames for OSX default to
# a bundle for the libs / app / frameserver
# with ~/.arcan for other resources
#
find_library(IOKIT NAMES IOKit)
find_library(COREFOUNDATION NAMES CoreFoundation)
LIST(APPEND MAIN_LIBRARIES ${IOKIT} ${COREFOUNDATION})
LIST(APPEND FSRV_LIBRARIES ${COREFOUNDATION})
LIST(APPEND SOURCES 
	SDLMain.m 
	${CMAKE_EXTERNAL_SRCDIR}/external/hidapi/hid_mac.c 
	${CMAKE_EXTERNAL_SRCDIR}/external/hidapi/hidapi.h 
	arcan_target_launcher.c 
	arcan_frameserver_backend_unix.c)
LIST(APPEND FSRV_SOURCES frameserver/arcan_frameserver.c)

add_definitions(-D__APPLE__ -D__UNIX -DLUA_51)
add_library( arcan_hijack SHARED arcan_target_osx.c arcan_frameserver_shmpage.c arcan_event.c frameserver/ntsc/snes_ntsc.c )

target_link_libraries( arcan_hijack ${SDL_LIBRARY} ${OPENGL_gl_LIBRARY} )

add_executable( arcan ${SOURCES} )
add_executable( arcan_frameserver ${FSRV_SOURCES})

# Packaging and installation. build a DMG which installs to a default
# Application folder, with resources, themes and frameworks included.
#
# The default search- order for resources/themes in the main app,
# should be ENV -> home -> unix "share" -> bundle

set(CPACK_BUNDLE_NAME Arcan)
set(CPACK_BUNDLE_PLIST Info.plist)
set(CPACK_BUNDLE_ICON Arcan.icns)

set(frameworks_dir ${bundle_name}/Contents/Frameworks/)
set(CMAKE_INSTALL_PREFIX ${bundle_name}/Contents/MacOS/)
set(DATA_INSTALL_DIR ".")
set(BIN_DST "../MacOS")
set(THEME_DST "../Resources/themes")
set(RESOURCES_DST "../Resources/resources")

install(TARGETS arcan_hijack DESTINATION ${BIN_DST})
install(FILES ${CMAKE_SOURCE_DIR}/arcan_romman.rb DESTINATION ${BIN_DST} PERMISSIONS WORLD_READ WORLD_EXECUTE OWNER_WRITE OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE)

SET(CPACK_GENERATOR ${CPACK_GENERATOR};Bundle)

elseif (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
set (PLATFORM_SOURCES
platform/posix/fmt_open.c
platform/posix/glob.c
platform/posix/map_resource.c
platform/posix/resource_io.c
platform/posix/ilaunch.c
platform/posix/strip_traverse.c
platform/posix/paths.c
platform/posix/sem.c
platform/posix/shm.c
platform/posix/time.c
platform/posix/warning.c
platform/sdl/event.c
platform/sdl/video.c
)

set (FSERV_PLATFORM_SOURCES
platform/posix/warning.c
platform/posix/time.c
platform/posix/sem.c
platform/posix/shm.c
platform/sdl/event.c
)

	add_definitions(-DPLATFORM_HEADER="platform/posix/platform.h")
	add_definitions(-DLUA_51 -D__UNIX -D_LIBUSB_BSD -D_POSIX_C_SOURCE)

	LIST(APPEND SOURCES ${PLATFORM_SOURCES})
	LIST(APPEND SOURCES 
		${CMAKE_EXTERNAL_SRCDIR}/hidapi/hid_linux.c
		${CMAKE_EXTERNAL_SRCDIR}/hidapi/hidapi.h
 		arcan_target_launcher.c arcan_frameserver_backend_unix.c)

	LIST(APPEND MAIN_LIBRARIES usb rt)
	LIST(APPEND FSRV_SOURCES frameserver/arcan_frameserver.c 
					${FSERV_PLATFORM_SOURCES})
	LIST(APPEND FSRV_LIBRARIES -lrt)

	add_library(arcan_hijack SHARED 
		arcan_target_unix.c
	 	arcan_event.c 
		arcan_target.c 
		frameserver/ntsc/snes_ntsc.c 
		frameserver/resampler/resample.c
	)
	
	set_property(TARGET arcan_hijack PROPERTY 
		COMPILE_DEFINITIONS ENABLE_X11HIJACK ENABLE_WINE_HIJACK)

	set_property(SOURCE arcan_target_unix.c 
		APPEND PROPERTY OBJECT_DEPENDS "arcan_target.c")
	target_link_libraries(arcan_hijack ${SDL_LIBRARY} ${OPENGL_gl_LIBRARY})

	set(BIN_DST ${CMAKE_INSTALL_PREFIX}/bin)
	set(THEME_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/themes)
	set(RESOURCES_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/resources)

	add_executable( arcan ${SOURCES})
	add_executable( arcan_frameserver ${FSRV_SOURCES})

	install(TARGETS arcan_hijack DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)
	install(FILES ${CMAKE_SOURCE_DIR}/arcan_romman.rb DESTINATION ${BIN_DST} PERMISSIONS WORLD_READ WORLD_EXECUTE OWNER_WRITE OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE)
#
# ----------------------- LINUX --------------------------
#
#
elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
set (PLATFORM_SOURCES
platform/posix/fmt_open.c
platform/posix/glob.c
platform/posix/map_resource.c
platform/posix/resource_io.c
platform/posix/ilaunch.c
platform/posix/strip_traverse.c
platform/posix/paths.c
platform/posix/sem.c
platform/posix/shm.c
platform/posix/time.c
platform/posix/warning.c
platform/sdl/event.c
platform/sdl/video.c
)

set (FSERV_PLATFORM_SOURCES
platform/posix/warning.c
platform/posix/time.c
platform/posix/sem.c
platform/posix/shm.c
platform/sdl/event.c
)

add_definitions(-DPLATFORM_HEADER="platform/posix/platform.h")
add_definitions(-DCLOCK_SOURCE_RAW)
add_definitions(-DLUA_51 -D__UNIX -D_POSIX_C_SOURCE -D_GNU_SOURCE)

find_program(GENERATE_TAGS ctags)

if (GENERATE_TAGS)
	message("--> ctags command found, generating tags output")
	set_source_files_properties( ctags.output PROPERTIES GENERATED true )
	add_custom_command( OUTPUT ctags.output
		COMMAND ctags -R --fields=+iaS --extra=+q -o ctags.output .
		WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} )
	LIST(APPEND SOURCES ctags.output)
endif (GENERATE_TAGS)

LIST(APPEND SOURCES 
	${CMAKE_EXTERNAL_SRCDIR}/hidapi/hid_linux.c
	${CMAKE_EXTERNAL_SRCDIR}/hidapi/hidapi.h
 	arcan_target_launcher.c 
	arcan_frameserver_backend_unix.c
)
LIST(APPEND SOURCES ${PLATFORM_SOURCES})

LIST(APPEND MAIN_LIBRARIES usb-1.0 m rt) 
LIST(APPEND FSRV_SOURCES frameserver/arcan_frameserver.c ${FSERV_PLATFORM_SOURCES})
LIST(APPEND FSRV_LIBRARIES rt m dl)

add_library(arcan_hijack SHARED 
	arcan_target_unix.c
	arcan_target.c	
	arcan_event.c 
	arcan_frameserver_shmpage.c 
	frameserver/ntsc/snes_ntsc.c
 	frameserver/resampler/resample.c)

set_property(TARGET arcan_hijack PROPERTY 
	COMPILE_DEFINITIONS ENABLE_X11HIJACK ENABLE_WINE_HIJACK)

target_link_libraries(arcan_hijack ${SDL_LIBRARY} ${OPENGL_gl_LIBRARY})

set(BIN_DST ${CMAKE_INSTALL_PREFIX}/bin)
set(THEME_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/themes)
set(RESOURCES_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/resources)

add_executable( arcan ${SOURCES} )
add_executable( arcan_frameserver ${FSRV_SOURCES})

install(TARGETS arcan_hijack DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)

if (${HAVE_64_BIT} AND NOT ${NO_HIJACK32})
	message("(*) 64-bit target detected, building compat. 32-bit hijack library, disable with -DNO_HIJACK32=1")
	add_library(arcan_hijack32 SHARED 
		arcan_target_unix.c 
		arcan_event.c 
		arcan_frameserver_shmpage.c 
		frameserver/ntsc/snes_ntsc.c)
	
	set_target_properties(arcan_hijack32 PROPERTIES COMPILE_FLAGS "-m32")
 	target_link_libraries(arcan_hijack32 -m32 -lrt )
	install(TARGETS arcan_hijack32 DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)
endif (${HAVE_64_BIT} AND NOT ${NO_HIJACK32})

install(FILES ${CMAKE_SOURCE_DIR}/arcan_romman.rb DESTINATION ${BIN_DST} PERMISSIONS WORLD_READ WORLD_EXECUTE OWNER_WRITE OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE)

if (EXISTS "/usr/bin/dpkg")
	execute_process(COMMAND "dpkg" "--print-architecture" OUTPUT_VARIABLE DPKGARCH)
	string(REPLACE "\n" "" DPKGARCH "${DPKGARCH}")
	set(CPACK_SYSTEM_NAME ${DPKGARCH})
	set(CPACK_DEBIAN_PACKAGE_NAME ${CPACK_PACKAGE_NAME})
	set(CPACK_DEBIAN_PACKAGE_VERSION ${VERSION})
	set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Bjorn Stahl")
	set(CPACK_DEBIAN_PACKAGE_DEPENDS "libc6 (>= 2.4), libglu1-mesa | libglu1, liblua5.1-0, libopenal1, libsdl-image1.2 (>= 1.2.10), libsdl-ttf2.0-0, libsdl1.2debian (>= 1.2.10-1), libsqlite3-0 (>= 3.6.0), libusb-1.0-0 (>= 2:1.0.8), libavcodec54 (>= 8:1.0.0), libavformat54 (>= 8:1.0-0), libavutil51 (>= 8:1.0.0, libswscale2 (>= 8:1.0.0), libavdevice54 (>= 8:1.0-0), libswresample0 (>= 8:1.0.0), libbz2-1.0, x264, librtmp0, ruby1.9.1, libsqlite3-ruby1.9.1, libnokogiri-ruby1.9.1, librmagick-ruby")

endif(EXISTS "/usr/bin/dpkg")

set(CPACK_SOURCE_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-dev_${VERSION}_${CPACK_SYSTEM_NAME}")
set(CPACK_SOURCE_IGNORE_FILES "/\\\\.git/;\\\\.#.*;#.*#;.*~;CMakeFiles;_CPack_Packages;.*\\\\.cmake;install_manifest.txt;CMakeCache.txt;${CMAKE_PACKAGE_NAME}.*\\\\.(tar\\\\.gz|tar\\\\.bz2|deb);Makefile;")

#
#
#
# ----------------------- WINDOWS --------------------------
#
#
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
set (PLATFORM_SOURCES
platform/posix/fmt_open.c
platform/win32/sem.c
platform/win32/strip_traverse.c
platform/win32/shm.c
platform/win32/time.c
platform/win32/glob.c
platform/win32/paths.c
platform/win32/resource_io.c
platform/win32/warning.c
platform/win32/map_resource.c
platform/sdl/event.c
platform/sdl/video.c
)

set (FSERV_PLATFORM_SOURCES
platform/win32/warning.c
platform/win32/time.c
platform/win32/sem.c
platform/win32/shm.c
platform/win32/realpath.c
platform/sdl/event.c
)
 
add_definitions(-DPLATFORM_HEADER="platform\\win32\\platform.h")
add_definitions(-m32 -mthreads -D__WINDOWS -DPOOR_GL_SUPPORT)

# the win32/ folder should be merged with the platform sources
LIST(APPEND SOURCES 
${CMAKE_EXTERNAL_SRCDIR}/hidapi/hid_win32.cpp 
${CMAKE_EXTERNAL_SRCDIR}/hidapi/hidapi.h 
win32/arcan_target_launcher_win32.c
win32/arcan_frameserver_backend_win32.c 
win32/getopt_win32.c 
win32/getopt.h 
win32/sdl_win32_main.c 
${PLATFORM_SOURCES})

LIST(APPEND FSRV_SOURCES 
win32/arcan_frameserver_win32.c 
arcan_frameserver_resource.obj 
${FSERV_PLATFORM_SOURCES})

LIST(APPEND FSRV_LIBRARIES mingwex ws2_32 winmm)
LIST(APPEND MAIN_LIBRARIES iberty winmm setupapi mingw32)

set(BIN_DST ".")
set(RESOURCES_DST "./resources")
set(THEME_DST "./themes")

add_custom_command(
OUTPUT arcan_resource.obj
DEPENDS arcan.rc
COMMAND windres.exe
ARGS -o arcan_resource.obj
-iarcan.rc
)

add_custom_command(
OUTPUT arcan_frameserver_resource.obj
DEPENDS win32/arcan_frameserver.rc
COMMAND windres.exe
ARGS -o arcan_frameserver_resource.obj
-iarcan_frameserver.rc
)

# there must be a sane way to do this and actually have it work,
# add_custom_target on the output seems to do absolutely nothing.
add_custom_command(
OUTPUT arcan_romman.exe
DEPENDS ${CMAKE_SOURCE_DIR}/arcan_romman.rb ${CMAKE_SOURCE_DIR}/resources/scripts/romman_base.rb
COMMAND ocra
ARGS --output arcan_romman.exe ${CMAKE_SOURCE_DIR}/arcan_romman.rb ${CMAKE_SOURCE_DIR}/resources/scripts/romman_base.rb
)

add_executable( arcan WIN32 ${SOURCES} arcan_resource.obj arcan_romman.exe)
add_executable( arcan_frameserver ${FSRV_SOURCES})

# ------------- Win32 Arcan Launcher Tool -----------
include_external_msproject(ArcanLauncher ${CMAKE_SOURCE_DIR}/win32/ArcanLauncher/ArcanLauncher/ArcanLauncher.csproj
	TYPE 1FC6864D-77E3-4AE9-AB3F-3E450B4335E4
	PLATFORM "Any CPU"
	)

# ------------- Win32 Installer ------------
 file (GLOB _dlls "${CMAKE_SOURCE_DIR}/win32/lib/distr/*.dll")
 install(FILES ${_dlls} DESTINATION ${BIN_DST})
 install(FILES arcan_romman.exe DESTINATION ${BIN_DST})
 install(FILES winicon.ico DESTINATION ${BIN_DST})
 install(FILES COPYRIGHT DESTINATION ${BIN_DST})
 install(FILES oalinst.exe DESTINATION ${BIN_DST})
 install(FILES "${CMAKE_SOURCE_DIR}/win32/ArcanLauncher/ArcanLauncher/bin/Release/ArcanLauncher.exe" DESTINATION ${BIN_DST})

# overwrite to reduce hassle on Vista++, only affects themes/resources
# doesn't seem to have the desired effect however ..
 set(SHARED_PERMISSIONS OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_WRITE WORLD_READ)
 set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_EXCECUTE WORLD_WRITE WORLD_READ)

 set_target_properties(arcan PROPERTIES COMPILE_FLAGS "-Dmain=SDL_main -DREPLACE_GETOPT")

 SET(CPACK_GENERATOR ${CPACK_GENERATOR};NSIS)
 SET(CPACK_NSIS_MUI_ICON "${CMAKE_CURRENT_SOURCE_DIR}/winicon.ico")
 SET(CPACK_NSIS_MUI_UNIICON "${CMAKE_CURRENT_SOURCE_DIR}/winicon.ico")
 SET(CPACK_NSIS_MUI_PRODUCT "Arcan")
 SET(CPACK_PACKAGE_INSTALL_DIRECTORY "Arcan")
 SET(CPACK_PACKAGE_VENDOR "Arcan Frontend")

# try to autoinstall OpenAL (if needed)
SET(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "${CPACK_NSIS_EXTRA_INSTALL_COMMANDS} 
WriteRegStr HKLM 'Software\\\\Arcan Frontend\\\\Arcan' 'InstallDir' '\$INSTDIR'
ExecWait '\\\"$INSTDIR\\\\oalinst.exe\\\" /s' ")

SET(CPACK_NSIS_CREATE_ICONS "CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Welcome).lnk' '\$INSTDIR\\\\arcan.exe' 'welcome'")
SET(CPACK_NSIS_CREATE_ICONS_EXTRA "
	AccessControl::GrantOnFile '\$INSTDIR\\\\themes' '(BU)' 'GenericRead + GenericWrite'
	AccessControl::GrantOnFile '\$INSTDIR\\\\resources' '(BU)' 'GenericRead + GenericWrite'
	CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\ArcanLauncher.lnk' '\$INSTDIR\\\\ArcanLauncher.exe' ''
	CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Build DB (full).lnk' '\$INSTDIR\\\\arcan_romman.exe' 'builddb --mamegood --mameskipclone --mameshorttitle --dbname ./resources/arcandb.sqlite --rompath ./resources/games --targetpath ./resources/targets'
	CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Gridle).lnk' '\$INSTDIR\\\\arcan.exe' 'gridle'
	CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Gridle Remote).lnk' '\$INSTDIR\\\\arcan.exe' 'gridle_remote'
	CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Streamer).lnk' '\$INSTDIR\\\\arcan.exe' '-V -v streamer'
  WriteINIStr '$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Help (online).url' 'InternetShortcut' 'URL' 'http://sourceforge.net/p/arcanfe/wiki/Home/'
")

SET(CPACK_NSIS_DELETE_ICONS_EXTRA "
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Welcome).lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests\\\\Event Test.lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests\\\\Font Test.lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests\\\\Event Test.lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests\\\\Sound Test.lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests\\\\Image Test.lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests\\\\Movie Test.lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests\\\\Core Comparator.lnk'
	RMDir '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Tests'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Build DB (Full).lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Gridle).lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Gridle Remote).lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Streamer).lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\ArcanLauncher.lnk'
	Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Help (online).url'
")

 SET(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION ".")
endif()

target_link_libraries( arcan ${MAIN_LIBRARIES} )
set_target_properties( arcan_frameserver PROPERTIES COMPILE_FLAGS "${FSRV_BUILD_FLAGS}" )
target_link_libraries( arcan_frameserver ${FSRV_LIBRARIES} )

# add_dependencies( arcan_frameserver nacl )

install(TARGETS arcan_frameserver DESTINATION ${BIN_DST})
#install(TARGETS arcan_modelconv DESTINATION ${BIN_DST})
install(TARGETS arcan DESTINATION ${BIN_DST})

install(DIRECTORY ${CMAKE_SOURCE_DIR}/themes/ DESTINATION ${THEME_DST} DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR} FILE_PERMISSIONS ${SHARED_PERMISSIONS} PATTERN ".svn" EXCLUDE)
install(DIRECTORY ${CMAKE_SOURCE_DIR}/resources/ DESTINATION ${RESOURCES_DST} DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR} FILE_PERMISSIONS ${SHARED_PERMISSIONS} PATTERN ".svn" EXCLUDE)

INCLUDE(InstallRequiredSystemLibraries)
set(CPACK_SOURCE_IGNORE_FILES "/\\\\..*$;~$;${CPACK_SOURCE_IGNORE_FILES}")
set(CPACK_PACKAGE_NAME "Arcan")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Scriptable frontend for games and emulators")
set(CPACK_PACKAGE_DESCRIPTION "ARCAN is a fully scriptable front-end for launching and managing emulators, games and other full-screen applications in a visually appealing and embeddable way.")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE.txt")

set(CPACK_PACKAGE_VERSION_MAJOR ${MAJOR_VERSION} )
set(CPACK_PACKAGE_VERSION_MINOR ${MINOR_VERSION} )
set(CPACK_PACKAGE_VERSION_PATCH ${PATCH_LEVEL} )
set(CPACK_PACKAGE_CONTACT "arcan-fe@b-stahl.se")
INCLUDE( CPack )
