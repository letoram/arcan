if (NOT TARGET RT::RT)
	find_library(RT_LIBRARIES rt)
	add_library(RT::RT INTERFACE IMPORTED)

	if (RT_LIBRARIES)
		set_target_properties(RT::RT PROPERTIES
			INTERFACE_LINK_LIBRARIES "${RT_LIBRARIES}")

	endif()
endif()
