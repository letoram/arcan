# tried playing nice by using REQUIRE_QUIET but some
# built-in modules (CheckLibraryExists, ...)
# wouldn't listen so how about a nice cup of shut up
function(message)
	list(GET ARGV 0 TYPE)
	if (type STREQUAL FATAL_ERROR)
		list(REMOVE_AT ARGV 0)
		_message(${TYPE} ${ARGV})
	endif()
endfunction()

function(amsg msg)
	_message("" ${msg})
endfunction()

PROJECT(arcan)
include(ExternalProject)
include(CheckIncludeFiles)
cmake_minimum_required(VERSION 2.8.12 FATAL_ERROR)

set(EXTERNAL_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../external)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/modules)

if (CMAKE_COLOR_MAKEFILE)
	include(CMakeColor)
endif()

if (GLOBAL_CFLAGS)
	add_definitions(${GLOBAL_CFLAGS})
endif()

add_compile_options(-std=gnu11 -Wall -Wno-missing-braces -Wno-unused-function)

# static base version, manually mantained
set(MAJOR_VERSION 0)
set(MINOR_VERSION 5)
set(ASHMIF_MAJOR 0)
set(ASHMIF_MINOR 5)
set(PATCH_LEVEL 0)
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})
set(PLATFORM_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/platform)

# blacklist some built-ins
if (NOT LUA_DROPSTR)
set(LUA_DROPSTR "io os package rawequal rawset rawget setfenv coroutine module require")
endif()

if (NOT GIT_MIRROR)
	set(GIT_MIRROR "https://www.github.com/mirror")
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
			message(FATAL_ERROR
				"${CLB_CYN}Extracting build tag using git failed, -DENGINE_BUILDTAG=mytag manually${CL_RST}")
		endif()

		string(STRIP ${GIT_VERSION} GIT_VERSION)

		execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			RESULT_VARIABLE EXIT_CODE
			OUTPUT_VARIABLE GIT_BRANCH
		)
		if (NOT ${EXIT_CODE} EQUAL 0)
			message(FATAL_ERROR
				"${CLB_CYN}Extracting build tag using git failed, -DENGINE_BUILDTAG=mytag manually${CL_RST}")
		endif()

		string(STRIP ${GIT_BRANCH} GIT_BRANCH)

		set(ENGINE_BUILDTAG arcan-git-${GIT_BRANCH}-${GIT_VERSION})
	else()
		message(FATAL_ERROR
			"${CLB_CYN}ENGINE_BUILDTAG not found and no git checkout detected, -DENGINE_BUILDTAG=mytag manually${CL_RST}")
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

# perhaps add an 'auto-detect' stage for Linux/BSD?
if (WIN32)
	set(VPLATFORM_STR "sdl")
	set(VIDEO_PLATFORM "sdl")
	set(DISABLE_HIJACK true)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	set(VPLATFORM_STR "sdl")
	set(VIDEO_PLATFORM "sdl")
else()
	set(VPLATFORM_STR "x11, x11-headless, sdl, egl-gles, egl-dri")
endif()
set(AGPPLATFORM_STR "gl21, gles2, gles3, stub")

# we can remove some of this cruft when 'buntu LTS gets ~3.0ish
option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)
option(DISABLE_JIT "Don't use the luajit-5.1 VM (if found)" OFF)
option(DOWNLOAD_MISSING "Download and build missing dependencies (if possible)" ON)
option(ENABLE_LED "Build with LED controller support in core" OFF)
option(ENABLE_LTO "Build with Link-Time Optimization enabled" OFF)
option(ENABLE_LWA "Build LWA client (arcan-in-arcan)" OFF)
option(ENABLE_SIMD "Build with SIMD vector instruction set support" ON)
option(ENABLE_SIMD_ALIGNED "Assert that SIMD data sources are 16-byte aligned" OFF)

