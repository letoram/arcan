# Expects:
# arcan_shmif (target)
# FSRV_ROOT (defined in frameservers/CMakeLists.txt)
#
if (${CMAKE_SSYTEM_NAME} MATCHES "FreeBSD" OR
	${CMAKE_SYSTEM_NAME} MATCHES "Linux")

	add_subdirectory(sdl12)

else()
	message("hijack libraries excluded, feature not supported for ${CMAKE_SYSTEM_NAME}")
endif()
