find_package(X11 QUIET)

if (X11_FOUND)
	set(X_SOURCES
		x.c
	)

	set(HIJACK_LIBSTRING "${HIJACK_LIBSTRING}x " PARENT_SCOPE)
	add_library(ahijack_x11 SHARED ${X_SOURCES})
	target_include_directories(ahijack_x11 PRIVATE ${X11_INCLUDE_DIR} ${FSRV_ROOT})
	target_link_libraries(ahijack_x11 arcan_shmif_int arcan_shmif_intext)
	install(TARGETS ahijack_x11 DESTINATION lib)

else()
	amsg("(${CL_GRN}hijack:x11${CL_RST}) disabled, ${CL_GRN}x11${CL_RED} not found${CL_RST}")
endif()
