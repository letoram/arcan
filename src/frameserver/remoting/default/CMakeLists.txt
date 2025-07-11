pkg_check_modules(LIBVNC QUIET libvncclient)

set(PROTOCOLS "a12")
set(SRCS
	${CMAKE_CURRENT_SOURCE_DIR}/remoting.c
	${CMAKE_CURRENT_SOURCE_DIR}/a12.c
	${CMAKE_CURRENT_SOURCE_DIR}/../../util/anet_helper.c
	${CMAKE_CURRENT_SOURCE_DIR}/../../util/anet_keystore_naive.c
)

set(UTIL_DIR ../util)
set(A12_DIR ${PLATFORM_ROOT}/../a12)
set(A12NET_DIR ${PLATFORM_ROOT}/../a12/net)
set(EXT_DIR ${A12_DIR}/external)

set(NET_INCLUDE_DIRS
	${UTIL_DIR}
	${A12_DIR}
	${EXT_DIR}
	${EXT_DIR}/blake3
	${EXT_DIR}/mono
	${EXT_DIR}/mono/optional
	${PLATFORM_ROOT}/../engine
)

set(LIBS arcan_a12)
set(INCS ${NET_INCLUDE_DIRS})

if (LIBVNC_FOUND)
	set(PROTOCOLS "${PROTOCOLS} vnc")
	list(APPEND SRCS
		${CMAKE_CURRENT_SOURCE_DIR}/vnc.c
	)
	list(APPEND LIBS
		${LIBVNC_LINK_LIBRARIES}
	)
	list(APPEND INCS
		${LIBVNC_INCLUDE_DIRS})
	set(REMOTING_DEFS
		ENABLE_VNC
		PARENT_SCOPE
	)
endif()

set(REMOTING_SOURCES ${SRCS} PARENT_SCOPE)
set(REMOTING_LIBS ${LIBS} PARENT_SCOPE)
set(REMOTING_INCLUDE_DIRS ${INCS} PARENT_SCOPE)

amsg("${CL_YEL}remoting support:\t${CL_GRN}${PROTOCOLS}${CL_RST}")
