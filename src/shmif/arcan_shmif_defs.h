#ifndef SHMIF_RGBA
#define SHMIF_RGBA(r, g, b, a)(\
((uint32_t) (a) << 24) |\
((uint32_t) (r) << 16) |\
((uint32_t) (g) << 8)  |\
((uint32_t) (b)) )
#endif

#ifndef SHMIF_RGBA_RSHIFT
#define SHMIF_RGBA_RSHIFT 16
#endif

#ifndef SHMIF_RGBA_GSHIFT
#define SHMIF_RGBA_GSHIFT 8
#endif

#ifndef SHMIF_RGBA_BSHIFT
#define SHMIF_RGBA_BSHIFT 0
#endif

#ifndef SHMIF_RGBA_ASHIFT
#define SHMIF_RGBA_ASHIFT 24
#endif

#ifndef SHMIF_RGBA_DECOMP
static inline void SHMIF_RGBA_DECOMP(shmif_pixel val,
	uint8_t* r, uint8_t* g, uint8_t* b, uint8_t* a)
{
	*b = (val & 0x000000ff);
	*g = (val & 0x0000ff00) >>  8;
	*r = (val & 0x00ff0000) >> 16;
	*a = (val & 0xff000000) >> 24;
}
#endif
