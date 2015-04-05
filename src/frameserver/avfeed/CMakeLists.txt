add_executable(afsrv_avfeed
	${FSRV_PLATFORM}
	default/avfeed.c
)

target_compile_definitions(afsrv_avfeed PRIVATE
		ENABLE_FSRV_AVFEED
		DEFAULT_FSRV_MODE=\"avfeed\"
)
target_include_directories(afsrv_avfeed PRIVATE ${FSRV_ROOTPATH})
target_link_libraries(afsrv_avfeed ${STDLIB} arcan_shmif)
