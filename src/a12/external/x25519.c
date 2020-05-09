/*
 * Implementation lifted from Monocypher
 * Removed some macro fsckery, more needed.
 */
#include <inttypes.h>
#include <stddef.h>
#include <string.h>

#include "x25519.h"

///////////////
/// X-25519 /// Taken from SUPERCOP's ref10 implementation.
///////////////

////////////////////////////////////
/// Arithmetic modulo 2^255 - 19 ///
////////////////////////////////////
//  Taken from SUPERCOP's ref10 implementation.
//  A bit bigger than TweetNaCl, over 4 times faster.

#define FOR_T(type, i, start, end) for (type i = (start); i < (end); i++)
#define FOR(i, start, end)         FOR_T(size_t, i, start, end)

typedef int8_t   i8;
typedef uint8_t  u8;
typedef int16_t  i16;
typedef uint32_t u32;
typedef int32_t  i32;
typedef int64_t  i64;
typedef uint64_t u64;

// field element
typedef int32_t fe[10];
static void fe_0(fe h) {            FOR(i, 0, 10) h[i] = 0; }
static void fe_1(fe h) { h[0] = 1;  FOR(i, 1, 10) h[i] = 0; }

static void fe_copy(fe h,const fe f           ){FOR(i,0,10) h[i] =  f[i];      }
static void fe_neg (fe h,const fe f           ){FOR(i,0,10) h[i] = -f[i];      }
static void fe_add (fe h,const fe f,const fe g){FOR(i,0,10) h[i] = f[i] + g[i];}
static void fe_sub (fe h,const fe f,const fe g){FOR(i,0,10) h[i] = f[i] - g[i];}

static u32 load24_le(const u8 s[3])
{
    return (u32)s[0]
        | ((u32)s[1] <<  8)
        | ((u32)s[2] << 16);
}

static u32 load32_le(const u8 s[4])
{
    return (u32)s[0]
        | ((u32)s[1] <<  8)
        | ((u32)s[2] << 16)
        | ((u32)s[3] << 24);
}

static u64 load64_le(const u8 s[8])
{
    return load32_le(s) | ((u64)load32_le(s+4) << 32);
}

static void store32_le(u8 out[4], u32 in)
{
    out[0] =  in        & 0xff;
    out[1] = (in >>  8) & 0xff;
    out[2] = (in >> 16) & 0xff;
    out[3] = (in >> 24) & 0xff;
}

static void store64_le(u8 out[8], u64 in)
{
    store32_le(out    , (u32)in );
    store32_le(out + 4, in >> 32);
}

static u64 rotr64(u64 x, u64 n) { return (x >> n) ^ (x << (64 - n)); }
static u32 rotl32(u32 x, u32 n) { return (x << n) ^ (x >> (32 - n)); }

static int neq0(u64 diff)
{   // constant time comparison to zero
    // return diff != 0 ? -1 : 0
    u64 half = (diff >> 32) | ((u32)diff);
    return (1 & ((half - 1) >> 32)) - 1;
}

static u64 x16(const u8 a[16], const u8 b[16])
{
    return (load64_le(a + 0) ^ load64_le(b + 0))
        |  (load64_le(a + 8) ^ load64_le(b + 8));
}

static void fe_cswap(fe f, fe g, int b)
{
    i32 mask = -b; // rely on 2's complement: -1 = 0xffffffff
    FOR (i, 0, 10) {
        i32 x = (f[i] ^ g[i]) & mask;
        f[i] = f[i] ^ x;
        g[i] = g[i] ^ x;
    }
}

static void fe_ccopy(fe f, const fe g, int b)
{
    i32 mask = -b; // rely on 2's complement: -1 = 0xffffffff
    FOR (i, 0, 10) {
        i32 x = (f[i] ^ g[i]) & mask;
        f[i] = f[i] ^ x;
    }
}

