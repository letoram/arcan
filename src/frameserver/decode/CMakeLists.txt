if (FSRV_DECODE_REQUIRED)
	find_package(VLC REQUIRED)
else()
	find_package(VLC)
endif()

if (LIBVLC_FOUND)
	add_executable(afsrv_decode
		${FSRV_PLATFORM}
		default/decode_vlc.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fft.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fftr.c
	)

	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}decode " PARENT_SCOPE)

	target_link_libraries(afsrv_decode ${LIBVLC_LIBRARY} ${STDLIB} arcan_shmif_int)
	target_include_directories(afsrv_decode PRIVATE
		${FSRV_ROOT}
		${EXTERNAL_SRC_DIR}
	)
	target_compile_definitions(afsrv_decode PRIVATE
		ENABLE_FSRV_DECODE
		DEFAULT_FSRV_MODE=\"decode\"
	)
	install(TARGETS afsrv_decode DESTINATION bin)
else()
	message("(${CL_GRN}decode${CL_RST}) disabled, ${CL_GRN}libvlc${CL_RED} not found${CL_RST}")
endif()
