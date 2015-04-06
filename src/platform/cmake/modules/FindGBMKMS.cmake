#
# Used for non-X11 dependant EGL/GL,GLES video platform
#

find_path(DRM_INCLUDE_DIR drm.h
		PATHS
    /usr/local/include/libdrm
    /usr/local/include/drm
    /usr/include/libdrm
    /usr/include/drm
)

find_path(GBM_INCLUDE_DIR gbm.h 
		PATHS
		/usr/local/include
		/usr/include
)

set(GBMKMS_INCLUDE_DIRS ${GBM_INCLUDE_DIR} ${DRM_INCLUDE_DIR})

find_library(GBMKMS_DRM_LIBRARY NAMES drm)
find_library(GBMKMS_GBM_LIBRARY NAMES gbm)

set(GBMKMS_LIBRARIES 
	${GBMKMS_DRM_LIBRARY} 
	${GBMKMS_GBM_LIBRARY}
)

include(FindPackageHandleStandardArgs)
FIND_PACKAGE_HANDLE_STANDARD_ARGS(GBMKMS DEFAULT_MSG GBMKMS_LIBRARIES)
