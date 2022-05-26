if (AVFEED_IMPLEMENTATION)
	add_subdirectory("${AVFEED_IMPLEMENTATION}")
else()
	add_subdirectory("default")
endif()

if (AVFEED_SOURCES)
	add_executable(afsrv_avfeed
		${FSRV_PLATFORM}
		${AVFEED_SOURCES}
	)
	add_sanitizers(afsrv_avfeed)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}avfeed " PARENT_SCOPE)
	target_compile_definitions(afsrv_avfeed PRIVATE
		ENABLE_FSRV_AVFEED
		DEFAULT_FSRV_MODE=\"avfeed\"
		${AVFEED_DEFS}
	)
	target_include_directories(afsrv_avfeed PRIVATE ${FSRV_ROOT} ${AVFEED_INCLUDE_DIRS})
	target_link_libraries(afsrv_avfeed ${STDLIB} arcan_shmif_int ${AVFEED_LIBS})
	install(TARGETS afsrv_avfeed DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
