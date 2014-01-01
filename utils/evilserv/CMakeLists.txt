cmake_minimum_required(VERSION 2.8)

list(APPEND SOURCES 
	evilserv.c
)

add_definitions(-std=c99 -DPLATFORM_HEADER="stdlib.h")
include_directories( ../../ )

add_executable(evilcore ${SOURCES})

