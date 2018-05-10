# Try to find fuse (devel)
# Once done, this will define
#
# FUSE3_FOUND - system has fuse
# FUSE3_INCLUDE_DIRS - the fuse include directories
# FUSE3_LIBRARIES - fuse libraries directories

if(FUSE3_INCLUDE_DIRS AND FUSE3_LIBRARIES)
set(FUSE3_FIND_QUIETLY TRUE)
endif(FUSE3_INCLUDE_DIRS AND FUSE3_LIBRARIES)

find_path( FUSE3_INCLUDE_DIR fuse3/fuse_lowlevel.h
  HINTS
  /usr/include
	/usr/local/include
  ${FUSE3_DIR}
  PATH_SUFFIXES fuse3 fuse )

find_library( FUSE3_LIBRARY fuse3
  HINTS
  /usr
  ${FUSE3_DIR}
  PATH_SUFFIXES lib )

set(FUSE3_INCLUDE_DIRS ${FUSE3_INCLUDE_DIR})
set(FUSE3_LIBRARIES ${FUSE3_LIBRARY})

# handle the QUIETLY and REQUIRED arguments and set FUSE3_FOUND to TRUE if
# all listed variables are TRUE
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(fuse3 DEFAULT_MSG FUSE3_INCLUDE_DIR FUSE3_LIBRARY)

mark_as_advanced(FUSE3_INCLUDE_DIR FUSE3_LIBRARY)
