find_path(OPENGL_INCLUDE_DIR GLES3/gl3.h
	/usr/include
	/usr/share/doc/NVIDIA_GLX-1.0/include
 	/usr/openwin/share/include
	/opt/graphics/OpenGL/include
 	${_OPENGL_INCLUDE_PATH}
 )

find_library(GLES3_LIBRARIES NAMES GLESv2)
find_path(OPENGL_INCLUDE_PATH GL/gl.h
	/usr/share/doc/NVIDIA_GLX-1.0/include
)

include(FindPackageHandleStandardArgs)
FIND_PACKAGE_HANDLE_STANDARD_ARGS(OpenGL DEFAULT_MSG GLES2_LIBRARIES)
