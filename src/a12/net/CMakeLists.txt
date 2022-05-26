set(ARCAN_SRC "../..")
set(A12_SRC "..")
set(A12_EXT "../external")

set(SOURCES
	a12_helper_cl.c
	a12_helper_srv.c
	net.c
	${ARCAN_SRC}/frameserver/util/anet_helper.c
	${ARCAN_SRC}/frameserver/util/anet_keystore_naive.c
)

set(INCLUDE_DIRS
	"${ARCAN_SRC}/shmif"
	"${A12_EXT}"
	"${A12_EXT}/blake3"
	"${A12_SRC}"
	"${ARCAN_SRC}/engine"
	"${ARCAN_SRC}/frameserver/util"
)

add_executable(arcan-net ${SOURCES})
add_sanitizers(arcan-net)
target_link_libraries(arcan-net PRIVATE arcan_a12 )
target_include_directories(arcan-net PRIVATE ${INCLUDE_DIRS})
install(TARGETS arcan-net DESTINATION ${CMAKE_INSTALL_BINDIR})
