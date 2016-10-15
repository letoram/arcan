# tried playing nice by using REQUIRE_QUIET but some built-in modules
# (CheckLibraryExists, ...) wouldn't listen so how about a nice cup
# of shut up.
function(message)
	list(GET ARGV 0 TYPE)
	if (TYPE STREQUAL "FATAL_ERROR")
		list(REMOVE_AT ARGV 0)
		_message(${TYPE} ${ARGV})
	endif()
endfunction()

function(amsg msg)
	_message("" ${msg})
endfunction()

PROJECT(arcan)
cmake_minimum_required(VERSION 2.8.12 FATAL_ERROR)
if (POLICY CMP0042)
cmake_policy(SET CMP0042 OLD)
endif()

set(EXTERNAL_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../external)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/modules)

set(SHARED_PERMISSIONS
	OWNER_WRITE OWNER_READ GROUP_WRITE GROUP_READ WORLD_READ)
set(SHARED_PERMISSIONS_DIR OWNER_WRITE OWNER_READ GROUP_WRITE
	GROUP_READ WORLD_EXECUTE WORLD_READ)

# another hack to strip noisy / useless data away from message() abuse
include(ExternalProject)
include(CheckIncludeFiles)

if (CMAKE_COLOR_MAKEFILE)
	include(CMakeColor)
endif()

if (GLOBAL_CFLAGS)
	add_definitions(${GLOBAL_CFLAGS})
endif()

# static base version, manually mantained
set(MAJOR_VERSION 0)
set(MINOR_VERSION 5)
set(PATCH_LEVEL 2)
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
	if (GIT_FOUND)
		execute_process(COMMAND ${GIT_EXECUTABLE} describe --always
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			RESULT_VARIABLE EXIT_CODE
			OUTPUT_VARIABLE GIT_VERSION
		)
		if (NOT ${EXIT_CODE} EQUAL 0)
			message(FATAL_ERROR
				"${CLB_RED}Extracting build tag using git failed, -DENGINE_BUILDTAG=mytag manually${CL_RST}")
		endif()

		string(STRIP ${GIT_VERSION} GIT_VERSION)

		execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			RESULT_VARIABLE EXIT_CODE
			OUTPUT_VARIABLE GIT_BRANCH
		)
		if (NOT ${EXIT_CODE} EQUAL 0)
			message(FATAL_ERROR
				"${CLB_RED}Extracting build tag using git failed, -DENGINE_BUILDTAG=mytag manually${CL_RST}")
		endif()

		string(STRIP ${GIT_BRANCH} GIT_BRANCH)

		set(ENGINE_BUILDTAG arcan-git-${GIT_BRANCH}-${GIT_VERSION})
	else()
		message(FATAL_ERROR
			"${CLB_RED}ENGINE_BUILDTAG not found and no git checkout detected, -DENGINE_BUILDTAG=mytag manually${CL_RST}")
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

if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	set(VPLATFORM_STR "sdl")
	set(VIDEO_PLATFORM "sdl")
else()
set(VPLATFORM_STR "egl-dri, egl-nvidia, sdl, egl-gles, x11, x11-headless")
endif()
set(AGPPLATFORM_STR "gl21, gles2, gles3, stub")

