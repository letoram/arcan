if (NOT TARGET Atomic::Atomic)
	find_library(ATOMIC_LIBRARIES NAMES atomic libatomic.so libatomic.so.1)
	add_library(Atomic::Atomic INTERFACE IMPORTED)

	if (ATOMIC_LIBRARIES)
		set_target_properties(Atomic::Atomic PROPERTIES
			INTERFACE_INCLUDE_DIRECTORIES "${ATOMIC_INCLUDE_DIRS}"
			INTERFACE_LINK_LIBRARIES "${ATOMIC_LIBRARIES}")
	endif()
endif()
