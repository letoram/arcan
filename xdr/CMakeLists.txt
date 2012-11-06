PROJECT(xdr)

SET(
 SOURCES
 xdr_private.h
 xdr.c
 xdr_array.c
 xdr_float.c
 xdr_mem.c
 xdr_rec.c
 xdr_reference.c
 xdr_sizeof.c
 xdr_stdio.c
 xdr_private.c
)

add_library(xdr STATIC ${SOURCES})
