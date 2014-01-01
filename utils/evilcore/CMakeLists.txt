cmake_minimum_required(VERSION 2.8)

list(APPEND SOURCES 
	evilcore.c
	libretro.h)

add_definitions(-std=c99)

add_library(evilcore SHARED ${SOURCES})

