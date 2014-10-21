if (NOT BCM_ROOT)
	set(BCM_ROOT "/opt/vc")
endif()

find_path(OPENGL_INCLUDE_DIR GL/gl.h
	/usr/share/doc/NVIDIA_GLX-1.0/include
 	/usr/openwin/share/include
	/opt/graphics/OpenGL/include
 	${_OPENGL_INCLUDE_PATH}
 )

#
# Broadcom (raspberry pi etc.) specific detection => hardcoded paths
#
if (EXISTS "${BCM_ROOT}/include/bcm_host.h")

# should be replaced with a real probe for SSE/NEON/nothing
	set (ENABLE_SIMD FALSE)

	set (GLES2_INCLUDE_DIRS
		${BCM_ROOT}/include/interface/vcos/pthreads
		${BCM_ROOT}/include
		${BCM_ROOT}/include/interface/vmcs_host/linux
		${BCM_ROOT}/include/GLES2
	)

	set(GLES2_BCM_IMPLEMENTATION TRUE)

	set (GLES2_LIBRARIES
		${BCM_ROOT}/lib/libGLESv2.so
		${BCM_ROOT}/lib/libbcm_host.so
		${BCM_ROOT}/lib/libEGL.so
	)
else()
	find_library(GLES2_LIBRARIES NAMES GLESv2)
	find_path(OPENGL_INCLUDE_PATH GL/gl.h
		/usr/share/doc/NVIDIA_GLX-1.0/include
	)

	include(FindPackageHandleStandardArgs)
	FIND_PACKAGE_HANDLE_STANDARD_ARGS(OpenGL DEFAULT_MSG GLES2_LIBRARIES)
endif ()

