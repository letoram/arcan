if (TERMINAL_IMPLEMENTATION)
	add_subdirectory("${TERMINAL_IMPLEMENTATION}")
else()
	add_subdirectory("default")
endif()

if (TERMINAL_SOURCES)
	add_executable(afsrv_terminal
		${FSRV_PLATFORM}
		${TERMINAL_SOURCES}
	)
	add_sanitizers(afsrv_terminal)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}terminal " PARENT_SCOPE)
	target_compile_definitions(afsrv_terminal PRIVATE
		ENABLE_FSRV_TERMINAL
		DEFAULT_FSRV_MODE=\"terminal\"
		${TERMINAL_DEFS}
	)

	target_include_directories(afsrv_terminal PRIVATE ${FSRV_ROOT} ${TERMINAL_INCLUDE_DIRS})
	target_link_libraries(afsrv_terminal ${STDLIB} arcan_shmif_int ${TERMINAL_LIBS})

	if (TERMINAL_DEPENDENCIES)
		add_dependencies(afsrv_terminal ${TERMINAL_DEPENDENCIES})
	endif()

	install(TARGETS afsrv_terminal DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
