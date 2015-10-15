set (GAME_SOURCES
	${CMAKE_CURRENT_SOURCE_DIR}/libretro.h
	${CMAKE_CURRENT_SOURCE_DIR}/libretro.c
	${CMAKE_CURRENT_SOURCE_DIR}/ntsc/snes_ntsc.h
	${CMAKE_CURRENT_SOURCE_DIR}/ntsc/snes_ntsc.c
	${FSRV_ROOT}/util/sync_plot.h
	${FSRV_ROOT}/util/sync_plot.c
	${FSRV_ROOT}/util/resampler/resample.c
	${FSRV_ROOT}/util/resampler/speex_resampler.h
	${FSRV_ROOT}/util/font_8x8.h
	${PLATFORM_ROOT}/posix/map_resource.c
	${PLATFORM_ROOT}/posix/resource_io.c
	PARENT_SCOPE
)

set (GAME_INCLUDE_DIRS
	${FSRV_ROOT}/../engine
	PARENT_SCOPE
)

#message(STATUS "-- Enabling experimental 3D support.")
#target_compile_definitions(afsrv_game PRIVATE
# HEADLESS_PLATFORM=\"${LWA_HEADLESS}\"
#	ENABLE_3DSUPPORT
# HEADLESS_NOARCAN
#)
