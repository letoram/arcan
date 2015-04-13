#Put here path to custom location
#example: /home/user/vlc/include etc..
find_path(LIBVNC_INCLUDE_DIR rfb/rfb.h
HINTS "$ENV{LIBVNC_INCLUDE_PATH}"
PATHS
    "$ENV{LIB_DIR}/include"
    "$ENV{LIB_DIR}/include/rfb"
    "/usr/include"
    "/usr/include/rfb"
    "/usr/local/include"
    "/usr/local/include/rfb"
    #mingw
    c:/msys/local/include
)
find_path(LIBVNC_INCLUDE_DIR PATHS "${CMAKE_INCLUDE_PATH}/rfb" NAMES rfb.h
				HINTS ${PC_LIBVNC_INCLUDEDIR} ${PC_LIBVNC_INCLUDE_DIRS})

#Put here path to custom location
#example: /home/user/vlc/lib etc..
find_library(LIBVNC_SERVER_LIBRARY NAMES vncserver libvncserver
	HINTS "$ENV{LIBVNC_LIBRARY_PATH}" ${PC_LIBVNCSERVER_LIBDIR} ${PC_LIBVNCSERVER_LIBRARY_DIRS}
PATHS
	"$ENV{LIB_DIR}/lib"
	#mingw
	c:/msys/local/lib
)
find_library(LIBVNC_CLIENT_LIBRARY NAMES vncclient libvncclient
HINTS "$ENV{LIBVNC_LIBRARY_PATH}" ${PC_LIBVNCCLIENT_LIBDIR} ${PC_LIBVNCCLIENT_LIBRARY_DIRS}
PATHS
	"$ENV{LIB_DIR}/lib"
	#mingw
	c:/msys/local/lib
)

if (LIBVNC_INCLUDE_DIR AND LIBVNC_SERVER_LIBRARY AND LIBVNC_CLIENT_LIBRARY)
set(LIBVNC_FOUND TRUE)
set(LIBVNC_LIBRARIES ${LIBVNC_SERVER_LIBRARY} ${LIBVNC_CLIENT_LIBRARY})
endif()

if (NOT LIBVNC_FOUND)
	if (LIBVNC_FIND_REQUIRED)
		message(FATAL_ERROR "Could not find LibVNC (client,server)")
	endif (LIBVNC_FIND_REQUIRED)
endif()
