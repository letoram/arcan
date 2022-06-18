# tried playing nice by using REQUIRE_QUIET but some built-in modules
# (CheckLibraryExists, ...) wouldn't listen so how about a nice cup
# of shut up.
function(message)
	list(GET ARGV 0 TYPE)
	if (TYPE STREQUAL "FATAL_ERROR")
		list(REMOVE_AT ARGV 0)
		_message(${TYPE} ${CL_RED} "${ARGV}" ${CL_RST})
	endif()
endfunction()

function(amsg msg)
	_message("" ${msg})
endfunction()

if (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client")
	PROJECT(arcan-libs)
else()
	PROJECT(arcan)
endif()

cmake_minimum_required(VERSION 3.1 FATAL_ERROR)

SET(CMAKE_SKIP_BUILD_RPATH  FALSE)
SET(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE)
SET(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")
SET(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
set(THREADS_PREFER_PTHREAD_FLAG TRUE)

set(EXTERNAL_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../external)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/modules)

set(SHARED_PERMISSIONS
	OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_READ)
set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE
	GROUP_READ WORLD_EXECUTE WORLD_READ)

# another hack to strip noisy / useless data away from message() abuse
include(ExternalProject)
include(CheckIncludeFiles)

find_package(PkgConfig REQUIRED)
find_package(Sanitizers REQUIRED)

# not pretty, but as a quick 'pending build system rewrite' thing
find_package(Threads REQUIRED)
find_package(Math REQUIRED)
find_package(RT REQUIRED)
find_package(DL REQUIRED)

set(STDLIB Threads::Threads Math::Math RT::RT DL::DL)

if (CMAKE_COLOR_MAKEFILE)
	include(CMakeColor)
endif()

if (GLOBAL_CFLAGS)
	add_definitions(${GLOBAL_CFLAGS})
endif()

# static base version, manually mantained
set(MAJOR_VERSION 0)
set(MINOR_VERSION 6)
set(PATCH_LEVEL 1)
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})
set(PLATFORM_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/platform)
set(ENGINE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/engine)

# distributions packaging a build should tag this accordingly so we
# can take that into consideration for bug reports
if (NOT DEFINED DISTR_TAG)
	set(DISTR_TAG "unknown")
endif()

# generate an identifiable buildtag for tracking purposes
if (NOT DEFINED ENGINE_BUILDTAG)
	find_package(Git)
	set(GIT_VERSION)
	if (GIT_FOUND)
		execute_process(COMMAND ${GIT_EXECUTABLE} describe --always --tags
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			RESULT_VARIABLE EXIT_CODE
			OUTPUT_VARIABLE GIT_VERSION
		)
		if (NOT ${EXIT_CODE} EQUAL 0)
		else()
			string(STRIP ${GIT_VERSION} GIT_VERSION)
		endif()

		execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			RESULT_VARIABLE EXIT_CODE
			OUTPUT_VARIABLE GIT_BRANCH
		)
		if (NOT ${EXIT_CODE} EQUAL 0)
		else()
			string(STRIP ${GIT_BRANCH} GIT_BRANCH)
		endif()

		if (GIT_VERSION STREQUAL "")
			amsg("${CL_RED}missing git_version, using 'relukn' for build tag${CL_RST}")
			set(ENGINE_BUILDTAG arcan-relukn-${VERSION})
		else()
			set(ENGINE_BUILDTAG arcan-git-${GIT_BRANCH}-${GIT_VERSION})
		endif()
	else()
		amsg("${CL_RED}git not found, using 'relukn' for build tag${CL_RST}")
		set(ENGINE_BUILDTAG arcan-relukn-${VERSION})
	endif()
endif()
set(SOURCE_TAG ${ENGINE_BUILDTAG})
set(ENGINE_BUILDTAG "")

set(SHARED_PERMISSIONS OWNER_WRITE OWNER_READ GROUP_READ WORLD_READ)
set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)

