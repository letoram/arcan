#include <stdint.h>
#include "arcan_shmif.h"

static inline void* align64(uint8_t* inptr)
{
	return (void*) (((uintptr_t)inptr % 64 != 0) ?
		inptr + 64 - ((uintptr_t) inptr % 64) : inptr);
}

uintptr_t arcan_shmif_mapav(
	struct arcan_shmif_page* addr,
	shmif_pixel* vbuf[], size_t vbufc, size_t vbuf_sz,
	shmif_asample* abuf[], size_t abufc, size_t abuf_sz)
{
/* now we are in bat county */
	uint8_t* wbuf = (uint8_t*)addr + sizeof(struct arcan_shmif_page);
	if (addr && vbuf)
		wbuf += addr->apad;

	for (size_t i = 0; i < abufc; i++){
			wbuf = align64(wbuf);
			if (abuf)
				abuf[i] = abuf_sz ? (shmif_asample*) wbuf : NULL;
			wbuf += abuf_sz;
	}

	for (size_t i = 0; i < vbufc; i++){
			wbuf = align64(wbuf);
			if (vbuf)
				vbuf[i] = vbuf_sz ? (shmif_pixel*) align64(wbuf) : NULL;
			wbuf += vbuf_sz;
		}

#ifdef ARCAN_SHMIF_OVERCOMMIT
	return ARCAN_SHMPAGE_MAX_SZ;
#else
	return (uintptr_t) wbuf - (uintptr_t) addr;
#endif
}
