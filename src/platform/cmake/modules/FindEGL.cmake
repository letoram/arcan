find_path(EGL_INCLUDE_DIR EGL/egl.h)

if (NOT BCM_ROOT)
	set(BCM_ROOT "/opt/vc")
endif()

#
# Broadcom (raspberry pi etc.) specific detection => hardcoded paths
#
if (VIDEO_PLATFORM STREQUAL "egl-gles" AND EXISTS "${BCM_ROOT}/include/bcm_host.h")
	set (EGL_INCLUDE_DIRS
		${BCM_ROOT}/include
	)

	set (EGL_LIBRARIES
		${BCM_ROOT}/lib/libEGL.so
	)
else()
	find_library(EGL_LIBRARIES NAMES EGL)
	include(FindPackageHandleStandardArgs)
#	FIND_PACKAGE_HANDLE_STANDARD_ARGS(OpenGL DEFAULT_MSG GLES2_LIBRARIES)
endif ()

