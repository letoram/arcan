set(UTIL_DIR ../util)
set(A12_DIR ${PLATFORM_ROOT}/../a12)
set(A12NET_DIR ${PLATFORM_ROOT}/../a12/net)
set(EXT_DIR ${A12_DIR}/external)

set(NET_INCLUDE_DIRS
	${UTIL_DIR}
	${A12_DIR}
	${EXT_DIR}
	${EXT_DIR}/blake3
	${PLATFORM_ROOT}/../engine
	PARENT_SCOPE
)
set(NET_LIBS arcan_a12 PARENT_SCOPE)

set(NET_SOURCES
	${CMAKE_CURRENT_SOURCE_DIR}/net.c
	${UTIL_DIR}/anet_keystore_naive.c
	${UTIL_DIR}/anet_helper.c

	${A12NET_DIR}/a12_helper_cl.c
	${A12NET_DIR}/a12_helper_srv.c
	${A12NET_DIR}/directory.c
	PARENT_SCOPE
)
