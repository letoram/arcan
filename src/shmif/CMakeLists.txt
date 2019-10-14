# This is used by the main arcan build system to define the shmif platform
# and install targets, but also for some external projects that need to
# do an in-source build of shmif- and its platform (automated build/
# test systems etc) without a full installation.
#
# defines:
# ARCAN_SHMIF_INCLUDE_DIR
# ARCAN_SHMIF_LIBRARY (set to arcan_shmif_int)
#
# Targets:
# arcan_shmif
# arcan_shmif_int
# arcan_tui
# arcan_shmif_ext
# arcan_tuiext
# arcan_shmif_intext
# arcan_shmif_server
#
# Installs: (if ARCAN_SOURCE_DIR is not set)
#
set(ASHMIF_MAJOR 0)
set(ASHMIF_MINOR 12)

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

set(ASHMIF_INSTPATH lib)

# a nasty little detail here is that we actually expand the build-time
# platforms into a header that is included in the beginning of the defs.h file.
# The reason for this is that different video platforms dictate different
# optimal 'default' packing formats and we go to quite some lengths to avoid
# having the whole fourcc like state space explosion of having to support every
# packing format in the world, or having clients to support multiple formats
# outside of GPU acceleration.
add_custom_command(
	OUTPUT ${ASD}/shmif/arcan_shmif_cfg.h
	COMMAND echo "\\#define ${AGP_PLATFORM}" > arcan_shmif_cfg.h
	WORKING_DIRECTORY ${ASD}/shmif
)

set (TUI_HEADERS
	${ASD}/shmif/arcan_tui.h
	${ASD}/shmif/arcan_tuidefs.h
	${ASD}/shmif/arcan_tuisym.h
	${ASD}/shmif/arcan_tui_bufferwnd.h
	${ASD}/shmif/arcan_tui_listwnd.h
)

set (SHMIF_HEADERS
	${ASD}/shmif/arcan_shmif_control.h
	${ASD}/shmif/arcan_shmif_interop.h
	${ASD}/shmif/arcan_shmif_event.h
	${ASD}/shmif/arcan_shmif_server.h
	${ASD}/shmif/arcan_shmif_sub.h
	${ASD}/shmif/arcan_shmif_defs.h
	${ASD}/shmif/arcan_shmif.h
	${ASD}/shmif/arcan_shmif_cfg.h
)

set (SHMIF_SOURCES
	${SHMIF_HEADERS}
	${ASD}/shmif/arcan_shmif_control.c
	${ASD}/shmif/arcan_shmif_sub.c
	${ASD}/shmif/arcan_shmif_evpack.c
)

if (LWA_PLATFORM_STR AND IS_DIRECTORY "${ASD}/shmif/${LWA_PLATFORM_STR}" AND
	EXISTS "${ASD}/shmif/${LWA_PLATFORM_STR}/${LWA_PLATFORM_STR}.c")
	set (SHMIF_EXT_SOURCES
		"${ASD}/shmif/${LWA_PLATFORM_STR}/${LWA_PLATFORM_STR}.c"
		${AGP_SOURCES}
		${PLATFORM_ROOT}/posix/mem.c
	)
else()
	set (SHMIF_EXT_SOURCES "${ASD}/shmif/stub/stub.c")
endif()

set(SHMIF_PLATFORM
	${ASD}/platform/posix/shmemop.c
	${ASD}/platform/posix/warning.c
	${ASD}/platform/posix/fdpassing.c
	${ASD}/platform/posix/random.c
	${ASD}/platform/posix/fdscan.c
)

if (BSD_BUILD)
	list(APPEND SHMIF_PLATFORM
		${ASD}/platform/posix/time.c
		${ASD}/platform/posix/sem.c
	)