#define FE_CARRY                                                        \
    i64 c0, c1, c2, c3, c4, c5, c6, c7, c8, c9;                         \
    c9 = (t9 + (i64)(1<<24)) >> 25; t0 += c9 * 19; t9 -= c9 * (1 << 25); \
    c1 = (t1 + (i64)(1<<24)) >> 25; t2 += c1;      t1 -= c1 * (1 << 25); \
    c3 = (t3 + (i64)(1<<24)) >> 25; t4 += c3;      t3 -= c3 * (1 << 25); \
    c5 = (t5 + (i64)(1<<24)) >> 25; t6 += c5;      t5 -= c5 * (1 << 25); \
    c7 = (t7 + (i64)(1<<24)) >> 25; t8 += c7;      t7 -= c7 * (1 << 25); \
    c0 = (t0 + (i64)(1<<25)) >> 26; t1 += c0;      t0 -= c0 * (1 << 26); \
    c2 = (t2 + (i64)(1<<25)) >> 26; t3 += c2;      t2 -= c2 * (1 << 26); \
    c4 = (t4 + (i64)(1<<25)) >> 26; t5 += c4;      t4 -= c4 * (1 << 26); \
    c6 = (t6 + (i64)(1<<25)) >> 26; t7 += c6;      t6 -= c6 * (1 << 26); \
    c8 = (t8 + (i64)(1<<25)) >> 26; t9 += c8;      t8 -= c8 * (1 << 26); \
    h[0]=(i32)t0;  h[1]=(i32)t1;  h[2]=(i32)t2;  h[3]=(i32)t3;  h[4]=(i32)t4; \
    h[5]=(i32)t5;  h[6]=(i32)t6;  h[7]=(i32)t7;  h[8]=(i32)t8;  h[9]=(i32)t9

static void fe_frombytes(fe h, const uint8_t s[32])
{
    i64 t0 =  load32_le(s);
    i64 t1 =  load24_le(s +  4) << 6;
    i64 t2 =  load24_le(s +  7) << 5;
    i64 t3 =  load24_le(s + 10) << 3;
    i64 t4 =  load24_le(s + 13) << 2;
    i64 t5 =  load32_le(s + 16);
    i64 t6 =  load24_le(s + 20) << 7;
    i64 t7 =  load24_le(s + 23) << 5;
    i64 t8 =  load24_le(s + 26) << 4;
    i64 t9 = (load24_le(s + 29) & 0x7fffff) << 2;
    FE_CARRY;
}

static void fe_mul_small(fe h, const fe f, i32 g)
{
    i64 t0 = f[0] * (i64) g;  i64 t1 = f[1] * (i64) g;
    i64 t2 = f[2] * (i64) g;  i64 t3 = f[3] * (i64) g;
    i64 t4 = f[4] * (i64) g;  i64 t5 = f[5] * (i64) g;
    i64 t6 = f[6] * (i64) g;  i64 t7 = f[7] * (i64) g;
    i64 t8 = f[8] * (i64) g;  i64 t9 = f[9] * (i64) g;
    FE_CARRY;
}
static void fe_mul121666(fe h, const fe f) { fe_mul_small(h, f, 121666); }

