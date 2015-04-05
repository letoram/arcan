if (FSRV_REMOTING_REQUIRED)
	find_package(VNC REQUIRED)
else()
	find_package(VNC)
endif()

if (LIBVNC_FOUND)
	message(STATUS "--(fsrv/remoting) building using libVNC")

	add_executable(afsrv_remoting
		${FSRV_PLATFORM}
		default/remoting.c
	)

	target_link_libraries(afsrv_remoting
		arcan_shmif
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

	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING} remoting")

else()
	message("remoting frameserver disabled, libvnc not found")
endif()
