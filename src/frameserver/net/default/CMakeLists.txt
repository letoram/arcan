if (FSRV_NET_REQUIRED)
	find_package(APR REQUIRED QUIET)
else()
	find_package(APR QUIET)
endif()

if (APR_FOUND)
	set(NET_SOURCES
		${CMAKE_CURRENT_SOURCE_DIR}/net_cl.c
		${CMAKE_CURRENT_SOURCE_DIR}/net.h
		${CMAKE_CURRENT_SOURCE_DIR}/net_shared.c
		${CMAKE_CURRENT_SOURCE_DIR}/net_srv.c
		${CMAKE_CURRENT_SOURCE_DIR}/net_shared.h
		PARENT_SCOPE
	)
	set(NET_INCLUDE_DIRS ${APR_INCLUDE_DIR} PARENT_SCOPE)
	set(NET_LIBS ${APR_LIBRARIES} PARENT_SCOPE)

else()
	amsg("(${CL_GRN}net${CL_RST}) disabled, ${CL_GRN}libapr${CL_RED} not found${CL_RST}")
endif()
