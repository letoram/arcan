set(UTIL_DIR ../util)
set(A12_DIR ${PLATFORM_ROOT}/../a12)

set(NET_INCLUDE_DIRS ${UTIL_DIR} ${A12_DIR} PARENT_SCOPE)
set(NET_LIBS arcan_a12 PARENT_SCOPE)

set(NET_SOURCES
	${CMAKE_CURRENT_SOURCE_DIR}/net_placeholder.c
	${UTIL_DIR}/anet_keystore_naive.c
	${UTIL_DIR}/anet_helper.c
	PARENT_SCOPE
)