static void fe_mul(fe h, const fe f, const fe g)
{
    // Everything is unrolled and put in temporary variables.
    // We could roll the loop, but that would make curve25519 twice as slow.
    i32 f0 = f[0]; i32 f1 = f[1]; i32 f2 = f[2]; i32 f3 = f[3]; i32 f4 = f[4];
    i32 f5 = f[5]; i32 f6 = f[6]; i32 f7 = f[7]; i32 f8 = f[8]; i32 f9 = f[9];
    i32 g0 = g[0]; i32 g1 = g[1]; i32 g2 = g[2]; i32 g3 = g[3]; i32 g4 = g[4];
    i32 g5 = g[5]; i32 g6 = g[6]; i32 g7 = g[7]; i32 g8 = g[8]; i32 g9 = g[9];
    i32 F1 = f1*2; i32 F3 = f3*2; i32 F5 = f5*2; i32 F7 = f7*2; i32 F9 = f9*2;
    i32 G1 = g1*19;  i32 G2 = g2*19;  i32 G3 = g3*19;
    i32 G4 = g4*19;  i32 G5 = g5*19;  i32 G6 = g6*19;
    i32 G7 = g7*19;  i32 G8 = g8*19;  i32 G9 = g9*19;

    i64 h0 = f0*(i64)g0 + F1*(i64)G9 + f2*(i64)G8 + F3*(i64)G7 + f4*(i64)G6
        +    F5*(i64)G5 + f6*(i64)G4 + F7*(i64)G3 + f8*(i64)G2 + F9*(i64)G1;
    i64 h1 = f0*(i64)g1 + f1*(i64)g0 + f2*(i64)G9 + f3*(i64)G8 + f4*(i64)G7
        +    f5*(i64)G6 + f6*(i64)G5 + f7*(i64)G4 + f8*(i64)G3 + f9*(i64)G2;
    i64 h2 = f0*(i64)g2 + F1*(i64)g1 + f2*(i64)g0 + F3*(i64)G9 + f4*(i64)G8
        +    F5*(i64)G7 + f6*(i64)G6 + F7*(i64)G5 + f8*(i64)G4 + F9*(i64)G3;
    i64 h3 = f0*(i64)g3 + f1*(i64)g2 + f2*(i64)g1 + f3*(i64)g0 + f4*(i64)G9
        +    f5*(i64)G8 + f6*(i64)G7 + f7*(i64)G6 + f8*(i64)G5 + f9*(i64)G4;
    i64 h4 = f0*(i64)g4 + F1*(i64)g3 + f2*(i64)g2 + F3*(i64)g1 + f4*(i64)g0
        +    F5*(i64)G9 + f6*(i64)G8 + F7*(i64)G7 + f8*(i64)G6 + F9*(i64)G5;
    i64 h5 = f0*(i64)g5 + f1*(i64)g4 + f2*(i64)g3 + f3*(i64)g2 + f4*(i64)g1
        +    f5*(i64)g0 + f6*(i64)G9 + f7*(i64)G8 + f8*(i64)G7 + f9*(i64)G6;
    i64 h6 = f0*(i64)g6 + F1*(i64)g5 + f2*(i64)g4 + F3*(i64)g3 + f4*(i64)g2
        +    F5*(i64)g1 + f6*(i64)g0 + F7*(i64)G9 + f8*(i64)G8 + F9*(i64)G7;
    i64 h7 = f0*(i64)g7 + f1*(i64)g6 + f2*(i64)g5 + f3*(i64)g4 + f4*(i64)g3
        +    f5*(i64)g2 + f6*(i64)g1 + f7*(i64)g0 + f8*(i64)G9 + f9*(i64)G8;
    i64 h8 = f0*(i64)g8 + F1*(i64)g7 + f2*(i64)g6 + F3*(i64)g5 + f4*(i64)g4
        +    F5*(i64)g3 + f6*(i64)g2 + F7*(i64)g1 + f8*(i64)g0 + F9*(i64)G9;
    i64 h9 = f0*(i64)g9 + f1*(i64)g8 + f2*(i64)g7 + f3*(i64)g6 + f4*(i64)g5
        +    f5*(i64)g4 + f6*(i64)g3 + f7*(i64)g2 + f8*(i64)g1 + f9*(i64)g0;

#define CARRY                                                             \
    i64 c0, c1, c2, c3, c4, c5, c6, c7, c8, c9;                           \
    c0 = (h0 + (i64) (1<<25)) >> 26; h1 += c0;      h0 -= c0 * (1 << 26); \
    c4 = (h4 + (i64) (1<<25)) >> 26; h5 += c4;      h4 -= c4 * (1 << 26); \
    c1 = (h1 + (i64) (1<<24)) >> 25; h2 += c1;      h1 -= c1 * (1 << 25); \
    c5 = (h5 + (i64) (1<<24)) >> 25; h6 += c5;      h5 -= c5 * (1 << 25); \
    c2 = (h2 + (i64) (1<<25)) >> 26; h3 += c2;      h2 -= c2 * (1 << 26); \
    c6 = (h6 + (i64) (1<<25)) >> 26; h7 += c6;      h6 -= c6 * (1 << 26); \
    c3 = (h3 + (i64) (1<<24)) >> 25; h4 += c3;      h3 -= c3 * (1 << 25); \
    c7 = (h7 + (i64) (1<<24)) >> 25; h8 += c7;      h7 -= c7 * (1 << 25); \
    c4 = (h4 + (i64) (1<<25)) >> 26; h5 += c4;      h4 -= c4 * (1 << 26); \
    c8 = (h8 + (i64) (1<<25)) >> 26; h9 += c8;      h8 -= c8 * (1 << 26); \
    c9 = (h9 + (i64) (1<<24)) >> 25; h0 += c9 * 19; h9 -= c9 * (1 << 25); \
    c0 = (h0 + (i64) (1<<25)) >> 26; h1 += c0;      h0 -= c0 * (1 << 26); \
    h[0]=(i32)h0;  h[1]=(i32)h1;  h[2]=(i32)h2;  h[3]=(i32)h3;  h[4]=(i32)h4; \
    h[5]=(i32)h5;  h[6]=(i32)h6;  h[7]=(i32)h7;  h[8]=(i32)h8;  h[9]=(i32)h9

    CARRY;
}

