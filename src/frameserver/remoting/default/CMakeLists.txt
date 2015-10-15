if (FSRV_REMOTING_REQUIRED)
	find_package(VNC REQUIRED QUIET)
else()
	find_package(VNC QUIET)
endif()

if (LIBVNC_FOUND)
	set(REMOTING_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/remoting.c
		PARENT_SCOPE
	)

	set(REMOTING_LIBS
		${LIBVNC_CLIENT_LIBRARY}
		PARENT_SCOPE
	)
else()
	amsg("(${CL_GRN}remoting${CL_RST}) disabled, ${CL_GRN}vnc${CL_RED} not found${CL_RST}")
endif()
