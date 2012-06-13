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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# --- Project metadata
PROJECT( arcan )

cmake_minimum_required(VERSION 2.6.0 FATAL_ERROR)
set(MAJOR_VERSION 0 )
set(MINOR_VERSION 1 )
set(PATCH_LEVEL 4 )
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})

set(SHARED_PERMISSIONS OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_READ)
set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_EXCECUTE WORLD_READ)

set( MAIN_LIBRARIES )

# --- Step 1, Dependencies
# paths / locations
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake_modules)

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
	set(SDLTTF_INCLUDE_DIR ${WININC}\\SDL)
	set(ZLIB_INCLUDE_DIR ${WININC})
	set(BZIP2_INCLUDE_DIR ${WININC})
	set(OPENAL_LIBRARY ${WINLIB}\\OpenAL32.lib)
	set(OPENAL_INCLUDE_DIR ${WININC}\\AL)
	set(ZLIB_LIBRARY ${WINLIB}\\zlib1.dll)
	set(LUA_LIBRARY ${WINLIB}\\..\\lua\\liblua.a)
	set(LUA_INCLUDE_DIR ${WININC}\\..\\lua)
	set(SQLITE3_INCLUDE_DIR ${WININC})
	set(SQLITE3_LIBRARY_RELEASE ${WINLIB}\\sqlite3.dll)
	set(SDLIMAGE_INCLUDE_DIR ${WININC}\\SDL)
	LIST(APPEND MAIN_LIBRARIES ${WINLIB}\\glew32s.lib)
endif()

FIND_PACKAGE ( SDL REQUIRED )
FIND_PACKAGE ( SDL_image REQUIRED )
FIND_PACKAGE ( SDL_ttf REQUIRED )
FIND_PACKAGE ( OpenGL REQUIRED )
FIND_PACKAGE ( OpenAL REQUIRED )
FIND_PACKAGE ( Lua51 REQUIRED )
FIND_PACKAGE ( BZip2 REQUIRED )
FIND_PACKAGE ( ZLIB REQUIRED )
FIND_PACKAGE ( FFMPEG REQUIRED )
FIND_PACKAGE ( VORBIS REQUIRED )
FIND_PACKAGE ( SQLITE3 REQUIRED )
FIND_PACKAGE ( OpenCTM REQUIRED )

LIST (APPEND 
	MAIN_LIBRARIES
	${SDL_LIBRARY}
	${SDLIMAGE_LIBRARY}
	${SDLTTF_LIBRARY}
	${LUA_LIBRARY}
	${OPENGL_LIBRARY}
	${OPENAL_LIBRARY}
	${BZIP2_LIBRARIES}
	${ZLIB_LIBRARY}
	${ASSERT_LIBRARY}
	${SQLITE3_LIBRARIES}
	${VORBIS_LIBRARIES}
	${OPENCTM_LIBRARIES}
)

set (
FSRV_LIBRARIES 
	${SDL_LIBRARY}
	${FFMPEG_LIBRARIES}
	${BZIP2_LIBRARIES}
	${ZLIB_LIBRARY}
)

include_directories ( 
	${LUA_INCLUDE_DIR}
	${OPENAL_INCLUDE_DIR}
	${SDL_INCLUDE_DIR}
	${SDLIMAGE_INCLUDE_DIR}
	${SDLTTF_INCLUDE_DIR}
	${SQLITE3_INCLUDE_DIR}
	${FFMPEG_INCLUDE_DIR}
	${FFMPEG_LIBAVCODEC_INCLUDE_DIR}
	${VORBIS_INCLUDE_DIR}
	${OPENCTM_INCLUDE_DIR}
)

# removed, current code has some serious issues
# if (MPG123_FOUND )
# message("mpg123 found, enabling mp3 support.")
# LIST(APPEND MAIN_LIBRARIES ${MPG123_LIBRARY} )
# # LIST(APPEND include_directories ${MPG123_INCLUDE_DIR} )
# add_definitions(-D_HAVE_MPG123)
# endif(MPG123_FOUND)

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
 arcan_shdrmgmt.c
 arcan_3dbase.c
 arcan_math.c
 arcan_audio.c
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
 arcan_general.c
 arcan_led.c
 arcan_led.h
 arcan_general.h
 arcan_db.h
 arcan_shdrmgmt.h
 arcan_frameserver_shmpage.h
 arcan_frameserver_shmpage.c
) 

