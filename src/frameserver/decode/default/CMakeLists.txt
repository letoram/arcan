if (FSRV_DECODE_REQUIRED)
	find_package(VLC REQUIRED)
else()
	find_package(VLC)
endif()

if (LIBVLC_FOUND)
	set(DECODE_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/decode_vlc.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fft.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fftr.c
		PARENT_SCOPE
	)

	set(DECODE_INCLUDE_DIRS
		${LIBVLC_INCLUDE_DIR}
		${EXTERNAL_SRC_DIR}/fft
		PARENT_SCOPE
	)

	set(DECODE_LIBS
		${LIBVLC_LIBRARY}
		PARENT_SCOPE
	)
else()
	amsg("(${CL_GRN}decode${CL_RST}) disabled, ${CL_GRN}libvlc${CL_RED} not found${CL_RST}")
endif()
