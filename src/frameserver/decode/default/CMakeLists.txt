set(DECODE_SOURCES
	${CMAKE_CURRENT_SOURCE_DIR}/decode.c
	${CMAKE_CURRENT_SOURCE_DIR}/decode_text.c
	${CMAKE_CURRENT_SOURCE_DIR}/decode_3d.c
	${CMAKE_CURRENT_SOURCE_DIR}/decode_img.c
	${FSRV_ROOT}/../platform/posix/map_resource.c
	${FSRV_ROOT}/../platform/posix/resource_io.c
)

set(DECODE_INCLUDE_DIRS
	${FSRV_ROOT}/../engine/external
	${FSRV_ROOT}/../platform
	${EXTERNAL_SRC_DIR}/fft
)

set(DECODE_LIBS
		arcan_tui
)

set(DECODE_DEFS)

pkg_check_modules(LIBVLC libvlc)
if (LIBVLC_FOUND)
	list(APPEND DECODE_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/decode_av.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fft.c
		${EXTERNAL_SRC_DIR}/fft/kiss_fftr.c
	)
	list(APPEND DECODE_INCLUDE_DIRS ${LIBVLC_INCLUDE_DIRS} )
	list(APPEND DECODE_LIBS ${LIBVLC_LINK_LIBRARIES})
	list(APPEND DECODE_DEFS HAVE_VLC)
else()
	amsg("(${CL_GRN}decode${CL_RST}) libVLC not found, ${CL_RED} video/audio support${CL_RST} disabled")
endif()

find_package(Espeak)
if (ESPEAK_FOUND)
	amsg("(${CL_GRN}decode${CL_RST}) addding support for ${CL_GRN} text-to-speech${CL_RST}")
	list(APPEND DECODE_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/decode_t2s.c)
	list(APPEND DECODE_DEFS HAVE_T2S)
	list(APPEND DECODE_LIBS ${ESPEAK_LIBRARIES})
	list(APPEND DECODE_INCLUDE_DIRS ${ESPEAK_INCLUDE_DIR} )
else()
	amsg("(${CL_GRN}decode${CL_RST}) Espeak- not found, ${CL_RED} text-to-speech${CL_RST} disabled")
endif()

find_package(MuPDF)
if (MUPDF_FOUND)
	amsg("(${CL_GRN}decode${CL_RST}) adding support for ${CL_GRN} PDF via MuPDF${CL_RST}")
	list(APPEND DECODE_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/decode_pdf.c)
	list(APPEND DECODE_DEFS HAVE_PDF)
	list(APPEND DECODE_LIBS ${MUPDF_LIBRARIES})
	list(APPEND DECODE_INCLUDE_DIRS ${MUPDF_INCLUDE_DIR})
else()
	amsg("(${CL_GRN}decode${CL_RST}) MuPDF not found, ${CL_RED} PDF support${CL_RST} disabled")
endif()

pkg_check_modules(MAGIC libmagic)
if (MAGIC_FOUND)
	amsg("(${CL_GRN}decode${CL_RST}) adding support for ${CL_GRN} probe (libmagic) ${CL_RST}")
	list(APPEND DECODE_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/decode_probe.c)
	list(APPEND DECODE_DEFS HAVE_PROBE)
	list(APPEND DECODE_LIBS ${MAGIC_LINK_LIBRARIES})
else()
	amsg("(${CL_GRN}decode${CL_RST}) libmagic not found, ${CL_RED} probe ${CL_RST} disabled")
endif()

pkg_check_modules(HUNSPELL hunspell)
if (HUNSPELL_FOUND)
	amsg("(${CL_GRN}decode${CL_RST}) adding support for ${CL_GRN} spell-checking via Hunspell ${CL_RST}")
		list(APPEND DECODE_SOURCES ${DECODE_SOURCES} ${CMAKE_CURRENT_SOURCE_DIR}/decode_spell.c)
		list(APPEND DECODE_LIBS ${DECODE_LIBS} ${HUNSPELL_LINK_LIBRARIES})
		list(APPEND DECODE_INCLUDE_DIRS ${DECODE_INCLUDE_DIRS} ${HUNSPELL_INCLUDE_DIRS})
		list(APPEND DECODE_DEFS HAVE_SPELL)
		set(ENC_FOUND "hunspell ${ENC_FOUND}")
else()
	set(ENC_MISSING "hunspell ${ENC_MISSING}, Hunspell not found, ${CL_RED} spell-checking ${CL_RED} disabled")
endif()

if (FSRV_DECODE_UVC)
	amsg("(${CL_GRN}decode${CL_RST}) adding support for ${CL_GRN}USB (uvc) Video${CL_RST}")
	set(DECODE_DEFS
		${DECODE_DEFS}
	)

	pkg_check_modules(FFMPEG REQUIRED libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

	if (STATIC_LIBUVC)
		pkg_check_modules(LIBUSB_1 REQUIRED libusb-1.0)
		ExternalProject_Add(libuvc
			SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/frameserver/decode/libuvc"
			BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/libuvc_static"
			UPDATE_COMMAND ""
			GIT_REPOSITORY "${EXTERNAL_SRC_DIR}/git/libuvc"
			${EXTERNAL_DEFS}
			${CMAKE_EXTERNAL_DEFS}
			-DBUILD_UVC_STATIC=ON
		)
		set(DECODE_DEPS libuvc)
		set(LIBUVC_INCLUDE_DIRS ${LIBUSB_1_INCLUDE_DIRS} ${CMAKE_CURRENT_BINARY_DIR}/libuvc_static/include)
		set(LIBUVC_LINK_LIBRARIES ${LIBUSB_1_LINK_LIBRARIES} ${CMAKE_CURRENT_BINARY_DIR}/libuvc_static/libuvc.a)
	else()
		pkg_check_modules(LIBUVC REQUIRED libuvc)
	endif()

	set(DECODE_INCLUDE_DIRS
		${DECODE_INCLUDE_DIRS}
		${FFMPEG_INCLUDE_DIRS}
		${LIBUVC_INCLUDE_DIRS}
		${CMAKE_CURRENT_BINARY_DIR}/../../../include)
	set(DECODE_LIBS
		${FFMPEG_LINK_LIBRARIES}
		${DECODE_LIBS}
		${LIBUVC_LINK_LIBRARIES}
	)
	set(DECODE_SOURCES
		${DECODE_SOURCES}
		${CMAKE_CURRENT_SOURCE_DIR}/uvc_support.c
	)
	set(DECODE_DEFS
		${DECODE_DEFS}
		HAVE_UVC
	)
else()
	amsg("(${CL_GRN}UVC${CL_RST}) not enabled, ${CL_GRN}camera support${CL_RED} disabled ${CL_RST}")
endif()

set(DECODE_DEPS ${DECODE_DEPS} PARENT_SCOPE)
set(DECODE_SOURCES ${DECODE_SOURCES} PARENT_SCOPE)
set(DECODE_LIBS ${DECODE_LIBS} PARENT_SCOPE)
set(DECODE_INCLUDE_DIRS ${DECODE_INCLUDE_DIRS} PARENT_SCOPE)
set(DECODE_DEFS ${DECODE_DEFS} PARENT_SCOPE)
