# Expects:
#  FSRV_PLATFORM (defined by platforms/CMakeLists.*)
#  FSRV_INCLUDES (defined by CMakeLists.txt + platforms/CMakeLists.*)
#  arcan_shmif (target)

# Options:
#  [ SPLIT_FRAMESERVER ] (different outputs)
#  [ DISABLE_FRAMESERVERS ] ignored entirely
#  FSRV_[ATYPE = subgroup (if not set, default is used)
#  FSRV_[ATYPE = subgroup]_REQUIRED (set if the module should fail on deps)
#
# Defines:
#  FSRV_MODES (list of ENABLE_FSRV_ATYPE)
#  FRAMESERVER_MODESTRING (exposed to scripting API)
#

if (NOT FSRV_PLATFORM)
	set(FSRV_PLATFORM ${FSRV_PLATFORM}
		${CMAKE_CURRENT_SOURCE_DIR}/frameserver.h
		${CMAKE_CURRENT_SOURCE_DIR}/frameserver.c
	)
endif()

set(FSRV_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
set(FSRV_ROOT ${FSRV_ROOT} PARENT_SCOPE)
set(FRAMESERVER_MODESTRING "")
set(ARCHETYPES)

if (NOT DISABLE_FSRV_TERMINAL)
	list(APPEND ARCHETYPES terminal)
endif()

if (NOT DISABLE_FSRV_GAME)
	list(APPEND ARCHETYPES game)
endif()

if (NOT DISABLE_FSRV_NET)
	list(APPEND ARCHETYPES net)
endif()

if (NOT DISABLE_FSRV_DECODE)
	list(APPEND ARCHETYPES decode)
endif()

if (NOT DISABLE_FSRV_ENCODE)
	list(APPEND ARCHETYPES encode)
endif()

if (NOT DISABLE_FSRV_REMOTING)
	list(APPEND ARCHETYPES remoting)
endif()

if (NOT DISABLE_FSRV_AVFEED)
	list(APPEND ARCHETYPES avfeed)
endif()

foreach(archetype ${ARCHETYPES})
	add_subdirectory(${archetype})
endforeach()

#
# afsrv is a chainloader, it takes a mode as first argument that
# matches any of the specified archetypes to allow for a non-interactive,
# non-parsing loader that can be given additional capabilities / privileges
# that are then dropped when setting up the specific sandbox.
#
# it is also used to track descriptor / environment leaks from the parent
#
add_executable(arcan_frameserver frameserver.c)
add_sanitizers(arcan_frameserver)
target_compile_definitions(arcan_frameserver PRIVATE AFSRV_CHAINLOADER)
install(TARGETS arcan_frameserver DESTINATION ${CMAKE_INSTALL_BINDIR})
amsg("${CL_YEL}frameservers\t${CL_GRN}${FRAMESERVER_MODESTRING}${CL_RST}")
set(FRAMESERVER_MODESTRING ${FRAMESERVER_MODESTRING} PARENT_SCOPE)
