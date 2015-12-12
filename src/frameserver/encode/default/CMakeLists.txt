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

	find_package(VNC)
	if (LIBVNC_FOUND)
		amsg("(${CL_GRN}encode${CL_RST}) building with ${CL_GRN}vnc${CL_RED} support ${CL_RST}\n")
		set(ENC_AUX_SOURCES
			${FSRV_ROOT}/util/vncserver.c
			${FSRV_ROOT}/util/vncserver.h
		)
		set(ENC_AUX_LIBS ${LIBVNC_SERVER_LIBRARY})
		set(ENCODE_DEFS
			HAVE_VNCSERVER
			PARENT_SCOPE
		)
	endif()

	set(ENCODE_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/encode.c
		${CMAKE_CURRENT_SOURCE_DIR}/encode_presets.h
		${CMAKE_CURRENT_SOURCE_DIR}/encode_presets.c
		${ENC_AUX_SOURCES}
		PARENT_SCOPE
	)

	set(ENCODE_INCLUDE_DIRS
		${FSRV_ROOT}/util
		${FFMPEG_INCLUDE_DIRS}
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