if (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client")
	amsg("Client- Library only build, for docker containers and networked clients")
	amsg("")
	amsg("${CL_WHT}Optional library flags:${CL_RST}")
	amsg("${CL_YEL}\t-DSHMIF_DISABLE_DEBUGIF=${CL_GRN}[Off|On]${CL_RST} - Remove server- controlled debug layer")
	amsg("")

	if (${CMAKE_SYSTEM_NAME} MATCHES "BSD|DragonFly")
		set(BSD_BUILD TRUE)
		set(EXTMAKE_CMD gmake)
	endif()
else()
	if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
		set(VPLATFORM_STR "sdl sdl2")
		if (NOT VIDEO_PLATFORM)
			set(VIDEO_PLATFORM "sdl2")
		endif()
		set(CMAKE_INSTALL_LIBDIR /usr/local/share/lib)
	else()
		set(VPLATFORM_STR "egl-dri, sdl, sdl2, egl-gles")
		if (NOT VIDEO_PLATFORM)
			set(VIDEO_PLATFORM "egl-dri")
		endif()
		include(GNUInstallDirs)
	endif()
	set(AGPPLATFORM_STR "gl21, gles2, gles3, stub")

	# we can remove some of this cruft when 'buntu LTS gets ~3.0ish
	option(DISABLE_JIT "Don't use the luajit-5.1 VM (if found)" OFF)
	option(STATIC_SQLite3 "Use SQLite3 Amalgamation" OFF)
	option(STATIC_OPENAL "Use static OpenAL (external/git folder)" OFF)
	option(STATIC_LIBUVC "Use static libuvc (external/git folder)" ON)
	option(ENABLE_LTO "Build with Link-Time Optimization enabled" OFF)
	option(ENABLE_LWA "Build LWA client (arcan-in-arcan)" ON)
	option(ENABLE_SIMD "Build with SIMD vector instruction set support" ON)
	option(ENABLE_SIMD_ALIGNED "Assert that SIMD data sources are 16-byte aligned" OFF)
	option(DISABLE_WAYLAND "Never build wayland support" OFF)
	option(HYBRID_SDL "Produce an arcan_sdl main binary as well" OFF)
	option(HYBRID_HEADLESS "Produce a headless binary as well" OFF)

	amsg("")
	amsg("${CL_WHT}Build Presets:")
	amsg("${CL_YEL}\t-DBUILD_PRESET=${CL_GRN}everything client${CL_RST}")
	amsg("")
	amsg("${CL_WHT}Audio/Video/Input Support:")
	amsg("${CL_YEL}\t-DVIDEO_PLATFORM=${CL_GRN}${VPLATFORM_STR}${CL_RST}")
	amsg("${CL_YEL}\t-DAGP_PLATFORM=${CL_GRN}${AGPPLATFORM_STR}${CL_RST}")
	amsg("")
	amsg("${CL_WHT}VIDEO_PLATFORM=egl-dri options:${CL_RST}")
	amsg("${CL_YEL}\t-DHYBRID_SDL=${CL_GRN}[Off|On]${CL_RST} - Enable arcan_sdl output build")
	amsg("${CL_YEL}\t-DHYBRID_HEADLESS=${CL_GRN}[Off|On]${CL_RST} - Enable arcan_headless output build")
	amsg("")
	amsg("${CL_WHT}Cmake Options:${CL_RST}")
	amsg("${CL_YEL}\t-DCMAKE_BUILD_TYPE=${CL_GRN}[Debug|Release|Profile|DebugTrace]")
	amsg("${CL_YEL}\t-DENABLE_WALL_SPAM=${CL_GRN}[Off|On]${CL_RST} - More build warnings")
	amsg("${CL_YEL}\t-DENABLE_SIMD=${CL_GRN}[On|Off]${CL_RST} - Enable SIMD optimized instructions")
	# amsg("    -DENABLE_PBO=[Appl-path] : Profile-based Optimization prepass with appl")
	# amsg("                               as optimization profile.")
	amsg("${CL_YEL}\t\t-DSIMD_ALIGNED=${CL_GRN}[Off|On]${CL_RST} - SIMD support assumes 16-byte alignment")
	amsg("${CL_YEL}\t-DENABLE_LTO=${CL_GRN}[Off|On]${CL_RST} - Build with Link-Time Optimizations")
	amsg("")
	amsg("${CL_WHT}Dependency Management:${CL_RST}")
	amsg("${CL_YEL}\t-DSTATIC_SQLite3=${CL_GRN}[Off|On]${CL_RST} - In-source SQLite3")
	amsg("${CL_YEL}\t-DSTATIC_OPENAL=${CL_GRN}[Off|On]${CL_RST} - In-source OpenAL, see external/README")
	amsg("${CL_YEL}\t-DSTATIC_LIBUVC=${CL_GRN}[Off|On]${CL_RST} - In-source libuvc")
	amsg("")
	amsg("${CL_WHT}Optional engine flags:${CL_RST}")
	amsg("${CL_YEL}\t-DENABLE_LWA=${CL_GRN}[Off|On]${CL_RST} - Build LWA Arcan client (nesting support)")
	amsg("${CL_YEL}\t-DDISABLE_JIT=${CL_GRN}[Off|On]${CL_RST} - Don't Link with luajit51 (even if found)")
	amsg("${CL_YEL}\t-DBUILTIN_LUA=${CL_GRN}[Off|On]${CL_RST} - Static build lua51 (with disable_jit)")
	amsg("${CL_YEL}\t-DSHMIF_DISABLE_DEBUGIF=${CL_GRN}[Off|On]${CL_RST} - Remove server- controlled debug layer")
	amsg("")
	amsg("${CL_WHT}Frameserver flags:${CL_RST}")
	amsg("${CL_WHT}Decode:${CL_RST}")
	amsg("${CL_YEL}\t-DFSRV_DECODE_UVC=${CL_GRN}[Off|On]${CL_RST} - Add support for libuvc- USB video cameras")
	amsg("${CL_WHT}Terminal:${CL_RST}")
	amsg("${CL_YEL}\t-DFSRV_TERMINAL_NOEXEC=${CL_GRN}[Off|On]${CL_RST} - Lock down 'exec' path from scripts")
	amsg("")
	amsg("${CL_WHT}Install / Autodetection Overrides:${CL_RST}")
	amsg("${CL_YEL}\t-D(DISABLE_FSRV_ (encode, decode, net, remoting, terminal, game)${CL_GRN}=ON${CL_RST}")
	amsg("${CL_YEL}\t-D(APPL_DEST, RES_DEST, APIMAN_DEST, MAN_DEST, SCRIPTS_DEST)=${CL_GRN}/some/path${CL_RST}")
	amsg("")

	# no other audio platforms supported currently
	set(AUDIO_PLATFORM "openal")
endif()

if (BUILD_PRESET STREQUAL "everything" AND NOT (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client" OR ${CMAKE_SYSTEM_NAME} MATCHES "Darwin"))
	set(VIDEO_PLATFORM "egl-dri")
	set(HYBRID_SDL ON)
	set(HYBRID_HEADLESS ON)
endif()

# can ignore this abomination on BSD
set(CSTD gnu11)

add_compile_options(-Wall)
if ("${CMAKE_C_COMPILER_ID}" MATCHES "GNU" AND NOT ENABLE_WALL_SPAM)
	add_compile_options(
		-Wno-missing-braces
		-Wno-unused-function
		-Wno-unused-value
		-Wno-unused-variable
		-Wno-unused-result
		-Wformat=0
	)

elseif ("${CMAKE_C_COMPILER_ID}" MATCHES "Clang" AND NOT ENABLE_WALL_SPAM)
	add_compile_options(
		-Wno-unknown-warning-option
		-Wno-unused-const-variable
		-Wno-unused-value
		-Wno-missing-braces
		-Wno-unused-function
		-Wno-atomic-alignment
		-Wno-unused-variable
		-Wno-unused-result
		-Wno-macro-redefined
	)
endif()

if (CMAKE_BUILD_TYPE STREQUAL "Profile")
	amsg("${CL_WHT}------------------*Profile Build*------------------${CL_RST}")
	add_definitions(-pg)
	set(CMAKE_EXE_LINKER_FLAGS "-pg")
endif(CMAKE_BUILD_TYPE STREQUAL "Profile")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	amsg("${CL_WHT}------------------*Debug Build*--------------------${CL_RST}\n")
	amsg("${CL_WHT}Debug Specific Setting:${CL_YEL}")
	amsg("\tLUA_TRACE_METHOD=${CL_RST}[${CL_GRN}off${CL_RST}|${CL_GRN}stderr${CL_RST}|${CL_GRN}coverage${CL_RST}]")
	if (LUA_TRACE_METHOD STREQUAL "stderr")
		set(LUA_TAG_MODE " trace-stderr")
		list(APPEND ARCAN_DEFINITIONS LUA_TRACE_STDERR)
	endif()

	if (LUA_TRACE_METHOD STREQUAL "coverage" AND NOT (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client"))
		set(LUA_TAG_MODE " trace-coverage")
		list(APPEND ARCAN_DEFINITIONS LUA_TRACE_COVERAGE)
	endif()

	add_definitions(-g -D_DEBUG -O0 -fno-omit-frame-pointer)

endif (CMAKE_BUILD_TYPE STREQUAL "Debug")

if (CMAKE_BUILD_TYPE STREQUAL "DebugTrace")
	amsg("${CL_WHT}-------------- *Debug Tracing Build* --------------${CL_WHT}")
	add_definitions(-g -D_DEBUG -DTRACE_ENABLE)
endif (CMAKE_BUILD_TYPE STREQUAL "DebugTrace")

if (ENABLE_LTO)
	add_compile_options(-flto)
endif()

if (NOT VIDEO_PLATFORM AND NOT (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client"))
	message(FATAL_ERROR "${CL_RED}Video Platform missing, see -DVIDEO_PLATFORM= above${CL_RST}")
endif()

add_compile_options(-std=${CSTD})

if (NOT (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client"))
	amsg("${CL_WHT}\n------------- Configuration Results ---------------${CL_RST}\n")

	amsg("\n${CL_WHT}-- Stage 1: dependencies and configuration${CL_RST}")
endif()

set(EXTERNAL_DEFS
UPDATE_COMMAND ""
PATCH_COMMAND ""
INSTALL_COMMAND ""
LOG_DOWNLOAD 1
LOG_UPLOAD 1
LOG_CONFIGURE 1
LOG_BUILD 1
LOG_TEST 1
LOG_INSTALL 1
)

set (CMAKE_EXTERNAL_DEFS
	CMAKE_ARGS
	-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
	-DMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
	-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
	-DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}
	-DLIBTYPE=STATIC
)

if (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client")
	find_package(Freetype REQUIRED QUIET)
	set(FREETYPE_DEFAULT_LIBRARIES ${FREETYPE_LIBRARIES})
	set(FREETYPE_DEFAULT_INCLUDE_DIRS ${FREETYPE_INCLUDE_DIRS})

	set(INCLUDE_DIRS
		${CMAKE_CURRENT_SOURCE_DIR}/engine
		${FREETYPE_DEFAULT_INCLUDE_DIRS}
	)
else()
	find_package(Freetype REQUIRED QUIET)
	set(FREETYPE_DEFAULT_LIBRARIES ${FREETYPE_LIBRARIES})
	set(FREETYPE_DEFAULT_INCLUDE_DIRS ${FREETYPE_INCLUDE_DIRS})

	# need the separation here to not confuse openAL here with
	# the version that we patch into LWA
	if (EXISTS ${EXTERNAL_SRC_DIR}/git/openal AND STATIC_OPENAL)
		amsg("${CL_YEL}Building OpenAL static from external/git mirror${CL_RST}")
		ExternalProject_Add(OpenAL
			SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/openal
			BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/openal_static
			UPDATE_COMMAND ""
			GIT_REPOSITORY "${EXTERNAL_SRC_DIR}/git/openal"
			${EXTERNAL_DEFS}
			${CMAKE_EXTERNAL_DEFS}
			-DALSOFT_BACKEND_DSOUND=OFF
			-DALSOFT_BACKEND_MMDEVAPI=OFF
			-DALSOFT_BACKEND_OPENSL=OFF
			-DALSOFT_BACKEND_PORTAUDIO=OFF
			-DALSOFT_BACKEND_SOLARIS=OFF
			-DALSOFT_BACKEND_SNDIO=OFF
			-DALSOFT_BACKEND_QSA=OFF
			-DALSOFT_BACKEND_WAVE=OFF
			-DALSOFT_BACKEND_WINMM=OFF
		)
		set(OPENAL_LIBRARY
			"${CMAKE_CURRENT_BINARY_DIR}/openal_static/libopenal.a"
		)
		set(OPENAL_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/include/AL")
		list(APPEND MAIN_DEPS OpenAL)
	else()
		find_package(OpenAL REQUIRED QUIET)
	endif()

	#
	# the amalgamation is already included in the external/ tree sqlite3 use is
	# primarily settings management and very limited amount of queries, size is
	# more important here
	#
	if (STATIC_SQLite3)
		amsg("${CL_YEL}Building SQLite3 from external/sqlite mirror${CL_RST}")
		add_library(sqlite3 STATIC ${EXTERNAL_SRC_DIR}/sqlite/sqlite3.c)
		set_target_properties(sqlite3 PROPERTIES COMPILE_FLAGS "-Os")
		set(SQLite3_INCLUDE_DIR ${EXTERNAL_SRC_DIR}/sqlite)
		set(SQLite3_LIBRARIES sqlite3)
	else()
		find_package(SQLite3 REQUIRED QUIET)
	endif()

	include(${PLATFORM_ROOT}/cmake/CMakeLists.AGP)
	include(${PLATFORM_ROOT}/cmake/CMakeLists.Video)
	set(EXTMAKE_CMD make)

	# for the statically- linked external dependencies, we need to hint where
	# we need the gmake rather than make system
	if (${CMAKE_SYSTEM_NAME} MATCHES "BSD|DragonFly")
		set(BSD_BUILD TRUE)
		set(EXTMAKE_CMD gmake)
	endif()

	set(LUA_LINKTYPE "dynamic")

	if (NOT DISABLE_JIT)
		set(LUA_TAG "luajit51")
		if (EXISTS ${EXTERNAL_SRC_DIR}/git/luajit)
			ExternalProject_Add(luajit
				SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/luajit
				GIT_REPOSITORY "${EXTERNAL_SRC_DIR}/git/luajit"
				CONFIGURE_COMMAND ""
				GIT_TAG "v2.1.0-beta3"
				UPDATE_COMMAND ""
				INSTALL_COMMAND ""
				BUILD_IN_SOURCE 1
				BUILD_COMMAND "${EXTMAKE_CMD}"
				DEFAULT_CC=${CMAKE_C_COMPILER}
				${EXTERNAL_DEFS}
			)
			set(LUA_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/luajit/src/libluajit.a")
			set(LUA_LIBRARIES ${LUA_LIBRARY})
			set(LUA_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/luajit/src")
			list(APPEND MAIN_DEPS luajit)
			set(LUA_LINKTYPE "static")
		else()
			pkg_check_modules(LUA luajit REQUIRED)
			find_library(LUA_LIBRARY NAMES ${LUA_LIBRARIES} PATHS ${LUA_LIBRARY_DIRS})
			set(LUA_INCLUDE_DIR ${LUA_INCLUDE_DIRS})
			set(LUA_LIBRARIES ${LUA_LINK_LIBRARIES})
		endif()
	endif()

	if (NOT LUA_LIBRARY OR DISABLE_JIT)
		set(LUA_TAG "lua51")
		if (NOT BUILTIN_LUA)
			find_package(Lua51 REQUIRED)
		else()
			add_subdirectory(${EXTERNAL_SRC_DIR}/lua ${CMAKE_CURRENT_BINARY_DIR}/lua)
			set(LUA_INCLUDE_DIR ${EXTERNAL_SRC_DIR}/lua)
			set(LUA_LIBRARIES lua51)
			set(LUA_LINKTYPE "static")
		endif()
	endif()

	LIST (APPEND
		ARCAN_LIBRARIES
		${FREETYPE_DEFAULT_LIBRARIES}
		${LUA_LIBRARIES}
		${SQLite3_LIBRARIES}
	)

	LIST (APPEND
		INCLUDE_DIRS
		${LUA_INCLUDE_DIR}
		${LUA_INCLUDE_DIRS}
		${OPENAL_INCLUDE_DIR}
		${FREETYPE_DEFAULT_INCLUDE_DIRS}
		${SQLite3_INCLUDE_DIR}
		${CMAKE_CURRENT_SOURCE_DIR}/platform
		${EXTERNAL_SRC_DIR}
		${CMAKE_CURRENT_SOURCE_DIR}/engine
	)

	list (APPEND SOURCES
		engine/arcan_event.c
		engine/arcan_lua.c
		engine/alt/nbio.c
		engine/alt/support.c
		engine/alt/types.c
		engine/alt/trace.c
		engine/arcan_main.c
		engine/arcan_conductor.c
		engine/arcan_db.c
		engine/arcan_video.c
		engine/arcan_renderfun.c
		engine/arcan_3dbase.c
		engine/arcan_math.c
		engine/arcan_audio.c
		engine/arcan_ttf.c
		engine/arcan_img.c
		engine/arcan_led.c
		engine/arcan_led.h
		engine/arcan_trace.c
		engine/arcan_ffunc_lut.c
		engine/arcan_ffunc_lut.h
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
		engine/arcan_monitor.c
		shmif/arcan_shmif_sub.c
		engine/arcan_vr.h
		engine/arcan_vr.c
		platform/platform.h
		platform/video_platform.h
		shmif/tui/raster/pixelfont.c
		shmif/tui/raster/raster.c
	)

	# database tool is sqlite3 + libc so less need to work
	# around with platform layers etc.
	set (ARCANDB_SOURCES
		tools/db/dbtool.c
		engine/arcan_db.c
		platform/posix/warning.c
		platform/posix/dbpath.c
		platform/stub/mem.c
	)

	if (ENABLE_SIMD)
		find_package(SSE QUIET)
		if (SSE_FOUND)
			if (SIMD_ALIGNED)
				set_property(SOURCE engine/arcan_math_simd.c
					APPEND PROPERTY COMPILE_DEFINITIONS ARCAN_MATH_ALIGNED_SIMD)
			endif()

			set_property(SOURCE engine/arcan_math.c
				APPEND PROPERTY COMPILE_DEFINITIONS ARCAN_MATH_SIMD)
			list(APPEND SOURCES engine/arcan_math_simd.c)

			set_property(SOURCE engine/arcan_math_simd.c
				APPEND PROPERTY COMPILE_FLAGS -msse3)
		endif()
	endif()
endif()

#
# Expand with more platforms as needed, all are expected to define PLATFORM_[
# ,fsrv, shmif]_SOURCES, add a global definition for PLATFORM_HEADER add any
# OS- specific definitions to ARCAN_LIBRARIES, set OS_DYLIB_EXTENSION
#
if (BSD_BUILD)
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.BSD)
elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Linux)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	message(FATAL_ERROR "Windows is no longer supported (rollback to 0.4)")
#
#	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Windows)
#
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Darwin)
   # OSX with CMAKE_OSX_SYSROOT set requires additional flags
   set (COMPILER
     "CC=${CMAKE_C_COMPILER} ${CMAKE_C_SYSROOT_FLAG} ${CMAKE_OSX_SYSROOT}"
     "CXX=${CMAKE_CXX_COMPILER} ${CMAKE_CXX_SYSROOT_FLAG} ${CMAKE_OSX_SYSROOT}"
     )
 else()
	message(FATAL_ERROR "${CL_RED}Unsupported OS(${CMAKE_SYSTEM_NAME}) detected, abandon ship!${CL_RST}")
endif()

if (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client")
	set(AGP_PLATFORM "stub")
else()
	amsg("\n${CL_WHT}---- Configuration results:${CL_RST}")
	amsg("${CL_YEL}compiler\t${CL_GRN}${CMAKE_C_COMPILER_ID}${CL_RST}")
	amsg("${CL_YEL}video   \t${CL_GRN}${VIDEO_PLATFORM}${CL_RST}")
	if (HYBRID_SDL)
		amsg("\t        \t${CL_GRN}+support sdl platform${CL_RST}")
	endif()
	if (HYBRID_HEADLESS)
		amsg("\t        \t${CL_GRN}+support headless platform${CL_RST}")
	endif()
	amsg("${CL_YEL}accel   \t${CL_GRN}${AGP_PLATFORM}${CL_RST}")
	amsg("${CL_YEL}audio   \t${CL_GRN}${AUDIO_PLATFORM}${CL_RST}")
	amsg("${CL_YEL}input   \t${CL_GRN}${INPUT_PLATFORM}${CL_RST}")
	amsg("${CL_YEL}headless\t${CL_GRN}${LWA_PLATFORM_STR}${CL_RST}")
	amsg("${CL_YEL}lua     \t${CL_GRN}${LUA_TAG}${LUA_TAG_MODE} ${LUA_LINKTYPE}${CL_RST}")

	amsg("\n${CL_WHT}-- Stage 2, Frameservers and external clients ${CL_RST}")
	set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
endif()

set(SHMIF_TUI true)
add_subdirectory(shmif)
add_subdirectory(a12)
if (NOT (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client"))
	add_subdirectory(wayland)
endif()

include_directories(${ARCAN_SHMIF_INCLUDE_DIR})

if (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client")
	# build the terminal emulator as well as that is typically useful
	set(DISABLE_FSRV_GAME TRUE)
	set(DISABLE_FSRV_DECODE TRUE)
	set(DISABLE_FSRV_NET TRUE)
	set(DISABLE_FSRV_ENCODE TRUE)
	set(DISABLE_FSRV_REMOTING TRUE)
	set(DISABLE_FSRV_AVFEED TRUE)
	add_subdirectory(frameserver)

	set(BIN_INSTALL)
else()
	add_subdirectory(frameserver)

	if (EXISTS ${EXTERNAL_SRC_DIR}/git/openal)
		if(ENABLE_LWA AND LWA_PLATFORM_STR)
			amsg("\n${CL_WHT}-- Stage 3, LWA Build${CL_RST}")
			include(platform/cmake/CMakeLists.LWA)
		else()
			amsg("\n${CL_WHT}-- Stage 3, LWA Build (omitted)${CL_RST}")
		endif()
	else()
		amsg("\n${CL_WHT}-- Stage 3, LWA Build (omitted, see external/README)${CL_RST}")
	endif()

	amsg("\n${CL_WHT}-- Stage 4, Linking / Packaging (=>${CMAKE_INSTALL_PREFIX})${CL_RST}")

	add_executable(arcan
		${SOURCES}
		${ARCAN_PLATFORM}
		${AGP_SOURCES}
	 	${PLATFORM_SOURCES}
		${VIDEO_PLATFORM_SOURCES}
		${PLATFORM_ROOT}/${INPUT_PLATFORM}/event.c
	)
	add_sanitizers(arcan)
	set(BIN_INSTALL)

	if (${FRAMESERVER_MODESTRING})
	string(STRIP ${FRAMESERVER_MODESTRING} FRAMESERVER_MODESTRING)
	endif()

	set(PLATFORM_BUILDTAG ${VIDEO_PLATFORM}-${AGP_PLATFORM}-${AUDIO_PLATFORM}-${INPUT_PLATFORM}-${LUA_TAG}-${DISTR_TAG})
	target_include_directories(arcan PRIVATE ${INCLUDE_DIRS})
	target_compile_definitions(arcan PRIVATE
		${ARCAN_DEFINITIONS}
		${ARCAN_NOLWA_DEFINITIONS}
		ARCAN_BUILDVERSION=\"${SOURCE_TAG}-${PLATFORM_BUILDTAG}-${CMAKE_SYSTEM_NAME}\"
		FRAMESERVER_MODESTRING=\"${FRAMESERVER_MODESTRING}\"
	)

	target_link_libraries(arcan
		${STDLIB}
		${ARCAN_LIBRARIES}
		${VIDEO_LIBRARIES}
		${AGP_LIBRARIES}
		${OPENAL_LIBRARY}
		arcan_shmif_int
	)

	# Primarily used by the Darwin platform, since it is scanned before we
	# have the targets defined, we expose and add the property here
	if (ARCAN_LNK_FLAGS)
	set_property(TARGET arcan APPEND PROPERTY LINK_FLAGS ${ARCAN_LNK_FLAGS})
	endif()

	if (MAIN_DEPS)
		add_dependencies(arcan ${MAIN_DEPS})
	endif()

	# Hybrid build is to allow the platform combination of egl-dri main with
	# fallback to SDL if X11 or Wayland is detected. We do this by resetting
	# and reusing the probe stage. It's not pretty, but beats a redesign.
	# Some cleanup possible by defining a function for taking [a,v,e,o] and
	# storing into a source/include/lib dir so that we can do that for both
	# arcan, the hybrids and lwa at the same time.
	if(VIDEO_PLATFORM STREQUAL "egl-dri")
	if(HYBRID_SDL)
		set_property(
			SOURCE engine/arcan_main.c
			APPEND PROPERTY COMPILE_DEFINITIONS
			ARCAN_HYBRID_SDL=1
		)

		amsg("-- Appending sdl platform build--")
		set(VIDEO_PLATFORM "sdl2")
		set(INPUT_PLATFORM "sdl2")
		set(ARCAN_DEFINITIONS "")
		set(ARCAN_NOLWA_DEFINITIONS "")
		set(VIDEO_PLATFORM_SOURCES "")
		set(INPUT_PLATFORM_SOURCES "")

	# HACK: Force- remove the psep-open from the platform and switch to the open
		list(FIND ARCAN_PLATFORM "${PLATFORM_ROOT}/posix/psep_open.c" _index)
		if (${_index} GREATER -1)
			list(REMOVE_AT ARCAN_PLATFORM ${_index})
			list(APPEND ARCAN_PLATFORM ${PLATFORM_ROOT}/posix/open.c)
		endif()

		include(${PLATFORM_ROOT}/cmake/CMakeLists.Video)

		add_executable(arcan_sdl
			${SOURCES}
			${ARCAN_PLATFORM}
			${AGP_SOURCES}
			${PLATFORM_SOURCES}
			${VIDEO_PLATFORM_SOURCES}
			${PLATFORM_ROOT}/sdl2/event.c
		)
		if (MAIN_DEPS)
			add_dependencies(arcan_sdl ${MAIN_DEPS})
		endif()
		target_include_directories(arcan_sdl PRIVATE ${INCLUDE_DIRS})

		set(PLATFORM_BUILDTAG sdl2-${AGP_PLATFORM}-sdl2-sdl2-${LUA_TAG}-${DISTR_TAG})
		target_compile_definitions(arcan_sdl PRIVATE
			${ARCAN_DEFINITIONS}
			${ARCAN_NOLWA_DEFINITIONS}
			ARCAN_BUILDVERSION=\"${SOURCE_TAG}-${PLATFORM_BUILDTAG}-${CMAKE_SYSTEM_NAME}\"
			FRAMESERVER_MODESTRING=\"${FRAMESERVER_MODESTRING}\"
		)
		target_link_libraries(arcan_sdl
			${STDLIB} ${ARCAN_LIBRARIES} ${VIDEO_LIBRARIES} ${OPENAL_LIBRARY}
			${AGP_LIBRARIES} arcan_shmif_int
		)
		list(APPEND BIN_INSTALL arcan_sdl)
	endif()

	# Hybrid headless is to allow an arcan setup where the normal egl drivers
	# etc. are being used, but the input platform is exposed as an connection
	# point in order to use it as a render server or client 'host' for remote
	# desktop like situations.
	if (HYBRID_HEADLESS)
		amsg("-- Appending headless platform build--")
		set(VIDEO_PLATFORM headless)
		set(ARCAN_DEFINITIONS "")
		include(${PLATFORM_ROOT}/cmake/CMakeLists.Video)

	# HACK: Force- remove the psep-open from the platform and switch to the open
		list(FIND ARCAN_PLATFORM "${PLATFORM_ROOT}/posix/psep_open.c" _index)
		if (${_index} GREATER -1)
			list(REMOVE_AT ARCAN_PLATFORM ${_index})
			list(APPEND ARCAN_PLATFORM ${PLATFORM_ROOT}/posix/open.c)
		endif()

		list(APPEND BIN_INSTALL arcan_headless)
		add_executable(arcan_headless
			${SOURCES}
			${ARCAN_PLATFORM}
			${AGP_SOURCES}
			${PLATFORM_SOURCES}
			${VIDEO_PLATFORM_SOURCES}
			${PLATFORM_ROOT}/headless/event.c
		)
		if (MAIN_DEPS)
			add_dependencies(arcan_headless ${MAIN_DEPS})
		endif()
		target_include_directories(arcan_headless PRIVATE ${INCLUDE_DIRS})

		set(PLATFORM_BUILDTAG headless-${AGP_PLATFORM}-${AUDIO_PLATFORM}-headless-${LUA_TAG}-${DISTR_TAG})
		target_compile_definitions(arcan_headless PRIVATE
			${ARCAN_DEFINITIONS} ${ARCAN_NOLWA_DEFINITIONS} ARCAN_HEADLESS
			FRAMESERVER_MODESTRING=\"${FRAMESERVER_MODESTRING}\"
			ARCAN_BUILDVERSION=\"${SOURCE_TAG}-${PLATFORM_BUILDTAG}-${CMAKE_SYSTEM_NAME}\"
		)
		target_link_libraries(arcan_headless
			${STDLIB} ${ARCAN_LIBRARIES} ${VIDEO_LIBRARIES} ${OPENAL_LIBRARY}
			${AGP_LIBRARIES} arcan_shmif_int
		)
		list(APPEND BIN_INSTALL arcan_headless)
	endif()
		set(VIDEO_PLATFORM egl-dri)
	endif() #egl-dri

	#
	# The database tool is a CLI for the engine/arcan_db with additional
	# code not part of the main arcan binaries (to make it somewhat harder
	# for a misbehaving script to add / introduce new configs / targets
	# and execute them.
	#
	add_executable(arcan_db ${ARCANDB_SOURCES})
	add_sanitizers(arcan_db)
	target_link_libraries(arcan_db ${STDLIB} ${SQLite3_LIBRARIES})
	target_include_directories(arcan_db PRIVATE ${INCLUDE_DIRS})
	target_compile_definitions(arcan_db PRIVATE ARCAN_DB_STANDALONE)
	list(APPEND BIN_INSTALL arcan_db)

	#
	# Special case, the egl-dri platform requires suid- for the chain-loader
	#
	#
	if (VIDEO_PLATFORM STREQUAL "egl-dri")
		amsg("${CL_YEL}egl-dri+privsep${CL_RST}\t${CL_GRN}installing SUID${CL_RST}")
		install(TARGETS arcan DESTINATION ${CMAKE_INSTALL_BINDIR}
			PERMISSIONS
				SETUID
				OWNER_WRITE OWNER_READ OWNER_EXECUTE
				GROUP_READ GROUP_EXECUTE
				WORLD_READ WORLD_EXECUTE
		)
	else()
	install(TARGETS arcan DESTINATION ${CMAKE_INSTALL_BINDIR})
	endif()

	install(TARGETS ${BIN_INSTALL} DESTINATION ${CMAKE_INSTALL_BINDIR})

	install(DIRECTORY ${CMAKE_SOURCE_DIR}/../data/appl
		DESTINATION ${APPL_DEST}
		DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR}
		FILE_PERMISSIONS ${SHARED_PERMISSIONS}
		PATTERN ".gitignore" EXCLUDE
	)

	install(DIRECTORY ${CMAKE_SOURCE_DIR}/../data/scripts
		DESTINATION ${SCRIPTS_DEST}
		DIRECTORY_PERMISSIONS ${SHARED_PERMISSIONS_DIR}
		FILE_PERMISSIONS ${SHARED_PERMISSIONS}
		PATTERN ".gitignore" EXCLUDE
	)

	install(DIRECTORY ${CMAKE_SOURCE_DIR}/../data/resources
		DESTINATION ${RES_DEST}
		DIRECTORY_PERMISSIONS ${SHARED_PERMISSIONS_DIR}
		FILE_PERMISSIONS ${SHARED_PERMISSIONS}
		PATTERN ".gitignore" EXCLUDE
	)

	if (MAN_DEST)
		install(FILES
			${CMAKE_CURRENT_SOURCE_DIR}/../doc/arcan.1
			${CMAKE_CURRENT_SOURCE_DIR}/../doc/arcan_db.1
			DESTINATION ${MAN_DEST}
			PERMISSIONS ${SHARED_PERMISSONS}
		)
	endif()
endif()

configure_file(${PLATFORM_ROOT}/cmake/shmif.pc.in
	${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif.pc @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif.pc
	DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)

if (NOT (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client"))
	configure_file(${PLATFORM_ROOT}/cmake/shmif_ext.pc.in
		${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-ext.pc @ONLY)
	install(FILES ${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-ext.pc
		DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)
endif()

configure_file(${PLATFORM_ROOT}/cmake/shmif_tui.pc.in
	${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-tui.pc @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-tui.pc
	DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)

configure_file(${PLATFORM_ROOT}/cmake/shmif_srv.pc.in
	${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-srv.pc @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-srv.pc
	DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)

if (NOT (CLIENT_LIBRARY_BUILD OR BUILD_PRESET STREQUAL "client"))
	#
	# Only installed if they have been generated manually, this is rather
	# suboptimal -- possibly replace with a compile- time option and a probe
	# for the correct ruby version
	#
	if (APIMAN_DEST AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/../doc/mantmp)
		amsg("${CL_YEL}API- manpages\t${CL_GRN}mantmp found")
		file(GLOB MANTMP ${CMAKE_CURRENT_SOURCE_DIR}/../doc/mantmp/*.3)
		install(FILES
			${MANTMP}
			DESTINATION ${APIMAN_DEST}
			PERMISSIONS ${SHARED_PERMISSIONS}
		)
	else()
		amsg("${CL_YEL}API- manpages\t${CL_RED}no mantmp, run ruby docgen.rb in arcan/doc${CL_RST}")
	endif()
	amsg("${CL_RST}")
endif()
