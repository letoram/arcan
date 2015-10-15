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

	set(TERMINAL_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/arcterm.c
		${CMAKE_CURRENT_SOURCE_DIR}/shl/shl-pty.c
		${CMAKE_CURRENT_SOURCE_DIR}/shl/shl-ring.c
		${TERM_AUX_SOURCES}
		PARENT_SCOPE
	)

	if (STATIC_FREETYPE)
		set(TERMINAL_DEPENDENCIES
			Freetype
			PARENT_SCOPE)
	endif()

	set(TERMINAL_LIBS
		util
		${LIBTSM_LIBRARIES}
		${TERM_AUX_LIBS}
		PARENT_SCOPE
	)

	set(TINC
		${LIBTSM_INCLUDE_DIR}
		${FSRV_ROOT}/../engine
	)

	if (FREETYPE_FOUND)
		set(TERMINAL_DEFS
			TTF_SUPPORT
			PARENT_SCOPE
		)

		set(TINC_AUX
			${TERMINAL_INCLUDE_DIRS}
			${FREETYPE_INCLUDE_DIRS}
		)
	endif()

	set(TERMINAL_INCLUDE_DIRS ${TINC} ${TINC_AUX} PARENT_SCOPE)
else()
	amsg("(${CL_GRN}terminal${CL_RST}) disabled, ${CL_GRN}libtsm${CL_RED} not found${CL_RST}")
endif()
