#ifndef SHMIF_RGBA
#define SHMIF_RGBA(r, g, b, a)(\
((uint32_t) (a) << 24) |\
((uint32_t) (r) << 16) |\
((uint32_t) (g) << 8)  |\
((uint32_t) (b)) )
#endif

/*
 * Channel shift constants matching the byte order a byte-addressed reader
 * would see on little-endian hosts. The SHMIF_RGBA() packing macro itself
 * is unchanged -- these constants only describe where each channel lives
 * in a shmif_pixel word for code that needs to extract channels directly
 * rather than going through SHMIF_RGBA_DECOMP.
 */
#ifndef SHMIF_RGBA_RSHIFT
#define SHMIF_RGBA_RSHIFT 0
#endif

#ifndef SHMIF_RGBA_GSHIFT
#define SHMIF_RGBA_GSHIFT 8
#endif

#ifndef SHMIF_RGBA_BSHIFT
#define SHMIF_RGBA_BSHIFT 16
#endif

#ifndef SHMIF_RGBA_ASHIFT
#define SHMIF_RGBA_ASHIFT 24
#endif

#ifndef SHMIF_RGBA_DECOMP
/*
 * Byte-addressable extraction where possible: shift/8 gives the exact
 * byte offset into the shmif_pixel word, skipping the 4-stage
 * shift-and-mask chain. On little-endian hosts this compiles to four
 * independent movzx loads with no dependency chain, which the
 * out-of-order scheduler can issue in parallel. On big-endian we fall
 * back to the classical shift form.
 *
 * The shift constants are kept in bits (not byte offsets) because the
 * SHMIF_RGBA() constructor still consumes them as bit counts in the
 * pack path.
 */
static inline void SHMIF_RGBA_DECOMP(shmif_pixel val,
	uint8_t* r, uint8_t* g, uint8_t* b, uint8_t* a)
{
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
	const uint8_t* bytes = (const uint8_t*)&val;
	*r = bytes[SHMIF_RGBA_RSHIFT >> 3];
	*g = bytes[SHMIF_RGBA_GSHIFT >> 3];
	*b = bytes[SHMIF_RGBA_BSHIFT >> 3];
	*a = bytes[SHMIF_RGBA_ASHIFT >> 3];
#else
	*r = (val >> SHMIF_RGBA_RSHIFT) & 0xff;
	*g = (val >> SHMIF_RGBA_GSHIFT) & 0xff;
	*b = (val >> SHMIF_RGBA_BSHIFT) & 0xff;
	*a = (val >> SHMIF_RGBA_ASHIFT) & 0xff;
#endif
}
#endif