set (
 FSRV_SOURCES
 frameserver/arcan_frameserver_decode.h
 frameserver/arcan_frameserver_decode.c
 frameserver/arcan_frameserver_libretro.h
 frameserver/arcan_frameserver_libretro.c
 arcan_frameserver_shmpage.h
 arcan_frameserver_shmpage.c
 arcan_general.c
 arcan_event.c
)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    message("Debug build")
	add_definitions(-g -D_DEBUG)
endif (CMAKE_BUILD_TYPE STREQUAL "Debug")

add_definitions(-std=gnu99 -D_BSD_SOURCE )

# OS Specific modifications
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
LIST(APPEND SOURCES SDLMain.m hidapi/hid_mac.c hidapi/hidapi.h arcan_target_launcher.c arcan_frameserver_backend_unix.c)
LIST(APPEND FSRV_SOURCES frameserver/arcan_frameserver.c)

# " probe " support not ready, idea is to sweep targets, look at dependencies with the hijack preloaded
# and figure out which symbols are used and available 

#add_custom_target(arcan_target_probebackend DEPENDS "arcan_target_probe.c")
#add_library(arcan_hijackprobe SHARED arcan_target_osx.c )
#add_dependencies(arcan_hijackprobe arcan_target_probebackend)
#set_target_properties(arcan_hijackprobe PROPERTIES COMPILE_FLAGS "-DPROBE")

add_definitions(-D__APPLE__ -D__UNIX -DLUA_51)
add_library( arcan_hijack SHARED arcan_target_osx.c arcan_event.c)
target_link_libraries( arcan_hijack ${SDL_LIBRARY} ${OPENGL_LIBRARY} )

add_executable( arcan ${SOURCES} )
add_executable( arcan_frameserver ${FSRV_SOURCES})
add_executable( arcan_modelconv arcan_modelconv.c arcan_math.c)

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
	add_definitions(-DLUA_51 -D__UNIX -D_LIBUSB_BSD)

	LIST(APPEND SOURCES hidapi/hid_linux.c hidapi/hidapi.h arcan_target_launcher.c arcan_frameserver_backend_unix.c)
	LIST(APPEND MAIN_LIBRARIES usb rt)
	LIST(APPEND FSRV_SOURCES frameserver/arcan_frameserver.c)
	LIST(APPEND FSRV_LIBRARIES -lrt)

	add_library(arcan_hijack SHARED arcan_target_unix.c arcan_event.c arcan_target.c)
	target_link_libraries(arcan_hijack ${SDL_LIBRARY} ${OPENAL_LIBRARY})
	
	set(BIN_DST ${CMAKE_INSTALL_PREFIX}/bin)
	set(THEME_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/themes)
	set(RESOURCES_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/resources)

	add_executable( arcan ${SOURCES})
	add_executable( arcan_frameserver ${FSRV_SOURCES})
	add_executable( arcan_modelconv arcan_modelconv.c arcan_math.c)

	install(TARGETS arcan_hijack DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)
	install(FILES ${CMAKE_SOURCE_DIR}/arcan_romman.rb DESTINATION ${BIN_DST} PERMISSIONS WORLD_READ WORLD_EXECUTE OWNER_WRITE OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE)
#
# ----------------------- LINUX --------------------------
#
#
elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
add_definitions(-DLUA_51 -D__UNIX -D_POSIX_C_SOURCE -D_GNU_SOURCE)

LIST(APPEND SOURCES hidapi/hid_linux.c hidapi/hidapi.h arcan_target_launcher.c arcan_frameserver_backend_unix.c)
LIST(APPEND MAIN_LIBRARIES usb-1.0 rt)
LIST(APPEND FSRV_SOURCES frameserver/arcan_frameserver.c)
LIST(APPEND FSRV_LIBRARIES -lrt -lm)

add_custom_target(arcan_target_backend DEPENDS "arcan_target.c")
add_library(arcan_hijack SHARED arcan_target_unix.c arcan_event.c)
add_dependencies(arcan_hijack arcan_target_backend)
target_link_libraries(arcan_hijack ${SDL_LIBRARY} ${OPENAL_LIBRARY})

# part of tools to troubleshoot / test hijack for a target (intended for the romman)
# add_custom_target(arcan_target_probebackend DEPENDS "arcan_target_probe.c")
# add_library(arcan_hijackprobe SHARED arcan_target_unix.c)
# add_dependencies(arcan_hijackprobe arcan_target_probebackend)
# set_target_properties(arcan_hijackprobe PROPERTIES COMPILE_FLAGS "-DPROBE")

