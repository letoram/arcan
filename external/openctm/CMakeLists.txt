PROJECT(openctm)

cmake_minimum_required(VERSION 2.6.0 FATAL_ERROR)
set(MAJOR_VERSION 1)
set(MINOR_VERSION 0)
set(PATCH_LEVEL 3)
set(VERSION ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_LEVEL})

file (GLOB lzmacode "./liblzma/*.c")

set (
 LIBFILES
 openctm.c
 openctm.h
 openctmpp.h
 stream.c
 compressMG1.c
 compressMG2.c
 compressRAW.c
)

LIST(APPEND LIBFILES ${lzmacode})

include_directories("./liblzma")
add_library(openctm STATIC ${LIBFILES})
target_link_libraries(openctm)
set_property(TARGET openctm APPEND PROPERTY COMPILE_FLAGS -Wno-unused-but-set-variable)
