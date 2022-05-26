if (NET_IMPLEMENTATION)
	add_subdirectory("${NET_IMPLEMENTATION}")
else()
	add_subdirectory("default")
endif()

if (NET_SOURCES)
	add_executable(afsrv_net
		${FSRV_PLATFORM}
		${NET_SOURCES}
	)
	add_sanitizers(afsrv_net)
	set(FRAMESERVER_MODESTRING "${FRAMESERVER_MODESTRING}net " PARENT_SCOPE)
	target_compile_definitions(afsrv_net PRIVATE
		ENABLE_FSRV_NET
		DEFAULT_FSRV_MODE=\"net\"
		${NET_DEFS}
	)
	target_include_directories(afsrv_net PRIVATE ${FSRV_ROOT} ${NET_INCLUDE_DIRS})
	target_link_libraries(afsrv_net ${STDLIB} arcan_shmif_int ${NET_LIBS})
	install(TARGETS afsrv_net DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()
