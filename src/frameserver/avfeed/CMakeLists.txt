message(${FSRV_ROOTPATH})

add_executable(afsrv_avfeed
	${FSRV_PLATFORM}
	default/avfeed.c
)

set_property(TARGET afsrv_avfeed APPEND PROPERTY
	COMPILE_DEFINITIONS ENABLE_FSRV_AVFEED DEFAULT_FSRV_MODE=\"avfeed\")

target_include_directories(afsrv_avfeed PRIVATE ${FSRV_ROOTPATH})
target_link_libraries(afsrv_avfeed ${STDLIB} arcan-shmif)
