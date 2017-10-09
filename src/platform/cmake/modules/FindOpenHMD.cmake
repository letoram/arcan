# Try to find OPENHMD. Once done, this will define:
#
#   OPENHMD_FOUND - variable which returns the result of the search
#   OPENHMD_INCLUDE_DIRS - list of include directories
#   OPENHMD_LIBRARIES - options for the linker

find_package(PkgConfig)
pkg_check_modules(PC_OPENHMD openhmd)

find_path(OPENHMD_INCLUDE_DIR
	openhmd.h
	HINTS ${PC_OPENHMD_INCLUDE_DIRS}
)
find_library(OPENHMD_LIBRARY
	openhmd
	HINTS ${PC_OPENHMD_LIBDIR} ${PC_OPENHMD_LIBRARY_DIRS}
)

set(OPENHMD_INCLUDE_DIRS ${OPENHMD_INCLUDE_DIR})
set(OPENHMD_LIBRARIES ${OPENHMD_LIBRARY})

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(OPENHMD DEFAULT_MSG
	OPENHMD_INCLUDE_DIR
	OPENHMD_LIBRARY
)

mark_as_advanced(
	OPENHMD_INCLUDE_DIR
	OPENHMD_LIBRARY
)
