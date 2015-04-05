if (FSRV_ENCODE_REQUIRED)
	find_package(FFMPEG REQUIRED)
	find_package(BZip2 REQUIRED)
	find_package(ZLIB REQUIRED)
	find_package(LibLZMA REQUIRED)
else()
	find_package(FFMPEG)
	find_package(BZip2)
	find_package(ZLIB)
	find_package(LibLZMA)
endif()

if (FFMPEG_FOUND AND BZIP2_FOUND AND ZLIB_FOUND AND LIBLZMA_FOUND)
	message(STATUS "--(fsrv/encode) building using FFMpeg")

	find_package(VNC)
	if (LIBVNC_FOUND)
		message(STATUS "--(fsrv/encode) adding VNC support using libvnc")
		set(ENC_AUX_SOURCES
			${FSRV_ROOTPATH}/util/vncserver.c
			${FSRV_ROOTPATH}/util/vncserver.h
		)
		set(ENC_AUX_LIBS ${LIBVNC_SERVER_LIBRARY})
	endif()

	add_executable(afsrv_encode
		${FSRV_PLATFORM}
		default/encode.c
		default/encode_presets.h
		default/encode_presets.c
		${ENC_AUX_SOURCES}
	)

	target_link_libraries(afsrv_encode
		arcan_shmif
		${FFMPEG_LIBRARIES}
		${BZIP2_LIBRARIES}
		${ZLIB_LIBRARIES}
		${LIBLZMA_LIBRARIES}
		${STDLIB}
		${ENC_AUX_LIBS}
	)

	target_include_directories(afsrv_encode PRIVATE
		${FSRV_ROOTPATH}
		${FSRV_ROOTPATH}/util
	)

	target_compile_definitions(afsrv_encode PRIVATE
		ENABLE_FSRV_ENCODE
		DEFAULT_FSRV_MODE=\"encode\"
	)

	if (LIBVNC_FOUND)
		target_compile_definitions(afsrv_encode PRIVATE HAVE_VNCSERVER)
	endif()

else()
	message("encode frameserver disabled, need ffmpeg, bz2, lzma and zlib\n")
endif()

