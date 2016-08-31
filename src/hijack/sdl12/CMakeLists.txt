find_package(SDL QUIET)

if (SDL_FOUND)
set(HIJACK_LIBSTRING "${HIJACK_LIBSTRING}sdl12 " PARENT_SCOPE)

# the weird unix_stub + fwdtbl was legacy from when this worked on OSX
	set(SDL12_SOURCES unix_stub.c sdl12.c)
	set(SDL12_INCLUDE_DIRS PRIVATE ${SDL_INCLUDE_DIR})
	set(SDL12_COMPILE_DEFINITIONS PRIVATE)
	set(SDL12_LIBRARIES PRIVATE arcan_shmif_int)

	if ((NOT LWA_PLATFORM_STR STREQUAL "broken") AND LWA_PLATFORM_STR)
		list(APPEND SDL12_SOURCES
			${AGP_SOURCES}
			${HEADLESS_PLATFORM}
			${PLATFORM_ROOT}/posix/mem.c
		)

		list(APPEND SDL12_INCLUDE_DIRS
			${FSRV_ROOT}
			${FSRV_ROOT}/../engine
			${FSRV_ROOT}/../platform
		)
		list(APPEND SDL12_LIBRARIES
			${SDL12_LIBRARIES}
			${AGP_LIBRARIES}
			arcan_shmif_intext
		)

		list(APPEND SDL12_COMPILE_DEFINITIONS
			HEADLESS_NOARCAN
			ENABLE_OPENGL
			WANT_ARCAN_SHMIF_HELPER
		)
	else()
		amsg("(hijack/sdl12) no LWA platform, 3D disabled.")
	endif()

	add_library(ahijack_sdl12 SHARED ${SDL12_SOURCES})
	target_compile_definitions(ahijack_sdl12 ${SDL12_COMPILE_DEFINITIONS})
	target_include_directories(ahijack_sdl12 PRIVATE ${SDL12_INCLUDE_DIRS})
	target_link_libraries(ahijack_sdl12 PRIVATE ${SDL12_LIBRARIES})
	install(TARGETS ahijack_sdl12 DESTINATION lib)

#
# currently disabled as the cross-compilation necessary
# for shmif is a real pain to try and set up, though it is somewhat needed :(
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
