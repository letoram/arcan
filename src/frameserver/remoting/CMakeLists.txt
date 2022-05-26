if (REMOTING_IMPLEMENTATION)
	add_subdirectory("${REMOTING_IMPLEMENTATION}")
else()
	add_subdirectory("default")
endif()

if (REMOTING_SOURCES)
	add_executable(afsrv_remoting
		${FSRV_PLATFORM}
		${REMOTING_SOURCES}
	)
	add_sanitizers(afsrv_remoting)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}remoting " PARENT_SCOPE)
	target_compile_definitions(afsrv_remoting PRIVATE
		ENABLE_FSRV_REMOTING
		DEFAULT_FSRV_MODE=\"remoting\"
		${REMOTING_DEFS}
	)
	target_include_directories(afsrv_remoting PRIVATE
		${FSRV_ROOT}
		${FSRV_ROOT}/util
		${REMOTING_INCLUDE_DIRS}
	)
	target_link_libraries(afsrv_remoting ${STDLIB} arcan_shmif_int ${REMOTING_LIBS})
	install(TARGETS afsrv_remoting DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
