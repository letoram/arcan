if (ENCODE_IMPLEMENTATION)
	add_subdirectory("${ENCODE_IMPLEMENTATION}")
else()
	add_subdirectory("default")
endif()

if (ENCODE_SOURCES)
	add_executable(afsrv_encode
		${FSRV_PLATFORM}
		${ENCODE_SOURCES}
	)
	add_sanitizers(afsrv_encode)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}encode " PARENT_SCOPE)
	target_compile_definitions(afsrv_encode PRIVATE
		ENABLE_FSRV_ENCODE
		DEFAULT_FSRV_MODE=\"encode\"
		${ENCODE_DEFS}
	)
	target_include_directories(afsrv_encode PRIVATE ${FSRV_ROOT} ${ENCODE_INCLUDE_DIRS})
	target_link_libraries(afsrv_encode ${STDLIB} arcan_shmif_int ${ENCODE_LIBS})
	install(TARGETS afsrv_encode DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
