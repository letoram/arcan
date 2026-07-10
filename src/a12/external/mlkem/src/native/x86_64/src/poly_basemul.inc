/*
 * Copyright (c) The mlkem-native project authors
 * SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT
 */

/* References
 * ==========
 *
 * - [REF_AVX2]
 *   CRYSTALS-Kyber optimized AVX2 implementation
 *   Bos, Ducas, Kiltz, Lepoint, Lyubashevsky, Schanck, Schwabe, Seiler, Stehlé
 *   https://github.com/pq-crystals/kyber/tree/main/avx2
 */

/*
 * This file is derived from the public domain
 * AVX2 Kyber implementation @[REF_AVX2], but it was significantly modified:
 *  1) we are using mulcache (following the aarch64 implementation),
 *  2) schoolbook macro was simplified to process one instead of two inputs,
 *     withouth any performance degradation. This also made it possible to
 *     avoid using the stack because we managed to fit the implemention
 *     into 16 available ymm registers,
 *  3) we use named variables instead of ymm registers directly.
 */

#define _q %ymm0
#define _qinv %ymm1
#define _a %ymm2
#define _b %ymm3
#define _c %ymm4
#define _d %ymm5
#define _dz %ymm6
#define _r0 %ymm7
#define _r1 %ymm8
#define _s0 %ymm9
#define _s1 %ymm10
#define _ac_hi %ymm11
#define _ad_hi %ymm12
#define _bdz_hi %ymm13
#define _bc_hi %ymm14
#define _a_lo %ymm13
#define _b_lo %ymm14

/* Polynomials to be multiplied are denoted (a + bX) (rsi arg) and
 * (c + dX) (rdx arg). The mulcache for (c + dX), that is, the precomputed
 * values of (d * zeta) is passed in rcx. We compute:
 *  (r + sX) = (a + bX) * (c + dX), where in the code we denote
 *    r = ac + bdz = r0 + r1,
 *    s = ad + bc = s0 + s1.
 */
.macro schoolbook iter k
vmovdqa (256*\k + 32*\iter +  0)*2(%rsi), _a
vmovdqa (256*\k + 32*\iter + 16)*2(%rsi), _b
vmovdqa (256*\k + 32*\iter +  0)*2(%rdx), _c
vmovdqa (256*\k + 32*\iter + 16)*2(%rdx), _d
vmovdqa (128*\k + 16*\iter)*2(%rcx), _dz

/* Prepare Montgomery twists */
vpmullw _a, _qinv, _a_lo
vpmullw _b, _qinv, _b_lo

/* Compute low-parts of monomials in (a + bX) * (c + dX),
 * using Montgomery twists calculated before. */
vpmullw _a_lo, _c,  _r0
vpmullw _a_lo, _d,  _s0
vpmullw _b_lo, _dz, _r1
vpmullw _b_lo, _c,  _s1

/* Compute the second high multiplication in Montgomery multiplication. */
vpmulhw _r0, _q, _r0
vpmulhw _s0, _q, _s0
vpmulhw _r1, _q, _r1
vpmulhw _s1, _q, _s1

/* Compute high-parts of monomials in (a + bX) * (c + dX). */
vpmulhw _a, _c,  _ac_hi
vpmulhw _a, _d,  _ad_hi
vpmulhw _b, _dz, _bdz_hi
vpmulhw _b, _c,  _bc_hi

/* Finish Montgomery multiplications */
vpsubw _r0, _ac_hi, _r0
vpsubw _s0, _ad_hi, _s0
.if \iter & 1 /* Every other (d * zeta) is stored negative */
vpsubw _bdz_hi, _r1, _r1
.else
vpsubw _r1, _bdz_hi, _r1
.endif
vpsubw _s1, _bc_hi, _s1

vpaddw _r0, _r1, _r0
vpaddw _s0, _s1, _s0
.if \k > 0
vmovdqa (32*\iter +  0)*2(%rdi), _r1
vmovdqa (32*\iter + 16)*2(%rdi), _s1
vpaddw _r0, _r1, _r0
vpaddw _s0, _s1, _s0
.endif

vmovdqa _r0, (32*\iter +  0)*2(%rdi)
vmovdqa _s0, (32*\iter + 16)*2(%rdi)
/* Bounds. The only assumptions we make on the input are:
 *  abs(a, b) < 2^12 and abs(c, d, dz) <= 2^15.
 * Therefore we have that the products a*c, b*dz, a*d, b*c are bounded by 3713.
 * For example,
 *  a*c <= ceil(abs(a) * abs(c) / 2^16) + (Q + 1)/2
 *      <= ceil(2^12 * 2*15 / 2^16) + (3329 + 1)/2
 *       = 3713
 * In the worst case, we accumulate 8 such products, which bounds the output
 * coefficients to 8 * 3713 which is less than 2^15 and fits in int16_t.
 */
.endm

.macro poly_basemul k
schoolbook 0 \k
schoolbook 1 \k
schoolbook 2 \k
schoolbook 3 \k
schoolbook 4 \k
schoolbook 5 \k
schoolbook 6 \k
schoolbook 7 \k
.endm

.macro polyvec_basemul k
  vmovdqa MLK_AVX2_BACKEND_DATA_OFFSET_16XQ*2(%r8), _q
  vmovdqa MLK_AVX2_BACKEND_DATA_OFFSET_16XQINV*2(%r8), _qinv
  .if \k > 0
    poly_basemul 0
  .endif
  .if \k > 1
    poly_basemul 1
  .endif
  .if \k > 2
    poly_basemul 2
  .endif
  .if \k > 3
    poly_basemul 3
  .endif
.endm

#undef _q
#undef _qinv
#undef _a
#undef _b
#undef _c
#undef _d
#undef _dz
#undef _r0
#undef _r1
#undef _s0
#undef _s1
#undef _ac_hi
#undef _ad_hi
#undef _bdz_hi
#undef _bc_hi
#undef _a_lo
#undef _b_lo
