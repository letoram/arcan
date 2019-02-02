if (FSRV_ENCODE_REQUIRED)
	find_package(FFMPEG REQUIRED QUIET)
	find_package(BZip2 REQUIRED QUIET)
	find_package(ZLIB REQUIRED QUIET)
	find_package(LibLZMA REQUIRED QUIET)
else()
	find_package(FFMPEG QUIET)
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

if (FFMPEG_FOUND AND BZIP2_FOUND AND ZLIB_FOUND AND LIBLZMA_FOUND)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}encode " PARENT_SCOPE)
	set(ENC_MISSING "")
	set(ENC_FOUND "")

	find_package(VNC)
	if (LIBVNC_FOUND)
		set(ENC_AUX_SOURCES
			${FSRV_ROOT}/util/vncserver.c
			${FSRV_ROOT}/util/vncserver.h
		)
		set(ENC_AUX_LIBS ${LIBVNC_SERVER_LIBRARY})
		set(ENCODE_DEFS
			HAVE_VNCSERVER
			PARENT_SCOPE
		)
		set(ENC_FOUND "vnc ${ENC_FOUND}")
	else()
		set(ENC_MISSING "vnc ${ENC_MISSING}")
	endif()

	find_package(Tesseract)
	if (Tesseract_FOUND)
		set(ENC_AUX_SOURCES ${ENC_AUX_SOURCES}
			${CMAKE_CURRENT_SOURCE_DIR}/ocr.c)
		set(ENC_AUX_LIBS ${Tesseract_LIBRARIES} ${ENC_AUX_LIBS})
		set(ENC_AUX_INCLUDES ${Tesseract_INCLUDE_DIRS})
		set(ENCODE_DEFS
			${ENCODE_DEFS}
			HAVE_OCR
			PARENT_SCOPE
		)
		set(ENC_FOUND "tesseract+leptonica(ocr) ${ENC_FOUND}")
	else()
		set(ENC_MISSING "tesseract+leptonica(ocr) ${ENC_MISSING}")
	endif()

	amsg("${CL_YEL}encode+opts\t${CL_GRN}${ENC_FOUND}${CL_RST}")
	amsg("${CL_YEL}encode-opts\t${CL_RED}${ENC_MISSING}${CL_RST}")
	set(ENCODE_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/encode.c
		${CMAKE_CURRENT_SOURCE_DIR}/encode_presets.h
		${CMAKE_CURRENT_SOURCE_DIR}/encode_presets.c
		${CMAKE_CURRENT_SOURCE_DIR}/img.c
		${PLATFORM_ROOT}/../engine/arcan_img.c
		${PLATFORM_ROOT}/posix/mem.c
		${ENC_AUX_SOURCES}
		PARENT_SCOPE
	)

	set(ENCODE_INCLUDE_DIRS
		${FSRV_ROOT}/util
		${ENC_AUX_INCLUDES}
		${FFMPEG_INCLUDE_DIRS}
		${PLATFORM_ROOT}/../engine
		PARENT_SCOPE
	)

	set(ENCODE_LIBS
		${FFMPEG_LIBRARIES}
		${BZIP2_LIBRARIES}
		${ZLIB_LIBRARIES}
		${LIBLZMA_LIBRARIES}
		${ENC_AUX_LIBS}
		PARENT_SCOPE
	)

else()
	amsg("(${CL_GRN}encode${CL_RST}) disabled, ${CL_GRN}${FSRV_ENC_MISSING}${CL_RED}not found${CL_RST}")
endif()