# we can remove some of this cruft when 'buntu LTS gets ~3.0ish
option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)
option(DISABLE_JIT "Don't use the luajit-5.1 VM (if found)" OFF)
option(DISABLE_HIJACK "Disable building hijack libraries" ON)
option(NO_FSRV "Disable building/launching frameservers" OFF)
option(STATIC_SQLITE3 "Use SQLite3 Amalgamation" OFF)
option(STATIC_FREETYPE "Use static Freetype (external/git folder)" OFF)
option(STATIC_OPENAL "Use static OpenAL (external/git folder)" OFF)
option(ENABLE_LTO "Build with Link-Time Optimization enabled" OFF)
option(ENABLE_LWA "Build LWA client (arcan-in-arcan)" ON)
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
amsg("${CL_YEL}\t\t-DASAN_TYPE= - specifiy sanitizer (varies with compiler)")
amsg("${CL_YEL}\t-DENABLE_SIMD=${CL_GRN}[On|Off]${CL_RST} - Enable SIMD optimized instructions")
# amsg("    -DENABLE_PBO=[Appl-path] : Profile-based Optimization prepass with appl")
# amsg("                               as optimization profile.")
amsg("${CL_YEL}\t\t-DSIMD_ALIGNED=${CL_GRN}[Off|On]${CL_RST} - SIMD support assumes 16-byte alignment")
amsg("${CL_YEL}\t-DENABLE_LTO=${CL_GRN}[Off|On]${CL_RST} - Build with Link-Time Optimizations")
amsg("")
amsg("${CL_WHT}Dependency Management:${CL_RST}")
amsg("${CL_YEL}\t-DSTATIC_SQLITE3=${CL_GRN}[Off|On]${CL_RST} - In-source SQLite3")
amsg("${CL_YEL}\t-DSTATIC_OPENAL=${CL_GRN}[Off|On]${CL_RST} - In-source OpenAL, see external/README")
amsg("${CL_YEL}\t-DSTATIC_FREETYPE=${CL_GRN}[Off|On]${CL_RST} In-source Freetype")
amsg("")
amsg("${CL_WHT}Optional engine flags:${CL_RST}")
amsg("${CL_YEL}\t-DENABLE_LWA=${CL_GRN}[Off|On]${CL_RST} - Build LWA Arcan client (nesting support)")
amsg("${CL_YEL}\t-DDISABLE_JIT=${CL_GRN}[Off|On]${CL_RST} - Don't Link with luajit51 (even if found)")
amsg("${CL_YEL}\t-DNO_FSRV=${CL_GRN}[Off|On]${CL_RST} - Build Arcan without support for frameservers")
amsg("")

# no other audio platforms supported currently
set(AUDIO_PLATFORM "openal")

# can ignore this abomination on BSD
set(CSTD gnu11)

if ("${CMAKE_C_COMPILER_ID}" MATCHES "GNU")
	execute_process(
		COMMAND ${CMAKE_C_COMPILER} -dumpversion OUTPUT_VARIABLE GCC_VERSION)

	if (NOT (GCC_VERSION VERSION_GREATER 4.6 OR GCC_VERSION VERSION_EQUAL 4.6))
		message(FATAL_ERROR "${CLB_RED}Ancient GCC Version detected, Arcan should be compiled with Clang-3.3+ or gcc 4.7+${CL_RST}")
	endif()

	if (GCC_VERSION VERSION_LESS 4.7)
		amsg("${CLB_RED}Ancient GCC Version (4.6.x) detected, switch to a less terrible distribution or be prepared for side-effects${CL_RST}")
		include_directories(${PLATFORM_ROOT}/freebsd) # stdalign.h placeholder
		set(CSTD gnu1x)
		add_compile_options("-D_Alignas(X)=")
		set(SIMD_ALIGNED OFF)
	endif()

	add_compile_options(-Wall -Wno-missing-braces -Wno-unused-function
		-Wno-unused-value -Wno-unused-variable
	)

elseif ("${CMAKE_C_COMPILER_ID}" MATCHES "Clang")
	add_compile_options(-Wall -Wno-unknown-warning-option -Wno-unused-const-variable
		-Wno-unused-value -Wno-missing-braces -Wno-unused-function
		-Wno-unused-variable
	)
else()
	message(FATAL_ERROR "${CLB_RED}Arcan requires an ISO C 9899:2011 capable compiler (Clang-3.3+ or gcc 4.7+)${CL_RST}")
endif()

if (CMAKE_BUILD_TYPE STREQUAL "Profile")
	amsg("${CL_WHT}------------------*Profile Build*------------------${CL_RST}")
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
	amsg("${CL_WHT}-------------- *Debug Tracing Build* --------------${CL_WHT}")
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

if (NOT VIDEO_PLATFORM)
	message(FATAL_ERROR "${CLB_RED}Video Platform missing, see -DVIDEO_PLATFORM= above${CL_RST}")
endif()

add_compile_options(-std=${CSTD})

amsg("\n${CL_WHT}-- Stage 1: dependencies and configuration${CL_RST}")

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