elseif(${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	list(APPEND SHMIF_PLATFORM
		${ASD}/platform/posix/time.c
		${ASD}/platform/posix/sem.c
	)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	list(APPEND SHMIF_PLATFORM
		${ASD}/platform/darwin/time.c
		${ASD}/platform/darwin/sem.c
	)
else()
	message(FATAL_ERROR "attempted to build arcan-shmif on an unsupported OS/platform")
endif()

set_property(SOURCE ${ASD}/platform/posix/fdpassing.c
	APPEND PROPERTY COMPILE_FLAGS -w)
set_property(SOURCE ${ASD}/platform/posix/fdpassing.c
	APPEND PROPERTY COMPILE_DEFINITIONS NONBLOCK_RECV)

set(SHMIF_TUI_SOURCES
# core implementation
	${ASD}/shmif/tui/tui.c
	${ASD}/shmif/tui/core/clipboard.c
	${ASD}/shmif/tui/core/input.c
	${ASD}/shmif/tui/core/setup.c
	${ASD}/shmif/tui/core/screen.c
	${ASD}/shmif/tui/core/dispatch.c

# text rasterization and metadata (client side rendering)
	${ASD}/shmif/tui/raster/pixelfont.c
	${ASD}/shmif/tui/raster/raster.c
	${ASD}/shmif/tui/raster/fontmgmt.c

# helper code
	${ASD}/shmif/tui/screen/tsm_screen.c
	${ASD}/shmif/tui/screen/tsm_unicode.c
	${ASD}/shmif/tui/screen/shl_htable.c
	${ASD}/shmif/tui/screen/wcwidth.c
	${ASD}/engine/arcan_ttf.c

# support widgers
	${ASD}/shmif/tui/widgets/copywnd.c
	${ASD}/shmif/tui/widgets/bufferwnd.c
	${ASD}/shmif/tui/widgets/listwnd.c
)

set(SHMIF_SERVER_SOURCES
	${ASD}/shmif/arcan_shmif_server.c
	${ASD}/platform/posix/frameserver.c
	${ASD}/shmif/arcan_shmif_control.c
	${ASD}/platform/posix/fsrv_guard.c
	${ASD}/platform/posix/mem.c
	${ASD}/shmif/arcan_shmif_evpack.c
)

set_property(SOURCE ${ASD}/engine/arcan_ttf.c
	APPEND PROPERTY COMPILE_DEFINITIONS SHMIF_TTF)

set_property(SOURCE ${ASD}/shmif/tui/raster/raster.c
	APPEND PROPERTY COMPILE_DEFINITIONS NO_ARCAN_AGP)

set(TARGET_LIST
	arcan_shmif
	arcan_shmif_int
	arcan_shmif_ext
	arcan_shmif_intext
	arcan_tui
	arcan_shmif_server
)

if (NOT SHMIF_DISABLE_DEBUGIF)
	list(APPEND SHMIF_SOURCES ${ASD}/shmif/arcan_shmif_debugif.c)
endif()

add_library(arcan_shmif_int STATIC ${SHMIF_SOURCES} ${SHMIF_PLATFORM})
add_library(arcan_shmif SHARED ${SHMIF_SOURCES} ${SHMIF_PLATFORM})
add_library(arcan_shmif_ext SHARED ${SHMIF_EXT_SOURCES})
add_library(arcan_shmif_intext SHARED ${SHMIF_EXT_SOURCES})
add_library(arcan_shmif_server SHARED ${SHMIF_SERVER_SOURCES} ${SHMIF_PLATFORM})

add_sanitizers(arcan_shmif_int arcan_shmif arcan_shmif_ext arcan_shmif_intext
	arcan_shmif_server)

if (NOT SHMIF_DISABLE_DEBUGIF)
	target_compile_definitions(arcan_shmif PRIVATE SHMIF_DEBUG_IF)
	target_compile_definitions(arcan_shmif_int PRIVATE SHMIF_DEBUG_IF)
endif()

# The TUI libraries / build setup is slated to change soonish when the TUI
# refactor branch completes. This would push the freetype/harfbuzz etc. stage
# to be a part of arcan instead and the library can be made to be quite tiny.
set(TUI_INCLUDE_DIRS /opt/local/include)
if (SHMIF_TUI_ACCEL)
	set(TUI_LIBRARIES arcan_shmif arcan_shmif_ext)
else()
	set(TUI_LIBRARIES arcan_shmif)
	set (TUI_DEFINITIONS SHMIF_TUI_DISABLE_GPU)
endif()

# STATIC_FREETYPE is inherited from the outer scope, means we have our own build
# of freetype that we should link to statically
if (STATIC_FREETYPE)
	add_library(arcan_tui STATIC ${SHMIF_TUI_SOURCES})
	target_link_libraries(arcan_tui PRIVATE ${STDLIB} ${FREETYPE_DEFAULT_LIBRARIES} ${TUI_LIBRARIES})
	find_package(Freetype QUIET)
	if (FREETYPE_FOUND)
		add_library(arcan_tuiext SHARED ${SHMIF_TUI_SOURCES})
		target_link_libraries(arcan_tuiext PRIVATE
			${STDLIB} ${FREETYPE_LIBRARIES} ${TUI_LIBRARIES})
		set_target_properties(arcan_tuiext PROPERTIES
			COMPILE_FLAGS -fPIC
			OUTPUT_NAME arcan_tui
			VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
		)
		target_compile_definitions(arcan_tuiext PRIVATE ${TUI_DEFINITIONS})
		set(TARGET_LIST ${TARGET_LIST} arcan_tuiext)
		target_include_directories(arcan_tuiext PRIVATE
			${INCLUDE_DIRS} ${TUI_INCLUDE_DIRS} ${ASD}/frameserver ${ASD}/engine ${ASD}/shmif)
# Due to the accelerated- GPU flags, we also NEED to build a shared library
# version as this likely pulls in libraries that we can't deal with statically
	else()
		amsg("${CL_YEL}only static freetype found, dynamic/accel shmif_tui disabled ${CL_RST}")
	endif()
# This means we already have a find-package for Freetype (parent requires it)
# and we can inherit/use those flags. For the time being, we need to treat
# Harfbuzz- style shaping separately though.
else()
	add_library(arcan_tui SHARED ${SHMIF_TUI_SOURCES})
	target_link_libraries(arcan_tui PRIVATE ${STDLIB} ${TUI_LIBRARIES} ${FREETYPE_LIBRARIES})
	set_target_properties(arcan_tui PROPERTIES VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR})
endif()

target_compile_definitions(arcan_tui PRIVATE ${TUI_DEFINITIONS})
target_include_directories(arcan_tui PRIVATE
	${INCLUDE_DIRS} ${TUI_INCLUDE_DIRS} ${ASD}/frameserver ${ASD}/shmif ${ASD}/engine)

target_link_libraries(arcan_shmif PRIVATE ${STDLIB})
target_link_libraries(arcan_shmif_int PRIVATE ${STDLIB})
target_link_libraries(arcan_shmif_ext PRIVATE ${STDLIB} ${VIDEO_LIBRARIES}
	${AGP_LIBRARIES} ${HEADLESS_LIBRARIES} arcan_shmif)
target_link_libraries(arcan_shmif_intext PRIVATE ${STDLIB} ${AGP_LIBRARIES}
	${VIDEO_LIBRARIES} ${HEADLESS_LIBRARIES} arcan_shmif)
target_link_libraries(arcan_shmif_server PRIVATE ${STDLIB} arcan_shmif_ext)

target_include_directories(arcan_shmif_ext PRIVATE ${INCLUDE_DIRS})
target_include_directories(arcan_shmif_intext PRIVATE ${INCLUDE_DIRS})
target_include_directories(arcan_shmif_server PRIVATE ${INCLUDE_DIRS})

# note that we enable fpic for the static here as some
# subdirectores need to pull it in as part of building a shared library
set_target_properties(arcan_shmif_int PROPERTIES
	COMPILE_FLAGS -fPIC
	OUTPUT_NAME arcan_shmif
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
)

if (CMAKE_C_FLAGS)
	string (REGEX REPLACE "-fsanitize=[^ ]+" "" CMAKE_C_FLAGS ${CMAKE_C_FLAGS})
endif()

set_target_properties(arcan_shmif PROPERTIES
	COMPILE_FLAGS -fPIC
	OUTPUT_NAME arcan_shmif
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
	SOVERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
)

set_target_properties(arcan_shmif_ext PROPERTIES
	COMPILE_FLAGS "-fPIC -DHEADLESS_NOARCAN"
	OUTPUT_NAME arcan_shmif_ext
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
)

set_target_properties(arcan_shmif_intext PROPERTIES
	COMPILE_FLAGS "-fPIC -DHEADLESS_NOARCAN"
	OUTPUT_NAME arcan_shmif_ext
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
)

set_target_properties(arcan_shmif_server PROPERTIES
	COMPILE_FLAGS "-fPIC"
	OUTPUT_NAME arcan_shmif_server
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
)

set(ARCAN_SHMIF_INCLUDE_DIR ${ASD}/shmif PARENT_SCOPE)
set(ARCAN_SHMIF_LIBRARY arcan_shmif_int ${ASHMIF_STDLIB} PARENT_SCOPE)

target_include_directories(arcan_shmif_int PRIVATE ${ASD}/shmif)
target_include_directories(arcan_shmif PRIVATE ${ASD}/shmif)
target_include_directories(arcan_shmif_server PRIVATE ${ASD}/shmif)

if (NOT ARCAN_SOURCE_DIR)
	install(TARGETS ${TARGET_LIST}
		LIBRARY DESTINATION ${ASHMIF_INSTPATH}
		ARCHIVE DESTINATION ${ASHMIF_INSTPATH}
	)
	install(FILES ${SHMIF_HEADERS} DESTINATION include/arcan/shmif)
	install(FILES ${TUI_HEADERS} DESTINATION include/arcan)
endif()
