include (CheckLibraryExists)
find_path(VORBIS_INCLUDE_DIR vorbis/vorbisfile.h)

message("-- Searching for OGG Vorbis.")
find_library(VORBISFILE_LIBRARY NAMES vorbisfile)
find_library(VORBIS_LIBRARY NAMES vorbis)
find_library(OGG_LIBRARY NAMES ogg)

if (VORBISFILE_LIBRARY AND VORBIS_LIBRARY AND OGG_LIBRARY)
	message("-- OGG/Vorbis support found (" ${VORBIS_LIBRARY} ")")

   set(VORBIS_FOUND TRUE)
   set(VORBIS_LIBRARIES ${VORBISFILE_LIBRARY} ${VORBIS_LIBRARY} ${OGG_LIBRARY})
   set(CMAKE_REQUIRED_LIBRARIES_TMP ${CMAKE_REQUIRED_LIBRARIES})
   set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES} ${OGGVORBIS_LIBRARIES})
else ()
   set(VORBIS_VERSION)
   set(VORBIS_FOUND FALSE)
   message("-- OGG/Vorbis not found.")
endif ()