amsg("")
amsg("${CL_WHT}Audio/Video/Input Support:")
amsg("${CL_YEL}(req.)\t-DVIDEO_PLATFORM=${CL_GRN}${VPLATFORM_STR}${CL_RST}")
amsg("${CL_YEL}\t-DAGP_PLATFORM=${CL_GRN}${AGPPLATFORM_STR}${CL_RST}")
amsg("")
amsg("${CL_WHT}Cmake Options:${CL_RST}")
amsg("${CL_YEL}\t-DCMAKE_BUILD_TYPE=${CL_GRN}[Debug|Release|Profile|DebugTrace]")
amsg("${CL_YEL}\t-DENABLE_ASAN=${CL_GRN}[Off|On]${CL_RST} - Build with Address Sanitizer enabled")
amsg("${CL_YEL}\t-DENABLE_SIMD=${CL_GRN}[On|Off]${CL_RST} - Enable SIMD optimized instructions")
# amsg("    -DENABLE_PBO=[Appl-path] : Profile-based Optimization prepass with appl")
# amsg("                               as optimization profile.")
amsg("${CL_YEL}\t\t-DSIMD_ALIGNED=${CL_GRN}[Off|On]${CL_RST} - SIMD support assumes 16-byte alignment")
amsg("${CL_YEL}\t-DENABLE_LTO=${CL_GRN}[Off|On]${CL_RST} - Build with Link-Time Optimizations")
amsg("")
amsg("Optional engine flags:")
amsg("${CL_YEL}\t-DENABLE_LED=${CL_GRN}[On|Off]${CL_RST} - Build with LED controller support in core")
amsg("${CL_YEL}\t-DENABLE_LWA=${CL_GRN}[Off|On]${CL_RST} - Build LWA Arcan client (nesting support)")
amsg("${CL_YEL}\t-DISABLE_JIT=${CL_GRN}[Off|On]${CL_RST} - Don't Link with luajit51 (even if found)")
amsg("${CL_YEL}\t-DDISABLE_FRAMESERVERS=${CL_GRN}[Off|On]${CL_RST} - Build Arcan without support for frameservers")
amsg("")

# no other audio platforms supported currently
set(AUDIO_PLATFORM "openal")

if ("${CMAKE_C_COMPILER_ID}" MATCHES "GNU")
	execute_process(
		COMMAND ${CMAKE_C_COMPILER} -dumpversion OUTPUT_VARIABLE GCC_VERSION)

	if (NOT (GCC_VERSION VERSION_GREATER 4.7 OR GCC_VERSION VERSION_EQUAL 4.7))
		message(FATAL_ERROR "${CLB_CYN}Ancient GCC Version detected, Arcan needs to be compiled with Clang-3.3+ or gcc 4.7+${CL_RST}")
	endif()

elseif ("${CMAKE_C_COMPILER_ID}" MATCHES "Clang")
else()
				message(FATAL_ERROR "${CLB_CYN}Arcan requires an ISO C 9899:2011 capable compiler (Clang-3.3+ or gcc 4.7+)${CL_RST}")
endif()

if (CMAKE_BUILD_TYPE STREQUAL "Profile")
	amsg("------------------*Profile Build*------------------")
	add_definitions(-pg)
	set(CMAKE_EXE_LINKER_FLAGS "-pg")
endif(CMAKE_BUILD_TYPE STREQUAL "Profile")

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	amsg("${CL_WHT}------------------*Debug Build*--------------------${CL_RST}")
	amsg("${CL_YEL}Debug Specific Setting:")
	amsg("\tLUA_TRACE_METHOD=${CL_RST}[${CL_GRN}off${CL_RST}|${CL_GRN}stderr${CL_RST}|${CL_GRN}coverage${CL_RST}]")
	if (LUA_TRACE_METHOD STREQUAL "stderr")
		set(LUA_TAG_MODE " trace-stderr")
		list(APPEND ARCAN_DEFINITIONS LUA_TRACE_STDERR)
	endif()

	if (LUA_TRACE_METHOD STREQUAL "coverage")
		set(LUA_TAG_MODE " trace-coverage")
		list(APPEND ARCAN_DEFINITIONS LUA_TRACE_COVERAGE)
	endif()

	add_definitions(-g -D_DEBUG -O0 -fno-omit-frame-pointer)

endif (CMAKE_BUILD_TYPE STREQUAL "Debug")

if (CMAKE_BUILD_TYPE STREQUAL "DebugTrace")
	amsg("-------------- *Debug Tracing Build* --------------")
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

find_package(Freetype REQUIRED QUIET)
find_package(OpenAL REQUIRED QUIET)
find_package(SQLITE3 REQUIRED QUIET)
find_package(SSE QUIET)

include(${PLATFORM_ROOT}/cmake/CMakeLists.AGP)
include(${PLATFORM_ROOT}/cmake/CMakeLists.Video)

