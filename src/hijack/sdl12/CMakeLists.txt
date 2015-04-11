find_package(SDL QUIET)

if (SDL_FOUND)
	set(SDL12_SOURCES
		unix_stub.c
		sdl12.c
	)

	set(HIJACK_LIBSTRING "${HIJACK_LIBSTRING}sdl12 " PARENT_SCOPE)
	add_library(ahijack_sdl12 SHARED ${SDL12_SOURCES})
	target_include_directories(ahijack_sdl12 PRIVATE ${SDL_INCLUDE_DIR} ${FSRV_ROOT})
	target_link_libraries(ahijack_sdl12 arcan_shmif_int)
	install(TARGETS ahijack_sdl12 DESTINATION lib)

	#
	# currently disabled as the cross-compilation necessary
	# for shmif is a real pain to try and set up.
	#
	#	if (CMAKE_SIZEOF_VOID_P EQUAL 8)
	#		message(STATUS " |--> building 32-bit backward compatibility")
	#		add_library(ahijack32_sdl12 SHARED
	#			${SHMIF_SOURCES}
	#			${SHMIF_PLATFORM}
	#			${SDL12_SOURCES}
	#		)
	#	target_include_directories(ahijack32_sdl12 PRIVATE
	#		${SDL_INCLUDE_DIR}
	#		${FSRV_ROOT}
	#	)
	#	install(TARGETS ahijack32_sdl12 DESTINATION lib)
	#	set_property(TARGET ahijack32_sdl12 APPEND PROPERTY COMPILE_FLAGS -m32)
	#	endif()
else()
	amsg("(${CL_GRN}hijack:sdl12${CL_RST}) disabled, ${CL_GRN}sdl12${CL_RED} not found${CL_RST}")
endif()