if (EXISTS ${EXTERNAL_SRC_DIR}/git/freetype AND STATIC_FREETYPE)
	amsg("${CL_YEL}Building Freetype static from external/git mirror${CL_RST}")
	find_package(PNG QUIET)
	if (PNG_FOUND)
		if (STATIC_FREETYPE_NOPNG)
			set(PNG_EXT_STATE OFF)
			amsg("${CL_YEL} |-> PNG support force-disabled.${CL_RST}")
		else()
			set(PNG_EXT_STATE ON)
			amsg("${CL_YEL} |-> PNG support (embedded bitmaps) added.${CL_RST}")
		endif()
	else()
		set(PNG_EXT_STATE OFF)
		amsg("${CL_YEL} |-> PNG support (embedded bitmaps) disabled, no libpng${CL_RST}")
	endif()
	ExternalProject_Add(Freetype
		SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/freetype"
		UPDATE_COMMAND ""
		GIT_REPOSITORY "${EXTERNAL_SRC_DIR}/git/freetype"
		${EXTERNAL_DEFS}
		${CMAKE_EXTERNAL_DEFS}
		-DWITH_ZLIB=OFF
		-DWITH_HarfBuzz=OFF
		-DWITH_BZip2=OFF
		-DWITH_PNG=${PNG_EXT_STATE}
	)
	if (CMAKE_BUILD_TYPE STREQUAL "Debug")
		set(FREETYPE_STATIC_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/lib/libfreetyped.a")
	else()
		set(FREETYPE_STATIC_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/lib/libfreetype.a")
	endif()

	set(FREETYPE_STATIC_INCLUDE_DIRS "${CMAKE_CURRENT_BINARY_DIR}/include/freetype2")
	set(FREETYPE_DEFAULT_LIBRARIES
		${FREETYPE_STATIC_LIBRARY}
		${PNG_LIBRARIES}
	)
	set(FREETYPE_DEFAULT_INCLUDE_DIRS "${CMAKE_CURRENT_BINARY_DIR}/include/freetype2")
	list(APPEND MAIN_DEPS Freetype)
else()
# need this maneuver to deal with the combination of
# static:arcan,arcan_lwa,arcan_shmif_tui] but also [dynamic:arcan_shmif_tui]
	find_package(Freetype REQUIRED QUIET)
	set(FREETYPE_DEFAULT_LIBRARIES ${FREETYPE_LIBRARIES})
	set(FREETYPE_DEFAULT_INCLUDE_DIRS ${FREETYPE_INCLUDE_DIRS})
endif()

# need the separation here to not confuse openAL here with
# the version that we patch into LWA
if (EXISTS ${EXTERNAL_SRC_DIR}/git/openal AND STATIC_OPENAL)
	amsg("${CL_YEL}Building OpenAL static from external/git mirror${CL_RST}")
	ExternalProject_Add(OpenAL
		SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/openal
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
		"${CMAKE_CURRENT_BINARY_DIR}/lib/libopenal.a"
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
if (STATIC_SQLITE3)
	amsg("${CL_YEL}Building SQLite3 from external/sqlite mirror${CL_RST}")
	add_library(sqlite3 STATIC ${EXTERNAL_SRC_DIR}/sqlite/sqlite3.c)
	set_target_properties(sqlite3 PROPERTIES COMPILE_FLAGS "-Os")
	set(SQLITE3_INCLUDE_DIR ${EXTERNAL_SRC_DIR}/sqlite)
	set(SQLITE3_LIBRARIES sqlite3 pthread)
else()
	find_package(SQLITE3 REQUIRED QUIET)
endif()

find_package(SSE QUIET)

include(${PLATFORM_ROOT}/cmake/CMakeLists.AGP)
include(${PLATFORM_ROOT}/cmake/CMakeLists.Video)
set(EXTMAKE_CMD make)

# for the statically- linked external dependencies, we need to hint where
# we need the gmake rather than make system
if (${CMAKE_SYSTEM_NAME} MATCHES "BSD" OR ${CMAKE_SYSTEM_NAME}} MATCHES "DragonFly")
set(BSD_BUILD TRUE)
set(EXTMAKE_CMD gmake)
endif()

if (NOT DISABLE_JIT)
	if (EXISTS ${EXTERNAL_SRC_DIR}/git/luajit)
		amsg("${CL_YEL}Building Luajit static from external/git mirror${CL_RST}")
		ExternalProject_Add(luajit
			SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/luajit
			GIT_REPOSITORY "${EXTERNAL_SRC_DIR}/git/luajit"
			CONFIGURE_COMMAND ""
			UPDATE_COMMAND ""
			INSTALL_COMMAND ""
			BUILD_IN_SOURCE 1
			BUILD_COMMAND "${EXTMAKE_CMD}"
			${EXTERNAL_DEFS}
		)
		set(LUA_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/luajit/src/libluajit.a")
		set(LUA_LIBRARIES ${LUA_LIBRARY})
		set(LUA51_JIT ON)
		set(LUA_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/luajit/src")
		list(APPEND MAIN_DEPS luajit)
	else()
		find_package(Lua51JIT QUIET)
	endif()

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
	${FREETYPE_DEFAULT_LIBRARIES}
	${LUA_LIBRARIES}
	${SQLITE3_LIBRARIES}
)

LIST (APPEND
	INCLUDE_DIRS
	${LUA_INCLUDE_DIR}
	${OPENAL_INCLUDE_DIR}
	${FREETYPE_DEFAULT_INCLUDE_DIRS}
	${SQLITE3_INCLUDE_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/platform
	${EXTERNAL_SRC_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/engine
)

add_subdirectory(${EXTERNAL_SRC_DIR}/openctm ${CMAKE_CURRENT_BINARY_DIR}/openctm)

list (APPEND SOURCES
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
	engine/arcan_led.c
	engine/arcan_led.h
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
)

# database tool is sqlite3 + libc so less need to work
# around with platform layers etc.
set (ARCANDB_SOURCES
	tools/arcan_dbtool.c
	engine/arcan_db.c
	platform/posix/warning.c
	platform/posix/dbpath.c
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

if (LUA51_JIT)
	set_property(SOURCE engine/arcan_lua.c APPEND PROPERTY
		COMPILE_DEFINITIONS LUA51_JIT)
	set(LUA_TAG "luajit51")
else()
	set(LUA_TAG "lua51")
endif()

# can we get sane literal concatenation one day?
set(PFT ${VIDEO_PLATFORM}-${AGP_PLATFORM}-${AUDIO_PLATFORM}-${INPUT_PLATFORM})
set(ENGINE_BUILDTAG ${ENGINE_BUILDTAG}-${PFT}-${LUA_TAG}-${DISTR_TAG})
unset(PFT)

#
# Expand with more platforms as needed, all are expected to define PLATFORM_[
# ,fsrv, shmif]_SOURCES, add a global definition for PLATFORM_HEADER add any
# OS- specific definitions to ARCAN_LIBRARIES, set OS_DYLIB_EXTENSION
#
if (BSD_BUILD)
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.BSD)
	set(ENGINE_BUILDTAG ${ENGINE_BUILDTAG}-fbsd)
	set(PKGCONFIG_DIR libdata/pkgconfig)

elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Linux)
	set(ENGINE_BUILDTAG ${ENGINE_BUILDTAG}-linux)
	set(PKGCONFIG_DIR lib/pkgconfig)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	message(FATAL_ERROR "Windows no longer supported (rollback to 0.4)")
#
#	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Windows)
#
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	include(${CMAKE_CURRENT_SOURCE_DIR}/platform/cmake/CMakeLists.Darwin)
	set(ENGINE_BUILDTAG ${ENGINE_BUILDTAG}-darwin)
	set(PKGCONFIG_DIR lib/pkgconfig)

else()
	message(FATAL_ERROR "${CLB_RED}Unsupported OS(${CMAKE_SYSTEM_NAME}) detected, abandon ship!${CL_RST}")
endif()

amsg("\n${CL_WHT}---- Configuration results:${CL_RST}")
amsg("${CL_YEL}Compiler\t${CLB_GRN}${CMAKE_C_COMPILER_ID}${CL_RST}")
amsg("${CL_YEL}Video   \t${CLB_GRN}${VIDEO_PLATFORM}${CL_RST}")
amsg("${CL_YEL}AGP     \t${CLB_GRN}${AGP_PLATFORM}${CL_RST}")
amsg("${CL_YEL}Audio   \t${CLB_GRN}${AUDIO_PLATFORM}${CL_RST}")
amsg("${CL_YEL}Input   \t${CLB_GRN}${INPUT_PLATFORM}${CL_RST}")
amsg("${CL_YEL}Headless\t${CLB_GRN}${LWA_PLATFORM_STR}${CL_RST}")
amsg("${CL_YEL}Lua     \t${CLB_GRN}${LUA_TAG}${LUA_TAG_MODE}${CL_RST}${CL_RST}")

amsg("\n${CL_WHT}-- Stage 2, Frameservers / Hijack${CLT_RST}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

add_subdirectory(shmif)
include_directories(${ARCAN_SHMIF_INCLUDE_DIR})

if (NO_FSRV)
	set(FSRV_DISABLE DISABLE_FRAMESERVERS)
	amsg("${CL_YEL}Frameservers:\t${CLB_GRN}Disabled${CL_RST}")
else()
	add_subdirectory(frameserver)
endif()

if (NOT DISABLE_HIJACK)
	add_subdirectory(hijack)
else()
	amsg("${CL_YEL}Hijack Libraries:\t${CLB_GRN}Disabled${CL_RST}")
endif()

set_property(SOURCE engine/arcan_lua.c engine/arcan_main.c
	APPEND PROPERTY COMPILE_DEFINITIONS
	ARCAN_BUILDVERSION=\"${ENGINE_BUILDTAG}\"
	OS_DYLIB_EXTENSION=\"${OS_DYLIB_EXTENSION}\"
	${FSRV_DISABLE}
)

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

amsg("\n${CL_WHT}-- Stage 4, Linking / Packaging${CL_RST}")

add_executable(arcan
	${SOURCES}
	${ARCAN_PLATFORM}
	${AGP_SOURCES}
 	${PLATFORM_SOURCES}
)

if (${FRAMESERVER_MODESTRING})
string(STRIP ${FRAMESERVER_MODESTRING} FRAMESERVER_MODESTRING)
endif()

target_include_directories(arcan PRIVATE ${INCLUDE_DIRS})
target_compile_definitions(arcan PRIVATE
	${ARCAN_DEFINITIONS}
	${ARCAN_NOLWA_DEFINITIONS}
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

if (ARCAN_LNK_FLAGS)
set_property(TARGET arcan APPEND PROPERTY LINK_FLAGS ${ARCAN_LNK_FLAGS})
endif()

if (MAIN_DEPS)
	add_dependencies(arcan ${MAIN_DEPS})
endif()

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

install(DIRECTORY ${CMAKE_SOURCE_DIR}/../data/appl
	DESTINATION ${APPL_DEST}
	DIRECTORY_PERMISSIONS ${SHARED_PERMISSONS_DIR}
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

if (PKGCONFIG_DIR)
	configure_file(${PLATFORM_ROOT}/cmake/shmif.pc.in
		${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif.pc @ONLY)
	install(FILES ${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif.pc
		DESTINATION ${CMAKE_INSTALL_PREFIX}/${PKGCONFIG_DIR})

	configure_file(${PLATFORM_ROOT}/cmake/shmif_ext.pc.in
		${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-ext.pc @ONLY)
	install(FILES ${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-ext.pc
		DESTINATION ${CMAKE_INSTALL_PREFIX}/${PKGCONFIG_DIR})

	configure_file(${PLATFORM_ROOT}/cmake/shmif_tui.pc.in
		${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-tui.pc @ONLY)
	install(FILES ${CMAKE_CURRENT_BINARY_DIR}/arcan-shmif-tui.pc
		DESTINATION ${CMAKE_INSTALL_PREFIX}/${PKGCONFIG_DIR})
endif()

#
# Only installed if they have been generated manually, this is rather
# suboptimal -- possibly replace with a compile- time option and a probe
# for the correct ruby version
#
if (APIMAN_DEST AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/../doc/mantmp)
	file(GLOB MANTMP ${CMAKE_CURRENT_SOURCE_DIR}/../doc/mantmp/*.3)
	install(FILES
		${MANTMP}
		DESTINATION ${APIMAN_DEST}
		PERMISSIONS ${SHARED_PERMISSIONS}
	)
else()
	amsg("${CLB_WHT} mantmp output not found, run:\n\t ${CL_YEL} cd ${CMAKE_CURRENT_SOURCE_DIR}/../doc ; ruby docgen.rb mangen\n ${CLB_WHT} and reconfigure for manpage generation. ${CL_RST}")
endif()