// we could use fe_mul() for this, but this is significantly faster
static void fe_sq(fe h, const fe f)
{
    i32 f0 = f[0]; i32 f1 = f[1]; i32 f2 = f[2]; i32 f3 = f[3]; i32 f4 = f[4];
    i32 f5 = f[5]; i32 f6 = f[6]; i32 f7 = f[7]; i32 f8 = f[8]; i32 f9 = f[9];
    i32 f0_2  = f0*2;   i32 f1_2  = f1*2;   i32 f2_2  = f2*2;   i32 f3_2 = f3*2;
    i32 f4_2  = f4*2;   i32 f5_2  = f5*2;   i32 f6_2  = f6*2;   i32 f7_2 = f7*2;
    i32 f5_38 = f5*38;  i32 f6_19 = f6*19;  i32 f7_38 = f7*38;
    i32 f8_19 = f8*19;  i32 f9_38 = f9*38;

    i64 h0 = f0  *(i64)f0    + f1_2*(i64)f9_38 + f2_2*(i64)f8_19
        +    f3_2*(i64)f7_38 + f4_2*(i64)f6_19 + f5  *(i64)f5_38;
    i64 h1 = f0_2*(i64)f1    + f2  *(i64)f9_38 + f3_2*(i64)f8_19
        +    f4  *(i64)f7_38 + f5_2*(i64)f6_19;
    i64 h2 = f0_2*(i64)f2    + f1_2*(i64)f1    + f3_2*(i64)f9_38
        +    f4_2*(i64)f8_19 + f5_2*(i64)f7_38 + f6  *(i64)f6_19;
    i64 h3 = f0_2*(i64)f3    + f1_2*(i64)f2    + f4  *(i64)f9_38
        +    f5_2*(i64)f8_19 + f6  *(i64)f7_38;
    i64 h4 = f0_2*(i64)f4    + f1_2*(i64)f3_2  + f2  *(i64)f2
        +    f5_2*(i64)f9_38 + f6_2*(i64)f8_19 + f7  *(i64)f7_38;
    i64 h5 = f0_2*(i64)f5    + f1_2*(i64)f4    + f2_2*(i64)f3
        +    f6  *(i64)f9_38 + f7_2*(i64)f8_19;
    i64 h6 = f0_2*(i64)f6    + f1_2*(i64)f5_2  + f2_2*(i64)f4
        +    f3_2*(i64)f3    + f7_2*(i64)f9_38 + f8  *(i64)f8_19;
    i64 h7 = f0_2*(i64)f7    + f1_2*(i64)f6    + f2_2*(i64)f5
        +    f3_2*(i64)f4    + f8  *(i64)f9_38;
    i64 h8 = f0_2*(i64)f8    + f1_2*(i64)f7_2  + f2_2*(i64)f6
        +    f3_2*(i64)f5_2  + f4  *(i64)f4    + f9  *(i64)f9_38;
    i64 h9 = f0_2*(i64)f9    + f1_2*(i64)f8    + f2_2*(i64)f7
        +    f3_2*(i64)f6    + f4  *(i64)f5_2;

    CARRY;
}

static void fe_sq2(fe h, const fe f)
{
    fe_sq(h, f);
    fe_mul_small(h, h, 2);
}

