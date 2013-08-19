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
 */

#include <xmmintrin.h>

void multiply_matrix(float* restrict dst, 
	float* restrict ina, float* restrict inb)
{
	const __m128 a = _mm_load_ps(&ina[0]);
	const __m128 b = _mm_load_ps(&ina[4]);
	const __m128 c = _mm_load_ps(&ina[8]);
	const __m128 d = _mm_load_ps(&ina[12]);

 	__m128 t1, t2;

 	t1 = _mm_set1_ps(inb[0]);
	t2 = _mm_mul_ps(a, t1);
	t1 =_mm_set1_ps(inb[1]);
	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
	t1 =_mm_set1_ps(inb[2]);
	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
	t1 =_mm_set1_ps(inb[3]);
	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

	_mm_store_ps(&dst[0], t2);

	t1 = _mm_set1_ps(inb[4]);
	t2 = _mm_mul_ps(a, t1);
	t1 =_mm_set1_ps(inb[5]);
	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
	t1 =_mm_set1_ps(inb[6]);
	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
	t1 =_mm_set1_ps(inb[7]);
	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

	_mm_store_ps(&dst[4], t2);

	t1 = _mm_set1_ps(inb[8]);
	t2 = _mm_mul_ps(a, t1);
	t1 =_mm_set1_ps(inb[9]);
	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
	t1 =_mm_set1_ps(inb[10]);
	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
	t1 =_mm_set1_ps(inb[11]);
	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

 	_mm_store_ps(&dst[8], t2);

 	t1 = _mm_set1_ps(inb[12]);
 	t2 = _mm_mul_ps(a, t1);
	t1 =_mm_set1_ps(inb[13]);
 	t2 = _mm_add_ps(_mm_mul_ps(b, t1), t2);
 	t1 =_mm_set1_ps(inb[14]);
 	t2 = _mm_add_ps(_mm_mul_ps(c, t1), t2);
 	t1 =_mm_set1_ps(inb[15]);
 	t2 = _mm_add_ps(_mm_mul_ps(d, t1), t2);

	_mm_store_ps(&dst[12], t2);
}
