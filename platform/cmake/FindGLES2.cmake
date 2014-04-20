
find_path(OPENGL_INCLUDE_DIR GL/gl.h
	/usr/share/doc/NVIDIA_GLX-1.0/include
 	/usr/openwin/share/include
	/opt/graphics/OpenGL/include
 	${_OPENGL_INCLUDE_PATH}
 )

# 
# Broadcom (raspberry pi etc.) specific detection => hardcoded paths
#
if (EXISTS "/opt/vc/include/bcm_host.h")
	message(STATUS "FindGLESv2: bcm_host detected, enabling raspberry pi / broadcom support")
	set (${GLES2_INCLUDE_DIR} 
		/opt/vc/include/interface/vcos/pthreads
		/opt/vc/include
		/opt/vc/include/interface/vmcs_host/linux
		/opt/vc/include/GLES2
	)

	set(GLES2_BCM_IMPLEMENTATION TRUE)

	set (${GLES2_LIBRARIES}
		/opt/vc/lib/libGLESv2.so
		/opt/vc/lib/libbcm_host.so
		/opt/vc/lib/libEGL.so
	)
else()
	find_library(GLES2_LIBRARIES NAMES GLESv2)
	find_path(OPENGL_INCLUDE_PATH GL/gl.h
		/usr/share/doc/NVIDIA_GLX-1.0/include
	)

	include(FindPackageHandleStandardArgs)
	FIND_PACKAGE_HANDLE_STANDARD_ARGS(OpenGL DEFAULT_MSG GLES2_LIBRARIES) 
endif ()