// This could be simplified, but it would be slower
static void fe_invert(fe out, const fe z)
{
    fe t0, t1, t2, t3;
    fe_sq(t0, z );
    fe_sq(t1, t0);
    fe_sq(t1, t1);
    fe_mul(t1,  z, t1);
    fe_mul(t0, t0, t1);
    fe_sq(t2, t0);                                fe_mul(t1 , t1, t2);
    fe_sq(t2, t1); FOR (i, 1,   5) fe_sq(t2, t2); fe_mul(t1 , t2, t1);
    fe_sq(t2, t1); FOR (i, 1,  10) fe_sq(t2, t2); fe_mul(t2 , t2, t1);
    fe_sq(t3, t2); FOR (i, 1,  20) fe_sq(t3, t3); fe_mul(t2 , t3, t2);
    fe_sq(t2, t2); FOR (i, 1,  10) fe_sq(t2, t2); fe_mul(t1 , t2, t1);
    fe_sq(t2, t1); FOR (i, 1,  50) fe_sq(t2, t2); fe_mul(t2 , t2, t1);
    fe_sq(t3, t2); FOR (i, 1, 100) fe_sq(t3, t3); fe_mul(t2 , t3, t2);
    fe_sq(t2, t2); FOR (i, 1,  50) fe_sq(t2, t2); fe_mul(t1 , t2, t1);
    fe_sq(t1, t1); FOR (i, 1,   5) fe_sq(t1, t1); fe_mul(out, t1, t0);
}

// This could be simplified, but it would be slower
static void fe_pow22523(fe out, const fe z)
{
    fe t0, t1, t2;
    fe_sq(t0, z);
    fe_sq(t1,t0);                   fe_sq(t1, t1);  fe_mul(t1, z, t1);
    fe_mul(t0, t0, t1);
    fe_sq(t0, t0);                                  fe_mul(t0, t1, t0);
    fe_sq(t1, t0);  FOR (i, 1,   5) fe_sq(t1, t1);  fe_mul(t0, t1, t0);
    fe_sq(t1, t0);  FOR (i, 1,  10) fe_sq(t1, t1);  fe_mul(t1, t1, t0);
    fe_sq(t2, t1);  FOR (i, 1,  20) fe_sq(t2, t2);  fe_mul(t1, t2, t1);
    fe_sq(t1, t1);  FOR (i, 1,  10) fe_sq(t1, t1);  fe_mul(t0, t1, t0);
    fe_sq(t1, t0);  FOR (i, 1,  50) fe_sq(t1, t1);  fe_mul(t1, t1, t0);
    fe_sq(t2, t1);  FOR (i, 1, 100) fe_sq(t2, t2);  fe_mul(t1, t2, t1);
    fe_sq(t1, t1);  FOR (i, 1,  50) fe_sq(t1, t1);  fe_mul(t0, t1, t0);
    fe_sq(t0, t0);  FOR (i, 1,   2) fe_sq(t0, t0);  fe_mul(out, t0, z);
}

static void fe_tobytes(uint8_t s[32], const fe h)
{
    i32 t[10];
    FOR (i, 0, 10) {
        t[i] = h[i];
    }
    i32 q = (19 * t[9] + (((i32) 1) << 24)) >> 25;
    FOR (i, 0, 5) {
        q += t[2*i  ]; q >>= 26;
        q += t[2*i+1]; q >>= 25;
    }
    t[0] += 19 * q;

    i32 c0 = t[0] >> 26; t[1] += c0; t[0] -= c0 * (1 << 26);
    i32 c1 = t[1] >> 25; t[2] += c1; t[1] -= c1 * (1 << 25);
    i32 c2 = t[2] >> 26; t[3] += c2; t[2] -= c2 * (1 << 26);
    i32 c3 = t[3] >> 25; t[4] += c3; t[3] -= c3 * (1 << 25);
    i32 c4 = t[4] >> 26; t[5] += c4; t[4] -= c4 * (1 << 26);
    i32 c5 = t[5] >> 25; t[6] += c5; t[5] -= c5 * (1 << 25);
    i32 c6 = t[6] >> 26; t[7] += c6; t[6] -= c6 * (1 << 26);
    i32 c7 = t[7] >> 25; t[8] += c7; t[7] -= c7 * (1 << 25);
    i32 c8 = t[8] >> 26; t[9] += c8; t[8] -= c8 * (1 << 26);
    i32 c9 = t[9] >> 25;             t[9] -= c9 * (1 << 25);

    store32_le(s +  0, ((u32)t[0] >>  0) | ((u32)t[1] << 26));
    store32_le(s +  4, ((u32)t[1] >>  6) | ((u32)t[2] << 19));
    store32_le(s +  8, ((u32)t[2] >> 13) | ((u32)t[3] << 13));
    store32_le(s + 12, ((u32)t[3] >> 19) | ((u32)t[4] <<  6));
    store32_le(s + 16, ((u32)t[5] >>  0) | ((u32)t[6] << 25));
    store32_le(s + 20, ((u32)t[6] >>  7) | ((u32)t[7] << 19));
    store32_le(s + 24, ((u32)t[7] >> 13) | ((u32)t[8] << 12));
    store32_le(s + 28, ((u32)t[8] >> 20) | ((u32)t[9] <<  6));
}

