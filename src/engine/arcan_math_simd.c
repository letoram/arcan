/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdbool.h>

#ifndef M_PI
#define M_PI 3.14159265
#endif

#include "arcan_math.h"

/*
 * If SIMD support is detected in build system,
 * this compilation unit will be added and
 * ARCAN_MATH_SIMD will be defined to exclude
 * the corresponding functions in arcan_math.c
 * this is for x64, for arm -- look
 * in arcan_math_neon.c
 */

#include <xmmintrin.h>
#include <pmmintrin.h>
#include <stdint.h>
#include <assert.h>

void mult_matrix_vecf(const float* ina,
	const float* const inv, float* dst)
{
#ifdef ARCAN_MATH_ALIGNED_SIMD
	assert((uintptr_t)dst % 16 == 0);
	assert((uintptr_t)ina % 16 == 0);
	assert((uintptr_t)inv % 16 == 0);
	__m128 r0 = _mm_load_ps(&ina[0]);
	__m128 r1 = _mm_load_ps(&ina[4]);
	__m128 r2 = _mm_load_ps(&ina[8]);
	__m128 r3 = _mm_load_ps(&ina[12]);
	const __m128 ir = _mm_load_ps(inv);
#else
	__m128 r0 = _mm_loadu_ps(&ina[0]);
	__m128 r1 = _mm_loadu_ps(&ina[4]);
	__m128 r2 = _mm_loadu_ps(&ina[8]);
	__m128 r3 = _mm_loadu_ps(&ina[12]);
	const __m128 ir = _mm_loadu_ps(inv);
#endif
/* column major curses .. */
	_MM_TRANSPOSE4_PS(r0, r1, r2, r3);

	__m128 m0 = _mm_mul_ps(r0, ir);
	__m128 m1 = _mm_mul_ps(r1, ir);
	__m128 m2 = _mm_mul_ps(r2, ir);
	__m128 m3 = _mm_mul_ps(r3, ir);

	__m128 a1 = _mm_hadd_ps(m0, m1);
	__m128 a2 = _mm_hadd_ps(m2, m3);
	__m128 rs = _mm_hadd_ps(a1, a2);

#ifdef ARCAN_MATH_ALIGNED_SIMD
	_mm_store_ps(dst, rs);
#else
	_mm_storeu_ps(dst, rs);
#endif
}

void multiply_matrix(float* restrict dst,
	const float* restrict ina, const float* restrict inb)
{
#ifdef ARCAN_MATH_ALIGNED_SIMD
	assert(((uintptr_t)dst % 16) == 0);
	assert(((uintptr_t)ina % 16) == 0);
	assert(((uintptr_t)inb % 16) == 0);

	const __m128 a = _mm_load_ps(&ina[0]);
	const __m128 b = _mm_load_ps(&ina[4]);
	const __m128 c = _mm_load_ps(&ina[8]);
	const __m128 d = _mm_load_ps(&ina[12]);
#else
	const __m128 a = _mm_loadu_ps(&ina[0]);
	const __m128 b = _mm_loadu_ps(&ina[4]);
	const __m128 c = _mm_loadu_ps(&ina[8]);
	const __m128 d = _mm_loadu_ps(&ina[12]);
#endif

 	__m128 t1, t2;

 	t1 = _mm_set1_ps(inb[0]);
	t2 = _mm_mul_ps(a, t1);
	t1 = _mm_set1_ps(inb[1]);
	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
	t1 = _mm_set1_ps(inb[2]);
	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
	t1 = _mm_set1_ps(inb[3]);
	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

/* can we guarantee alignment? else
 * __mm_storeu_ps */
#ifdef ARCAN_MATH_ALIGNED_SIMD
	_mm_store_ps(&dst[0], t2);
#else
	_mm_storeu_ps(&dst[0], t2);
#endif

	t1 = _mm_set1_ps(inb[4]);
	t2 = _mm_mul_ps(a, t1);
	t1 = _mm_set1_ps(inb[5]);
	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
	t1 = _mm_set1_ps(inb[6]);
	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
	t1 = _mm_set1_ps(inb[7]);
	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

#ifdef ARCAN_MATH_ALIGNED_SIMD
	_mm_store_ps(&dst[4], t2);
#else
	_mm_storeu_ps(&dst[4], t2);
#endif

	t1 = _mm_set1_ps(inb[8]);
	t2 = _mm_mul_ps(a, t1);
	t1 = _mm_set1_ps(inb[9]);
	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
	t1 = _mm_set1_ps(inb[10]);
	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
	t1 = _mm_set1_ps(inb[11]);
	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

#ifdef ARCAN_MATH_ALIGNED_SIMD
	_mm_store_ps(&dst[8], t2);
#else
	_mm_storeu_ps(&dst[8], t2);
#endif

 	t1 = _mm_set1_ps(inb[12]);
 	t2 = _mm_mul_ps(a, t1);
	t1 = _mm_set1_ps(inb[13]);
 	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
 	t1 = _mm_set1_ps(inb[14]);
 	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
 	t1 = _mm_set1_ps(inb[15]);
 	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

#ifdef ARCAN_MATH_ALIGNED_SIMD
	_mm_store_ps(&dst[12], t2);
#else
	_mm_storeu_ps(&dst[12], t2);
#endif
}

