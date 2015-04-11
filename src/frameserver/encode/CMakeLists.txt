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
	endif()

	add_executable(afsrv_encode
		${FSRV_PLATFORM}
		default/encode.c
		default/encode_presets.h
		default/encode_presets.c
		${ENC_AUX_SOURCES}
	)

	target_link_libraries(afsrv_encode
		arcan_shmif_int
		${FFMPEG_LIBRARIES}
		${BZIP2_LIBRARIES}
		${ZLIB_LIBRARIES}
		${LIBLZMA_LIBRARIES}
		${STDLIB}
		${ENC_AUX_LIBS}
	)

	target_include_directories(afsrv_encode PRIVATE
		${FSRV_ROOT}
		${FSRV_ROOT}/util
	)

	set_target_properties(afsrv_encode PROPERTIES
		COMPILE_FLAGS -Wno-deprecated-declarations
	)
	target_compile_definitions(afsrv_encode PRIVATE
		ENABLE_FSRV_ENCODE
		DEFAULT_FSRV_MODE=\"encode\"
	)
	if (LIBVNC_FOUND)
		target_compile_definitions(afsrv_encode PRIVATE HAVE_VNCSERVER)
	endif()

	install(TARGETS afsrv_encode DESTINATION bin)

else()
	amsg("(${CL_GRN}encode${CL_RST}) disabled, ${CL_GRN}${FSRV_ENC_MISSING}${CL_RED}not found${CL_RST}")
endif()