amsg("${CL_WHT}-- Stage 1: dependencies and configuration${CL_RST}")
if (NOT DISABLE_JIT)
	find_package(Lua51JIT QUIET)
	if (LUA_LIBRARY)
		set(LUA_VSTR "lua5.1 (JIT)")
	endif()
endif()

if (NOT LUA_LIBRARY OR DISABLE_JIT)
	find_package(Lua51 QUIET)
endif()

if (NOT LUA_LIBRARIES)
	add_subdirectory(${EXTERNAL_SRC_DIR}/lua ${CMAKE_CURRENT_BINARY_DIR}/lua)
	set(LUA_INCLUDE_DIR ${EXTERNAL_SRC_DIR}/lua)
	set(LUA_LIBRARIES lua51)
	set(LUA_VSTR "lua5.1 (interp)")
endif()

LIST (APPEND
	ARCAN_LIBRARIES
	openctm
	${FREETYPE_LIBRARY}
	${LUA_LIBRARIES}
	${SQLITE3_LIBRARIES}
)

LIST (APPEND
	INCLUDE_DIRS
	${LUA_INCLUDE_DIR}
	${OPENAL_INCLUDE_DIR}
	${FREETYPE_INCLUDE_DIRS}
	${SQLITE3_INCLUDE_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/platform
	${EXTERNAL_SRC_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/shmif
	${CMAKE_CURRENT_SOURCE_DIR}/engine
)

add_subdirectory(${EXTERNAL_SRC_DIR}/openctm ${CMAKE_CURRENT_BINARY_DIR}/openctm)

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

set_property(SOURCE engine/arcan_renderfun.c
	APPEND PROPERTY COMPILE_FLAGS
	"-Wno-unused-value -Wno-unused-variable"
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

if (ENABLE_LED)
	list(APPEND ${SOURCES}
		arcan_led.c
		arcan_led.h
	)
	add_definitions(-DARCAN_LED)
endif()

if (LUA51_JIT)
	set_property(SOURCE engine/arcan_lua.c APPEND PROPERTY
		COMPILE_DEFINITIONS LUA51_JIT)
	set(LUA_TAG "luajit51")
else()
	set(LUA_TAG "lua51")
endif()

# can we get sane literal concatenation one day?
set(PFT ${VIDEO_PLATFORM}-${AGP_PLATFORM}-${AUDIO_PLATFORM}-${INPUT_PLATFORM})
set(ENGINE_BUILDTAG ${ENGINE_BUILDTAG}-${PFT}-${LUA_TAG})
unset(PFT)

set (SHMIF_HEADERS
	shmif/arcan_shmif_control.h
	shmif/arcan_shmif_interop.h
	shmif/arcan_shmif_event.h
	shmif/arcan_shmif.h
)

set (SHMIF_SOURCES
	${SHMIF_HEADERS}
	shmif/arcan_shmif_control.c
	shmif/arcan_shmif_interop.c
)

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/shmif)

#
# Expand with more platforms as needed, all are expected to define
# PLATFORM_[ ,fsrv, shmif]_SOURCES, add a global definition
# for PLATFORM_HEADER add any OS- specific definitions to
# ARCAN_LIBRARIES, set OS_DYLIB_EXTENSION
#
if (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.FreeBSD)

elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Linux)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Windows)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Darwin)

else()
	message(FATAL_ERROR "${CLB_WHT}Unsupported OS detected, abandon ship!${CL_RST}")
endif()

amsg("\n${CL_WHT}---- Configuration results:----${CL_RST}")
amsg("${CL_YEL}Compiler\t${CLB_GRN}${CMAKE_C_COMPILER_ID}${CL_RST}")
amsg("${CL_YEL}Video   \t${CLB_GRN}${VIDEO_PLATFORM}${CL_RST}")
amsg("${CL_YEL}AGP     \t${CLB_GRN}${AGP_PLATFORM}${CL_RST}")
amsg("${CL_YEL}Audio   \t${CLB_GRN}${AUDIO_PLATFORM}${CL_RST}")
amsg("${CL_YEL}Input   \t${CLB_GRN}${INPUT_PLATFORM}${CL_RST}")
amsg("${CL_YEL}Headless\t${CLB_GRN}${LWA_PLATFORM_STR}${CL_RST}")
amsg("${CL_YEL}Lua     \t${CLB_GRN}${LUA_TAG}${LUA_TAG_MODE}${CL_RST}${CL_RST}")

