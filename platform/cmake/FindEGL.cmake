find_path(EGL_INCLUDE_DIR EGL/egl.h)

# 
# Broadcom (raspberry pi etc.) specific detection => hardcoded paths
#
if (EXISTS "/opt/vc/include/bcm_host.h")
	message(STATUS "FindEGL: bcm_host detected, enabling raspberry pi / broadcom support")
	set (${GLES2_INCLUDE_DIR} 
		/opt/vc/include
	)

	set (${EGL_LIBRARIES}
		/opt/vc/lib/libEGL.so
	)
else()
	find_library(EGL_LIBRARIES NAMES EGL)
	include(FindPackageHandleStandardArgs)
	FIND_PACKAGE_HANDLE_STANDARD_ARGS(OpenGL DEFAULT_MSG GLES2_LIBRARIES) 
endif ()

