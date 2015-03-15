PROJECT( test )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

FIND_PACKAGE( Lua51  )
if (NOT LUA_LIBRARIES)
	message("--> Lua Library not found, building from arcan source/external/lua")

	if (NOT ARCAN_SOURCE_DIR)
	get_filename_component(ASD_SEARCH ${CMAKE_CURRENT_SOURCE_DIR} ABSOLUTE)
	set(ASD_LAST "/")

	while(NOT ${ASD_LAST} STREQUAL ${ASD_SEARCH} AND NOT ARCAN_SOURCE_DIR)
		set(ASD_LAST ${ASD_SEARCH})
		get_filename_component(ASD_SEARCH ${ASD_SEARCH} DIRECTORY)
		if (IS_DIRECTORY ${ASD_SEARCH}/src)
			set(ARCAN_SOURCE_DIR ${ASD_SEARCH}/src)
		endif()
	endwhile()

	if (NOT ARCAN_SOURCE_DIR)
		message(FATAL_ERROR "ARCAN_SOURCE_DIR is not set, use -DARCAN_SOURCE_DIR=")
	endif()
	endif()

	set (LUA_INCLUDE_DIR ${ARCAN_SOURCE_DIR}/external/lua)
endif (NOT LUA_LIBRARIES)

include_directories(${LUA_INCLUDE_DIR})

add_library (test SHARED test.c)
target_link_libraries(${PROJECT_NAME})
