add_executable(afsrv_avfeed
	${FSRV_PLATFORM}
	default/avfeed.c
)

set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}avfeed " PARENT_SCOPE)

target_compile_definitions(afsrv_avfeed PRIVATE
		ENABLE_FSRV_AVFEED
		DEFAULT_FSRV_MODE=\"avfeed\"
)
target_include_directories(afsrv_avfeed PRIVATE ${FSRV_ROOT})
target_link_libraries(afsrv_avfeed ${STDLIB} arcan_shmif_int)
install(TARGETS afsrv_avfeed DESTINATION bin)
