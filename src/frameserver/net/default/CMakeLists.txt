set(UTIL_DIR ../util)
set(A12_DIR ${PLATFORM_ROOT}/../a12)
set(A12NET_DIR ${PLATFORM_ROOT}/../a12/net)
set(EXT_DIR ${A12_DIR}/external)

set (NET_DEFS
	BLAKE3_NO_AVX2
	BLAKE3_NO_AVX512
	BLAKE3_NO_SSE41
	WANT_KEYSTORE_HASHER
	PARENT_SCOPE
)

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
	${A12NET_DIR}/a12_helper_discover.c
	${A12NET_DIR}/dir_supp.c
	${A12NET_DIR}/dir_cl.c

	${EXT_DIR}/blake3/blake3.c
	${EXT_DIR}/blake3/blake3_dispatch.c
	${EXT_DIR}/blake3/blake3_portable.c

	PARENT_SCOPE
)
