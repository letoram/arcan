#
# Port of LUA5.1 makefiles to CMakeLists for easier build integration
#
PROJECT ( lua51 )
cmake_minimum_required( VERSION 2.8 )

set (MAJOR_VERSION 5 )
set (MINOR_VERSION 1 )
set (PATCH_LEVEL 5 )
set (VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})

if (${CMAKE_SYSTEM_NAME} MATCHES "BSD" OR ${CMAKE_SYSTEM_NAME} MATCHES
	"DragonFly")
	add_definitions( -DLUA_USE_POSIX )
	set (LIBRARIES
		m
	)
elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	add_definitions( -DLUA_USE_LINUX )
	set (LIBRARIES
		m
		dl
	)
elseif (${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	set (LIBRARIES
		m
	)
endif ()

set (SOURCES
	lapi.c
	lcode.c
	ldebug.c
	ldo.c
	ldump.c
	lfunc.c
	lgc.c
	llex.c
	lmem.c
	lobject.c
	lopcodes.c
	lparser.c
	lstate.c
	lstring.c
	ltable.c
	ltm.c
	lundump.c
	lvm.c
	lzio.c
	lauxlib.c
	lbaselib.c
	ldblib.c
	liolib.c
	lmathlib.c
	loslib.c
	ltablib.c
	lstrlib.c
	loadlib.c
	linit.c
)

add_library(lua51 STATIC ${SOURCES})
target_link_libraries(lua51 ${LIBRARIES})
