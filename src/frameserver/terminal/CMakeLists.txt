if (FSRV_TERMINAL_REQUIRED)
	find_package(TSM REQUIRED QUIET)
else()
	find_package(TSM QUIET)
endif()

if (LIBTSM_FOUND)
	find_package(Freetype QUIET)
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

	if (STATIC_FREETYPE)
		add_dependencies(afsrv_terminal Freetype)
	endif()

	target_link_libraries(afsrv_terminal
		arcan_shmif_int
		util
		${LIBTSM_LIBRARIES}
		${STDLIB}
		${TERM_AUX_LIBS}
	)

	target_compile_definitions(afsrv_terminal PRIVATE
		ENABLE_FSRV_TERMINAL
		DEFAULT_FSRV_MODE=\"terminal\"
	)

	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}terminal " PARENT_SCOPE)

	install(TARGETS afsrv_terminal DESTINATION bin)

	if (FREETYPE_FOUND)
		target_compile_definitions(afsrv_terminal PRIVATE TTF_SUPPORT)
		target_include_directories(afsrv_terminal PRIVATE ${FREETYPE_INCLUDE_DIRS})
	endif()

	target_include_directories(afsrv_terminal PRIVATE
		${FSRV_ROOT}/../engine
		${FSRV_ROOT}
		${FSRV_ROOT}/util
		${LIBTSM_INCLUDE_DIRS}
	)

else()
	amsg("(${CL_GRN}terminal${CL_RST}) disabled, ${CL_GRN}libtsm${CL_RED} not found${CL_RST}")
endif()
