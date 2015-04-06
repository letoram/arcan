# - Try to find VPX
# Once done this will define
#
#  VPX_FOUND - system has VPX
#  VPX_INCLUDE_DIRS - the VPX include directory
#  VPX_LIBRARIES - Link these to use VPX
#  VPX_DEFINITIONS - Compiler switches required for using VPX
#

if (VPX_LIBRARIES AND VPX_INCLUDE_DIRS)
  set(VPX_FOUND TRUE)
else (VPX_LIBRARIES AND VPX_INCLUDE_DIRS)
  #include(UsePkgConfig)
  #pkgconfig(VPX _VPXIncDir _VPXLinkDir _VPXLinkFlags _VPXCflags)
  set(VPX_DEFINITIONS "")

  find_path(VPX_INCLUDE_DIR
    NAMES
      vpx/vp8.h
    PATHS
      ${_VPXIncDir}
      /usr/include
      /usr/local/include
      /opt/local/include
      /sw/include
  )

  find_library(VPX_LIBRARY
    NAMES
      vpx
      vpx
    PATHS
      ${_VPXLinkDir}
      /usr/lib
      /usr/local/lib
      /opt/local/lib
      /sw/lib
  )

  if (VPX_LIBRARY)
    set(VPX_FOUND TRUE)
  endif (VPX_LIBRARY)

  set(VPX_INCLUDE_DIRS
    ${VPX_INCLUDE_DIR}
  )

  if (VPX_FOUND)
    set(VPX_LIBRARIES
      ${VPX_LIBRARIES}
      ${VPX_LIBRARY}
    )
  endif (VPX_FOUND)

  if (VPX_INCLUDE_DIRS AND VPX_LIBRARIES)
    set(VPX_FOUND TRUE)
  endif (VPX_INCLUDE_DIRS AND VPX_LIBRARIES)

  if (VPX_FOUND)
    if (NOT VPX_FIND_QUIETLY)
      message(STATUS "Found VPX: ${VPX_LIBRARIES}")
    endif (NOT VPX_FIND_QUIETLY)
  else (VPX_FOUND)
    if (VPX_FIND_REQUIRED)
      message(FATAL_ERROR "Could not find VPX")
    endif (VPX_FIND_REQUIRED)
  endif (VPX_FOUND)

  # show the VPX_INCLUDE_DIRS and VPX_LIBRARIES variables only in the advanced view
  mark_as_advanced(VPX_INCLUDE_DIRS VPX_LIBRARIES)

endif (VPX_LIBRARIES AND VPX_INCLUDE_DIRS)
