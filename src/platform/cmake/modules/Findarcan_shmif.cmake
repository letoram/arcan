include(FindPackageHandleStandardArgs)

find_path(ARCAN_SHMIF_INCLUDE_DIR arcan_shmif.h
	HINTS
		ENV_ARCAN_SHMIF_DIR
	PATHS
		/usr/include/arcan/shmif
		/usr/local/include/arcan/shmif
)

find_path(ARCAN_TUI_INCLUDE_DIR arcan_tui.h
	HINTS
		ENV_ARCAN_TUI_DIR
	PATHS
		/usr/include/arcan
		/usr/local/include/arcan
)

find_library(ARCAN_SHMIF_LIBRARY
	NAMES arcan_shmif
		PATH_SUFFIXES arcan
	PATHS
		/usr/local/lib
		/usr/lib
)

find_library(ARCAN_SHMIF_EXT_LIBRARY
	NAMES arcan_shmif_ext
		PATH_SUFFIXES arcan
	PATHS
		/usr/local/lib
		/usr/lib
)

find_library(ARCAN_TUI_LIBRARY
	NAMES arcan_tui
		PATH_SUFFIXES arcan
	PATHS
		/usr/local/lib
		/usr/lib
)

find_library(ARCAN_SHMIF_SERVER_LIBRARY
	NAMES arcan_shmif_server
		PATH_SUFFIXES arcan
	PATHS
		/usr/local/lib
		/usr/lib
)

add_library(arcan_shmif STATIC IMPORTED)
find_library(ARCAN_SHMIF_LIBRARY_PATH arcan_shmif HINTS "${CMAKE_CURRENT_LIST_DIR}/../../")
set_target_properties(arcan_shmif PROPERTIES IMPORTED_LOCATION "${ARCAN_SHMIF_LIBRARY_PATH}")
set(ARCAN_SHMIF_LIBRARIES ${ARCAN_SHMIF_LIBRARY} ${ARCAN_SHMIF_EXT_LIBRARY} ${ARCAN_TUI_LIBRARY})

FIND_PACKAGE_HANDLE_STANDARD_ARGS(arcan_shmif
	REQUIRED_VARS ARCAN_SHMIF_LIBRARY ARCAN_SHMIF_INCLUDE_DIR ARCAN_TUI_INCLUDE_DIR
)
