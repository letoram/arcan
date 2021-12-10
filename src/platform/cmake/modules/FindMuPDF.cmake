# mupdf does not provide a libmupdf.pc :-(
#
# mupdf
# mupdf-third
# mupdf-pkcs7
# mupdf-threads
#
# math (already got this elsewhere)
#
# mupdf itself needs
# zlib
# jpeg
# harfbuzz
# freetype
# jbig2dec
# openjp2
# gumbo

find_package(PkgConfig)
pkg_check_modules(PC_MUPDF QUIET mupdf)
pkg_check_modules(HARFBUZZ QUIET harfbuzz)
pkg_check_modules(JBIG2DEC QUIET jbig2dec)
pkg_check_modules(GUMBO QUIET gumbo)
pkg_check_modules(OPENJP2 QUIET libopenjp2)

find_path( MUPDF_INCLUDE_DIR
	NAMES mupdf/fitz.h
	PATHS ${PC_MUPDF_INCLUDE_DIRS}
	PATH_SUFFIXES mypdf
)

find_package(Freetype QUIET)
find_package(ZLIB QUIET)
find_package(JPEG QUIET)

# from mupdf there can be multiple extra libraries built
find_library(MUPDF_LIBRARY
	NAMES mupdf
	PATHS ${PC_MUPDF_LIBRARY_DIRS}
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(MUPDF
	FOUND_VAR MUPDF_FOUND
	REQUIRED_VARS
		FREETYPE_FOUND
		ZLIB_FOUND
		JPEG_FOUND
		GUMBO_FOUND
		OPENJP2_FOUND
		HARFBUZZ_FOUND
		MUPDF_LIBRARY
		MUPDF_INCLUDE_DIR
)

if (FREETYPE_FOUND AND ZLIB_FOUND AND JPEG_FOUND AND GUMBO_FOUND AND OPENJP2_FOUND AND HARFBUZZ_FOUND)
	set(MUPDF_FOUND 1)
	set(MUPDF_LIBRARIES
		${MUPDF_LIBRARY}
		${FREETYPE_LIBRARIES}
		${ZLIB_LIBRARIES}
		${JPEG_LIBRARIES}
		${HARFBUZZ_LIBRARIES}
		${JBIG2DEC_LIBRARIES}
		${GUMBO_LIBRARIES}
		${OPENJP2_LIBRARIES}
	)

	set(MUPDF_INCLUDE_DIRS
		${MUPDF_INCLUDE_DIR}
		${FREETYPE_INCLUDE_DIRS}
		${ZLIB_INCLUDE_DIRS}
		${HARFBUZZ_INCLUDE_DIRS}
		${JBIG2DEC_INCLUDE_DIRS}
		${GUMBO_INCLUDE_DIRS}
		${OPENJP2_INCLUDE_DIRS}
	)

	find_library(MUPDF_THIRD_LIBRARY NAMES mupdf-third)
	if (MUPDF_THIRD_LIBRARY)
		list(APPEND MUPDF_LIBRARIES ${MUPDF_THIRD_LIBRARY})
	endif()

	find_library(MUPDF_PKCS7_LIBRARY NAMES mupdf-pkcs7)
	if (MUPDF_PKCS7_LIBRARY)
		list(APPEND MUPDF_LIBRARIES ${MUPDF_PKCS7_LIBRARY})
	endif()

	find_library(MUPDF_THREAD_LIBRARY NAMES mupdf-threads)
	if (MUPDF_THREAD_LIBRARY)
		list(APPEND MUPDF_LIBRARIES ${MUPDF_THREAD_LIBRARY})
	endif()
endif()
