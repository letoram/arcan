if (NOT TARGET DL::DL)
	find_library(DL_LIBRARIES dl)
	add_library(DL::DL INTERFACE IMPORTED)

	if (DL_LIBRARIES)
		set_target_properties(DL::DL PROPERTIES
			INTERFACE_LINK_LIBRARIES "${DL_LIBRARIES}")

	endif()
endif()
