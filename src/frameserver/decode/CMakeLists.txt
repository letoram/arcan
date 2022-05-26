if (DECODE_IMPLEMENTATION)
	add_subdirectory("${DECODE_IMPLEMENTATION}")
else()
	add_subdirectory("default")
endif()

if (DECODE_SOURCES)
	add_executable(afsrv_decode
		${FSRV_PLATFORM}
		${DECODE_SOURCES}
	)
	add_sanitizers(afsrv_decode)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}decode " PARENT_SCOPE)
	target_compile_definitions(afsrv_decode PRIVATE
		ENABLE_FSRV_DECODE
		DEFAULT_FSRV_MODE=\"decode\"
		${DECODE_DEFS}
	)
	target_include_directories(afsrv_decode PRIVATE ${FSRV_ROOT} ${DECODE_INCLUDE_DIRS})
	target_link_libraries(afsrv_decode ${STDLIB} arcan_shmif_int ${DECODE_LIBS})
	if (DECODE_DEPS)
		add_dependencies(afsrv_decode ${DECODE_DEPS})
	endif()

	install(TARGETS afsrv_decode DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
