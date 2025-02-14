#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "arcan_mem.h"

void arcan_fatal(const char* msg, ...);

#ifndef REALLOC_STEP
#define REALLOC_STEP 16
#endif

void arcan_mem_init()
{
}

void arcan_mem_tick()
{
}

void* arcan_alloc_mem(size_t nb, enum arcan_memtypes type, enum arcan_memhint hint, enum arcan_memalign align)
{
    void* rptr = NULL;

    switch (type) {
    case ARCAN_MEM_BINDING:
    case ARCAN_MEM_THREADCTX:
    case ARCAN_MEM_VBUFFER:
    case ARCAN_MEM_ABUFFER:
    case ARCAN_MEM_MODELDATA:
    case ARCAN_MEM_VSTRUCT:
    case ARCAN_MEM_EXTSTRUCT:
    case ARCAN_MEM_STRINGBUF:
    case ARCAN_MEM_VTAG:
    case ARCAN_MEM_ATAG:

        switch (align) {
        case ARCAN_MEMALIGN_NATURAL:
        case ARCAN_MEMALIGN_PAGE:
        case ARCAN_MEMALIGN_SIMD:
            rptr = malloc(nb);
        break;
        }
    break;

    case ARCAN_MEM_ENDMARKER:
    default:
        abort();
    }

    if (!rptr) {
        if ((hint & ARCAN_MEM_NONFATAL) == 0)
            arcan_fatal("arcan_alloc_mem(), out of memory.\n");
        return NULL;
    }

    if (hint & ARCAN_MEM_BZERO) {
        memset(rptr, '\0', nb);
    }

    return rptr;
}

void arcan_mem_growarr(struct arcan_strarr* res)
{
    char** newbuf = arcan_alloc_mem(
        (res->limit + REALLOC_STEP) * sizeof(char*),
        ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
    );

    if (res->data)
        memcpy(newbuf, res->data, res->limit * sizeof(char*));
    arcan_mem_free(res->data);
    res->data = newbuf;
    res->limit += REALLOC_STEP;
}

void arcan_mem_freearr(struct arcan_strarr* res)
{
    if (!res || !res->data)
        return;

    char** cptr = res->data;
    while (cptr && *cptr)
        arcan_mem_free(*cptr++);

    arcan_mem_free(res->data);

    memset(res, '\0', sizeof(struct arcan_strarr));
}

void* arcan_alloc_fillmem(const void* data, size_t ds, enum arcan_memtypes type, enum arcan_memhint hint, enum arcan_memalign align)
{
    void* buf = arcan_alloc_mem(ds, type, hint, align);

    if (!buf)
        return NULL;

    memcpy(buf, data, ds);

    return buf;
}

void arcan_mem_free(void* inptr)
{
    free(inptr);
}
