find_package(X11 QUIET)

if (X11_FOUND)
	set(HIJACK_LIBSTRING "${HIJACK_LIBSTRING}x11 " PARENT_SCOPE)

	set(X_SOURCES x.c)
	set(X_INCLUDE_DIRS PRIVATE ${X11_INCLUDE_DIR} ${FSRV_ROOT})
	set(X_COMPILE_DEFINITIONS PRIVATE WANT_X_FUNCTIONS)
	set(X_LIBRARIES PRIVATE arcan_shmif_int)

if ((NOT LWA_PLATFORM_STR STREQUAL "broken") AND LWA_PLATFORM_STR)
		list(APPEND X_SOURCES
			${AGP_SOURCES}
			${HEADLESS_PLATFORM}
			${PLATFORM_ROOT}/posix/mem.c
		)

		list(APPEND X_INCLUDE_DIRS
			${FSRV_ROOT}
			${FSRV_ROOT}/../engine
			${FSRV_ROOT}/../platform
		)
		list(APPEND X_LIBRARIES
			${SDL12_LIBRARIES}
			${AGP_LIBRARIES}
			arcan_shmif_intext
		)

		list(APPEND X_COMPILE_DEFINITIONS
			HEADLESS_NOARCAN
			WANT_GLX_FUNCTIONS
			WANT_ARCAN_SHMIF_HELPER
		)
	else()
		amsg("(hijack/x11) no LWA platform, 3D/GLX disabled.")
	endif()


	add_library(ahijack_x11 SHARED ${X_SOURCES})
	target_compile_definitions(ahijack_x11 ${X_COMPILE_DEFINITIONS})
	target_include_directories(ahijack_x11 PRIVATE ${X_INCLUDE_DIRS})
	target_link_libraries(ahijack_x11 PRIVATE ${X_LIBRARIES})
	install(TARGETS ahijack_x11 DESTINATION lib)

else()
	amsg("(${CL_GRN}hijack:x11${CL_RST}) disabled, ${CL_GRN}x11${CL_RED} not found${CL_RST}")
endif()
