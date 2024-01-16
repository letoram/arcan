set(ARCAN_SRC "../..")
set(A12_SRC "..")
set(A12_EXT "../external")

set(SOURCES
	a12_helper_cl.c
	a12_helper_srv.c
	a12_helper_discover.c
	net.c
	nbio.c
	dir_lua.c
	dir_lua_appl.c
	dir_cl.c
	dir_srv.c
	dir_srv_worker.c
	dir_supp.c
	${ARCAN_SRC}/engine/arcan_db.c
	${ARCAN_SRC}/platform/posix/warning.c
	${ARCAN_SRC}/platform/posix/dbpath.c
	${ARCAN_SRC}/platform/posix/resource_io.c
	${ARCAN_SRC}/platform/posix/map_resource.c
	${ARCAN_SRC}/platform/stub/mem.c
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
	"${ARCAN_SRC}/platform"
	${LUA_INCLUDE_DIR}
	${LUA_INCLUDE_DIRS}
	${SQLite3_INCLUDE_DIR}
)

add_executable(arcan-net ${SOURCES})
add_sanitizers(arcan-net)
target_link_libraries(arcan-net PRIVATE arcan_a12
	${STDLIB}
	${LUA_LIBRARIES}
	${SQLite3_LIBRARIES}
)
target_include_directories(arcan-net PRIVATE ${INCLUDE_DIRS})
target_compile_definitions(arcan-net PRIVATE WANT_KEYSTORE_HASHER ARCAN_DB_STANDALONE ARCAN_BUILDVERSION=\"${SOURCE_TAG}-${CMAKE_SYSTEM_NAME}\")
install(TARGETS arcan-net DESTINATION ${CMAKE_INSTALL_BINDIR})