set(BIN_DST ${CMAKE_INSTALL_PREFIX}/bin)
set(THEME_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/themes)
set(RESOURCES_DST ${CMAKE_INSTALL_PREFIX}/share/arcan/resources)

add_executable( arcan ${SOURCES})
add_executable( arcan_frameserver ${FSRV_SOURCES})
add_executable( arcan_modelconv arcan_modelconv.c arcan_math.c)

install(TARGETS arcan_hijack DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)
install(FILES ${CMAKE_SOURCE_DIR}/arcan_romman.rb DESTINATION ${BIN_DST} PERMISSIONS WORLD_READ WORLD_EXECUTE OWNER_WRITE OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE)

if (EXISTS "/usr/bin/dpkg")
	execute_process(COMMAND "dpkg" "--print-architecture" OUTPUT_VARIABLE DPKGARCH)
	string(REPLACE "\n" "" DPKGARCH "${DPKGARCH}")
	set(CPACK_SYSTEM_NAME ${DPKGARCH})
	set(CPACK_DEBIAN_PACKAGE_NAME ${CPACK_PACKAGE_NAME})
	set(CPACK_DEBIAN_PACKAGE_VERSION ${VERSION})
	set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Bjorn Stahl")
	set(CPACK_DEBIAN_PACKAGE_DEPENDS "libc6 (>= 2.4), libglu1-mesa | libglu1, liblua5.1-0, libopenal1, libsdl-image1.2 (>= 1.2.10), libsdl-ttf2.0-0, libsdl1.2debian (>= 1.2.10-1), libsqlite3-0 (>= 3.6.0), libusb-1.0-0 (>= 2:1.0.8), libvorbisfile3 (>= 1.1.2), libavcodec-extra-53 (>= 4:0.7-1), libavformat53 (>= 4:0.7-1) | libavformat-extra-53 (>= 4:0.7-1), libavutil-extra-51 (>= 4:0.7-1), libswscale2 (>= 4:0.7-1) | libswscale-extra-2 (>= 4:0.7-1), libavdevice53 (>= 4:0.7-1), libbz2-1.0, libvorbis0a, libogg0, ruby1.9.1, libsqlite3-ruby1.9.1, libnokogiri-ruby1.9.1")
endif(EXISTS "/usr/bin/dpkg")

set(CPACK_SOURCE_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-dev_${VERSION}_${CPACK_SYSTEM_NAME}")
set(CPACK_SOURCE_IGNORE_FILES "/\\\\.git/;\\\\.#.*;#.*#;.*~;CMakeFiles;_CPack_Packages;.*\\\\.cmake;install_manifest.txt;CMakeCache.txt;${CMAKE_PACKAGE_NAME}.*\\\\.(tar\\\\.gz|tar\\\\.bz2|deb);Makefile;")

set(CPACK_RPM_PACKAGE_NAME ${CPACK_DEBIAN_PACKAGE_DESCRIPTION})
set(CPACK_RPM_PACKAGE_DESCRIPTION ${CPACK_DEBIAN_PACKAGE_DESCRIPTION})
set(CPACK_RPM_PACKAGE_LICENSE "GNU General Public License (GPL")
#
#
#
# ----------------------- WINDOWS --------------------------
#
#

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
 add_definitions(-m32 -D__WINDOWS -DPOOR_GL_SUPPORT)

 LIST(APPEND SOURCES hidapi/hid_win32.cpp hidapi/hidapi.h win32/arcan_target_launcher_win32.c win32/arcan_frameserver_backend_win32.c win32/getopt_win32.c win32/getopt.h win32/sdl_win32_main.c)
 LIST(APPEND FSRV_SOURCES win32/arcan_frameserver_win32.c arcan_frameserver_resource.obj)

 LIST(APPEND FSRV_LIBRARIES mingwex ws2_32)
 LIST(APPEND MAIN_LIBRARIES iberty winmm setupapi mingw32 ${WINLIB}/libvorbisfile.a ${WINLIB}/libvorbis.a ${WINLIB}/libogg.a)

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
 add_executable( arcan_modelconv arcan_modelconv.c arcan_math.c)

 file (GLOB _dlls "${CMAKE_SOURCE_DIR}/win32/lib/distr/*.dll")
 install(FILES ${_dlls} DESTINATION ${BIN_DST})
 install(FILES arcan_romman.exe DESTINATION ${BIN_DST})
 install(FILES winicon.ico DESTINATION ${BIN_DST})
 install(FILES oalinst.exe DESTINATION ${BIN_DST})

# overwrite to reduce hassle on Vista++, only affects themes/resources
# doesn't seem to have the desired effect however ..
 set(SHARED_PERMISSIONS OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_WRITE WORLD_READ)
 set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_EXCECUTE WORLD_WRITE WORLD_READ)

 set_target_properties(arcan PROPERTIES COMPILE_FLAGS "-Dmain=SDL_main -DREPLACE_GETOPT")
 SET(CPACK_GENERATOR ${CPACK_GENERATOR};NSIS)
 SET(CPACK_NSIS_MUI_ICON "${CMAKE_CURRENT_SOURCE_DIR}/winicon.ico")
 SET(CPACK_NSIS_MUI_UNIICON "${CMAKE_CURRENT_SOURCE_DIR}/winicon.ico")
 SET(CPACK_PACKAGE_INSTALL_DIRECTORY "Arcan")
