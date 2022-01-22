if (FSRV_ENCODE_REQUIRED)
	pkg_check_modules(FFMPEG REQUIRED QUIET libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)
	find_package(BZip2 REQUIRED QUIET)
	find_package(ZLIB REQUIRED QUIET)
	find_package(LibLZMA REQUIRED QUIET)
else()
	pkg_check_modules(FFMPEG QUIET libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)
	find_package(BZip2 QUIET)
	find_package(ZLIB QUIET)
	find_package(LibLZMA QUIET)
endif()

if (NOT FFMPEG_FOUND)
	set(FSRV_ENC_MISSING "${FSRV_ENC_MISSING}ffmpeg ")
endif()

if (NOT BZIP2_FOUND)
	set(FSRV_ENC_MISSING "${FSRV_ENC_MISSING}bzip2 ")
endif()

if (NOT ZLIB_FOUND)
	set(FSRV_ENC_MISSING "${FSRV_ENC_MISSING}zlib ")
endif()

if (NOT LIBLZMA_FOUND)
	set(FSRV_ENC_MISSING "${FSRV_ENC_MISSING}lzma ")
endif()

set(ENCODE_DEFS "")
if (FFMPEG_FOUND AND BZIP2_FOUND AND ZLIB_FOUND AND LIBLZMA_FOUND)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}encode " PARENT_SCOPE)
	set(ENC_MISSING "")
	set(ENC_FOUND "")

	pkg_check_modules(LIBVNC libvncserver)
	if (LIBVNC_FOUND)
		set(ENC_AUX_SOURCES
			${CMAKE_CURRENT_SOURCE_DIR}/vnc.c
		)
		set(ENC_AUX_LIBS ${LIBVNC_LINK_LIBRARIES})
		set(ENCODE_DEFS
			${ENCODE_DEFS}
			HAVE_VNCSERVER
			WANT_H264_ENC
			WANT_H264_DEC
		)
		set(ENC_FOUND "vnc ${ENC_FOUND}")
	else()
		set(ENC_MISSING "vnc ${ENC_MISSING}")
	endif()

	pkg_check_modules(Tesseract tesseract)
	if (Tesseract_FOUND)
		set(ENC_AUX_SOURCES ${ENC_AUX_SOURCES}
			${CMAKE_CURRENT_SOURCE_DIR}/ocr.c)
		set(ENC_AUX_LIBS ${Tesseract_LINK_LIBRARIES} ${ENC_AUX_LIBS})
		set(ENC_AUX_INCLUDES ${Tesseract_INCLUDE_DIRS})
		set(ENCODE_DEFS
			${ENCODE_DEFS}
			HAVE_OCR
		)
		set(ENC_FOUND "tesseract+leptonica(ocr) ${ENC_FOUND}")
	else()
		set(ENC_MISSING "tesseract+leptonica(ocr) ${ENC_MISSING}")
	endif()

	amsg("${CL_YEL}encode+opts\t${CL_GRN}${ENC_FOUND}${CL_RST}")
	amsg("${CL_YEL}encode-opts\t${CL_RED}${ENC_MISSING}${CL_RST}")

	set(ENCODE_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/encode.c
		${CMAKE_CURRENT_SOURCE_DIR}/encode_ffmpeg.c
		${CMAKE_CURRENT_SOURCE_DIR}/a12.c
		${CMAKE_CURRENT_SOURCE_DIR}/encode_presets.h
		${CMAKE_CURRENT_SOURCE_DIR}/encode_presets.c
		${CMAKE_CURRENT_SOURCE_DIR}/img.c
		${CMAKE_CURRENT_SOURCE_DIR}/../../util/anet_helper.c
		${CMAKE_CURRENT_SOURCE_DIR}/../../util/anet_keystore_naive.c
		${PLATFORM_ROOT}/../engine/arcan_img.c
		${PLATFORM_ROOT}/posix/mem.c
		${ENC_AUX_SOURCES}
	)

	set(ENCODE_INCLUDE_DIRS
		${FSRV_ROOT}/util
		${ENC_AUX_INCLUDES}
		${FFMPEG_INCLUDE_DIRS}
		${PLATFORM_ROOT}/../engine
		${PLATFORM_ROOT}/../a12
		PARENT_SCOPE
	)

	set(ENCODE_LIBS
		${FFMPEG_LINK_LIBRARIES}
		${BZIP2_LIBRARIES}
		${ZLIB_LIBRARIES}
		${LIBLZMA_LIBRARIES}
		${ENC_AUX_LIBS}
		arcan_a12
		PARENT_SCOPE
	)

	if (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
		list(APPEND ENCODE_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/v4l.c)
		list(APPEND ENCODE_DEFS HAVE_V4L2)
	endif()

	set(ENCODE_DEFS
		${ENCODE_DEFS}
		PARENT_SCOPE
	)

	set(ENCODE_SOURCES
		${ENCODE_SOURCES}
		PARENT_SCOPE
	)

else()
	amsg("(${CL_GRN}encode${CL_RST}) disabled, ${CL_GRN}${FSRV_ENC_MISSING}${CL_RED}not found${CL_RST}")
endif()

