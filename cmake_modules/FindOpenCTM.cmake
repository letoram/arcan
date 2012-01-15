include (CheckLibraryExists)
find_path(OPENCTM_INCLUDE_DIR openctm.h)

message("-- Searching for OpenCTM")
find_library(OPENCTM_LIBRARY openctm)

if (OPENCTM_LIBRARY)
	message("-- OpenCTM support found (" ${OPENCTM_LIBRARY} ")")

   set(OPENCTM_FOUND TRUE)
   set(OPENCTM_LIBRARIES ${OPENCTM_LIBRARY})
   set(CMAKE_REQUIRED_LIBRARIES_TMP ${CMAKE_REQUIRED_LIBRARIES})
   set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES} ${OPENCTM_LIBRARIES})
else ()
   set(OPENCTM_FOUND FALSE)
   message("-- OpenCTM not found.")
endif ()


