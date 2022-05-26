if (GAME_IMPLEMENTATION)
	add_subdirectory("${GAME_IMPLEMENTATION}")
else()
	add_subdirectory("default")
endif()

if (GAME_SOURCES)
	add_executable(afsrv_game
		${FSRV_PLATFORM}
		${GAME_SOURCES}
	)
	add_sanitizers(afsrv_game)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}game " PARENT_SCOPE)
	target_compile_definitions(afsrv_game PRIVATE
		ENABLE_FSRV_GAME
		DEFAULT_FSRV_MODE=\"game\"
		${GAME_DEFINITIONS}
	)
	target_include_directories(afsrv_game PRIVATE
		${FSRV_ROOT}
		${FSRV_ROOT}/util
		${GAME_INCLUDE_DIRS}
		${INCLUDE_DIRS}
	)

	target_link_libraries(afsrv_game PRIVATE
		${STDLIB}
		arcan_shmif_int
		${GAME_LIBS}
	)
	install(TARGETS afsrv_game DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
