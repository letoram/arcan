#
# The big first todo for this frameserver is to evacuate
# APR support altogether, it was used in the hopes of mitigating
# some of the porting issues from socket use, and was terrible
# in this regard.
#

if (FSRV_NET_REQUIRED)
	find_package(APR REQUIRED)
else()
	find_package(APR)
endif()

if (APR_FOUND)
	message(STATUS "--(fsrv/net) building using LibAPR")
	add_executable(afsrv_net
		${FSRV_PLATFORM}
		default/net_cl.c
		default/net.h
		default/net_shared.c
		default/net_srv.c
		default/net_shared.h
	)
	target_include_directories(afsrv_net PRIVATE
		${FSRV_ROOT}
		${APR_INCLUDE_DIR}
	)
	target_compile_definitions(afsrv_net PRIVATE
		ENABLE_FSRV_NET
		DEFAULT_FSRV_MODE=\"net\"
	)
	target_link_libraries(afsrv_net
		${APR_LIBRARIES}
		arcan_shmif
		${STDLIB}
	)
else()
	message("net frameserver disabled, libapr not found\n")
endif()
