set (SOURCE_LIST
	${CMAKE_CURRENT_SOURCE_DIR}/libretro.h
	${CMAKE_CURRENT_SOURCE_DIR}/libretro.c
	${CMAKE_CURRENT_SOURCE_DIR}/ntsc/snes_ntsc.h
	${CMAKE_CURRENT_SOURCE_DIR}/ntsc/snes_ntsc.c
	${FSRV_ROOT}/util/sync_plot.h
	${FSRV_ROOT}/util/sync_plot.c
	${FSRV_ROOT}/util/font_8x8.h
	${PLATFORM_ROOT}/posix/map_resource.c
	${PLATFORM_ROOT}/posix/resource_io.c
)

set (GAME_INCLUDE_DIRS
	${FSRV_ROOT}/../engine
	${FSRV_ROOT}/../platform
	PARENT_SCOPE
)

if ((NOT LWA_PLATFORM_STR STREQUAL "broken") AND LWA_PLATFORM_STR)
	amsg("${CL_YEL}game/retro\t${CL_GRN}3D support (lwa)${CL_RST}")
	list(APPEND SOURCE_LIST
		${AGP_SOURCES}
		${HEADLESS_PLATFORM}
		${PLATFORM_ROOT}/posix/mem.c
	)

	set(GAME_LIBS
		${VIDEO_LIBRARIES}
		${HEADLESS_LIBRARIES}
		arcan_shmif_intext
		${AGP_LIBRARIES}
		PARENT_SCOPE
	)

	set(GAME_DEFINITIONS
		FRAMESERVER_LIBRETRO_3D
		HEADLESS_NOARCAN
		FRAMESERVER_MODESTRING=\"\"
		HEADLESS_PLATFORM=\"${HEADLESS_PLATFORM}\"
		PARENT_SCOPE
	)
else()
	amsg("${CL_YEL}game/retro\t${CL_RED}No 3D (missing lwa platform)${CL_RST}")
endif()

set(GAME_SOURCES ${SOURCE_LIST} PARENT_SCOPE)
