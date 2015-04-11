#Put here path to custom location
#example: /home/user/vlc/include etc..
find_path(LIBTSM_INCLUDE_DIR libtsm.h
HINTS "$ENV{LIBTSM_INCLUDE_PATH}"
PATHS
    "$ENV{LIB_DIR}/include"
    "/usr/include"
    "/usr/local/include"
    #mingw
    c:/msys/local/include
)

find_library(LIBTSM_LIBRARIES NAMES tsm
	HINTS "$ENV{LIBTSM_LIBRARY_PATH}"
PATHS
	"$ENV{LIB_DIR}/lib"
	"/usr/local/lib"
	#mingw
	c:/msys/local/lib
)

if (LIBTSM_INCLUDE_DIR AND LIBTSM_LIBRARIES)
set(LIBTSM_FOUND TRUE)
endif()

if (LIBTSM_FOUND)
	message(STATUS "--> libtsm found")
else (LIBTSM_FOUND)
	if (LIBTSM_FIND_REQUIRED)
		message(FATAL_ERROR "Could not find LibTSM")
	endif (LIBTSM_FIND_REQUIRED)
endif (LIBTSM_FOUND)

FIND_PACKAGE_HANDLE_STANDARD_ARGS(TSM
                                  REQUIRED_VARS FREETYPE_LIBRARY FREETYPE_INCLUDE_DIRS
                                  VERSION_VAR FREETYPE_VERSION_STRING)