# SET(CPACK_PACKAGE_ICON "${CMAKE_SOURCE_DIR}\\\\InstallIcon.bmp") -- horrible scaling

# try to autoinstall OpenAL (if needed)
SET(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "${CPACK_NSIS_EXTRA_INSTALL_COMMANDS}
ExecWait '\\\"$INSTDIR\\\\redist\\\\oalinst.exe\\\" /s'" )

SET(CPACK_NSIS_CREATE_ICONS "CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Welcome).lnk' '\$INSTDIR\\\\arcan.exe' 'welcome'")
SET(CPACK_NSIS_CREATE_ICONS_EXTRA "
    AccessControl::GrantOnFile '\$INSTDIR\\\\themes' '(BU)' 'GenericRead + GenericWrite'
	AccessControl::GrantOnFile '\$INSTDIR\\\\resources' '(BU)' 'GenericRead + GenericWrite'
		   CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Getting Started.lnk' '\$INSTDIR\\\\resources\\\\doc\\\\quickstart.pdf'
		   CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Event Test.lnk' '\$INSTDIR\\\\arcan.exe' 'eventtest'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Font Test.lnk' '\$INSTDIR\\\\arcan.exe' 'fonttest'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Event Test.lnk' '\$INSTDIR\\\\arcan.exe' 'eventtest'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Sound Test.lnk' '\$INSTDIR\\\\arcan.exe' 'soundtest'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Image Test.lnk' '\$INSTDIR\\\\arcan.exe' 'imagetest'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Movie Test.lnk' '\$INSTDIR\\\\arcan.exe' 'movietest'
		   CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Build DB.lnk' '\$INSTDIR\\\\arcan_romman.exe' 'builddb --generic --mamegood --mameskipclone --mameshorttitle --dbname ./resources/arcandb.sqlite --rompath ./resources/games --targetpath ./resources/targets'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Gridle).lnk' '\$INSTDIR\\\\arcan.exe' 'gridle'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Dishwater).lnk' '\$INSTDIR\\\\arcan.exe' 'dishwater'
           CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Arcan (Space).lnk' '\$INSTDIR\\\\arcan.exe' 'space'
")
	
SET(CPACK_NSIS_DELETE_ICONS_EXTRA "
		Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Welcome).lnk' 
		   Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Getting Started.lnk'
		   Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Event Test.lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Font Test.lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Event Test.lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Sound Test.lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Image Test.lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Movie Test.lnk'
		   Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Build DB.lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Gridle).lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Dishwater).lnk'
           Delete '\$SMPROGRAMS\\\\$MUI_TEMP\\\\Arcan (Space).lnk'
")


 SET(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION ".")
endif()

target_link_libraries( arcan ${MAIN_LIBRARIES} )
target_link_libraries( arcan_modelconv ${OPENCTM_LIBRARIES} )
set_target_properties(arcan_frameserver PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations")
target_link_libraries( arcan_frameserver ${FSRV_LIBRARIES} )

install(TARGETS arcan_frameserver DESTINATION ${BIN_DST})
install(TARGETS arcan_modelconv DESTINATION ${BIN_DST})
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
set(CPACK_PACKAGE_CONTACT "arcan-fe@sourceforge.net")
INCLUDE( CPack )
