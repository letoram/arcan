if (FSRV_TERMINAL_REQUIRED)
	find_package(TSM REQUIRED)
else()
	find_package(TSM)
endif()

if (LIBTSM_FOUND)
	message(STATUS "--(fsrv/terminal) building terminal support using libTSM")

	find_package(Freetype)
	if (FREETYPE_FOUND)
		set(TERM_AUX_LIBS ${FREETYPE_LIBRARY})
		set(TERM_AUX_SOURCES ${FSRV_ROOT}/../engine/arcan_ttf.c)
	endif()

	add_executable(afsrv_terminal
		${FSRV_PLATFORM}
		default/arcterm.c
		default/shl/shl-pty.c
		default/shl/shl-ring.c
		${TERM_AUX_SOURCES}
	)

	target_link_libraries(afsrv_terminal
		arcan_shmif
		util
		${LIBTSM_LIBRARIES}
		${STDLIB}
		${TERM_AUX_LIBS}
	)

	target_compile_definitions(afsrv_terminal PRIVATE
		ENABLE_FSRV_TERMINAL
		DEFAULT_FSRV_MODE=\"terminal\"
	)

	if (FREETYPE_FOUND)
		target_compile_definitions(afsrv_terminal PRIVATE TTF_SUPPORT)
	endif()

	target_include_directories(afsrv_terminal PRIVATE
		${FSRV_ROOT}
		${FSRV_ROOT}/util
		${LIBTSM_INCLUDE_DIRS}
	)

else()
	message("terminal frameserver disabled, libtsm not found")
endif()