static u64 x32(const u8 a[32],const u8 b[32]){return x16(a,b)| x16(a+16, b+16);}

static int crypto_verify32(const u8 a[32], const u8 b[32])
{
	return neq0(x32(a, b));
}

static int zerocmp32(const u8 p[32])
{
	static const u8 zero[128] = {0};
	return crypto_verify32(p, zero);
}

//  Parity check.  Returns 0 if even, 1 if odd
static int fe_isnegative(const fe f)
{
    uint8_t s[32];
    fe_tobytes(s, f);
    uint8_t isneg = s[0] & 1;
    return isneg;
}

static int fe_isnonzero(const fe f)
{
    uint8_t s[32];
    fe_tobytes(s, f);
    int isnonzero = zerocmp32(s);
    return isnonzero;
}

static void trim_scalar(uint8_t s[32])
{
    s[ 0] &= 248;
    s[31] &= 127;
    s[31] |= 64;
}

static int scalar_bit(const uint8_t s[32], int i) {
    if (i < 0) { return 0; } // handle -1 for sliding windows
    return (s[i>>3] >> (i&7)) & 1;
}

extern void arcan_random(uint8_t* dst, size_t nb);
void x25519_private_key(uint8_t secret[static 32])
{
	arcan_random(secret, 32);
	secret[0] &= 248;
	secret[31] &= 127;
	secret[31] |= 64;
}

void x25519_public_key(
	const uint8_t secret[static 32], uint8_t public[static 32])
{
	const uint8_t basepoint[32] = {9};
	x25519_shared_secret(public, secret, basepoint);
}

int x25519_shared_secret(
	uint8_t secret_out[static 32],
	const uint8_t secret [static 32], const uint8_t ext_pub [static 32])
{
    // computes the scalar product
    fe x1;
    fe_frombytes(x1, ext_pub);

    // restrict the possible scalar values
    uint8_t e[32];
		memcpy(e, secret, 32);
    trim_scalar(e);

    // computes the actual scalar product (the result is in x2 and z2)
    fe x2, z2, x3, z3, t0, t1;
    // Montgomery ladder
    // In projective coordinates, to avoid divisions: x = X / Z
    // We don't care about the y coordinate, it's only 1 bit of information
    fe_1(x2);        fe_0(z2); // "zero" point
    fe_copy(x3, x1); fe_1(z3); // "one"  point
    int swap = 0;
    for (int pos = 254; pos >= 0; --pos) {
        // constant time conditional swap before ladder step
        int b = scalar_bit(e, pos);
        swap ^= b; // xor trick avoids swapping at the end of the loop
        fe_cswap(x2, x3, swap);
        fe_cswap(z2, z3, swap);
        swap = b;  // anticipates one last swap after the loop

        // Montgomery ladder step: replaces (P2, P3) by (P2*2, P2+P3)
        // with differential addition
        fe_sub(t0, x3, z3);  fe_sub(t1, x2, z2);    fe_add(x2, x2, z2);
        fe_add(z2, x3, z3);  fe_mul(z3, t0, x2);    fe_mul(z2, z2, t1);
        fe_sq (t0, t1    );  fe_sq (t1, x2    );    fe_add(x3, z3, z2);
        fe_sub(z2, z3, z2);  fe_mul(x2, t1, t0);    fe_sub(t1, t1, t0);
        fe_sq (z2, z2    );  fe_mul121666(z3, t1);  fe_sq (x3, x3    );
        fe_add(t0, t0, z3);  fe_mul(z3, x1, z2);    fe_mul(z2, t1, t0);
    }
    // last swap is necessary to compensate for the xor trick
    // Note: after this swap, P3 == P2 + P1.
    fe_cswap(x2, x3, swap);
    fe_cswap(z2, z3, swap);

    // normalises the coordinates: x == X / Z
    fe_invert(z2, z2);
    fe_mul(x2, x2, z2);
    fe_tobytes(secret_out, x2);

    // Returns -1 if the output is all zero
    // (happens with some malicious public keys)
    return -1 - zerocmp32(secret_out);
}
