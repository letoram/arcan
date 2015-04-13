if (FSRV_REMOTING_REQUIRED)
	find_package(VNC REQUIRED QUIET)
else()
	find_package(VNC QUIET)
endif()

if (LIBVNC_FOUND)
	add_executable(afsrv_remoting
		${FSRV_PLATFORM}
		default/remoting.c
	)

	target_link_libraries(afsrv_remoting
		arcan_shmif_int
		${LIBVNC_CLIENT_LIBRARY}
		${STDLIB}
	)

	target_include_directories(afsrv_remoting PRIVATE
		${FSRV_ROOT}
		${FSRV_ROOT}/util
		${LIBVNC_INCLUDE_DIR}
	)

	target_compile_definitions(afsrv_remoting PRIVATE
		ENABLE_FSRV_REMOTING
		DEFAULT_FSRV_MODE=\"remoting\"
	)

	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}remoting " PARENT_SCOPE)

	install(TARGETS afsrv_remoting DESTINATION bin)

else()
	message("(${CL_GRN}remoting${CL_RST}) disabled, ${CL_GRN}vnc${CL_RED} not found${CL_RST}")
endif()
