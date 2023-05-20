# This is used by the main arcan build system to define the shmif platform
# and install targets, but also for some external projects that need to
# do an in-source build of shmif- and its platform (automated build/
# test systems etc) without a full installation.
#
# Defines:
# ARCAN_SHMIF_INCLUDE_DIR
# ARCAN_SHMIF_LIBRARY (set to arcan_shmif_int)
#
# Out-outs:
# SHMIF_DISABLE_DEBUGIF
# TUI_RASTER_NO_TTF
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
set(ASHMIF_MINOR 16)

if (ARCAN_SOURCE_DIR)
	set(ASD ${ARCAN_SOURCE_DIR})
else()
	set(ASD ${CMAKE_CURRENT_SOURCE_DIR}/../)
endif()

set (TUI_HEADERS
	${ASD}/shmif/arcan_tui.h
	${ASD}/shmif/arcan_tuidefs.h
	${ASD}/shmif/arcan_tuisym.h
	${ASD}/shmif/arcan_tui_bufferwnd.h
	${ASD}/shmif/arcan_tui_listwnd.h
	${ASD}/shmif/arcan_tui_linewnd.h
	${ASD}/shmif/arcan_tui_readline.h
)

set (SHMIF_HEADERS
	${ASD}/shmif/arcan_shmif_control.h
	${ASD}/shmif/arcan_shmif_interop.h
	${ASD}/shmif/arcan_shmif_event.h
	${ASD}/shmif/arcan_shmif_server.h
	${ASD}/shmif/arcan_shmif_sub.h
	${ASD}/shmif/arcan_shmif_defs.h
	${ASD}/shmif/arcan_shmif.h
)

set (SHMIF_SOURCES
	${SHMIF_HEADERS}
	${ASD}/shmif/arcan_shmif_control.c
	${ASD}/shmif/arcan_shmif_sub.c
	${ASD}/shmif/arcan_shmif_evpack.c
	${ASD}/engine/arcan_trace.c
	${ASD}/shmif/platform/exec.c
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

# support widgets
	${ASD}/shmif/tui/widgets/bufferwnd.c
	${ASD}/shmif/tui/widgets/listwnd.c
	${ASD}/shmif/tui/widgets/linewnd.c
	${ASD}/shmif/tui/widgets/readline.c
)

set(SHMIF_SERVER_SOURCES
	${ASD}/shmif/arcan_shmif_server.c
	${ASD}/platform/posix/frameserver.c
	${ASD}/shmif/arcan_shmif_control.c
	${ASD}/platform/posix/fsrv_guard.c
	${ASD}/platform/posix/mem.c
	${ASD}/shmif/arcan_shmif_evpack.c
	${ASD}/shmif/platform/exec.c
)

if (NOT TUI_RASTER_NO_TTF)
	list(APPEND
		SHMIF_TUI_SOURCES
		${ASD}/engine/arcan_ttf.c
	)
	set_property(SOURCE ${ASD}/engine/arcan_ttf.c
		APPEND PROPERTY COMPILE_DEFINITIONS SHMIF_TTF)
else()
	list(APPEND
		SHMIF_TUI_SOURCES
		${ASD}/shmif/tui/raster/ttfstub.c)
endif()

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

add_sanitizers(arcan_shmif_int arcan_shmif arcan_shmif_ext arcan_shmif_intext	arcan_shmif_server)

if (NOT SHMIF_DISABLE_DEBUGIF)
	target_compile_definitions(arcan_shmif PRIVATE SHMIF_DEBUG_IF)
	target_compile_definitions(arcan_shmif_int PRIVATE SHMIF_DEBUG_IF)
endif()

# The TUI libraries / build setup is slated to change soonish when the TUI
# refactor branch completes. This would push the freetype/harfbuzz etc. stage
# to be a part of arcan instead and the library can be made to be quite tiny.
set(TUI_INCLUDE_DIRS
	/opt/local/include
	${INCLUDE_DIRS}
	${ASD}/frameserver
	${ASD}/engine
	${ASD}/engine/external
	${ASD}/shmif
)

set(TUI_LIBRARIES arcan_shmif)

# The consequence for tui client side not having advanced font support is that
# the client might try and use 'drawing characters' that does not have a valid
# version in the font, or miss control over ligature substitutions and other
# similar font features. Shape-break attribute is intended to mitigate that
# somewhat.
add_library(arcan_tui SHARED ${SHMIF_TUI_SOURCES})
if (NOT TUI_RASTER_NO_TTF)
	list(APPEND TUI_LIBRARIES ${FREETYPE_LIBRARIES})
endif()
target_link_libraries(arcan_tui PRIVATE ${STDLIB} ${TUI_LIBRARIES})
set_target_properties(arcan_tui PROPERTIES VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR})

target_compile_definitions(arcan_tui PRIVATE ${TUI_DEFINITIONS})
target_include_directories(arcan_tui PRIVATE ${TUI_INCLUDE_DIRS})

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
	OUTPUT_NAME arcan_shmif_intext
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
)

set_target_properties(arcan_shmif_server PROPERTIES
	COMPILE_FLAGS "-fPIC"
	OUTPUT_NAME arcan_shmif_server
	VERSION ${ASHMIF_MAJOR}.${ASHMIF_MINOR}
)

set(ARCAN_SHMIF_INCLUDE_DIR ${ASD}/shmif PARENT_SCOPE)
set(ARCAN_SHMIF_LIBRARY arcan_shmif_int ${STDLIB} PARENT_SCOPE)

target_include_directories(arcan_shmif_int PRIVATE ${ASD}/shmif)
target_include_directories(arcan_shmif PRIVATE ${ASD}/shmif)
target_include_directories(arcan_shmif_server PRIVATE ${ASD}/shmif)

if (NOT ARCAN_SOURCE_DIR)
	install(TARGETS ${TARGET_LIST}
		LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
		ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
	)
	install(FILES ${SHMIF_HEADERS} DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/arcan/shmif)
	install(FILES ${TUI_HEADERS} DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/arcan)
endif()
