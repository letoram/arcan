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
	)

	set(DECODE_INCLUDE_DIRS
		${LIBVLC_INCLUDE_DIR}
		${EXTERNAL_SRC_DIR}/fft
	)

	set(DECODE_LIBS
		${LIBVLC_LIBRARY}
	)

	if (FSRV_DECODE_UVC)
		amsg("(${CL_GRN}decode${CL_RST}) adding support for ${CL_GRN}USB (uvc) Video${CL_RST}")
		set(DECODE_DEFS
			${DECODE_DEFS}
		)

		find_package(libusb-1.0 REQUIRED)

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
		set(DECODE_INCLUDE_DIRS
			${DECODE_INCLUDE_DIRS}
			${LIBUSB_1_INCLUDE_DIRS}
			${CMAKE_CURRENT_BINARY_DIR}/libuvc_static/include
			${CMAKE_CURRENT_BINARY_DIR}/../../../include)
		set(DECODE_LIBS
			${DECODE_LIBS}
			${LIBUSB_1_LIBRARIES}
			${CMAKE_CURRENT_BINARY_DIR}/libuvc_static/libuvc.a
		)
		set(DECODE_SOURCES
			${DECODE_SOURCES}
			${CMAKE_CURRENT_SOURCE_DIR}/uvc_support.c
		)
		set(DECODE_DEFS
			${DECODE_DEFS}
			HAVE_UVC
		)
	endif()
else()
	amsg("(${CL_GRN}decode${CL_RST}) disabled, ${CL_GRN}libvlc${CL_RED} not found${CL_RST}")
endif()

set(DECODE_DEPS ${DECODE_DEPS} PARENT_SCOPE)
set(DECODE_SOURCES ${DECODE_SOURCES} PARENT_SCOPE)
set(DECODE_LIBS ${DECODE_LIBS} PARENT_SCOPE)
set(DECODE_INCLUDE_DIRS ${DECODE_INCLUDE_DIRS} PARENT_SCOPE)
set(DECODE_DEFS ${DECODE_DEFS} PARENT_SCOPE)
