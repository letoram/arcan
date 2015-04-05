if (FSRV_DECODE_REQUIRED)
	find_package(VLC REQUIRED)
else()
	find_package(VLC)
endif()

if (LIBVLC_FOUND)
	message(STATUS "--(fsrv/decode) building using libVLC\n")
	add_executable(afsrv_decode
		${FSRV_PLATFORM}
		default/decode_vlc.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fft.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fftr.c
	)

	target_link_libraries(afsrv_decode ${LIBVLC_LIBRARY} ${STDLIB} arcan_shmif)
	target_include_directories(afsrv_decode PRIVATE ${FSRV_ROOTPATH})
	target_compile_definitions(afsrv_decode PRIVATE
		ENABLE_FSRV_DECODE
		DEFAULT_FSRV_MODE=\"decode\"
	)
else()
	message("decode frameserver disabled, libvlc not found\n")
endif()