amsg("\n-- Stage 2, Frameservers / Hijack")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

if (NOT DISABLE_FRAMESERVERS)
	add_subdirectory(frameserver)
else()
	set(FSRV_DISABLE DISABLE_FRAMESERVERS)
	amsg("${CL_YEL}Frameservers:\t${CLB_GRN}Disabled${CL_RST}")
endif()

if (NOT DISABLE_HIJACK)
	add_subdirectory(hijack)
else()
	amsg("${CL_YEL}Hijack Libraries:\t${CLB_GRN}Disabled${CL_RST}")
endif()

set_property(SOURCE engine/arcan_lua.c engine/arcan_main.c
	APPEND PROPERTY COMPILE_DEFINITIONS
	FRAMESERVER_MODESTRING=\"${FRAMESERVER_MODESTRING}\"
	LUA_DROPSTR=\"${LUA_DROPSTR}\"
	ARCAN_BUILDVERSION=\"${ENGINE_BUILDTAG}\"
	OS_DYLIB_EXTENSION=\"{OS_DYLIB_EXTENSION}\"
	${FSRV_DISABLE}
)

if (ENABLE_LWA AND HEADLESS_PLATFORM)
	amsg("\n-- Stage 3, LWA Build")
	include(platform/cmake/CMakeLists.LWA)
else()
	amsg("\n-- Stage 3, LWA Build (omitted)")
endif()

amsg("\n-- Stage 4, Linking / Packaging")

add_library(arcan_shmif_int STATIC
	${SHMIF_SOURCES}
	${SHMIF_PLATFORM}
)
add_library(arcan_shmif SHARED
	${SHMIF_SOURCES}
	${SHMIF_PLATFORM}
)
target_link_libraries(arcan_shmif PRIVATE ${STDLIB})
target_link_libraries(arcan_shmif_int PRIVATE ${STDLIB})

# note that we enable fpic for the static here as some
# subdirectores need to pull it in as part of building a shared library
set_target_properties(arcan_shmif_int PROPERTIES
	COMPILE_FLAGS -fPIC
	ALIAS "arcan_shmif"
	VERSION "${ASHMIF_MAJOR}.${ASHMIF_MINOR}"
)
set_target_properties(arcan_shmif PROPERTIES
	VERSION "${ASHMIF_MAJOR}.${ASHMIF_MINOR}"
	SOVERSION ${ASHMIF_MAJOR}
)

install(TARGETS arcan_shmif arcan_shmif_int
	LIBRARY DESTINATION lib/arcan
	ARCHIVE DESTINATION lib/arcan
)
install(FILES ${SHMIF_HEADERS} DESTINATION include/arcan/shmif)

# The config file is more similar to a regular find module,
# the procedure for doing something this trivial ("install library,
# provide means for other projects to find library") seems excessively
# verbose and 'cmake:y'.
install(FILES ${PLATFORM_ROOT}/cmake/arcan_shmif-config.cmake
	DESTINATION CMake COMPONENT dev)

add_executable(arcan
	${SOURCES}
	${ARCAN_PLATFORM}
	${AGP_SOURCES}
 	${PLATFORM_SOURCES}
)

target_include_directories(arcan PRIVATE ${INCLUDE_DIRS})
target_compile_definitions(arcan PRIVATE ${ARCAN_DEFINITIONS})
target_link_libraries(arcan
	${STDLIB}
	${ARCAN_LIBRARIES}
	${VIDEO_LIBRARIES}
	${AGP_LIBRARIES}
	${OPENAL_LIBRARY}
)
#
# The database tool is a CLI for the engine/arcan_db with additional
# code not part of the main arcan binaries (to make it somewhat harder
# for a misbehaving script to add / introduce new configs / targets
# and execute them.
#
add_executable(arcan_db ${ARCANDB_SOURCES})
target_link_libraries(arcan_db ${STDLIB} ${SQLITE3_LIBRARIES})
target_include_directories(arcan_db PRIVATE ${INCLUDE_DIRS})
target_compile_definitions(arcan_db PRIVATE ARCAN_DB_STANDALONE)
install(TARGETS arcan arcan_db DESTINATION bin)
