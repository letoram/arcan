message(STATUS "--(fsrv/game) building game support using libretro")

#
#set(GAME_AUX_LIBS
#	${AGP_LIBRARIES}
#	${LWA_LIBRARIES}
#)

#set(GAME_AUX_SOURCES
#	${AGP_SOURCES}
#)

add_executable(afsrv_game
	default/libretro.h
	default/libretro.c
	default/ntsc/snes_ntsc.h
	default/ntsc/snes_ntsc.c
	${FSRV_ROOT}/util/sync_plot.h
	${FSRV_ROOT}/util/sync_plot.c
	${FSRV_ROOT}/util/resampler/resample.c
	${FSRV_ROOT}/util/resampler/speex_resampler.h
	${FSRV_ROOT}/util/font_8x8.h
	${GAME_AUX_SOURCES}
	${FSRV_PLATFORM}
)

set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING} game")

target_link_libraries(afsrv_game
	arcan_shmif
	${GAME_AUX_LIBS}
	${STDLIB}
)

target_compile_definitions(afsrv_game PRIVATE
	ENABLE_FSRV_GAME
	DEFAULT_FSRV_MODE=\"game\"
)

target_include_directories(afsrv_game PRIVATE
	${FSRV_ROOT}
	${FSRV_ROOT}/util
)

install(TARGETS afsrv_game DESTINATION bin)

#message(STATUS "-- Enabling experimental 3D support.")
#target_compile_definitions(afsrv_game PRIVATE
# HEADLESS_PLATFORM=\"${LWA_HEADLESS}\"
#	ENABLE_3DSUPPORT
# HEADLESS_NOARCAN
#)
